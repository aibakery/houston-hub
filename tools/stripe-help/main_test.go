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
	b, err := os.ReadFile("../../connectors/stripe/lib/schemas.luau")
	if err != nil {
		t.Fatal(err)
	}
	modules := map[string]string{"lib/schemas.luau": string(b)}
	m, err := manifest.Parse([]byte(`{"schema_version":1,"name":"Stripe schema fixture","files":["main.luau"],"proxy":[{"match":{"protocol":"http","host":["example.com"]},"action":{}}]}`))
	if err != nil {
		t.Fatal(err)
	}
	for _, tc := range []struct {
		name, operation, input string
		valid                  bool
	}{

		{"nested customer", "createCustomer", `{"email":"ana@example.com","address":{"country":"US"},"metadata":{"project":"demo"}}`, true},
		{"clear customer field", "updateCustomer", `{"customer_id":"cus_1","shipping":""}`, true},
		{"null form field", "updateCustomer", `{"customer_id":"cus_1","shipping":null}`, false},
		{"deep null", "createCustomer", `{"address":{"future_field":null}}`, false},
		{"invalid form key", "createCustomer", `{"metadata":{"bad[key]":"value"}}`, false},
		{"integer amount", "createPaymentIntent", `{"amount":1500,"currency":"usd","automatic_payment_methods":{"enabled":true}}`, true},
		{"fractional amount", "createPaymentIntent", `{"amount":1.5,"currency":"usd"}`, false},
		{"zero amount", "createPaymentIntent", `{"amount":0,"currency":"usd"}`, false},
		{"nested type", "createPaymentIntent", `{"amount":1500,"currency":"usd","automatic_payment_methods":{"enabled":"yes"}}`, false},
		{"price product data", "createPrice", `{"currency":"usd","product_data":{"name":"Demo"},"unit_amount":100}`, true},
		{"price needs product", "createPrice", `{"currency":"usd","unit_amount":100}`, false},
		{"price ambiguous product", "createPrice", `{"currency":"usd","product":"prod_1","product_data":{"name":"Demo"},"unit_amount":100}`, false},
		{"tier upper bound", "createPrice", `{"currency":"usd","product":"prod_1","billing_scheme":"tiered","tiers_mode":"graduated","tiers":[{"unit_amount":100,"up_to":"inf"}]}`, true},
		{"tier missing bound", "createPrice", `{"currency":"usd","product":"prod_1","billing_scheme":"tiered","tiers":[{"unit_amount":100}]}`, false},
		{"query filters", "listCustomers", `{"limit":100,"created":{"gte":1790812800},"expand":["data.default_source"]}`, true},
		{"query page bounds", "listCustomers", `{"limit":101}`, false},
		{"exclusive cursors", "listCustomers", `{"starting_after":"cus_1","ending_before":"cus_2"}`, false},
		{"path ID", "getCustomer", `{"customer_id":"../customers"}`, false},
		{"header control", "createCustomer", `{"idempotency_key":"key\nvalue"}`, false},
		{"subscription customer account", "createSubscription", `{"customer_account":"acct_1","items":[{"price":"price_1"}]}`, true},
		{"subscription customer needed", "createSubscription", `{"items":[{"price":"price_1"}]}`, false},
		{"checkout items needed", "createCheckoutSession", `{"mode":"payment","success_url":"https://example.com/ok"}`, false},
		{"file metadata", "uploadFile", `{"path":"evidence.pdf","purpose":"dispute_evidence","file_link_data":{"create":false}}`, true},
		{"file name constraint", "uploadFile", `{"path":"evidence.pdf","purpose":"dispute_evidence","filename":"../evidence.pdf"}`, false},
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
