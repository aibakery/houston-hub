package main

import (
	"net/http"
	"testing"
)

func TestStripeAccessRoutes(t *testing.T) {
	m := parseManifest(t, "../../connectors/stripe/houston.json")
	const api = "https://api.stripe.com"
	const files = "https://files.stripe.com"
	for _, access := range []string{"read-only", "read-write"} {
		r, err := m.Resolve(nil, map[string]any{"access": access}, map[string]any{"token": "rk_test_fixture"}, "token")
		if err != nil {
			t.Fatal(err)
		}
		assertRoutes(t, r, "rk_test_fixture", true,
			"GET "+api+"/v1/account", "GET "+api+"/v1/balance", "GET "+api+"/v1/customers?limit=10",
			"GET "+api+"/v1/customers/search?query=email", "GET "+api+"/v1/invoices/in_1/lines",
			"GET "+api+"/v1/payment_intents/pi_1", "GET "+api+"/v1/files/file_1", "GET "+files+"/v1/files/file_1/contents")
		assertRoutes(t, r, "rk_test_fixture", access == "read-write",
			"POST "+api+"/v1/payment_intents", "POST "+api+"/v1/payment_intents/pi_1/confirm", "POST "+api+"/v1/refunds",
			"POST "+api+"/v1/payouts", "POST "+api+"/v1/invoices/in_1/send", "DELETE "+api+"/v1/customers/cus_1",
			"DELETE "+api+"/v1/subscriptions/sub_1", "POST "+files+"/v1/files")
		assertRoutes(t, r, "rk_test_fixture", false,
			"POST "+api+"/v1/files", "GET "+api+"/v1/files/file_1/contents", "POST "+files+"/v1/refunds",
			"GET "+api+"/v1/api_keys", "POST "+api+"/oauth/token", "GET "+api+"/v1/atlas/companies",
			"POST "+api+"/v1/accounts", "GET "+api+"/v1/accounts/acct_1", "GET "+api+"/v1/webhook_endpoints",
			"GET https://dashboard.stripe.com/atlas", "GET https://api.stripe.com.evil.test/v1/balance",
			"GET https://files.stripe.com.evil.test/v1/files/file_1/contents", "GET "+api+"/v1/customers/%2e%2e/balance",
			"PUT "+api+"/v1/customers/cus_1", "GET "+api+"/v2/core/accounts")
		for _, rule := range m.Proxy {
			if len(rule.Match.Host) != 1 || len(rule.Match.Method) != 1 {
				t.Fatal("unexpected broad Stripe rule")
			}
		}
		recipe, err := r.Proxy.HTTPRecipe("GET", api+"/v1/balance", nil)
		if err != nil {
			t.Fatal(err)
		}
		headers, err := recipe.Prepare(r.Context, http.Header{
			"Authorization": {"forged"}, "Stripe-Version": {"old"}, "Stripe-Account": {"acct_other"}, "Stripe-Context": {"acct_other"}, "X-HTTP-Method-Override": {"POST"},
		})
		if err != nil {
			t.Fatal(err)
		}
		if headers.Get("Stripe-Version") != "2026-09-30.endive" || headers.Get("Authorization") != "Bearer rk_test_fixture" {
			t.Fatal(headers)
		}
		for _, header := range []string{"Stripe-Account", "Stripe-Context", "X-HTTP-Method-Override"} {
			if headers.Get(header) != "" {
				t.Fatalf("kept %s", header)
			}
		}
	}
}
