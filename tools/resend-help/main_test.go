package main

import (
	"context"
	"encoding/json"
	"os"
	"strings"
	"testing"

	"github.com/aibakery/houston-hub/manifest"
	"github.com/aibakery/houston-hub/tools/conformance"
)

func TestNativeSchemasAndConnectorTransport(t *testing.T) {
	b, err := os.ReadFile("../../connectors/resend/lib/schemas.luau")
	if err != nil {
		t.Fatal(err)
	}
	modules := map[string]string{"lib/schemas.luau": string(b)}
	m, err := manifest.Parse([]byte(`{"schema_version":1,"name":"Resend schema fixture","files":["main.luau"],"proxy":[{"match":{"protocol":"http","host":["example.com"]},"action":{}}]}`))
	if err != nil {
		t.Fatal(err)
	}
	for _, tc := range []struct {
		name, operation, input string
		valid                  bool
	}{
		{"template defaults", "sendEmail", `{"to":"ana@example.com","template":{"id":"welcome"}}`, true},
		{"template with literal body", "sendEmail", `{"to":"ana@example.com","template":{"id":"welcome"},"html":"<p>Hello</p>"}`, false},
		{"literal email", "sendEmail", `{"to":"ana@example.com","from":"hello@example.com","subject":"Hello","text":"Hi"}`, true},
		{"literal email needs content", "sendEmail", `{"to":"ana@example.com","from":"hello@example.com","subject":"Hello"}`, false},
		{"batch", "sendBatchEmails", `{"emails":[{"to":"ana@example.com","template":{"id":"welcome"}}],"idempotency_key":"batch-1"}`, true},
		{"batch attachments", "sendBatchEmails", `{"emails":[{"to":"ana@example.com","template":{"id":"welcome"},"attachments":[{"path":"https://example.com/a.pdf"}]}]}`, false},
		{"CSV import", "createContactImport", `{"path":"contacts.csv","column_map":{"email":"Email"},"topics":[{"id":"topic-1","subscription":"opt_out"}]}`, true},
		{"CSV import needs file", "createContactImport", `{"column_map":{"email":"Email"}}`, false},
		{"query array", "listThreads", `{"inbox_id":"support@example.com","folders":["inbox"],"read":false}`, true},
		{"query CSV", "listThreads", `{"inbox_id":"support@example.com","folders":"inbox,archive"}`, true},
		{"query null", "listThreads", `{"inbox_id":"support@example.com","read":null}`, false},
		{"event email", "sendEvent", `{"event":"user.created","email":"ana@example.com","payload":{"plan":"pro"}}`, true},
		{"event ambiguous contact", "sendEvent", `{"event":"user.created","email":"ana@example.com","contact_id":"00000000-0000-4000-8000-000000000001"}`, false},
		{"event payload types", "createEvent", `{"name":"user.created","schema":{"plan":"string","joined_at":"date"}}`, true},
		{"event invalid payload type", "createEvent", `{"name":"user.created","schema":{"plan":"object"}}`, false},
		{"automation nested condition", "createAutomation", `{"name":"Welcome","steps":[{"key":"start","type":"trigger","config":{"event_name":"user.created"}},{"key":"check","type":"condition","config":{"type":"and","rules":[{"type":"rule","field":"payload.amount","operator":"gt","value":10}]}}],"connections":[{"from":"start","to":"check"}]}`, true},
		{"automation wrong config", "createAutomation", `{"name":"Welcome","steps":[{"key":"start","type":"trigger","config":{"duration":"1 hour"}}],"connections":[]}`, false},
		{"automation condition type", "createAutomation", `{"name":"Welcome","steps":[{"key":"start","type":"trigger","config":{"event_name":"user.created"}},{"key":"check","type":"condition","config":{"type":"rule","field":"payload.amount","operator":"gt","value":"ten"}}],"connections":[{"from":"start","to":"check"}]}`, false},
		{"automation patch graph pair", "updateAutomation", `{"automation_id":"automation-1","steps":[{"key":"start","type":"trigger","config":{"event_name":"user.created"}}]}`, false},
		{"automation disable", "updateAutomation", `{"automation_id":"automation-1","status":"disabled"}`, true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			operation, _ := json.Marshal(tc.operation)
			modules["main.luau"] = `local schema=require("lib/schemas.luau")[` + string(operation) + `];schema.examples={json.decode([====[` + tc.input + `]====])};return {invoke=function(input) return input end,help={text="Schema fixture",functions={invoke={description="Native input",inputSchema=schema}}}}`
			_, err := conformance.CheckCatalog(context.Background(), "", *m, modules, map[string]string{"example.luau": `return {scenario={},run=function(c) assert(type(fixture.example("invoke"))=="table") end}`})
			if tc.valid && err != nil {
				t.Fatal(err)
			}
			if !tc.valid && (err == nil || !strings.Contains(err.Error(), "inputSchema.examples[0]")) {
				t.Fatalf("invalid input should fail schema validation: %v", err)
			}
		})
	}
}
