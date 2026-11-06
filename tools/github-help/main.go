// Command github-help derives native REST request documentation for the API
// version pinned by the connector, including GitHub's versioned schema patches.
package main

import (
	"crypto/sha256"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"strings"

	"github.com/aibakery/houston-hub/tools/internal/helpschema"
)

type object = map[string]any

func obj(v any) object { m, _ := v.(map[string]any); return m }
func list(v any) []any { a, _ := v.([]any); return a }
func must(e error) {
	if e != nil {
		panic(e)
	}
}
func clone(v any) any {
	b, e := json.Marshal(v)
	must(e)
	var out any
	must(json.Unmarshal(b, &out))
	return out
}
func resolve(spec object, v any) object {
	s := obj(v)
	if ref, ok := s["$ref"].(string); ok {
		if !strings.HasPrefix(ref, "#/") {
			panic("external ref " + ref)
		}
		var target any = spec
		for _, key := range strings.Split(ref[2:], "/") {
			key = strings.ReplaceAll(strings.ReplaceAll(key, "~1", "/"), "~0", "~")
			target = obj(target)[key]
		}
		if target == nil {
			panic("missing " + ref)
		}
		return obj(clone(target))
	}
	return obj(clone(s))
}

var placeholders = regexp.MustCompile(`\{([^}]+)\}`)
var opaque = map[string]bool{"branch": true, "ref": true, "path": true, "basehead": true, "tag": true, "name": true, "tree_sha": true}

