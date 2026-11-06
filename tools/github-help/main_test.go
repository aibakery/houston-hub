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

func TestNativeInputSemantics(t *testing.T) {
	modules := map[string]string{}
	for _, name := range []string{"connector.luau", "lib/help.luau"} {
		b, e := os.ReadFile("../../connectors/github/" + name)
		if e != nil {
			t.Fatal(e)
		}
		modules[name] = string(b)
	}
	source := modules["connector.luau"]
	raw, e := os.ReadFile("../../connectors/github/houston.json")
	if e != nil {
		t.Fatal(e)
	}
	m, e := manifest.Parse(raw)
	if e != nil {
		t.Fatal(e)
	}
	for _, tc := range []struct {
		name, operation, input string
		valid                  bool
	}{
		{"numeric identifier", "getIssue", `{"owner":"octocat","repo":"Hello-World","issue_number":42}`, true},
		{"decimal identifier", "getIssue", `{"owner":"octocat","repo":"Hello-World","issue_number":"00042"}`, true},
		{"safe string upper bound", "getIssue", `{"owner":"octocat","repo":"Hello-World","issue_number":"9007199254740991"}`, true},
		{"unsafe string identifier", "getIssue", `{"owner":"octocat","repo":"Hello-World","issue_number":"9007199254740992"}`, false},
		{"zero identifier", "getIssue", `{"owner":"octocat","repo":"Hello-World","issue_number":0}`, false},
		{"opaque slash and percent", "getContent", `{"owner":"octocat","repo":"Hello-World","path":"docs/100%.md"}`, true},
		{"opaque dot segment", "getContent", `{"owner":"octocat","repo":"Hello-World","path":"docs/../README.md"}`, false},
		{"encoded separator", "getContent", `{"owner":"octocat","repo":"Hello-World","path":"docs%252FREADME.md"}`, false},
		{"page upper bound", "listIssues", `{"owner":"octocat","repo":"Hello-World","per_page":101}`, false},
		{"page lower bound", "listIssues", `{"owner":"octocat","repo":"Hello-World","page":0}`, false},
		{"query null", "listIssues", `{"owner":"octocat","repo":"Hello-World","state":null}`, false},
		{"native query enum", "listIssues", `{"owner":"octocat","repo":"Hello-World","state":"invalid"}`, false},
		{"labels CSV query", "listIssues", `{"owner":"octocat","repo":"Hello-World","labels":"bug,triage"}`, true},
		{"labels array query unsupported", "listIssues", `{"owner":"octocat","repo":"Hello-World","labels":["bug"]}`, false},
		{"recursive boolean", "getTree", `{"owner":"octocat","repo":"Hello-World","tree_sha":"main","recursive":false}`, true},
		{"recursive string", "getTree", `{"owner":"octocat","repo":"Hello-World","tree_sha":"main","recursive":"false"}`, false},
		{"archive format", "downloadArtifact", `{"owner":"octocat","repo":"Hello-World","artifact_id":42,"archive_format":"tar","save_as":"artifact.tar"}`, false},
		{"download destination required", "downloadRunLogs", `{"owner":"octocat","repo":"Hello-World","run_id":42}`, false},
		{"raw diff", "getPull", `{"owner":"octocat","repo":"Hello-World","pull_number":42,"format":"diff"}`, true},
		{"raw format enum", "getPull", `{"owner":"octocat","repo":"Hello-World","pull_number":42,"format":"html"}`, false},
		{"native assignees", "createIssue", `{"owner":"octocat","repo":"Hello-World","title":"Fix empty input","assignees":["octocat"]}`, true},
		{"native assignee array", "createIssue", `{"owner":"octocat","repo":"Hello-World","title":"Fix empty input","assignees":"octocat"}`, false},
		{"label clearing", "setLabels", `{"owner":"octocat","repo":"Hello-World","issue_number":42,"labels":[]}`, true},
		{"native label objects", "setLabels", `{"owner":"octocat","repo":"Hello-World","issue_number":42,"labels":[{"name":"bug"}]}`, true},
		{"nested label name", "setLabels", `{"owner":"octocat","repo":"Hello-World","issue_number":42,"labels":[{}]}`, false},
		{"pull from issue", "createPull", `{"owner":"octocat","repo":"Hello-World","head":"feature/help","base":"main","issue":42}`, true},
		{"pull title or issue", "createPull", `{"owner":"octocat","repo":"Hello-World","head":"feature/help","base":"main"}`, false},
		{"tree inline content", "createTree", `{"owner":"octocat","repo":"Hello-World","tree":[{"path":"notes.md","mode":"100644","type":"blob","content":"Hello"}]}`, true},
		{"tree file deletion", "createTree", `{"owner":"octocat","repo":"Hello-World","tree":[{"path":"notes.md","mode":"100644","type":"blob","sha":null}]}`, true},
		{"tree conflicting sources", "createTree", `{"owner":"octocat","repo":"Hello-World","tree":[{"path":"notes.md","mode":"100644","type":"blob","content":"Hello","sha":"abc"}]}`, false},
		{"tree missing content", "createTree", `{"owner":"octocat","repo":"Hello-World","tree":[{"path":"notes.md","mode":"100644","type":"blob"}]}`, false},
		{"nested committer required fields", "putFile", `{"owner":"octocat","repo":"Hello-World","path":"notes.md","message":"Add notes","content":"SGVsbG8=","committer":{"name":"Example"}}`, false},
		{"review comment line", "createPullReviewComment", `{"owner":"octocat","repo":"Hello-World","pull_number":42,"body":"Please test this","commit_id":"abc","path":"main.go"}`, false},
		{"review file subject", "createPullReviewComment", `{"owner":"octocat","repo":"Hello-World","pull_number":42,"body":"Please test this","commit_id":"abc","path":"main.go","subject_type":"file"}`, true},
		{"review multiline side", "createPullReviewComment", `{"owner":"octocat","repo":"Hello-World","pull_number":42,"body":"Please test this","commit_id":"abc","path":"main.go","line":12,"start_line":10}`, false},
		{"review changes body", "submitPullReview", `{"owner":"octocat","repo":"Hello-World","pull_number":42,"review_id":7,"event":"REQUEST_CHANGES"}`, false},
		{"review approval", "submitPullReview", `{"owner":"octocat","repo":"Hello-World","pull_number":42,"review_id":7,"event":"APPROVE"}`, true},
		{"requested reviewers meaningful", "requestReviewers", `{"owner":"octocat","repo":"Hello-World","pull_number":42,"reviewers":[]}`, false},
		{"workflow native inputs", "dispatchWorkflow", `{"owner":"octocat","repo":"Hello-World","workflow_id":"ci.yml","ref":"main","inputs":{"environment":"staging"}}`, true},
		{"gist native files", "createGist", `{"files":{"notes.md":{"content":"Hello"}},"public":false}`, true},
		{"gist nested content", "createGist", `{"files":{"notes.md":{}}}`, false},
		{"gist file null deletion", "updateGist", `{"gist_id":"abc","files":{"old.md":null}}`, true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			operation, _ := json.Marshal(tc.operation)
			modules["connector.luau"] = source[:strings.LastIndex(source, "return exports")] + `local schema=exports.help().functions[` + string(operation) + `].inputSchema;schema.examples={json.decode([====[` + tc.input + `]====])};return {invoke=function(input) return input end,help={text="Schema fixture",functions={invoke={description="Native input",inputSchema=schema}}}}`
			_, err := conformance.CheckCatalog(context.Background(), "", *m, modules, map[string]string{
				"example.luau": `return {scenario={config={access="read-write"},auth_method="token",auth_config={token="fixture-token"}},run=function(c) assert(type(fixture.example("invoke"))=="table") end}`,
				"oauth.luau":   `return {scenario={publisher={client_id="Iv23liFixture",client_secret="fixture-client-secret"},config={access="read-write"},auth_method="oauth",auth_config={}},run=function(c) assert(type(fixture.example("invoke"))=="table") end}`,
			})
			if tc.valid && err != nil {
				t.Fatal(err)
			}
			if !tc.valid && (err == nil || !strings.Contains(err.Error(), "inputSchema.examples[0]")) {
				t.Fatalf("invalid input should fail schema validation: %v", err)
			}
		})
	}
}

func TestVersionPatches(t *testing.T) {
	op := object{"requestBody": object{"content": object{"application/json": object{"schema": object{"properties": object{"mode": object{"type": "string", "enum": []any{"old"}}}}}}},
		"x-github-breaking-changes": []any{
			object{"version": "2026-03-10", "patch": object{"requestBody": object{"content": object{"application/json": object{"schema": object{"required": []any{"mode"}, "properties": object{"mode": object{"enum": []any{"new"}}}}}}}}},
			object{"version": "2026-03-10", "patch": []any{object{"op": "add", "path": "/requestBody/content/application~1json/schema/properties/mode/default", "value": "new"}}},
			object{"version": "2027-01-01", "patch": object{"summary": "Future contract"}},
		}}
	applyVersion(op, "2026-03-10")
	schema := obj(obj(obj(obj(op["requestBody"])["content"])["application/json"])["schema"])
	mode := obj(obj(schema["properties"])["mode"])
	if mode["default"] != "new" || list(mode["enum"])[0] != "new" || list(schema["required"])[0] != "mode" {
		t.Fatalf("versioned schema: %#v", schema)
	}
}
