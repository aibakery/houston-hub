package helpschema

import (
	"context"
	"encoding/json"
	"strings"
	"testing"

	"github.com/aibakery/houston-hub/manifest"
	"github.com/aibakery/houston-hub/tools/conformance"
)

// Check semantic composition with Houston's production JSON Schema validator,
// including closed referenced body branches and closed nested objects.
func TestFlattenedParametersPreserveBodyValidation(t *testing.T) {
	var spec object
	err := json.Unmarshal([]byte(`{"components":{"schemas":{
  "payload":{"type":"object","properties":{"title":{"type":"string"}},"required":["title"],"additionalProperties":false},
  "body":{"oneOf":[
   {"type":"object","properties":{"type":{"const":"create"},"payload":{"$ref":"#/components/schemas/payload"}},"required":["type","payload"],"additionalProperties":false},
   {"type":"object","properties":{"type":{"const":"delete"}},"required":["type"],"additionalProperties":false}
  ]}
 }}}`), &spec)
	if err != nil {
		t.Fatal(err)
	}
	op := object{"parameters": []any{object{"in": "path", "name": "page_id", "required": true, "schema": object{"type": "string", "minLength": 1}}},
		"requestBody": object{"content": object{"application/json": object{"schema": object{"$ref": "#/components/schemas/body", "description": "Body with a ref sibling."}}}}}
	schema, err := Input(spec, op, "/pages/{page_id}", nil, nil, true)
	if err != nil {
		t.Fatal(err)
	}
	m, err := manifest.Parse([]byte(`{"schema_version":1,"name":"Schema fixture","files":["main.luau"],"proxy":[{"match":{"protocol":"http","host":["example.com"]},"action":{}}]}`))
	if err != nil {
		t.Fatal(err)
	}
	cases := []struct {
		name, example string
		valid         bool
	}{
		{"create", `{"page_id":"page","type":"create","payload":{"title":"Roadmap"}}`, true},
		{"delete", `{"page_id":"page","type":"delete"}`, true},
		{"missing path", `{"type":"delete"}`, false},
		{"missing discriminator", `{"page_id":"page","payload":{"title":"Roadmap"}}`, false},
		{"missing body", `{"page_id":"page","type":"create"}`, false},
		{"extra body key", `{"page_id":"page","type":"delete","extra":true}`, false},
		{"nested URL field", `{"page_id":"page","type":"create","payload":{"title":"Roadmap","page_id":"nested"}}`, false},
		{"nested required", `{"page_id":"page","type":"create","payload":{}}`, false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			var example any
			if err := json.Unmarshal([]byte(tc.example), &example); err != nil {
				t.Fatal(err)
			}
			schema["examples"] = []any{example}
			raw, err := json.Marshal(schema)
			if err != nil {
				t.Fatal(err)
			}
			source := `return {save=function(input) return input end,help={text="Schema fixture",functions={save={description="Save a page.",inputSchema=json.decode([====[` + string(raw) + `]====])}}}}`
			_, err = conformance.CheckCatalog(context.Background(), "", *m, map[string]string{"main.luau": source}, map[string]string{"example.luau": `return {scenario={},run=function(c) local result=fixture.example("save");assert(result.page_id=="page") end}`})
			if tc.valid && err != nil {
				t.Fatal(err)
			}
			if !tc.valid && (err == nil || !strings.Contains(err.Error(), "inputSchema.examples[0]")) {
				t.Fatalf("invalid input should fail in the generated example: %v", err)
			}
		})
	}
}

func TestOpenAPI30NullableAndExclusiveBounds(t *testing.T) {
	schema := object{"type": "object", "properties": object{
		"amount": object{"type": "number", "minimum": 0, "exclusiveMinimum": true},
		"note":   object{"type": "string", "nullable": true},
	}, "default": object{"nullable": true, "exclusiveMinimum": true, "minimum": 0}}
	converted := obj(normalize30(schema))
	props := obj(converted["properties"])
	if obj(props["amount"])["exclusiveMinimum"] != 0 || obj(converted["default"])["nullable"] != true {
		t.Fatalf("conversion changed a data literal or exclusive bound: %#v", converted)
	}
	m, err := manifest.Parse([]byte(`{"schema_version":1,"name":"OpenAPI conversion fixture","files":["main.luau"],"proxy":[{"match":{"protocol":"http","host":["example.com"]},"action":{}}]}`))
	if err != nil {
		t.Fatal(err)
	}
	for _, tc := range []struct {
		name, input string
		valid       bool
	}{
		{"null note", `{"amount":12.34,"note":null}`, true},
		{"text note", `{"amount":12.34,"note":"Invoice"}`, true},
		{"zero amount", `{"amount":0}`, false},
		{"invalid note", `{"note":7}`, false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			var input any
			if err := json.Unmarshal([]byte(tc.input), &input); err != nil {
				t.Fatal(err)
			}
			converted["examples"] = []any{input}
			raw, err := json.Marshal(converted)
			if err != nil {
				t.Fatal(err)
			}
			source := `return {save=function(input) return input end,help={text="Update metadata",functions={save={description="Save metadata.",inputSchema=json.decode([====[` + string(raw) + `]====])}}}}`
			_, err = conformance.CheckCatalog(context.Background(), "", *m, map[string]string{"main.luau": source}, map[string]string{"example.luau": `return {scenario={},run=function() fixture.example("save") end}`})
			if tc.valid && err != nil {
				t.Fatal(err)
			}
			if !tc.valid && (err == nil || !strings.Contains(err.Error(), "inputSchema.examples")) {
				t.Fatalf("expected example validation failure: %v", err)
			}
		})
	}
}
