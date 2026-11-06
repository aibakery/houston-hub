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
		b, e := os.ReadFile("../../connectors/pennylane/" + name)
		if e != nil {
			t.Fatal(e)
		}
		modules[name] = string(b)
	}
	source := modules["connector.luau"]
	raw, e := os.ReadFile("../../connectors/pennylane/houston.json")
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
		{"numeric path", "getCustomerInvoice", `{"id":42}`, true},
		{"large native string ID", "getCustomerInvoice", `{"id":"9223372036854775807"}`, true},
		{"unsafe numeric ID", "getCustomerInvoice", `{"id":9007199254740992}`, false},
		{"path bound", "getCustomerInvoice", `{"id":"10000000000000000000"}`, false},
		{"negative path", "getCustomerInvoice", `{"id":-1}`, false},
		{"page bound", "getCustomerInvoices", `{"limit":101}`, false},
		{"ledger extended page", "getLedgerAccounts", `{"limit":1000}`, true},
		{"query null", "getCustomerInvoices", `{"cursor":null}`, false},
		{"native nested filter", "getCustomerInvoices", `{"filter":[{"field":"customer_id","operator":"in","value":[12,34]}]}`, true},
		{"filter field", "getCustomerInvoices", `{"filter":[{"field":"password","operator":"eq","value":"x"}]}`, false},
		{"filter field operator", "getCustomerInvoices", `{"filter":[{"field":"draft","operator":"gt","value":true}]}`, false},
		{"filter list value", "getCustomerInvoices", `{"filter":[{"field":"id","operator":"in","value":42}]}`, false},
		{"filter scalar value", "getCustomerInvoices", `{"filter":[{"field":"id","operator":"eq","value":[42]}]}`, false},
		{"filter JSON", "getCustomerInvoices", `{"filter":"[{\"field\":\"id\",\"operator\":\"eq\",\"value\":42}]"}`, true},
		{"sort field", "getCustomerInvoices", `{"sort":"-unknown"}`, false},
		{"change continuation exclusion", "getCustomerInvoicesChanges", `{"cursor":"opaque","start_date":"2026-11-01T00:00:00Z"}`, false},
		{"invoice manual line", "postCustomerInvoices", `{"date":"2026-11-01","deadline":"2026-11-30","customer_id":42,"draft":true,"invoice_lines":[{"label":"Consulting","quantity":1,"raw_currency_unit_price":"100.00","unit":"piece","vat_rate":"FR_200"}]}`, true},
		{"invoice product line", "postCustomerInvoices", `{"date":"2026-11-01","deadline":"2026-11-30","customer_id":42,"draft":true,"invoice_lines":[{"product_id":7,"quantity":2}]}`, true},
		{"invoice missing line payload", "postCustomerInvoices", `{"date":"2026-11-01","deadline":"2026-11-30","customer_id":42,"draft":true,"invoice_lines":[{"quantity":2}]}`, false},
		{"invoice decimal type", "postCustomerInvoices", `{"date":"2026-11-01","deadline":"2026-11-30","customer_id":42,"draft":true,"invoice_lines":[{"label":"Consulting","quantity":1,"raw_currency_unit_price":100,"unit":"piece","vat_rate":"FR_200"}]}`, false},
		{"native date format", "postCustomerInvoices", `{"date":"tomorrow","deadline":"2026-11-30","customer_id":42,"draft":true,"invoice_lines":[{"product_id":7,"quantity":2}]}`, false},
		{"category replacement", "putCustomerInvoiceCategories", `{"customer_invoice_id":42,"categories":[{"id":7,"weight":"1"}]}`, true},
		{"category clearing", "putCustomerInvoiceCategories", `{"customer_invoice_id":42,"categories":[]}`, true},
		{"category weight type", "putCustomerInvoiceCategories", `{"customer_invoice_id":42,"categories":[{"id":7,"weight":1}]}`, false},
		{"subscription native mode", "putBillingSubscriptions", `{"id":42,"mode":{"type":"awaiting_validation"}}`, true},
		{"subscription email payload", "putBillingSubscriptions", `{"id":42,"mode":{"type":"email"}}`, false},
		{"subscription email variant", "putBillingSubscriptions", `{"id":42,"mode":{"type":"email","email_settings":{"recipients":["billing@example.com"]}}}`, true},
		{"subscription recurring branch", "putBillingSubscriptions", `{"id":42,"recurring_rule":{"type":"monthly","day_of_month":1,"interval":1}}`, true},
		{"subscription recurring bound", "putBillingSubscriptions", `{"id":42,"recurring_rule":{"type":"monthly","day_of_month":32}}`, false},
		{"transaction customer", "updateTransaction", `{"id":42,"customer_id":12}`, true},
		{"transaction null clearing", "updateTransaction", `{"id":42,"customer_id":null}`, true},
		{"transaction exclusive relation", "updateTransaction", `{"id":42,"customer_id":12,"supplier_id":34}`, false},
		{"multipart native nested fields", "createCustomerInvoiceEInvoiceImport", `{"file":"invoice.pdf","send_to_pa":false,"invoice_options":{"customer_id":12,"invoice_lines":[{"e_invoice_line_id":"line-1","ledger_account_id":34}]}}`, true},
		{"multipart nested required", "createCustomerInvoiceEInvoiceImport", `{"file":"invoice.pdf","invoice_options":{"invoice_lines":[{"ledger_account_id":34}]}}`, false},
		{"multipart override conflict", "createCustomerInvoiceEInvoiceImport", `{"file":"invoice.pdf","override_invoice_lines":[],"invoice_options":{"invoice_lines":[]}}`, false},
		{"multipart name", "postFileAttachments", `{"file":"invoice.pdf","filename":"../invoice.pdf"}`, false},
		{"webhook event enum", "postWebhookSubscriptions", `{"callback_url":"https://example.com/webhooks","events":["made.up"]}`, false},
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
