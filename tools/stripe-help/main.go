// Command stripe-help derives native form schemas from the Stripe OpenAPI
// release matching the API version pinned in the connector.
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
func must(e error) {
	if e != nil {
		panic(e)
	}
}

var placeholders = regexp.MustCompile(`\{([^}]+)\}`)
var requiredFields = regexp.MustCompile(`required = \{([^}]+)\}`)
var quoted = regexp.MustCompile(`"([^"]+)"`)

func required(s object, names ...string) {
	a, _ := s["required"].([]any)
	for _, n := range names {
		if !slices.Contains(a, any(n)) {
			a = append(a, n)
		}
	}
	s["required"] = a
}

// Strip SDK-only annotations without touching literal defaults or examples.
// Null is never a form value in this transport; clearing uses empty strings.
func form(v any) {
	s := obj(v)
	if s == nil {
		return
	}
	delete(s, "nullable")
	for k := range s {
		if strings.HasPrefix(k, "x-") {
			delete(s, k)
		}
	}
	for _, k := range []string{"properties", "$defs", "patternProperties"} {
		for _, c := range obj(s[k]) {
			form(c)
		}
	}
	for _, k := range []string{"items", "additionalProperties", "not", "if", "then", "else"} {
		form(s[k])
	}
	for _, k := range []string{"allOf", "oneOf", "anyOf", "prefixItems"} {
		a, _ := s[k].([]any)
		for _, c := range a {
			form(c)
		}
	}
}
func main() {
	snapshot := flag.String("openapi", "", "local https://raw.githubusercontent.com/stripe/openapi/v2592/openapi/spec3.sdk.json snapshot")
	root := flag.String("root", ".", "Hub root")
	flag.Parse()
	raw, e := os.ReadFile(*snapshot)
	must(e)
	var spec object
	must(json.Unmarshal(raw, &spec))
	code, e := os.ReadFile(filepath.Join(*root, "connectors/stripe/connector.luau"))
	must(e)
	version, _ := obj(spec["info"])["version"].(string)
	if version == "" || !strings.Contains(string(code), `["Stripe-Version"] = {"`+version+`"}`) {
		panic("OpenAPI version does not match connector")
	}
	b, e := os.ReadFile(filepath.Join(*root, "tools/stripe-help/examples.json"))
	must(e)
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
	for _, ep := range helpschema.Endpoints(string(code)) {
		n, ok := routes[ep.Method+" "+placeholders.ReplaceAllString(ep.Path, "{}")]
		download, upload := ep.Name == "downloadFile", ep.Name == "uploadFile"
		if !ok && !download {
			panic("missing native route " + ep.Name)
		}
		body := object{"type": "object", "properties": object{}, "additionalProperties": false}
		for _, content := range obj(obj(n.op["requestBody"])["content"]) {
			if s := obj(obj(content)["schema"]); s != nil {
				body = s
			}
		}
		props := obj(body["properties"])
		params, _ := n.op["parameters"].([]any)
		for _, value := range params {
			p := obj(value)
			if p["in"] == "query" {
				name := p["name"].(string)
				props[name] = p["schema"]
				if p["description"] != nil {
					obj(props[name])["description"] = p["description"]
				}
				if p["required"] == true {
					required(body, name)
				}
			}
		}
		for _, name := range placeholders.FindAllStringSubmatch(ep.Path, -1) {
			props[name[1]] = object{"type": "string", "minLength": 1, "pattern": "^[A-Za-z0-9_-]+$"}
			required(body, name[1])
		}
		if ep.Method == "POST" {
			props["idempotency_key"] = object{"type": "string", "minLength": 1, "maxLength": 255, "pattern": `^[^\u0000-\u001f\u007f]+$`, "description": "Idempotency-Key header. Reuse only for an identical intended request; Stripe can prune keys after 24 hours."}
		}
		if upload || download {
			props["path"] = object{"type": "string", "minLength": 1, "description": "Houston session file path; uploads read this file, downloads save here and return a signed Houston URL."}
			required(body, "path")
		}
		if upload {
			delete(props, "file")
			a := body["required"].([]any)
			body["required"] = slices.DeleteFunc(a, func(v any) bool { return v == "file" })
			props["filename"] = object{"type": "string", "minLength": 1, "pattern": `^[^/\\"\u0000-\u001f\u007f]+$`, "description": "Defaults to the basename of path."}
			props["content_type"] = object{"type": "string", "minLength": 1, "pattern": `^[^\u0000-\u001f\u007f]+$`, "default": "application/octet-stream"}
		}
		if m := requiredFields.FindStringSubmatch(ep.Definition); len(m) > 0 {
			for _, name := range quoted.FindAllStringSubmatch(m[1], -1) {
				required(body, name[1])
				p := obj(props[name[1]])
				if p["type"] == "string" {
					p["minLength"] = 1
				}
			}
		}
		if p := obj(props["limit"]); p != nil {
			p["minimum"], p["maximum"], p["default"] = 1, 100, 10
		}
		if props["starting_after"] != nil && props["ending_before"] != nil {
			body["not"] = object{"required": []string{"starting_after", "ending_before"}}
		}
		form(body)
		op := object{"requestBody": object{"content": object{"application/json": object{"schema": body}}}}
		schema, e := helpschema.Input(spec, op, "", nil, nil, true)
		must(e)
		defs := schema["$defs"]
		schema, e = helpschema.FlattenObject(obj(schema["allOf"].([]any)[0]))
		must(e)
		if defs != nil {
			schema["$defs"] = defs
		}
		if ep.Name == "createPrice" {
			schema["oneOf"] = []any{object{"required": []string{"product"}}, object{"required": []string{"product_data"}}}
		}
		supplement(ep.Name, schema)
		if len(examples[ep.Name]) == 0 {
			panic("missing examples " + ep.Name)
		}
		schema["examples"] = examples[ep.Name]
		schemas[ep.Name] = schema
		cases[ep.Name] = object{"method": ep.Method, "path": ep.Path, "upload": upload, "download": download}
	}
	if len(schemas) != len(examples) {
		panic("orphan examples")
	}
	directory := filepath.Join(*root, "connectors/stripe/lib")
	must(os.MkdirAll(directory, 0755))
	for name, value := range map[string]any{"schemas": schemas, "example-routes": cases} {
		// Keep this generated native reference under the runtime's 1 MiB
		// module limit without dropping descriptions or nested constraints.
		b, e = json.Marshal(value)
		must(e)
		header := fmt.Sprintf("-- Code generated by go run ./tools/stripe-help -openapi <snapshot>; DO NOT EDIT.\n-- Source: https://raw.githubusercontent.com/stripe/openapi/v2592/openapi/spec3.sdk.json\n-- SHA-256: %x\n-- Authored examples: tools/stripe-help/examples.json\nreturn json.decode([====[\n", sha256.Sum256(raw))
		must(os.WriteFile(filepath.Join(directory, name+".luau"), []byte(header+string(b)+"\n]====])\n"), 0644))
	}
}
