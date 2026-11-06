package main

import (
	"context"
	"encoding/json"
	"strings"
	"testing"

	"github.com/aibakery/houston-hub/manifest"
	"github.com/aibakery/houston-hub/tools/conformance"
)

func TestDiscoveryConversion(t *testing.T) {
	var source object
	if err := json.Unmarshal([]byte(`{"id":"Node","type":"object","properties":{"count":{"type":"integer","minimum":"1","maximum":"20","default":"5","required":true,"format":"int32"},"children":{"type":"array","items":{"$ref":"Node"}},"tags":{"type":"string","repeated":true},"free":{"type":"any"}}}`), &source); err != nil {
		t.Fatal(err)
	}
	c := converter{schemas: object{"Node": source}, definitions: object{}}
	result, err := c.schema(object{"$ref": "Node"})
	if err != nil {
		t.Fatal(err)
	}
	if obj(result)["$ref"] != "#/$defs/Node" || len(c.definitions) != 1 {
		t.Fatalf("recursive reference: %#v %#v", result, c.definitions)
	}
	node := obj(c.definitions["Node"])
	p := obj(node["properties"])
	count := obj(p["count"])
	if count["minimum"] != float64(1) || count["maximum"] != float64(20) || count["default"] != float64(5) || count["x-google-format"] != "int32" {
		t.Fatalf("numeric parameter: %#v", count)
	}
	if node["required"].([]string)[0] != "count" || obj(p["tags"])["type"] != "array" || obj(obj(p["tags"])["items"])["type"] != "string" {
		t.Fatalf("presence/repetition: %#v", node)
	}
	if _, err := c.schema(object{"$ref": "Missing"}); err == nil {
		t.Fatal("unresolved provider reference accepted")
	}
}

func TestGeneratedGoogleSchemasValidateExamples(t *testing.T) {
	m, err := manifest.Parse([]byte(`{"schema_version":1,"name":"Google schema fixture","files":["main.luau"],"proxy":[{"match":{"protocol":"http","host":["example.com"]},"action":{}}]}`))
	if err != nil {
		t.Fatal(err)
	}
	var schemas object
	if err := json.Unmarshal([]byte(`{
		"Request":{"id":"Request","type":"object","properties":{"insertText":{"$ref":"InsertTextRequest"},"deleteTab":{"$ref":"DeleteTabRequest"}}},
		"InsertTextRequest":{"id":"InsertTextRequest","type":"object","properties":{"text":{"type":"string"},"location":{"$ref":"Location"},"endOfSegmentLocation":{"type":"object"}}},
		"Location":{"id":"Location","type":"object","properties":{"index":{"type":"integer"},"tabId":{"type":"string"}}},
		"DeleteTabRequest":{"id":"DeleteTabRequest","type":"object","properties":{"tabId":{"type":"string"}}}
	}`), &schemas); err != nil {
		t.Fatal(err)
	}
	c := converter{api: "gdocs", schemas: schemas, definitions: object{}}
	request, err := c.schema(object{"$ref": "Request"})
	if err != nil {
		t.Fatal(err)
	}
	schema := object{"type": "object", "properties": object{"request": request}, "required": []string{"request"}, "$defs": c.definitions}
	for _, tc := range []struct {
		name, request string
		valid         bool
	}{
		{"indexed insertion", `{"insertText":{"text":"Hello","location":{"index":1}}}`, true},
		{"append insertion", `{"insertText":{"text":"Hello","endOfSegmentLocation":{}}}`, true},
		{"missing command", `{}`, false},
		{"two commands", `{"insertText":{"text":"Hello","endOfSegmentLocation":{}},"deleteTab":{"tabId":"t.1"}}`, false},
		{"missing text", `{"insertText":{"endOfSegmentLocation":{}}}`, false},
		{"missing location", `{"insertText":{"text":"Hello"}}`, false},
		{"two locations", `{"insertText":{"text":"Hello","location":{"index":1},"endOfSegmentLocation":{}}}`, false},
		{"missing index", `{"insertText":{"text":"Hello","location":{"tabId":"t.1"}}}`, false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			var example object
			if err := json.Unmarshal([]byte(`{"request":`+tc.request+`}`), &example); err != nil {
				t.Fatal(err)
			}
			schema["examples"] = []any{example}
			raw, err := json.Marshal(schema)
			if err != nil {
				t.Fatal(err)
			}
			source := `return {edit=function(input) return input end, help={text="Document editing", functions={edit={description="Apply one Google Docs command.",inputSchema=json.decode([====[` + string(raw) + `]====])}}}}`
			_, err = conformance.CheckCatalog(context.Background(), "", *m, map[string]string{"main.luau": source},
				map[string]string{"example.luau": `return {scenario={},run=function() local result=fixture.example("edit");assert(type(result.request)=="table") end}`})
			if tc.valid && err != nil {
				t.Fatal(err)
			}
			if !tc.valid && (err == nil || !strings.Contains(err.Error(), "inputSchema.examples")) {
				t.Fatalf("invalid command should fail schema validation: %v", err)
			}
		})
	}
}

func TestDocsRequestConstraints(t *testing.T) {
	c := converter{api: "gdocs", schemas: object{}, definitions: object{}}
	value, err := c.schema(object{"id": "InsertTextRequest", "type": "object", "properties": object{
		"text": object{"type": "string"}, "location": object{"type": "object"}, "endOfSegmentLocation": object{"type": "object"},
	}})
	if err != nil {
		t.Fatal(err)
	}
	schema := obj(value)
	if schema["required"].([]string)[0] != "text" || len(schema["oneOf"].([]any)) != 2 {
		t.Fatalf("insertion constraints: %#v", schema)
	}
	value, err = c.schema(object{"id": "Request", "type": "object", "properties": object{"insertText": object{"type": "object"}, "deleteTab": object{"type": "object"}}})
	if err != nil || len(obj(value)["oneOf"].([]any)) != 2 {
		t.Fatalf("command union: %#v, %v", value, err)
	}
	if _, err := c.schema(object{"id": "InsertTextRequest", "type": "object", "properties": object{}}); err == nil {
		t.Fatal("provider drift in a constrained field accepted")
	}
}
