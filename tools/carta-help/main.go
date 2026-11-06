// Command carta-help turns public Carta documentation operation snapshots into
// offline function schemas, preserving their native request field names.
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
func list(v any) []any {
	if a, ok := v.([]any); ok {
		return a
	}
	a := []any{}
	if names, ok := v.([]string); ok {
		for _, name := range names {
			a = append(a, name)
		}
	}
	return a
}
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
	connector := flag.String("connector", "carta", "carta or carta-crm")
	snapshots := flag.String("snapshots", "", "directory of public documentation operation JSON snapshots")
	fetch := flag.Bool("fetch", false, "download current public documentation snapshots before generation")
	root := flag.String("root", ".", "Hub root")
	flag.Parse()
	if *connector != "carta" && *connector != "carta-crm" {
		panic("unsupported connector")
	}
	if *snapshots == "" {
		panic("provide -snapshots directory")
	}
	if *fetch {
		must(fetchSnapshots(*connector, *snapshots))
	}
	code, e := os.ReadFile(filepath.Join(*root, "connectors", *connector, "connector.luau"))
	must(e)
	files, e := filepath.Glob(filepath.Join(*snapshots, "*.json"))
	must(e)
	routes := map[string]object{}
	hashes := map[string]string{}
	for _, file := range files {
		raw, e := os.ReadFile(file)
		must(e)
		var op object
		must(json.Unmarshal(raw, &op))
		key := strings.ToUpper(op["method"].(string)) + " " + placeholders.ReplaceAllString(op["path"].(string), "{}")
		if routes[key] != nil {
			panic("duplicate route " + key)
		}
		routes[key] = op
		hashes[key] = fmt.Sprintf("%x", sha256.Sum256(raw))
	}
	examples := map[string][]object{}
	b, e := os.ReadFile(filepath.Join(*root, "tools/carta-help", *connector+"-examples.json"))
	must(e)
	must(json.Unmarshal(b, &examples))
	schemas, cases := object{}, object{}
	var failures []string
	for _, ep := range helpschema.Endpoints(string(code)) {
		key := ep.Method + " " + placeholders.ReplaceAllString(ep.Path, "{}")
		op := obj(clone(routes[key]))
		if op == nil {
			failures = append(failures, "missing route "+ep.Name+" "+key)
			continue
		}
		if *connector == "carta-crm" {
			supplementCRM(op)
		}
		if *connector == "carta" && (ep.Name == "getStockSplitChanges" || ep.Name == "initiateSecondarySettlement") {
			body := obj(obj(obj(op["requestBody"])["content"])["application/json"])
			security := obj(obj(obj(obj(body["schema"])["properties"])["securities"])["items"])
			// The native reference describes these wire values in prose.
			obj(obj(security["properties"])["securityType"])["enum"] = []string{"option_grant", "certificate"}
			obj(obj(security["properties"])["securityId"])["pattern"] = "^[0-9]+$"
		}
		fields := func(key string) []string {
			value, err := helpschema.Fields(string(code), ep.Definition, key)
			must(err)
			return value
		}
		query, extra, required := fields("query"), fields("extra"), fields("required")
		pathFields := placeholders.FindAllStringSubmatch(ep.Path, -1)
		nativeFields := placeholders.FindAllStringSubmatch(op["path"].(string), -1)
		querySchemas := object{}
		params := list(op["parameters"])
		for _, raw := range params {
			p := obj(raw)
			name, _ := p["name"].(string)
			if p["in"] == "path" {
				for i, n := range nativeFields {
					if name == n[1] {
						p["name"] = pathFields[i][1]
						break
					}
				}
				pattern, max := "^[A-Za-z0-9_-]+$", 64
				if *connector == "carta-crm" {
					pattern, max = "^[A-Za-z0-9][A-Za-z0-9_.-]*$", 200
				}
				p["schema"] = object{"anyOf": []any{object{"type": "integer", "minimum": 0, "maximum": 9007199254740991}, object{"type": "string", "minLength": 1, "maxLength": max, "pattern": pattern}}}
				if p["description"] != nil {
					obj(p["schema"])["description"] = p["description"]
				}
			}
			if p["in"] == "query" && slices.Contains(query, name) {
				s := obj(p["schema"])
				if s == nil {
					panic("missing query schema " + ep.Name + " " + name)
				}
				if *connector == "carta-crm" {
					dateShapes(s)
				}
				if p["description"] != nil {
					s["description"] = p["description"]
				}
				if s["type"] == "array" {
					s["minItems"] = 1
					s = object{"anyOf": []any{s, s["items"]}}
				}
				if (*connector == "carta" && slices.Contains([]string{"fundIds", "partnerIds"}, name)) || (*connector == "carta-crm" && slices.Contains([]string{"fundCartaIds", "prospectPublicIds"}, name)) {
					s = object{"anyOf": []any{s, object{"type": "array", "minItems": 1, "items": object{"anyOf": []any{object{"type": "string", "minLength": 1}, object{"type": "integer", "minimum": 0, "maximum": 9007199254740991}}}}}, "description": "A comma-separated string or a nonempty array of IDs."}
				}
				querySchemas[name] = s
			}
		}
		for _, field := range extra {
			s := object{"type": "string", "minLength": 1, "description": "Houston session file path containing the OCF ZIP archive; streamed as the raw application/zip body."}
			params = append(params, object{"name": field, "in": "header", "schema": s})
		}
		op["parameters"] = params
		mandatory := []string{}
		for _, field := range required {
			if slices.Contains(query, field) || slices.Contains(extra, field) {
				mandatory = append(mandatory, field)
			}
		}
		body := (ep.Method == "POST" || ep.Method == "PATCH" || ep.Method == "PUT") && !strings.Contains(ep.Definition, "body = false")
		input, err := helpschema.Input(object{"openapi": "3.0.0"}, op, ep.Path, append(slices.Clone(query), extra...), mandatory, body)
		if err != nil {
			failures = append(failures, ep.Name+": "+err.Error())
			continue
		}
		for field, s := range querySchemas {
			obj(input["properties"])[field] = s
		}
		for _, field := range extra {
			obj(input["properties"])[field] = object{"type": "string", "minLength": 1, "description": "Houston session file path for the OCF ZIP archive."}
		}
		need := list(input["required"])
		for _, field := range required {
			if !slices.Contains(need, any(field)) {
				need = append(need, field)
			}
		}
		input["required"] = need
		if *connector == "carta" && ep.Name == "initiateSecondarySettlement" {
			input["if"] = object{"properties": object{"rightOfFirstRefusal": object{"properties": object{"outcome": object{"enum": []string{"WAIVED", "EXERCISED_BY_STAKEHOLDER"}}}}}}
			input["then"] = object{"required": []string{"buyerInformation"}}
		}
		if *connector == "carta" && ep.Name == "finalizeSecondarySettlement" {
			input["additionalProperties"] = false
		}
		if len(examples[ep.Name]) == 0 {
			panic("missing authored examples for " + ep.Name)
		}
		input["examples"] = examples[ep.Name]
		description, _ := op["description"].(string)
		schemas[ep.Name] = object{"inputSchema": input, "description": description}
		cases[ep.Name] = object{"method": ep.Method, "path": ep.Path, "query": query, "extra": extra, "body": body, "source": op["x-documentation-url"], "sha256": hashes[key]}
	}
	if len(failures) > 0 {
		panic(strings.Join(failures, "\n"))
	}
	if len(schemas) != len(examples) {
		panic("orphaned authored examples")
	}
	directory := filepath.Join(*root, "connectors", *connector, "lib")
	must(os.MkdirAll(directory, 0755))
	for name, value := range map[string]any{"help": schemas, "example-routes": cases} {
		b, e = json.MarshalIndent(value, "", "\t")
		must(e)
		header := fmt.Sprintf("-- Code generated by go run ./tools/carta-help -connector %s -snapshots <directory>; DO NOT EDIT.\n-- Native schemas from public docs.carta.com operation assets.\n-- Per-operation source URLs and snapshot hashes: lib/example-routes.luau.\n-- Authored examples: tools/carta-help/%s-examples.json\nreturn json.decode([====[\n", *connector, *connector)
		must(os.WriteFile(filepath.Join(directory, name+".luau"), []byte(header+string(b)+"\n]====])\n"), 0644))
	}
}
