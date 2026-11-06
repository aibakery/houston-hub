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

// Check the actual bundle, including shared endpoint query declarations and
// generated provider bodies. Only the selected documented example is replaced.
func TestInputBoundaries(t *testing.T) {
	directory := "../../connectors/wise/"
	raw, err := os.ReadFile(directory + "houston.json")
	if err != nil {
		t.Fatal(err)
	}
	m, err := manifest.Parse(raw)
	if err != nil {
		t.Fatal(err)
	}
	modules := map[string]string{}
	for _, file := range []string{"connector.luau", "lib/help.luau", "lib/body-schemas.luau", "lib/examples.luau"} {
		b, e := os.ReadFile(directory + file)
		if e != nil {
			t.Fatal(e)
		}
		modules[file] = string(b)
	}
	examples := strings.Replace(modules["lib/examples.luau"], "return json.decode(", "local all = json.decode(", 1)
	for _, tc := range []struct {
		name, operation, input string
		valid                  bool
	}{
		{"safe ID limit", "getProfile", `{"profileId":"9007199254740991"}`, true},
		{"unsafe ID", "getProfile", `{"profileId":"9007199254740992"}`, false},
		{"zero ID", "getProfile", `{"profileId":"0000"}`, false},
		{"leading zero ID", "getProfile", `{"profileId":"00000101"}`, true},
		{"too many digits", "getProfile", `{"profileId":"00000000000000101"}`, false},
		{"bounded size string", "listActivities", `{"profileId":101,"size":"0100"}`, true},
		{"size too large", "listActivities", `{"profileId":101,"size":"101"}`, false},
		{"zero size", "listActivities", `{"profileId":101,"size":0}`, false},
		{"zero offset", "listTransfers", `{"profile":101,"offset":"00"}`, true},
		{"negative offset", "listTransfers", `{"profile":101,"offset":-1}`, false},
		{"CSV list spaces", "listBalances", `{"profileId":101,"types":" STANDARD , SAVINGS "}`, true},
		{"array list spaces", "listBalances", `{"profileId":101,"types":[" STANDARD ","SAVINGS"]}`, true},
		{"invalid list value", "listBalances", `{"profileId":101,"types":"STANDARD,OTHER"}`, false},
		{"empty CSV item", "listTransfers", `{"profile":101,"status":"processing,,outgoing_payment_sent"}`, false},
		{"quote null omission", "createQuote", `{"profileId":101,"sourceCurrency":"GBP","targetCurrency":"EUR","sourceAmount":null,"targetAmount":100}`, true},
		{"quote ambiguous amount", "createQuote", `{"profileId":101,"sourceCurrency":"GBP","targetCurrency":"EUR","sourceAmount":100,"targetAmount":100}`, false},
		{"quote lacks amount", "createQuote", `{"profileId":101,"sourceCurrency":"GBP","targetCurrency":"EUR","sourceAmount":null,"targetAmount":null}`, false},
		{"jar needs name", "createBalance", `{"profileId":101,"currency":"EUR","type":"SAVINGS","idempotenceUuid":"00000000-0000-4000-8000-000000000001"}`, false},
		{"movement amount form", "createBalanceMovement", `{"profileId":101,"amount":{"value":25,"currency":"GBP"},"sourceBalanceId":101,"targetBalanceId":102,"idempotenceUuid":"00000000-0000-4000-8000-000000000001"}`, true},
		{"movement needs destination", "createBalanceMovement", `{"profileId":101,"amount":{"value":25,"currency":"GBP"},"sourceBalanceId":101,"idempotenceUuid":"00000000-0000-4000-8000-000000000001"}`, false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			name, _ := json.Marshal(tc.operation)
			modules["lib/examples.luau"] = examples + `all[` + string(name) + `]={json.decode([====[` + tc.input + `]====])};return all`
			fixture := `return {scenario={config={access="read-write"},auth_method="token",auth_config={token="fixture-wise-token"}},configure=function() http={request=function() return fixture.operation({statusCode=200,headers={},body=fixture.reader("{}")}) end} end,run=function(c) assert(type(fixture.example(` + string(name) + `))=="table") end}`
			_, err := conformance.CheckCatalog(context.Background(), "", *m, modules, map[string]string{"example.luau": fixture})
			if tc.valid && err != nil {
				t.Fatal(err)
			}
			if !tc.valid && (err == nil || !strings.Contains(err.Error(), "inputSchema.examples[0]")) {
				t.Fatalf("invalid input should fail schema validation: %v", err)
			}
		})
	}
}
