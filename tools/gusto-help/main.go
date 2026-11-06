// Command gusto-help derives offline schemas from Gusto's public reference.
package main

import (
	"crypto/sha256"
	"encoding/json"
	"flag"
	"fmt"
	"github.com/aibakery/houston-hub/tools/internal/helpschema"
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"strings"
)

type object = map[string]any

func obj(v any) object { m, _ := v.(map[string]any); return m }
func list(v any) []any { a, _ := v.([]any); return a }
func must(e error) {
	if e != nil {
		panic(e)
	}
}

var placeholders = regexp.MustCompile(`\{([^}]+)\}`)

func main() {
	root := flag.String("root", ".", "Hub root")
	directory := flag.String("snapshots", "", "directory of local operation OpenAPI snapshots")
	fetch := flag.Bool("fetch", false, "download public reference snapshots (version is verified before generation)")
	flag.Parse()
	if *directory == "" {
		panic("provide -snapshots directory")
	}
	code, e := os.ReadFile(filepath.Join(*root, "connectors/gusto/connector.luau"))
	must(e)
	source := string(code)
	if *fetch {
		must(fetchSnapshots(source, *directory))
	}
	versionMatch := regexp.MustCompile(`local VERSION = "([^"]+)"`).FindStringSubmatch(source)
	if len(versionMatch) == 0 {
		panic("missing API version")
	}
	version := versionMatch[1]
	examples := map[string][]object{}
	b, e := os.ReadFile(filepath.Join(*root, "tools/gusto-help/examples.json"))
	must(e)
	must(json.Unmarshal(b, &examples))
	schemas, cases := object{}, object{}
	var failures []string
	for _, ep := range helpschema.Endpoints(source) {
		raw, e := os.ReadFile(filepath.Join(*directory, ep.Name+".json"))
		must(e)
		var spec object
		must(json.Unmarshal(raw, &spec))
		if obj(spec["info"])["version"] != version {
			panic("snapshot version differs from connector: " + ep.Name)
		}
		var op object
		var nativePath string
		for path, v := range obj(spec["paths"]) {
			if placeholders.ReplaceAllString(path, "{}") == placeholders.ReplaceAllString(ep.Path, "{}") {
				if candidate := obj(obj(v)[strings.ToLower(ep.Method)]); candidate != nil {
					op = candidate
					nativePath = path
				}
			}
		}
		if op == nil {
			failures = append(failures, "missing route: "+ep.Name)
			continue
		}
		fields := func(key string) []string { v, e := helpschema.Fields(source, ep.Definition, key); must(e); return v }
		query, required, allow := fields("query"), fields("required"), fields("allow")
		localNames, nativeNames := placeholders.FindAllStringSubmatch(ep.Path, -1), placeholders.FindAllStringSubmatch(nativePath, -1)
		querySchemas := object{}
		for _, raw := range list(op["parameters"]) {
			p := obj(raw)
			name, _ := p["name"].(string)
			if p["in"] == "path" {
				for i, n := range nativeNames {
					if name == n[1] {
						p["name"] = localNames[i][1]
						break
					}
				}
				p["schema"] = object{"anyOf": []any{object{"type": "integer", "minimum": 0, "maximum": 9007199254740991}, object{"type": "string", "minLength": 1, "pattern": "^[A-Za-z0-9_-]+$"}}}
			}
			if p["in"] == "query" && slices.Contains(query, name) {
				s := obj(p["schema"])
				if p["description"] != nil {
					s["description"] = p["description"]
				}
				if s["type"] == "array" {
					s["minItems"] = 1
					item := obj(s["items"])
					pattern := "[^,]+"
					if values := list(item["enum"]); len(values) > 0 {
						parts := []string{}
						for _, v := range values {
							parts = append(parts, regexp.QuoteMeta(fmt.Sprint(v)))
						}
						pattern = "(" + strings.Join(parts, "|") + ")"
					}
					s = object{"anyOf": []any{s, object{"type": "string", "pattern": "^" + pattern + "(," + pattern + ")*$"}}}
				}
				if description, _ := s["description"].(string); s["type"] == "string" && strings.Contains(strings.ToLower(description), "comma") {
					item := object{"type": "string", "minLength": 1}
					if name == "benefit_type" {
						item = object{"type": "integer", "minimum": 1}
					}
					s = object{"anyOf": []any{s, object{"type": "array", "minItems": 1, "items": item}}}
				}
				querySchemas[name] = s
				p["schema"] = s
			}
		}
		body := (ep.Method == "POST" || ep.Method == "PUT" || ep.Method == "PATCH") && !strings.Contains(ep.Definition, "body = false")
		mandatory := []string{}
		for _, name := range required {
			if slices.Contains(query, name) {
				mandatory = append(mandatory, name)
			}
		}
		schema, e := helpschema.Input(spec, op, ep.Path, query, mandatory, body)
		if e != nil {
			failures = append(failures, ep.Name+": "+e.Error())
			continue
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
		if len(allow) > 0 {
			schema["additionalProperties"] = false
			for _, name := range allow {
				obj(schema["properties"])[name] = true
			}
		}
		supplement(ep.Name, schema)
		if len(examples[ep.Name]) == 0 {
			panic("missing authored example: " + ep.Name)
		}
		schema["examples"] = examples[ep.Name]
		record := object{"inputSchema": schema}
		// Reads can return nil for HTTP 204. outputSchema describes only object
		// results, so declare it only on operations whose adapter always returns one.
		if ep.Method != "GET" && !strings.Contains(ep.Definition, "write = false") {
			record["outputSchema"] = object{"type": "object", "properties": object{"items": object{"type": "array"}, "page": object{"type": "integer"}, "per": object{"type": "integer"}, "total_count": object{"type": "integer"}, "total_pages": object{"type": "integer"}}}
		}
		schemas[ep.Name] = record
		cases[ep.Name] = object{"method": ep.Method, "path": ep.Path, "query": query, "body": body, "version": version, "source": fmt.Sprintf("https://docs.gusto.com/app-integrations/reference/%s.md", regexp.MustCompile(`doc = "([^"]+)"`).FindStringSubmatch(ep.Definition)[1]), "sha256": fmt.Sprintf("%x", sha256.Sum256(raw))}
	}
	for name := range examples {
		if schemas[name] == nil {
			panic("example without endpoint: " + name)
		}
	}
	if len(failures) > 0 {
		panic(strings.Join(failures, "\n"))
	}
	destination := filepath.Join(*root, "connectors/gusto/lib")
	must(os.MkdirAll(destination, 0755))
	for name, value := range map[string]any{"help": schemas, "example-routes": cases} {
		b, e = json.MarshalIndent(value, "", "\t")
		must(e)
		must(os.WriteFile(filepath.Join(destination, name+".luau"), []byte("-- Code generated by go run ./tools/gusto-help -snapshots <directory>; DO NOT EDIT.\n-- Native API version "+version+"; per-operation source URLs and SHA-256 in example-routes.luau.\n-- Authored examples: tools/gusto-help/examples.json\nreturn json.decode([====[\n"+string(b)+"\n]====])\n"), 0644))
	}
}
