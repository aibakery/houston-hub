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

func TestNativeSchemas(t *testing.T) {
	modules := map[string]string{}
	for _, name := range []string{"connector.luau", "lib/help.luau", "lib/examples.luau", "lib/native.luau"} {
		b, err := os.ReadFile("../../connectors/meta/" + name)
		if err != nil {
			t.Fatal(err)
		}
		modules[name] = string(b)
	}
	source := modules["connector.luau"]
	raw, err := os.ReadFile("../../connectors/meta/houston.json")
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
		{"string ID", "getObject", `{"id":"101_456"}`, true},
		{"numeric ID loses precision", "getObject", `{"id":101}`, false},
		{"post ID format", "updatePost", `{"post":"101","message":"Hello"}`, false},
		{"field expansion", "getPage", `{"fields":"id,instagram_business_account{id,username}"}`, true},
		{"credential field", "getPage", `{"fields":"id,ACCESS_TOKEN"}`, false},
		{"page size", "listFeed", `{"limit":100}`, true},
		{"page size overflow", "listFeed", `{"limit":101}`, false},
		{"Instagram page size", "listInstagramComments", `{"media":"123","limit":51}`, false},
		{"query null", "listFeed", `{"since":null}`, false},
		{"native metric list", "getInsights", `{"object":"me","metric":["page_media_view","page_post_engagements"],"period":"day"}`, true},
		{"native metric CSV", "getInsights", `{"object":"me","metric":"page_media_view,page_post_engagements"}`, true},
		{"metric name type", "getInsights", `{"object":"me","metric":[{}]}`, false},
		{"next alone", "listComments", `{"next":"opaque"}`, true},
		{"next mixed", "listComments", `{"next":"opaque","object":"101_456"}`, false},
		{"normal required ID", "listComments", `{"limit":10}`, false},
		{"nested attached media", "createPost", `{"attached_media":[{"media_fbid":"123"}]}`, true},
		{"nested attached media ID", "createPost", `{"attached_media":[{}]}`, false},
		{"write field normalization", "createPost", `{"message":"Hello","access token":"private"}`, false},
		{"native message recipient", "sendMessage", `{"recipient":{"id":"123"},"message":{"text":"Hello"},"messaging_type":"RESPONSE"}`, true},
		{"recipient choice", "sendMessage", `{"recipient":{"id":"123","comment_id":"456"},"message":{"text":"Hello"}}`, false},
		{"message nested attachment", "sendMessage", `{"recipient":{"id":"123"},"message":{"attachment":{"type":"image"}}}`, false},
		{"sender action", "sendMessage", `{"recipient":{"id":"123"},"sender_action":"typing_on"}`, true},
		{"sender action enum", "sendMessage", `{"recipient":{"id":"123"},"sender_action":"typo"}`, false},
		{"carousel native IDs", "createInstagramContainer", `{"ig_user":"123","media_type":"CAROUSEL","children":["456","789"]}`, true},
		{"carousel missing children", "createInstagramContainer", `{"ig_user":"123","media_type":"CAROUSEL","image_url":"https://example.com/a.jpg"}`, false},
		{"carousel minimum", "createInstagramContainer", `{"ig_user":"123","media_type":"CAROUSEL","children":["456"]}`, false},
		{"carousel CSV minimum", "createInstagramContainer", `{"ig_user":"123","media_type":"CAROUSEL","children":"456"}`, false},
		{"reel requires video", "createInstagramContainer", `{"ig_user":"123","media_type":"REELS","image_url":"https://example.com/a.jpg"}`, false},
		{"native tag coordinates", "createInstagramContainer", `{"ig_user":"123","image_url":"https://example.com/a.jpg","user_tags":[{"username":"artist","x":1.5}]}`, false},
		{"session file upload", "uploadPhoto", `{"path":"photo.jpg","published":false}`, true},
		{"file and URL conflict", "uploadPhoto", `{"path":"photo.jpg","url":"https://example.com/a.jpg"}`, false},
		{"multipart null", "uploadPhoto", `{"path":"photo.jpg","caption":null}`, false},
		{"multipart extension", "uploadPhoto", `{"path":"photo.jpg","future_field":{"enabled":true}}`, true},
		{"node update native allowlist", "updatePost", `{"post":"101_456","about":"Hello"}`, false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			operation, _ := json.Marshal(tc.operation)
			modules["connector.luau"] = source[:strings.LastIndex(source, "return exports")] + `local schema=exports.help().functions[` + string(operation) + `].inputSchema;schema.examples={json.decode([====[` + tc.input + `]====])};return {invoke=function(input) return input end,help={text="Schema fixture",functions={invoke={description="Native input",inputSchema=schema}}}}`
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
