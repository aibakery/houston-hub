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

// Validate the generated union schemas and the configured restrictions with the
// runtime's JSON Schema implementation, independently of Dropbox HTTP mocks.
func TestNativeAndCustomArgumentSchemas(t *testing.T) {
	modules := map[string]string{}
	for _, name := range []string{"help", "schemas", "policy"} {
		b, err := os.ReadFile("../../connectors/dropbox/lib/" + name + ".luau")
		if err != nil {
			t.Fatal(err)
		}
		modules["lib/"+name+".luau"] = string(b)
	}
	m, err := manifest.Parse([]byte(`{"schema_version":1,"name":"Dropbox schema fixture","files":["main.luau"],"proxy":[{"match":{"protocol":"http","host":["example.com"]},"action":{}}]}`))
	if err != nil {
		t.Fatal(err)
	}
	for _, tc := range []struct {
		name, operation, input string
		custom, valid          bool
	}{
		{"write tag", "upload", `{"path":"/Reports/a.pdf","session_path":"a.pdf","mode":"overwrite"}`, false, true},
		{"revision payload", "upload", `{"path":"/Reports/a.pdf","session_path":"a.pdf","mode":{".tag":"update","update":"015f000000001"}}`, false, true},
		{"missing revision payload", "upload", `{"path":"/Reports/a.pdf","session_path":"a.pdf","mode":{".tag":"update"}}`, false, false},
		{"null revision payload", "upload", `{"path":"/Reports/a.pdf","session_path":"a.pdf","mode":{".tag":"update","update":null}}`, false, false},
		{"member payload", "removeFileMember", `{"file":"/Reports/a.pdf","member":{".tag":"email","email":"ana@example.com"}}`, false, true},
		{"missing member payload", "removeFileMember", `{"file":"/Reports/a.pdf","member":{".tag":"email"}}`, false, false},
		{"null member payload", "removeFileMember", `{"file":"/Reports/a.pdf","member":{".tag":"email","email":null}}`, false, false},
		{"clear deadline", "updateFileRequest", `{"id":"oaCAVmEyrqYnkZX9955Y","deadline":{".tag":"update"}}`, false, true},
		{"set deadline", "updateFileRequest", `{"id":"oaCAVmEyrqYnkZX9955Y","deadline":{".tag":"update","deadline":"2026-12-01T12:00:00Z","allow_late_uploads":"one_day"}}`, false, true},
		{"late uploads need deadline", "updateFileRequest", `{"id":"oaCAVmEyrqYnkZX9955Y","deadline":{".tag":"update","allow_late_uploads":"one_day"}}`, false, false},
		{"custom canonical path", "getMetadata", `{"path":"/Reports/a.pdf"}`, true, true},
		{"custom ID alias", "getMetadata", `{"path":"id:example"}`, true, false},
		{"custom dot component", "getMetadata", `{"path":"/Reports/../a.pdf"}`, true, false},
		{"custom trailing space", "getMetadata", `{"path":"/Reports /a.pdf"}`, true, false},
		{"custom empty component", "getMetadata", `{"path":"/Reports//a.pdf"}`, true, false},
		{"custom control", "getMetadata", `{"path":"/Reports/a\u0000.pdf"}`, true, false},
		{"custom search folder", "search", `{"query":"report","options":{"path":"/Reports","max_results":20}}`, true, true},
		{"custom search requires folder", "search", `{"query":"report","options":{"max_results":20}}`, true, false},
		{"custom search requires options", "search", `{"query":"report"}`, true, false},
		{"custom explicit destination", "createFolder", `{"path":"/Reports/New","autorename":false}`, true, true},
		{"custom autorename", "createFolder", `{"path":"/Reports/New","autorename":true}`, true, false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			policy := "nil"
			if tc.custom {
				policy = `require("lib/policy.luau")('{"/Reports":"read-write"}', function() error("Help must stay offline") end)`
			}
			style := "nil"
			if tc.operation == "upload" {
				style = `"upload"`
			}
			name, _ := json.Marshal(tc.operation)
			modules["main.luau"] = `local doc = require("lib/help.luau").build(` + string(name) + `, {route="fixture", read=true, style=` + style + `, help="() -> native JSON."}, ` + policy + `)
    doc.inputSchema.examples = {json.decode([====[` + tc.input + `]====])}
    return {invoke=function(input) return input end, help={text="Schema fixture",functions={invoke=doc}}}`
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
