package main

import (
	"net/http"
	"testing"
)

// Pennylane serves its API on the same host as its web app, OAuth and file links, so the
// token reaches only the Company API v2 routes in the endpoint table, and writes only on
// read-write connections. Export jobs only read and stay available read-only.
func TestPennylaneAccessRoutes(t *testing.T) {
	m := parseManifest(t, "../../connectors/pennylane/houston.json")
	const api = "https://app.pennylane.com/api/external/v2"
	for _, access := range []string{"read-only", "read-write"} {
		r, err := m.Resolve(nil, map[string]any{"access": access}, map[string]any{"token": "pennylane-fixture"}, "token")
		if err != nil {
			t.Fatal(err)
		}
		assertRoutes(t, r, "pennylane-fixture", true,
			"GET "+api+"/me", "GET "+api+"/customer_invoices?limit=50&filter=%5B%5D", "GET "+api+"/customer_invoices/42",
			"GET "+api+"/customer_invoices/42/invoice_lines", "GET "+api+"/supplier_invoices/7/payments", "GET "+api+"/ledger_entry_lines",
			"GET "+api+"/trial_balance?period_start=2026-01-01&period_end=2026-03-31", "GET "+api+"/changelogs/transactions",
			"GET "+api+"/webhook_subscriptions", "POST "+api+"/exports/fecs", "GET "+api+"/exports/fecs/9")
		assertRoutes(t, r, "pennylane-fixture", access == "read-write",
			"POST "+api+"/customer_invoices", "PUT "+api+"/customer_invoices/42/finalize", "POST "+api+"/customer_invoices/42/send_by_email",
			"DELETE "+api+"/customer_invoices/42", "PUT "+api+"/customers/12/categories", "POST "+api+"/file_attachments",
			"POST "+api+"/ledger_entry_lines/lettering", "DELETE "+api+"/ledger_entry_lines/lettering", "POST "+api+"/webhook_subscriptions",
			"DELETE "+api+"/webhook_subscriptions/5")
		// The token must never reach OAuth, the web app, signed file links, API v1 or other hosts.
		assertRoutes(t, r, "pennylane-fixture", false,
			"POST https://app.pennylane.com/oauth/token", "POST https://app.pennylane.com/oauth/revoke", "GET https://app.pennylane.com/oauth/authorize",
			"GET https://app.pennylane.com/", "GET https://app.pennylane.com/auth/login", "GET https://app.pennylane.com/public/invoice/pdf?encrypted_id=x",
			"GET https://app.pennylane.com/rails/active_storage/blobs/redirect/x/invoice.pdf", "GET https://app.pennylane.com/api/external/v1/me",
			"POST "+api+"/ledger_attachments", "PATCH "+api+"/customer_invoices/42", "DELETE "+api+"/customers/12", "GET "+api+"/companies",
			"GET "+api+"/customer_invoices/%2e%2e/me", "GET "+api+"/customer_invoices/a%2Fb", "GET "+api,
			"GET https://app.pennylane.com.example.com/api/external/v2/me", "GET https://api.pennylane.com/api/external/v2/me",
			"GET http://app.pennylane.com:8080/api/external/v2/me", "GET https://pennylane.com/api/external/v2/me")
	}
}

// Method-override headers can turn a POST into another method, so the read-only export
// route refuses them.
func TestPennylaneReadOnlyPostRejectsMethodOverrides(t *testing.T) {
	r, err := parseManifest(t, "../../connectors/pennylane/houston.json").Resolve(nil, map[string]any{"access": "read-only"}, map[string]any{"token": "pennylane-fixture"}, "token")
	if err != nil {
		t.Fatal(err)
	}
	recipe, err := r.Proxy.HTTPRecipe("POST", "https://app.pennylane.com/api/external/v2/exports/fecs", nil)
	if err != nil {
		t.Fatal(err)
	}
	assertPrepareRejectsMethodOverrides(t, recipe, r.Context, "export")
	headers, err := recipe.Prepare(r.Context, http.Header{})
	if err != nil || headers.Get("Authorization") != "Bearer pennylane-fixture" {
		t.Fatalf("export headers %v: %v", headers, err)
	}
}
