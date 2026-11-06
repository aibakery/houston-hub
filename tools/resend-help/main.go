// Command resend-help derives native schemas from Resend's public OpenAPI,
// adding connector transport rules and constraints from the official SDK.
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
func must(err error) {
	if err != nil {
		panic(err)
	}
}
func clone(v any) any {
	b, err := json.Marshal(v)
	must(err)
	var c any
	must(json.Unmarshal(b, &c))
	return c
}
func resolve(spec object, v any) object {
	s := obj(clone(v))
	for s["$ref"] != nil {
		p := strings.Split(strings.TrimPrefix(s["$ref"].(string), "#/"), "/")
		var target any = spec
		for _, key := range p {
			target = obj(target)[key]
		}
		s = obj(clone(target))
	}
	return s
}

var placeholders = regexp.MustCompile(`\{([^}]+)\}`)

func main() {
	snapshot := flag.String("openapi", "", "local snapshot of https://raw.githubusercontent.com/resend/resend-openapi/main/resend.json")
	root := flag.String("root", ".", "Hub root")
	flag.Parse()
	raw, err := os.ReadFile(*snapshot)
	must(err)
	var spec object
	must(json.Unmarshal(raw, &spec))
	supplement(spec)
	code, err := os.ReadFile(filepath.Join(*root, "connectors/resend/connector.luau"))
	must(err)
	b, err := os.ReadFile(filepath.Join(*root, "tools/resend-help/examples.json"))
	must(err)
	var examples map[string][]object
	must(json.Unmarshal(b, &examples))
	type native struct {
		path string
		op   object
	}
	routes := map[string]native{}
	for path, value := range obj(spec["paths"]) {
		for method, op := range obj(value) {
			if obj(op) != nil {
				routes[strings.ToUpper(method)+" "+placeholders.ReplaceAllString(path, "{}")] = native{path, obj(op)}
			}
		}
	}
	schemas, cases := object{}, object{}
	var failures []string
	for _, ep := range helpschema.Endpoints(string(code)) {
		n, ok := routes[ep.Method+" "+placeholders.ReplaceAllString(ep.Path, "{}")]
		if !ok {
			panic("missing route " + ep.Name)
		}
		op := obj(clone(n.op))
		params := list(op["parameters"])
		nativeNames, localNames := placeholders.FindAllStringSubmatch(n.path, -1), placeholders.FindAllStringSubmatch(ep.Path, -1)
		fields := func(key string) []string {
			value, err := helpschema.Fields(string(code), ep.Definition, key)
			must(err)
			return value
		}
		query, extra, required := fields("query"), fields("extra"), fields("required")
		querySchemas := object{}
		for i, value := range params {
			p := resolve(spec, value)
			params[i] = p
			if p["in"] == "path" {
				for index, name := range nativeNames {
					if p["name"] == name[1] {
						p["name"] = localNames[index][1]
					}
				}
				p["schema"] = object{"type": "string", "minLength": 1, "pattern": `^[^/\\%\u0000-\u001f\u007f]+$`, "not": object{"enum": []string{".", ".."}}, "description": "Resource ID; routes documented for contacts, inboxes and suppressions also accept email addresses, templates accept aliases, and events accept names."}
			}
			if p["in"] == "query" && slices.Contains(query, p["name"].(string)) {
				s := resolve(spec, p["schema"])
				if p["description"] != nil {
					s["description"] = p["description"]
				}
				if s["type"] == "array" {
					s["minItems"] = 1
					s = object{"anyOf": []any{s, object{"type": "string", "minLength": 1, "description": "Comma-separated values with the same allowed items."}}}
				}
				if ep.Name == "listAutomationRuns" && p["name"] == "status" {
					s = object{"anyOf": []any{s, object{"type": "array", "minItems": 1, "items": stringsEnum("running", "completed", "failed", "cancelled")}}}
				}
				if p["name"] == "limit" {
					s["default"] = 100
				}
				p["schema"] = s
				querySchemas[p["name"].(string)] = s
			}
		}
		op["parameters"] = params
		body := (ep.Method == "POST" || ep.Method == "PATCH" || ep.Method == "PUT") && !strings.Contains(ep.Definition, "body = false")
		upload := strings.Contains(ep.Definition, "upload = true")
		wrap := ""
		if m := regexp.MustCompile(`body = "([^"]+)"`).FindStringSubmatch(ep.Definition); len(m) > 0 {
			wrap = m[1]
		}
		if ep.Name == "updateEmail" {
			op["requestBody"] = object{"content": object{"application/json": object{"schema": object{"$ref": "#/components/schemas/UpdateEmailOptions"}}}}
		}
		if upload {
			op["requestBody"] = object{"content": object{"application/json": object{"schema": object{"$ref": "#/components/schemas/HoustonContactImport"}}}}
		}
		if wrap != "" {
			request := obj(obj(obj(op["requestBody"])["content"])["application/json"])
			array := obj(request["schema"])
			array["minItems"], array["maxItems"] = 1, 100
			array["items"] = object{"allOf": []any{array["items"], object{"properties": object{"attachments": false}}}}
			request["schema"] = object{"type": "object", "properties": object{wrap: array}, "required": []string{wrap}, "additionalProperties": false}
		}
		// Header/session arguments are accepted alongside native body fields. Add them
		// as synthetic parameters so closed request-body branches allow them as well.
		for _, field := range extra {
			s := object{"type": "string", "minLength": 1}
			if field == "idempotency_key" {
				s["maxLength"] = 256
				s["description"] = "Idempotency-Key header, retained by Resend for 24 hours. Reuse only for the same intended send/draft."
			} else {
				s["description"] = "Session file path. Imports stream an existing CSV; attachment lookups save to this path and return a signed Houston URL."
			}
			op["parameters"] = append(list(op["parameters"]), object{"name": field, "in": "header", "schema": s})
		}
		if upload {
			required = append(required, "path")
		}
		schema, err := helpschema.Input(spec, op, ep.Path, append(slices.Clone(query), extra...), required, body)
		if err != nil {
			failures = append(failures, fmt.Sprintf("%s: %v", ep.Name, err))
			continue
		}
		// Unlike the shared optional-query default, this transport rejects JSON null.
		for name, value := range querySchemas {
			obj(schema["properties"])[name] = value
		}
		for _, field := range extra {
			p := obj(obj(schema["properties"])[field])
			if branches := list(p["anyOf"]); len(branches) == 2 && obj(branches[1])["type"] == "null" {
				obj(schema["properties"])[field] = branches[0]
			}
		}
		if slices.Contains(query, "after") && slices.Contains(query, "before") {
			schema["not"] = object{"required": []string{"after", "before"}}
		}
		if len(examples[ep.Name]) == 0 {
			panic("missing examples " + ep.Name)
		}
		schema["examples"] = examples[ep.Name]
		schemas[ep.Name] = schema
		cases[ep.Name] = object{"method": ep.Method, "path": ep.Path, "query": query, "extra": extra, "body": body, "wrap": wrap, "upload": upload}
	}
	if len(failures) > 0 {
		panic(strings.Join(failures, "\n"))
	}
	if len(schemas) != len(examples) {
		panic("orphaned examples")
	}
	directory := filepath.Join(*root, "connectors/resend/lib")
	must(os.MkdirAll(directory, 0755))
	for name, value := range map[string]any{"schemas": schemas, "example-routes": cases} {
		b, err = json.MarshalIndent(value, "", "\t")
		must(err)
		header := fmt.Sprintf("-- Code generated by go run ./tools/resend-help -openapi <snapshot>; DO NOT EDIT.\n-- Source: https://raw.githubusercontent.com/resend/resend-openapi/main/resend.json\n-- SHA-256: %x\n-- Supplemental shapes: official resend-node automation-step.interface.ts and tools/resend-help/supplement.go.\n-- Authored examples: tools/resend-help/examples.json\nreturn json.decode([====[\n", sha256.Sum256(raw))
		must(os.WriteFile(filepath.Join(directory, name+".luau"), []byte(header+string(b)+"\n]====])\n"), 0644))
	}
}
