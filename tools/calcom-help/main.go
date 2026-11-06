// Command calcom-help derives native request schemas for the connector's pinned
// per-controller API versions from Cal.com's published OpenAPI document.
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
func clone(v any) any {
	b, e := json.Marshal(v)
	must(e)
	var out any
	must(json.Unmarshal(b, &out))
	return out
}

var placeholders = regexp.MustCompile(`\{([^}]+)\}`)

func main() {
	snapshot := flag.String("openapi", "", "local https://cal.com/docs/api-reference/v2/openapi.json snapshot")
	root := flag.String("root", ".", "Hub root")
	flag.Parse()
	raw, e := os.ReadFile(*snapshot)
	must(e)
	var spec object
	must(json.Unmarshal(raw, &spec))
	supplement(spec)
	code, e := os.ReadFile(filepath.Join(*root, "connectors/calcom/connector.luau"))
	must(e)
	source := string(code)
	versions := map[string]string{}
	for _, m := range regexp.MustCompile(`local (\w+) = "(\d{4}-\d{2}-\d{2})"`).FindAllStringSubmatch(source, -1) {
		versions[m[1]] = m[2]
	}
	type native struct {
		path string
		op   object
	}
	routes := map[string]native{}
	for path, v := range obj(spec["paths"]) {
		for method, op := range obj(v) {
			if obj(op) != nil {
				routes[strings.ToUpper(method)+" "+placeholders.ReplaceAllString(path, "{}")] = native{path, obj(op)}
			}
		}
	}
	examples := map[string][]object{}
	b, e := os.ReadFile(filepath.Join(*root, "tools/calcom-help/examples.json"))
	must(e)
	must(json.Unmarshal(b, &examples))
	schemas, cases := object{}, object{}
	var failures []string
	for _, ep := range helpschema.Endpoints(source) {
		if len(examples[ep.Name]) == 0 {
			panic("missing authored example: " + ep.Name)
		}
		n, ok := routes[ep.Method+" "+placeholders.ReplaceAllString(ep.Path, "{}")]
		if !ok {
			failures = append(failures, "missing route "+ep.Name)
			continue
		}
		op := obj(clone(n.op))
		fields := func(key string) []string { v, e := helpschema.Fields(source, ep.Definition, key); must(e); return v }
		query, extra, required := fields("query"), fields("extra"), fields("required")
		version := ""
		if m := regexp.MustCompile(`version = (\w+)`).FindStringSubmatch(ep.Definition); len(m) > 0 {
			version = versions[m[1]]
			if version == "" {
				panic("unknown version " + m[1])
			}
		}
		nativeVersion := ""
		nativeNames, localNames := placeholders.FindAllStringSubmatch(n.path, -1), placeholders.FindAllStringSubmatch(ep.Path, -1)
		querySchemas := object{}
		for _, value := range list(op["parameters"]) {
			p := obj(value)
			name, _ := p["name"].(string)
			if name == "cal-api-version" {
				nativeVersion, _ = obj(p["schema"])["default"].(string)
				if nativeVersion == "" {
					nativeVersion, _ = obj(p["schema"])["example"].(string)
				}
			}
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
				if name == "take" || name == "skip" || name == "limit" || name == "hostsLimit" {
					s["type"] = "integer"
				}
				if p["description"] != nil {
					s["description"] = p["description"]
				}
				if s["type"] == "array" {
					s["minItems"] = 1
					scalar := s["items"]
					if description, _ := s["description"].(string); strings.Contains(description, "comma") {
						item := "[^,]+"
						if values := list(obj(scalar)["enum"]); len(values) > 0 {
							parts := []string{}
							for _, v := range values {
								parts = append(parts, regexp.QuoteMeta(v.(string)))
							}
							item = "(" + strings.Join(parts, "|") + ")"
						}
						repeat := "*"
						if max, ok := s["maxItems"].(float64); ok {
							repeat = fmt.Sprintf("{0,%d}", int(max)-1)
						}
						scalar = object{"type": "string", "pattern": "^" + item + "(," + item + ")" + repeat + "$"}
					}
					s = object{"anyOf": []any{s, scalar}}
				}
				querySchemas[name] = s
				p["schema"] = s
			}
		}
		if nativeVersion != version {
			failures = append(failures, fmt.Sprintf("%s version: connector %q, snapshot %q", ep.Name, version, nativeVersion))
			continue
		}
		body := (ep.Method == "POST" || ep.Method == "PUT" || ep.Method == "PATCH") && !strings.Contains(ep.Definition, "body = false")
		wrap := ""
		if m := regexp.MustCompile(`body = "([^"]+)"`).FindStringSubmatch(ep.Definition); len(m) > 0 {
			wrap = m[1]
			request := obj(obj(obj(op["requestBody"])["content"])["application/json"])
			request["schema"] = object{"type": "object", "properties": object{wrap: request["schema"]}, "required": []string{wrap}, "additionalProperties": false}
		}
		mandatory := []string{}
		for _, field := range required {
			if slices.Contains(query, field) || slices.Contains(extra, field) {
				mandatory = append(mandatory, field)
			}
		}
		schema, err := helpschema.Input(spec, op, ep.Path, append(slices.Clone(query), extra...), mandatory, body)
		if err != nil {
			failures = append(failures, ep.Name+": "+err.Error())
			continue
		}
		for name, s := range querySchemas {
			obj(schema["properties"])[name] = s
		}
		need := schema["required"].([]string)
		for _, field := range required {
			if !slices.Contains(need, field) {
				need = append(need, field)
			}
		}
		schema["required"] = need
		if ep.Name == "getSlots" {
			schema["allOf"] = []any{eventSelector()}
		}
		schema["examples"] = examples[ep.Name]
		schemas[ep.Name] = object{"inputSchema": schema, "outputSchema": object{"type": "object", "properties": object{"status": object{"const": "success"}}, "required": []string{"status"}}}
		cases[ep.Name] = object{"method": ep.Method, "path": ep.Path, "query": query, "body": body, "wrap": wrap, "version": version}
	}
	for name := range examples {
		if schemas[name] == nil {
			panic("example without endpoint: " + name)
		}
	}
	if len(failures) > 0 {
		panic(strings.Join(failures, "\n"))
	}
	directory := filepath.Join(*root, "connectors/calcom/lib")
	must(os.MkdirAll(directory, 0755))
	for name, value := range map[string]any{"help": schemas, "example-routes": cases} {
		b, e = json.MarshalIndent(value, "", "\t")
		must(e)
		header := fmt.Sprintf("-- Code generated by go run ./tools/calcom-help -openapi <snapshot>; DO NOT EDIT.\n-- Source: https://cal.com/docs/api-reference/v2/openapi.json\n-- SHA-256: %x\n-- Authored examples: tools/calcom-help/examples.json\nreturn json.decode([====[\n", sha256.Sum256(raw))
		must(os.WriteFile(filepath.Join(directory, name+".luau"), []byte(header+string(b)+"\n]====])\n"), 0644))
	}
}
