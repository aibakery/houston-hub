package main

import (
	"context"
	"encoding/json"
	"strings"
	"testing"

	"github.com/aibakery/houston-hub/manifest"
	"github.com/aibakery/houston-hub/tools/conformance"
	"github.com/vektah/gqlparser/v2/ast"
	"github.com/vektah/gqlparser/v2/parser"
)

func TestGraphQLInputsRetainRequiredNullableListsAndRecursion(t *testing.T) {
	doc, err := parser.ParseSchema(&ast.Source{Input: `
enum Status { started completed }
input Filter { and: [Filter!] status: Status }
input Input { title: String! labels: [String!]! filter: Filter priority: Int! = 2 }
`})
	if err != nil {
		t.Fatal(err)
	}
	g := generator{types: map[string]*ast.Definition{}, defs: object{}}
	for _, d := range doc.Definitions {
		g.types[d.Name] = d
	}
	input, err := g.named("Input")
	if err != nil {
		t.Fatal(err)
	}
	schema := object{"type": "object", "properties": object{"input": input}, "required": []string{"input"}, "$defs": g.defs}
	m, err := manifest.Parse([]byte(`{"schema_version":1,"name":"GraphQL inputs","files":["main.luau"],"proxy":[{"match":{"protocol":"http","host":["example.com"]},"action":{}}]}`))
	if err != nil {
		t.Fatal(err)
	}
	for _, tc := range []struct {
		name, input string
		valid       bool
	}{
		{"recursive filter and default", `{"title":"Fix login","labels":["bug"],"filter":{"and":[{"status":"started"},{"and":[{"status":"completed"}]}]}}`, true},
		{"nullable filter and scalar list coercion", `{"title":"Fix login","labels":"bug","filter":null}`, true},
		{"empty list", `{"title":"Fix login","labels":[]}`, true},
		{"provider extension", `{"title":"Fix login","labels":[],"newProviderField":true}`, true},
		{"required nested title", `{"labels":[]}`, false},
		{"nonnullable title", `{"title":null,"labels":[]}`, false},
		{"nonnullable list", `{"title":"Fix login","labels":null}`, false},
		{"nonnullable list item", `{"title":"Fix login","labels":[null]}`, false},
		{"enum inside recursion", `{"title":"Fix login","labels":[],"filter":{"and":[{"status":"other"}]}}`, false},
		{"default does not permit null", `{"title":"Fix login","labels":[],"priority":null}`, false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			var value any
			if err := json.Unmarshal([]byte(tc.input), &value); err != nil {
				t.Fatal(err)
			}
			schema["examples"] = []any{object{"input": value}}
			raw, err := json.Marshal(schema)
			if err != nil {
				t.Fatal(err)
			}
			source := `return {save=function(input) return input end,help={text="Input fixture",functions={save={description="Save input.",inputSchema=json.decode([====[` + string(raw) + `]====])}}}}`
			_, err = conformance.CheckCatalog(context.Background(), "", *m, map[string]string{"main.luau": source}, map[string]string{"example.luau": `return {scenario={},run=function(c) assert(fixture.example("save").input.title=="Fix login") end}`})
			if tc.valid && err != nil {
				t.Fatal(err)
			}
			if !tc.valid && (err == nil || !strings.Contains(err.Error(), "inputSchema.examples[0]")) {
				t.Fatalf("invalid input should fail in the generated example: %v", err)
			}
		})
	}
}
