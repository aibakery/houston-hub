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

func TestFastmailHelpCallForms(t *testing.T) {
	modules := map[string]string{}
	for _, name := range []string{"connector.luau", "lib/help.luau"} {
		b, err := os.ReadFile("../../connectors/fastmail/" + name)
		if err != nil {
			t.Fatal(err)
		}
		modules[name] = string(b)
	}
	source := modules["connector.luau"]
	raw, err := os.ReadFile("../../connectors/fastmail/houston.json")
	if err != nil {
		t.Fatal(err)
	}
	m, err := manifest.Parse(raw)
	if err != nil {
		t.Fatal(err)
	}
	for _, tc := range []struct {
		name, operation, input string
		valid                  bool
	}{
		{"zero args", "getProfile", `{}`, true},
		{"filtered page", "listMessages", `{"from":["a@example.com","b@example.com"],"maxResults":500}`, true},
		{"page bound", "listMessages", `{"maxResults":501}`, false},
		{"fractional page", "listMessages", `{"maxResults":1.5}`, false},
		{"page token", "listThreads", `{"pageToken":"20"}`, true},
		{"invalid token", "listThreads", `{"pageToken":"-1"}`, false},
		{"timestamp", "listMessages", `{"after":"2026-11-06T12:00:00Z"}`, true},
		{"native filter shape", "listMessages", `{"alias":{"email":"a@example.com"}}`, false},
		{"named message", "getMessage", `{"id":{"id":"m","bodyFormat":"html","maxBodyValueBytes":0}}`, true},
		{"positional message", "getMessage", `{"id":"m","opts":{"bodyFormat":"text"}}`, true},
		{"body format", "getMessage", `{"id":"m","opts":{"bodyFormat":"markdown"}}`, false},
		{"body bytes", "getMessage", `{"id":"m","opts":{"maxBodyValueBytes":-1}}`, false},
		{"empty batch", "getMessages", `{"input":{"ids":[]}}`, false},
		{"mixed ID batch", "getMessages", `{"input":{"ids":["a",{"id":"b"}]}}`, true},
		{"invalid batch ID", "getMessages", `{"input":[{"id":42}]}`, false},
		{"attachment named", "getAttachment", `{"input":{"messageId":"m","attachmentId":"b"}}`, true},
		{"attachment missing ID", "getAttachment", `{"input":{"messageId":"m"}}`, false},
		{"attachment positional", "getAttachment", `{"input":"m","attachment":"b","path":"downloads/file"}`, true},
		{"attachment conflicting forms", "getAttachment", `{"input":{"messageId":"m","attachmentId":"b"},"attachment":"c"}`, false},
		{"empty downloads", "getAttachments", `{"input":{"messageId":"m","items":[]}}`, true},
		{"download items required", "getAttachments", `{"input":"m"}`, false},
		{"envelope attachment metadata", "listAttachments", `{"message":{"id":"m","subject":"Receipt","attachments":[{"id":"b","inline":false}]}}`, true},
		{"move named", "moveMessages", `{"input":{"ids":["a","b"],"folder":"INBOX"}}`, true},
		{"move positional", "moveMessages", `{"input":["a","b"],"folder":"INBOX"}`, true},
		{"move missing destination", "moveMessages", `{"input":["a"]}`, false},
		{"mark rows", "markRead", `{"ids":[{"id":"a"},"b"]}`, true},
		{"mark empty", "markRead", `{"ids":[]}`, false},
		{"folder parent row", "createFolder", `{"input":{"name":"Receipts","parent":{"id":"in"}}}`, true},
		{"empty folder name", "createFolder", `{"input":{"name":""}}`, false},
		{"send nested addresses", "sendMessage", `{"to":[{"email":"a@example.com","name":"A"}],"text":"","attachments":["receipt.pdf"]}`, true},
		{"send empty recipients", "sendMessage", `{"to":[],"text":"Hello"}`, false},
		{"send nested recipient", "sendMessage", `{"to":[{"name":"A"}],"text":"Hello"}`, false},
		{"send attachment path", "sendMessage", `{"to":[{"email":"a@example.com"}],"text":"Hello","attachments":[{"filename":"receipt.pdf"}]}`, false},
		{"reply named alias", "replyMessage", `{"input":{"messageId":"m","text":"Thanks","all":true}}`, true},
		{"reply positional", "replyMessage", `{"input":{"id":"m"},"options":{"text":"Thanks"}}`, true},
		{"reply text required", "replyMessage", `{"input":{"id":"m","all":true}}`, false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			operation, _ := json.Marshal(tc.operation)
			modules["connector.luau"] = source[:strings.LastIndex(source, "return functions")] + `local schema=functions.help().functions[` + string(operation) + `].inputSchema;schema.examples={json.decode([====[` + tc.input + `]====])};return {invoke=function(input) return input end,help={text="Schema fixture",functions={invoke={description="Mail input",inputSchema=schema}}}}`
			_, err := conformance.CheckCatalog(context.Background(), "", *m, modules, map[string]string{"example.luau": `return {scenario={config={access="read-write"},auth_method="token",auth_config={token="fixture-token"}},run=function(c) assert(type(fixture.example("invoke"))=="table") end}`})
			if tc.valid && err != nil {
				t.Fatal(err)
			}
			if !tc.valid && (err == nil || !strings.Contains(err.Error(), "inputSchema.examples[0]")) {
				t.Fatalf("invalid input should fail schema validation: %v", err)
			}
		})
	}
}
