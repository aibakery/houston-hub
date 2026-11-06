package main

import (
	"context"
	"encoding/json"
	"github.com/aibakery/houston-hub/tools/internal/helpschema"
	"os"
	"regexp"
	"strings"
	"testing"

	"github.com/aibakery/houston-hub/manifest"
	"github.com/aibakery/houston-hub/tools/conformance"
)

func TestNativeSchemasAndConnectorTransport(t *testing.T) {
	b, err := os.ReadFile("../../connectors/tipeee/lib/help.luau")
	if err != nil {
		t.Fatal(err)
	}
	modules := map[string]string{"lib/help.luau": string(b)}
	examples, err := os.ReadFile("../../connectors/tipeee/lib/examples.luau")
	if err != nil {
		t.Fatal(err)
	}
	modules["lib/examples.luau"] = string(examples)
	source, err := os.ReadFile("../../connectors/tipeee/connector.luau")
	if err != nil {
		t.Fatal(err)
	}
	endpoints := map[string]any{}
	for _, ep := range helpschema.Endpoints(string(source)) {
		query, err := helpschema.Fields(string(source), ep.Definition, "query")
		if err != nil {
			t.Fatal(err)
		}
		required, err := helpschema.Fields(string(source), ep.Definition, "required")
		if err != nil {
			t.Fatal(err)
		}
		record := map[string]any{"method": ep.Method, "path": ep.Path, "query": query, "required": required, "about": "Native operation"}
		if match := regexp.MustCompile("body = " + "\"([^\"]+)\"").FindStringSubmatch(ep.Definition); len(match) > 0 {
			record["body"] = match[1]
		}
		endpoints[ep.Name] = record
	}
	endpointJSON, err := json.Marshal(endpoints)
	if err != nil {
		t.Fatal(err)
	}

	m, err := manifest.Parse([]byte(`{"schema_version":1,"name":"Tipeee schema fixture","files":["main.luau"],"proxy":[{"match":{"protocol":"http","host":["example.com"]},"action":{}}]}`))
	if err != nil {
		t.Fatal(err)
	}
	for _, tc := range []struct {
		name, operation, input string
		valid                  bool
	}{

		{"numeric identifier", "getReward", "{\"project\":\"my-art\",\"reward\":12}", true},
		{"path traversal", "getReward", "{\"project\":\"../art\",\"reward\":12}", false},
		{"top tippers minimum", "listTopTippers", "{\"project\":\"my-art\",\"perPage\":1}", false},
		{"top tippers maximum", "listTopTippers", "{\"project\":\"my-art\",\"perPage\":150}", true},
		{"top tippers overflow", "listTopTippers", "{\"project\":\"my-art\",\"perPage\":151}", false},
		{"query omission", "listNews", "{\"project\":\"my-art\",\"statusFilter\":null}", true},
		{"draft explicit boolean", "createNews", "{\"project\":\"my-art\",\"data\":{\"name\":\"Update\",\"contentv2\":{\"translations\":{\"en\":{\"html\":\"\u003cp\u003eHello\u003c/p\u003e\"}}},\"draft\":\"true\"}}", false},
		{"draft required", "createNews", "{\"project\":\"my-art\",\"data\":{\"name\":\"Update\",\"contentv2\":{\"translations\":{\"en\":{\"html\":\"\u003cp\u003eHello\u003c/p\u003e\"}}}}}", false},
		{"native reward nested stock", "updateReward", "{\"project\":\"my-art\",\"reward\":12,\"data\":{\"modules\":{\"stock\":{\"available\":{\"unlimited\":false,\"quantity\":5}}}}}", true},
		{"stock quantity type", "updateReward", "{\"project\":\"my-art\",\"reward\":12,\"data\":{\"modules\":{\"stock\":{\"available\":{\"unlimited\":false,\"quantity\":\"five\"}}}}}", false},
		{"form omitted optional null", "updateReward", "{\"project\":\"my-art\",\"reward\":12,\"data\":{\"price\":null}}", true},
		{"form required null", "createReward", "{\"project\":\"my-art\",\"data\":{\"price\":null,\"translations\":{\"en\":{\"name\":\"Print\"}}}}", false},
		{"method override rejected", "updateProject", "{\"project\":\"my-art\",\"data\":{\"_method\":\"delete\"}}", false},
		{"credential body rejected", "updateProject", "{\"project\":\"my-art\",\"data\":{\"access_token\":\"secret\"}}", false},
		{"form key syntax", "updateProject", "{\"project\":\"my-art\",\"data\":{\"nested\":{\"not[a]\":\"value\"}}}", false},
		{"message response", "sendMessage", "{\"data\":{\"action\":\"RESPONSE\",\"content\":\"Thank you\",\"thread\":4}}", true},
		{"message broadcast rules", "sendMessage", "{\"data\":{\"action\":\"CREATE\",\"content\":\"Hello\",\"project\":7,\"title\":\"News\"}}", false},
		{"message erratum parent", "sendMessage", "{\"data\":{\"action\":\"ERRATUM\",\"content\":\"Correction\",\"thread\":4}}", false},
		{"message action enum", "sendMessage", "{\"data\":{\"action\":\"typo\",\"content\":\"Hi\"}}", false},
		{"comment empty", "createComment", "{\"thread\":\"news-update\",\"data\":{\"body\":\"\"}}", false},
		{"publication explicit terms", "publishProject", "{\"project\":\"my-art\",\"data\":{\"tipeee\":\"on\",\"adyen\":\"on\",\"hyperwallet\":\"on\"}}", true},
		{"publication implicit terms", "publishProject", "{\"project\":\"my-art\",\"data\":{\"tipeee\":true,\"adyen\":true,\"hyperwallet\":true}}", false},
		{"closure code leading zero", "closeProject", "{\"project\":\"my-art\",\"data\":{\"token\":\"012345\"}}", true},
		{"closure numeric code", "closeProject", "{\"project\":\"my-art\",\"data\":{\"token\":12345}}", false},
		{"payment filename year", "downloadPayments", "{\"report\":\"my-art_2026.csv\",\"output\":\"payments.csv\"}", true},
		{"payment filename missing year", "downloadPayments", "{\"report\":\"my-art.csv\",\"output\":\"payments.csv\"}", false},
		{"download output required", "downloadPrivateMedia", "{\"media\":\"attachment-demo\"}", false},
		{"upload file required", "uploadMedia", "{\"type\":\"image\"}", false},
		{"upload file specification", "uploadMedia", "{\"type\":\"image\",\"files\":{\"uploadedFile\":{\"path\":\"art.png\",\"filename\":\"art.png\",\"contentType\":\"image/png\"}}}", true},
		{"upload unknown file option", "uploadMedia", "{\"type\":\"image\",\"files\":{\"uploadedFile\":{\"path\":\"art.png\",\"filename\":\"art.png\",\"contentType\":\"image/png\",\"url\":\"https://example.com\"}}}", false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			operation, _ := json.Marshal(tc.operation)
			modules["main.luau"] = `local endpoints=json.decode([====[` + string(endpointJSON) + `]====]);local schema=require("lib/help.luau")(endpoints)[` + string(operation) + `].inputSchema;schema.examples={json.decode([====[` + tc.input + `]====])};return {invoke=function(input) return input end,help={text="Schema fixture",functions={invoke={description="Native input",inputSchema=schema}}}}`
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
