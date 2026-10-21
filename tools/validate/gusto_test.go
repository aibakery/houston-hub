package main

import "testing"

func TestGustoAccessRoutes(t *testing.T) {
	m := parseManifest(t, "../../connectors/gusto/houston.json")
	// Houston's app signs in to production; a connection's own app to production or the demo.
	for method, origin := range map[string]string{"gusto": "gusto.com", "own_app": "gusto.com", "demo": "gusto-demo.com"} {
		a := m.Auth[method]
		if a.AuthorizeURL != "https://app."+origin+"/oauth/authorize" || a.TokenURL != "https://api."+origin+"/oauth/token" || a.PKCE != "none" || !a.RequireRefresh {
			t.Fatalf("%s endpoints %s %s %s", method, a.AuthorizeURL, a.TokenURL, a.PKCE)
		}
		for _, access := range []string{"read-only", "read-write"} {
			config := map[string]any{"access": access}
			publisher := map[string]any{"client_id": "houston-client", "client_secret": "houston-secret"}
			if method != "gusto" {
				config["own_app"], config["client_id"], config["client_secret"], publisher = true, "fixture-client", "fixture-secret", nil
			}
			r, err := m.Resolve(publisher, config, nil, method)
			if err != nil {
				t.Fatal(err)
			}
			// Gusto assigns scopes to the app at review; requesting one it lacks fails the sign-in.
			if len(r.Scopes) != 0 {
				t.Fatalf("%s requests scopes %v", method, r.Scopes)
			}
			token := "gusto-" + method
			r.Context.Auth[method]["access_token"] = token
			for _, api := range []string{"https://api.gusto.com/v1", "https://api.gusto-demo.com/v1"} {
				assertRoutes(t, r, token, true,
					"GET "+api+"/token_info", "GET "+api+"/companies/c1/employees?include=custom_fields&page=1&per=100",
					"GET "+api+"/companies/c1/payrolls/p1?include=taxes", "GET "+api+"/companies/c1/pay_schedules/assignments",
					"POST "+api+"/payrolls/p1/reports/general_ledger", "POST "+api+"/payrolls/p1/employees/e1/calculate_accruing_time_off_hours")
				assertRoutes(t, r, token, access == "read-write",
					"POST "+api+"/companies/c1/employees", "PUT "+api+"/employees/e1", "DELETE "+api+"/employees/e1",
					"PUT "+api+"/companies/c1/payrolls/p1/prepare", "PUT "+api+"/companies/c1/payrolls/p1",
					"PATCH "+api+"/employees/e1/section603_high_earner_statuses/2026", "DELETE "+api+"/time_tracking/time_sheets/t1?version=v1")
				// Running payroll and paying contractors move money; app-level webhooks, events,
				// provisioning and disconnecting need a system token and are not exposed.
				assertRoutes(t, r, token, false,
					"PUT "+api+"/companies/c1/payrolls/p1/submit", "PUT "+api+"/companies/c1/payrolls/p1/calculate", "PUT "+api+"/companies/c1/payrolls/p1/cancel",
					"POST "+api+"/companies/c1/payrolls", "POST "+api+"/companies/c1/contractor_payments", "PUT "+api+"/contractor_payments/cp1/fund",
					"GET "+api+"/webhook_subscriptions", "GET "+api+"/events", "POST "+api+"/provision", "POST "+api+"/companies/c1/disconnect_app_integration",
					"GET "+api+"/employees/e1/bank_accounts", "PATCH "+api+"/employees/e1", "PUT "+api+"/companies/c1", "GET "+api+"/employees/%2e%2e/token_info")
			}
			// The token endpoints and lookalike hosts never receive the access token.
			assertRoutes(t, r, token, false,
				"POST https://api.gusto.com/oauth/token", "POST https://api.gusto-demo.com/oauth/revoke", "GET https://app.gusto.com/v1/token_info",
				"GET https://mcp.api.gusto.com/v1/token_info", "GET https://api.gusto.com.example.com/v1/token_info", "GET https://api.gusto.com/v2/token_info")
		}
	}
}

func TestGustoRoutesStripMethodOverrides(t *testing.T) {
	r, err := parseManifest(t, "../../connectors/gusto/houston.json").Resolve(
		map[string]any{"client_id": "houston-client", "client_secret": "houston-secret"}, map[string]any{"access": "read-write"}, nil, "gusto")
	if err != nil {
		t.Fatal(err)
	}
	r.Context.Auth["gusto"]["access_token"] = "gusto-token"
	assertStripsMethodOverrides(t, r, "GET https://api.gusto.com/v1/employees/e1", "POST https://api.gusto.com/v1/payrolls/p1/reports/general_ledger",
		"POST https://api.gusto.com/v1/companies/c1/employees", "PUT https://api.gusto.com/v1/employees/e1",
		"PATCH https://api.gusto.com/v1/employees/e1/section603_high_earner_statuses/2026", "DELETE https://api.gusto.com/v1/employees/e1")
}
