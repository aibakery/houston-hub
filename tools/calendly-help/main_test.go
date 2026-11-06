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

func TestExampleRequestUsesConnectorWireConvention(t *testing.T) {
	input := object{"event": "https://api.calendly.com/scheduled_events/E1", "action": []any{"Add", "Remove"}, "reason": "A change", "optional": nil}
	ep := endpoint{"cancel", "POST", "/scheduled_events/{event}/cancellation", []string{"action", "optional"}, nil}
	want := object{"method": "POST", "url": "https://api.calendly.com/scheduled_events/E1/cancellation?action=Add,Remove", "body": object{"reason": "A change"}}
	if got := exampleRequest(ep, input); !reflect.DeepEqual(got, want) {
		t.Fatalf("request: %#v", got)
	}
	if input["event"] != "https://api.calendly.com/scheduled_events/E1" || input["action"] == nil {
		t.Fatal("modified caller input")
	}
}

func TestContactRulesValidateRealInput(t *testing.T) {
	m, err := manifest.Parse([]byte(`{"schema_version":1,"name":"Contact schema fixture","files":["main.luau"],"proxy":[{"match":{"protocol":"http","host":["example.com"]},"action":{}}]}`))
	if err != nil {
		t.Fatal(err)
	}
	for _, tc := range []struct {
		name, input string
		valid       bool
	}{
		{"partial update", `{"contact":"C1","company":"ExampleCo"}`, true},
		{"primary email", `{"contact":"C1","emails":[{"email":"ana@example.com","is_primary":true}]}`, true},
		{"two primary emails", `{"contact":"C1","emails":[{"email":"ana@example.com","is_primary":true},{"email":"work@example.com","is_primary":true}]}`, false},
		{"no primary email", `{"contact":"C1","emails":[{"email":"ana@example.com","is_primary":false}]}`, false},
		{"missing change", `{"contact":"C1"}`, false},
		{"unknown field", `{"contact":"C1","typo":"ExampleCo"}`, false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			email := object{"type": "object", "properties": object{"email": object{"type": "string", "format": "email"}, "is_primary": object{"type": "boolean"}}, "required": []string{"email", "is_primary"}}
			schema := object{"type": "object", "required": []string{"contact"}, "properties": object{"contact": object{"type": "string"}}, "allOf": []any{object{"type": "object", "properties": object{"company": object{"type": "string"}, "emails": object{"type": "array", "items": email}, "phone_numbers": object{"type": "array", "items": object{"type": "object"}}}}}}
			supplement("updateContact", schema)
			var input object
			if err := json.Unmarshal([]byte(tc.input), &input); err != nil {
				t.Fatal(err)
			}
			schema["examples"] = []any{input}
			raw, err := json.Marshal(schema)
			if err != nil {
				t.Fatal(err)
			}
			source := `return {update=function(input) return input end,help={text="Contact editing",functions={update={description="Update a contact.",inputSchema=json.decode([====[` + string(raw) + `]====])}}}}`
			_, err = conformance.CheckCatalog(context.Background(), "", *m, map[string]string{"main.luau": source}, map[string]string{"example.luau": `return {scenario={},run=function() assert(fixture.example("update").contact=="C1") end}`})
			if tc.valid && err != nil {
				t.Fatal(err)
			}
			if !tc.valid && (err == nil || !strings.Contains(err.Error(), "inputSchema.examples")) {
				t.Fatalf("expected example validation failure: %v", err)
			}
		})
	}
}
