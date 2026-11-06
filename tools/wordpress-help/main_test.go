package main

import (
	"context"
	"encoding/json"
	"reflect"
	"strings"
	"testing"

	"github.com/aibakery/houston-hub/manifest"
	"github.com/aibakery/houston-hub/tools/conformance"
)

func TestResourceDeclarations(t *testing.T) {
	source := `local ALL = {"list", "create", "batch"}
local READ = {"list"}
local RESOURCES = {
 {one = "Product", many = "Products", path = "/products", ops = ALL, doc = "products"},
 {one = "Note", many = "Notes", path = "/orders/{order_id}/notes", ops = {"list", "create"}, doc = "notes"},
}
local OPERATIONS = {
 list = {many = true, method = "GET", suffix = ""},
 create = {many = false, method = "POST", suffix = ""},
 batch = {many = true, method = "POST", suffix = "/batch"},
}
local endpoints = {
 search = {method = "GET", path = "/search", doc = "search"},
}`
	got, err := declarations(source)
	want := []endpoint{{"batchProducts", "POST", "/products/batch", "products"}, {"createNote", "POST", "/orders/{order_id}/notes", "notes"},
		{"createProduct", "POST", "/products", "products"}, {"listNotes", "GET", "/orders/{order_id}/notes", "notes"},
		{"listProducts", "GET", "/products", "products"}, {"search", "GET", "/search", "search"}}
	if err != nil || !reflect.DeepEqual(got, want) {
		t.Fatalf("declarations: %#v, %v", got, err)
	}
	if _, err := declarations("local unrelated = {}"); err == nil {
		t.Fatal("missing operation table accepted")
	}
}

func TestNativeSchemaConversionPreservesData(t *testing.T) {
	value := object{"type": "object", "properties": object{"item": object{"type": "string", "required": true}},
		"default": object{"required": false, "context": "view"}, "oneOf": []any{object{"required": []any{"item"}}}}
	converted := obj(schema(value))
	if !reflect.DeepEqual(converted["default"], value["default"]) || !reflect.DeepEqual(converted["required"], []string{"item"}) ||
		!reflect.DeepEqual(converted["oneOf"], value["oneOf"]) {
		t.Fatalf("schema conversion changed data or presence rules: %#v", converted)
	}
}

func TestWooBatchSchemasValidateNestedInputs(t *testing.T) {
	id, text := object{"type": "integer", "minimum": 0}, object{"type": "string", "minLength": 1}
	endpoints := []endpoint{{"batchItems", "POST", "/groups/{group_id}/items/batch", "items"},
		{"createItem", "POST", "/groups/{group_id}/items", "items"}, {"updateItem", "PUT", "/groups/{group_id}/items/{id}", "items"},
		{"deleteItem", "DELETE", "/groups/{group_id}/items/{id}", "items"}}
	records := object{
		"batchItems": object{"type": "object", "properties": object{"group_id": id, "name": text}},
		"createItem": object{"type": "object", "properties": object{"group_id": id, "name": text}, "required": []string{"group_id", "name"}},
		"updateItem": object{"type": "object", "properties": object{"group_id": id, "id": id, "name": text}, "required": []string{"group_id", "id"}},
		"deleteItem": object{"type": "object", "properties": object{"group_id": id, "id": id}, "required": []string{"group_id", "id"}},
	}
	if err := batches(endpoints, records); err != nil {
		t.Fatal(err)
	}
	m, err := manifest.Parse([]byte(`{"schema_version":1,"name":"Woo batch schema fixture","files":["main.luau"],"proxy":[{"match":{"protocol":"http","host":["example.com"]},"action":{}}]}`))
	if err != nil {
		t.Fatal(err)
	}
	for _, tc := range []struct {
		name, input string
		valid       bool
	}{
		{"mixed batch", `{"group_id":0,"create":[{"name":"New"}],"update":[{"id":9,"name":"Renamed"}],"delete":[8]}`, true},
		{"partial update", `{"group_id":2,"update":[{"id":9}]}`, true},
		{"missing parent", `{"create":[{"name":"New"}]}`, false},
		{"missing create field", `{"group_id":2,"create":[{}]}`, false},
		{"missing update ID", `{"group_id":2,"update":[{"name":"New"}]}`, false},
		{"invalid delete ID", `{"group_id":2,"delete":[{"id":9}]}`, false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			var example object
			if err := json.Unmarshal([]byte(tc.input), &example); err != nil {
				t.Fatal(err)
			}
			input := obj(records["batchItems"])
			input["examples"] = []any{example}
			raw, err := json.Marshal(input)
			if err != nil {
				t.Fatal(err)
			}
			source := `return {batch=function(input) return input end,help={text="Batch editing",functions={batch={description="Create, update and delete items in a group.",inputSchema=json.decode([====[` + string(raw) + `]====])}}}}`
			_, err = conformance.CheckCatalog(context.Background(), "", *m, map[string]string{"main.luau": source},
				map[string]string{"example.luau": `return {scenario={},run=function() assert(fixture.example("batch").group_id~=nil) end}`})
			if tc.valid && err != nil {
				t.Fatal(err)
			}
			if !tc.valid && (err == nil || !strings.Contains(err.Error(), "inputSchema.examples")) {
				t.Fatalf("invalid batch should fail schema validation: %v", err)
			}
		})
	}
}
