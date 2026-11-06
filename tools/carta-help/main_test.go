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
	b, err := os.ReadFile("../../connectors/carta/lib/help.luau")
	if err != nil {
		t.Fatal(err)
	}
	modules := map[string]string{"lib/help.luau": string(b)}
	m, err := manifest.Parse([]byte(`{"schema_version":1,"name":"Carta schema fixture","files":["main.luau"],"proxy":[{"match":{"protocol":"http","host":["example.com"]},"action":{}}]}`))
	if err != nil {
		t.Fatal(err)
	}
	for _, tc := range []struct {
		name, operation, input string
		valid                  bool
	}{

		{"numeric path", "getIssuer", `{"id":101}`, true},
		{"unsafe numeric ID", "getIssuer", `{"id":9007199254740992}`, false},
		{"missing path", "getIssuer", `{}`, false},
		{"query null", "listIssuers", `{"pageSize":null}`, false},
		{"CSV filters", "listPartnerContacts", `{"firmId":"101","fundIds":"101,102","partnerIds":"201,202"}`, true},
		{"array filters", "listPartnerContacts", `{"firmId":"101","fundIds":[101,"102"]}`, true},
		{"empty array filter", "listPartnerContacts", `{"firmId":"101","fundIds":[]}`, false},
		{"stock split enum", "getStockSplitChanges", `{"issuerId":"101","securities":[{"securityType":"option_grant","securityId":"101"}],"since":{"value":"2026-10-01T00:00:00Z"}}`, true},
		{"stock split enum case", "getStockSplitChanges", `{"issuerId":"101","securities":[{"securityType":"OPTION_GRANT","securityId":"101"}],"since":{"value":"2026-10-01T00:00:00Z"}}`, false},
		{"completion datetime", "updateExerciseMoneyMovement", `{"issuerId":"101","exerciseId":"101","moneyMovement":{"completionDate":{"value":"2026-10-19T12:00:00Z"}}}`, true},
		{"completion plain date", "updateExerciseMoneyMovement", `{"issuerId":"101","exerciseId":"101","moneyMovement":{"completionDate":{"value":"2026-10-19"}}}`, false},
		{"wrapped decimal", "createCapitalCall", `{"firmId":"101","fundId":"101","externalReferenceId":"call-1","sourceSystem":"houston","dueDate":{"value":"2026-11-30"},"amount":{"value":"1000.00"},"postAsDraft":true}`, true},
		{"decimal numeric value", "createCapitalCall", `{"firmId":"101","fundId":"101","externalReferenceId":"call-1","sourceSystem":"houston","dueDate":{"value":"2026-11-30"},"amount":{"value":1000},"postAsDraft":true}`, false},
		{"decimal malformed value", "createCapitalCall", `{"firmId":"101","fundId":"101","externalReferenceId":"call-1","sourceSystem":"houston","dueDate":{"value":"2026-11-30"},"amount":{"value":"one thousand"},"postAsDraft":true}`, false},
		{"draft flag required", "createCapitalCall", `{"firmId":"101","fundId":"101","externalReferenceId":"call-1","sourceSystem":"houston","dueDate":{"value":"2026-11-30"},"amount":{"value":"1000"}}`, false},
		{"finalize path only", "finalizeSecondarySettlement", `{"issuerId":"101","secondaryTransactionId":"101"}`, true},
		{"upload session path", "uploadOpenCapTable", `{"path":"captable.zip"}`, true},
		{"upload path required", "uploadOpenCapTable", `{}`, false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			operation, _ := json.Marshal(tc.operation)
			modules["main.luau"] = `local schema=require("lib/help.luau")[` + string(operation) + `].inputSchema;schema.examples={json.decode([====[` + tc.input + `]====])};return {invoke=function(input) return input end,help={text="Schema fixture",functions={invoke={description="Native input",inputSchema=schema}}}}`
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
