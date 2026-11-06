// Command pennylane-help composes native Company API v2 request schemas from
// Pennylane's published OpenAPI and the connector's actual endpoint declarations.
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

var placeholders = regexp.MustCompile(`\{([^}]+)\}`)

func main() {
	snapshot := flag.String("openapi", "", "local https://pennylane.readme.io/openapi/accounting.json snapshot")
	root := flag.String("root", ".", "Hub root")
	flag.Parse()
	raw, e := os.ReadFile(*snapshot)
	must(e)
	var spec object
	must(json.Unmarshal(raw, &spec))
	if obj(spec["info"])["version"] != "2.0" {
		panic("expected Company API v2")
	}
	code, e := os.ReadFile(filepath.Join(*root, "connectors/pennylane/connector.luau"))
	must(e)
	source := string(code)
	examples := map[string][]object{}
	b, e := os.ReadFile(filepath.Join(*root, "tools/pennylane-help/examples.json"))
	must(e)
	must(json.Unmarshal(b, &examples))
	schemas, routes := object{}, object{}
	for _, ep := range helpschema.Endpoints(source) {
		if len(examples[ep.Name]) == 0 {
			panic("missing authored example " + ep.Name)
		}
		pathItem := obj(obj(spec["paths"])["/api/external/v2"+ep.Path])
		op := obj(clone(pathItem[strings.ToLower(ep.Method)]))
		if op == nil {
			panic("missing native operation " + ep.Name)
		}
		fields := func(key string) []string { v, e := helpschema.Fields(source, ep.Definition, key); must(e); return v }
		query, required, parts := fields("query"), fields("required"), fields("parts")
		body := ep.Method != "GET" && !strings.Contains(ep.Definition, "body = false")
		wrap := ""
		if m := regexp.MustCompile(`body = "([^"]+)"`).FindStringSubmatch(ep.Definition); len(m) > 0 {
			wrap = m[1]
		}
		params := append(list(pathItem["parameters"]), list(op["parameters"])...)
		querySchemas := object{}
		for _, v := range params {
			p := obj(v)
			name, _ := p["name"].(string)
			if p["in"] == "path" {
				p["schema"] = object{"anyOf": []any{object{"type": "integer", "minimum": 0, "maximum": 9007199254740991}, object{"type": "string", "pattern": "^[0-9]{1,19}$"}}, "description": "Nonnegative numeric ID (safe integers) or up to 19 decimal digits."}
			}
			if p["in"] == "query" && slices.Contains(query, name) {
				s := obj(clone(p["schema"]))
				if s == nil {
					panic("query lacks schema " + ep.Name + "." + name)
				}
				if p["description"] != nil {
					s["description"] = p["description"]
				}
				if name == "filter" {
					s = filterSchema(s)
				}
				if name == "sort" {
					sortSchema(s)
				}
				if name == "limit" {
					s["default"] = 20
				}
				querySchemas[name] = s
				p["schema"] = s
			}
		}
		op["parameters"] = params
		if body {
			content := obj(obj(op["requestBody"])["content"])
			if wrap == "multipart" {
				native := obj(clone(obj(content["multipart/form-data"])["schema"]))
				if native == nil {
					panic("missing multipart " + ep.Name)
				}
				props := obj(native["properties"])
				allowed := append(slices.Clone(parts), "file", "filename", "content_type")
				for key := range props {
					if !slices.Contains(allowed, key) {
						delete(props, key)
					}
				}
				props["file"] = object{"type": "string", "minLength": 1, "description": "Existing private session file; streamed to Pennylane."}
				props["filename"] = object{"type": "string", "minLength": 1, "maxLength": 255, "pattern": `^[^\u0000-\u001f\u007f"/\\]+$`, "description": "Plain file name, at most 255 bytes; defaults to the session path basename."}
				props["content_type"] = object{"type": "string", "pattern": `^[A-Za-z0-9.+-]+/[A-Za-z0-9.+-]+$`, "description": "MIME type; inferred from filename when omitted."}
				native["required"] = []string{"file"}
				content["application/json"] = object{"schema": native}
			} else if wrap != "" {
				native := obj(content["application/json"])["schema"]
				content["application/json"] = object{"schema": object{"type": "object", "properties": object{wrap: native}, "required": []string{wrap}, "additionalProperties": false}}
			} else if obj(content["application/json"])["schema"] == nil {
				panic("missing JSON body " + ep.Name)
			}
			constrainFormats(obj(obj(content["application/json"])["schema"]))
		}
		mandatory := []string{}
		for _, field := range required {
			if slices.Contains(query, field) {
				mandatory = append(mandatory, field)
			}
		}
		schema, err := helpschema.Input(spec, op, ep.Path, query, mandatory, body)
		if err != nil {
			panic(ep.Name + ": " + err.Error())
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
		if slices.Contains(query, "start_date") {
			schema["not"] = object{"required": []string{"start_date", "cursor"}}
		}
		if wrap == "multipart" && slices.Contains(parts, "override_invoice_lines") {
			schema["not"] = object{"required": []string{"override_invoice_lines", "invoice_options"}, "properties": object{"invoice_options": object{"required": []string{"invoice_lines"}}}}
		}
		constrainFormats(schema)
		schema["examples"] = examples[ep.Name]
		schemas[ep.Name] = object{"description": op["summary"], "inputSchema": schema}
		readOnly := ep.Method == "GET" || strings.Contains(ep.Definition, "write = false")
		routes[ep.Name] = object{"method": ep.Method, "path": ep.Path, "query": query, "body": body, "wrap": wrap, "parts": parts, "readOnly": readOnly}
	}
	for name := range examples {
		if schemas[name] == nil {
			panic("example without endpoint " + name)
		}
	}
	directory := filepath.Join(*root, "connectors/pennylane/lib")
	must(os.MkdirAll(directory, 0755))
	for name, value := range map[string]any{"help": schemas, "example-routes": routes} {
		b, e = json.MarshalIndent(value, "", "\t")
		must(e)
		header := fmt.Sprintf("-- Code generated by go run ./tools/pennylane-help -openapi <snapshot>; DO NOT EDIT.\n-- Source: https://pennylane.readme.io/openapi/accounting.json\n-- SHA-256: %x\n-- Authored examples: tools/pennylane-help/examples.json\nreturn json.decode([====[\n", sha256.Sum256(raw))
		must(os.WriteFile(filepath.Join(directory, name+".luau"), []byte(header+string(b)+"\n]====])\n"), 0644))
	}
}

func constrainFormats(schema object) {
	// The published subscription unions close both the wrapper (which declares
	// no properties) and every alternative. Closing the wrapper rejects all
	// documented alternatives; retain the alternatives' native closed shapes.
	if schema["additionalProperties"] == false && schema["properties"] == nil {
		for _, key := range []string{"anyOf", "oneOf"} {
			branches := list(schema[key])
			closed := len(branches) > 0
			for _, branch := range branches {
				closed = closed && obj(branch)["additionalProperties"] == false && obj(branch)["properties"] != nil
			}
			if closed {
				delete(schema, "additionalProperties")
			}
		}
	}
	if schema["format"] == "date" {
		schema["pattern"] = `^[0-9]{4}-[0-9]{2}-[0-9]{2}$`
	}
	if schema["format"] == "date-time" {
		schema["pattern"] = `^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?(Z|[+-][0-9]{2}:[0-9]{2})$`
	}
	for _, key := range []string{"properties", "$defs", "patternProperties"} {
		for _, v := range obj(schema[key]) {
			constrainFormats(obj(v))
		}
	}
	for _, key := range []string{"items", "additionalProperties", "not", "if", "then", "else"} {
		if child := obj(schema[key]); child != nil {
			constrainFormats(child)
		}
	}
	for _, key := range []string{"allOf", "anyOf", "oneOf", "prefixItems"} {
		for _, v := range list(schema[key]) {
			constrainFormats(obj(v))
		}
	}
}

var backticks = regexp.MustCompile("`([^`]+)`")
var operators = map[string]bool{"eq": true, "not_eq": true, "lt": true, "lteq": true, "gt": true, "gteq": true, "in": true, "not_in": true, "start_with": true}

func filterSchema(native object) object {
	description, _ := native["description"].(string)
	branches := []any{}
	for _, line := range strings.Split(description, "\n") {
		a, z, ok := strings.Cut(line, ":")
		if !ok || !strings.HasPrefix(strings.TrimSpace(a), "-") {
			continue
		}
		fields, ops := []any{}, []any{}
		for _, m := range backticks.FindAllStringSubmatch(a, -1) {
			fields = append(fields, m[1])
		}
		for _, m := range backticks.FindAllStringSubmatch(z, -1) {
			if operators[m[1]] {
				ops = append(ops, m[1])
			}
		}
		if len(fields) == 0 || len(ops) == 0 {
			continue
		}
		branches = append(branches, object{"type": "object", "properties": object{"field": object{"enum": fields}, "operator": object{"enum": ops}, "value": filterValue()}, "required": []string{"field", "operator", "value"}, "additionalProperties": false})
	}
	condition := object{"type": "object", "properties": object{"field": object{"type": "string", "minLength": 1}, "operator": object{"enum": []string{"eq", "not_eq", "lt", "lteq", "gt", "gteq", "in", "not_in", "start_with"}}, "value": filterValue()}, "required": []string{"field", "operator", "value"}, "additionalProperties": false}
	if len(branches) > 0 {
		condition["anyOf"] = branches
	}
	condition["allOf"] = []any{object{"if": object{"properties": object{"operator": object{"enum": []string{"in", "not_in"}}}, "required": []string{"operator"}}, "then": object{"properties": object{"value": object{"type": "array", "minItems": 1}}}, "else": object{"properties": object{"value": object{"not": object{"type": "array"}}}}}}
	return object{"anyOf": []any{object{"type": "array", "items": condition, "minItems": 1}, object{"type": "string", "pattern": `^\s*\[`, "description": "JSON text encoding the same filter array; the provider validates its contents."}}, "description": description}
}
func filterValue() object {
	return object{"anyOf": []any{object{"type": []string{"string", "number", "boolean", "null"}}, object{"type": "array", "items": object{"type": []string{"string", "number", "boolean", "null"}}}}}
}
func sortSchema(s object) {
	description, _ := s["description"].(string)
	_, fields, ok := strings.Cut(description, "Available fields")
	if !ok {
		return
	}
	values := []string{}
	for _, m := range backticks.FindAllStringSubmatch(fields, -1) {
		values = append(values, m[1], "-"+m[1])
	}
	if len(values) > 0 {
		s["enum"] = values
	}
}