func main() {
	snapshot := flag.String("openapi", "", "local github/rest-api-description descriptions/api.github.com/api.github.com.json snapshot")
	root := flag.String("root", ".", "Hub root")
	flag.Parse()
	raw, e := os.ReadFile(*snapshot)
	must(e)
	var spec object
	must(json.Unmarshal(raw, &spec))
	code, e := os.ReadFile(filepath.Join(*root, "connectors/github/connector.luau"))
	must(e)
	source := string(code)
	versionMatch := regexp.MustCompile(`local VERSION = "([^"]+)"`).FindStringSubmatch(source)
	if len(versionMatch) != 2 || versionMatch[1] != "2026-03-10" {
		panic("review generator for connector API version")
	}
	version := versionMatch[1]
	examples := map[string][]object{}
	b, e := os.ReadFile(filepath.Join(*root, "tools/github-help/examples.json"))
	must(e)
	must(json.Unmarshal(b, &examples))
	type native struct {
		path     string
		item, op object
	}
	operations := map[string]native{}
	for path, v := range obj(spec["paths"]) {
		for method, op := range obj(v) {
			if obj(op) != nil {
				operations[strings.ToUpper(method)+" "+placeholders.ReplaceAllString(path, "{}")] = native{path, obj(v), obj(op)}
			}
		}
	}
	endpoints := append(helpschema.Endpoints(source), helpschema.Endpoint{Name: "downloadGistFile", Method: "GET", Path: "/gists/{gist_id}", Definition: `required = {"filename", "save_as"}`})
	schemas, routes := object{}, object{}
	for _, ep := range endpoints {
		if len(examples[ep.Name]) == 0 {
			panic("missing authored example " + ep.Name)
		}
		n, ok := operations[ep.Method+" "+placeholders.ReplaceAllString(ep.Path, "{}")]
		if !ok {
			panic("missing native endpoint " + ep.Name)
		}
		op := obj(clone(n.op))
		applyVersion(op, version)
		fields := func(key string) []string { v, e := helpschema.Fields(source, ep.Definition, key); must(e); return v }
		query, required := fields("query"), fields("required")
		body := (ep.Method == "POST" || ep.Method == "PUT" || ep.Method == "PATCH" || strings.Contains(ep.Definition, "body = true")) && !strings.Contains(ep.Definition, "body = false")
		save := ""
		if m := regexp.MustCompile(`save = ("[^"]+"|JSON)`).FindStringSubmatch(ep.Definition); len(m) > 0 {
			save = strings.Trim(m[1], `"`)
			if save == "JSON" {
				save = "application/vnd.github+json"
			}
		}
		diff := strings.Contains(ep.Definition, "diff = true")
		auth := ""
		if m := regexp.MustCompile(`auth = "([^"]+)"`).FindStringSubmatch(ep.Definition); len(m) > 0 {
			auth = m[1]
		}
		params := []any{}
		querySchemas := object{}
		nativeNames, localNames := placeholders.FindAllStringSubmatch(n.path, -1), placeholders.FindAllStringSubmatch(ep.Path, -1)
		for _, v := range append(list(n.item["parameters"]), list(op["parameters"])...) {
			p := resolve(spec, v)
			name, _ := p["name"].(string)
			if p["in"] == "path" {
				for i, n := range nativeNames {
					if n[1] == name {
						name = localNames[i][1]
						p["name"] = name
						break
					}
				}
				original := resolve(spec, p["schema"])
				s := pathSchema(name)
				if values := original["enum"]; values != nil {
					s["enum"] = values
				}
				p["schema"] = s
			}
			if p["in"] == "query" && slices.Contains(query, name) {
				s := resolve(spec, p["schema"])
				if p["description"] != nil {
					s["description"] = p["description"]
				}
				if s["type"] == "array" {
					s = csv(s)
				}
				if name == "recursive" {
					s = object{"type": "boolean", "default": false, "description": "true recurses; false omits the native recursive flag."}
				}
				if name == "per_page" {
					s["minimum"] = 1
					s["maximum"] = 100
				}
				if name == "page" {
					s["minimum"] = 1
				}
				querySchemas[name] = s
				p["schema"] = s
			}
			params = append(params, p)
		}
		extra := []string{}
		extraParam := func(name string, s object) {
			extra = append(extra, name)
			querySchemas[name] = s
			params = append(params, object{"name": name, "in": "query", "schema": s})
		}
		if save != "" || ep.Name == "downloadGistFile" {
			extraParam("save_as", object{"type": "string", "minLength": 1, "pattern": `^[^\u0000-\u001f\u007f]+$`, "description": "Private session path. Replaced only after the download succeeds; returns {path,size,url}."})
		}
		if diff {
			extraParam("format", object{"enum": []string{"diff", "patch"}, "description": "Return raw diff or patch text instead of the normal JSON object."})
		}
		if ep.Name == "downloadGistFile" {
			extraParam("filename", object{"type": "string", "minLength": 1, "description": "Exact file key in getGist().files, for example notes.md."})
		}
		op["parameters"] = params
		if body && obj(obj(obj(op["requestBody"])["content"])["application/json"])["schema"] == nil {
			op["requestBody"] = object{"content": object{"application/json": object{"schema": object{"type": "object", "properties": object{}, "additionalProperties": false}}}}
		}
		mandatory := []string{}
		for _, name := range required {
			if slices.Contains(query, name) || slices.Contains(extra, name) {
				mandatory = append(mandatory, name)
			}
		}
		schema, err := helpschema.Input(spec, op, ep.Path, append(slices.Clone(query), extra...), mandatory, body)
		if err != nil {
			panic(ep.Name + ": " + err.Error())
		}
		for name, s := range querySchemas {
			obj(schema["properties"])[name] = s
		}
		need := schema["required"].([]string)
		for _, name := range required {
			if !slices.Contains(need, name) {
				need = append(need, name)
			}
		}
		schema["required"] = need
		supplement(ep.Name, schema)
		schema["examples"] = examples[ep.Name]
		record := object{"description": op["summary"], "inputSchema": schema}
		if slices.Contains(required, "save_as") {
			record["outputSchema"] = downloadSchema()
		}
		if ep.Name == "downloadGistFile" {
			record["description"] = "Download a complete gist file by its exact filename using the provider raw URL."
		}
		schemas[ep.Name] = record
		routes[ep.Name] = object{"method": ep.Method, "path": ep.Path, "query": query, "body": body, "save": save, "diff": diff, "auth": auth, "version": version}
	}
	for name := range examples {
		if schemas[name] == nil {
			panic("example without endpoint " + name)
		}
	}
	directory := filepath.Join(*root, "connectors/github/lib")
	must(os.MkdirAll(directory, 0755))
	for name, value := range map[string]any{"help": schemas, "example-routes": routes} {
		b, e = json.MarshalIndent(value, "", "\t")
		must(e)
		header := fmt.Sprintf("-- Code generated by go run ./tools/github-help -openapi <snapshot>; DO NOT EDIT.\n-- Source: https://github.com/github/rest-api-description/blob/main/descriptions/api.github.com/api.github.com.json\n-- API version: %s; snapshot SHA-256: %x\n-- Authored examples: tools/github-help/examples.json\nreturn json.decode([====[\n", version, sha256.Sum256(raw))
		must(os.WriteFile(filepath.Join(directory, name+".luau"), []byte(header+string(b)+"\n]====])\n"), 0644))
	}
}

func pathSchema(name string) object {
	if name == "archive_format" {
		return object{"const": "zip", "description": "GitHub Actions artifacts are ZIP archives."}
	}
	numeric := object{"type": "integer", "minimum": 1, "maximum": 9007199254740991}
	if strings.HasSuffix(name, "_number") || (strings.HasSuffix(name, "_id") && name != "workflow_id" && name != "gist_id") {
		max := "9007199254740991"
		alternatives := []string{max, "[1-9][0-9]{0,14}"}
		for i, digit := range max {
			low := 0
			if i == 0 {
				low = 1
			}
			if int(digit-'0') > low {
				alternatives = append(alternatives, fmt.Sprintf("%s[%d-%d][0-9]{%d}", max[:i], low, digit-'0'-1, len(max)-i-1))
			}
		}
		return object{"anyOf": []any{numeric, object{"type": "string", "pattern": "^0*(" + strings.Join(alternatives, "|") + ")$"}}, "description": "Positive safe integer ID, or its decimal digits."}
	}
	if opaque[name] {
		return object{"type": "string", "minLength": 1, "pattern": `^[^\\\u0000-\u001f\u007f-\u009f]+$`, "not": object{"anyOf": []any{object{"pattern": `(^|/)(\.*)(/|$)`}, object{"pattern": `%([2][5])*(2[fF]|5[cC])`}}}, "description": "Slash-separated names; literal percent signs are allowed. Empty/dot-only parts, backslashes, escaped separators and Unicode path look-alikes are rejected by the transport."}
	}
	return object{"anyOf": []any{numeric, object{"type": "string", "minLength": 1, "maxLength": 16384, "pattern": `^[^/\\%\u0000-\u001f\u007f-\u009f]+$`, "not": object{"pattern": `^\.+$`}}}, "description": "One GitHub name or SHA; no path separators, percent escapes, dot-only segments or Unicode path look-alikes."}
}
func csv(s object) object {
	item := obj(s["items"])
	pattern := "[^,]+"
	if values := list(item["enum"]); len(values) > 0 {
		parts := []string{}
		for _, v := range values {
			parts = append(parts, regexp.QuoteMeta(fmt.Sprint(v)))
		}
		pattern = "(" + strings.Join(parts, "|") + ")"
	}
	return object{"type": "string", "pattern": "^" + pattern + "(," + pattern + ")*$", "description": fmt.Sprint(s["description"]) + " Pass a comma-separated string; this connector sends scalar query values."}
}
func downloadSchema() object {
	return object{"type": "object", "properties": object{"path": object{"type": "string"}, "size": object{"type": "integer", "minimum": 0}, "url": object{"type": "string", "format": "uri"}}, "required": []string{"path", "size", "url"}, "additionalProperties": false}
}
