package main

import (
	"net/http"
	"regexp"
	"testing"
)

var wisePlaceholder = regexp.MustCompile(`\{\w+\}`)

func TestWiseAccessRoutes(t *testing.T) {
	m := parseManifest(t, "../../connectors/wise/houston.json")
	const quote = "2d0b3b6e-6f1c-4c43-9c6a-1b6a0f4f3a10"
	for _, hosts := range [][2]string{{"api.wise.com", "api.wise-sandbox.com"}, {"api.wise-sandbox.com", "api.wise.com"}} {
		host, api, other := hosts[0], "https://"+hosts[0], "https://"+hosts[1]
		for _, access := range []string{"read-only", "read-write"} {
			r, err := m.Resolve(nil, map[string]any{"access": access, "api_host": host}, map[string]any{"token": "wise_fixture"}, "token")
			if err != nil {
				t.Fatal(err)
			}
			assertRoutes(t, r, "wise_fixture", true,
				"GET "+api+"/v1/me", "GET "+api+"/v2/profiles", "GET "+api+"/v4/profiles/1/balances?types=STANDARD",
				"GET "+api+"/v1/profiles/1/total-funds/EUR", "GET "+api+"/v1/profiles/1/activities?size=100",
				"GET "+api+"/v1/profiles/1/balance-statements/2/statement.json?currency=EUR",
				"GET "+api+"/v1/profiles/1/balance-statements/2/statement.mt940", "GET "+api+"/v1/transfers?profile=1",
				"GET "+api+"/v1/transfers/9/receipt.pdf", "GET "+api+"/v3/profiles/1/quotes/"+quote,
				"GET "+api+"/v1/quotes/"+quote+"/account-requirements", "GET "+api+"/v2/accounts?profileId=1", "GET "+api+"/v1/rates")
			for _, rule := range m.Proxy {
				for _, method := range rule.Match.Method {
					for _, path := range rule.Match.Path {
						route := method + " " + api + wisePlaceholder.ReplaceAllString(path, quote)
						if method == "GET" {
							assertRoutes(t, r, "wise_fixture", true, route)
							continue
						}
						assertRoutes(t, r, "wise_fixture", access == "read-write", route)
					}
				}
			}
			assertRoutes(t, r, "wise_fixture", false,
				"GET "+other+"/v2/profiles", "POST "+api+"/oauth/token", "GET "+api+"/v1/user/pin",
				"POST "+api+"/v1/one-time-token/pin/verify", "GET "+api+"/v1/identity/one-time-token/status",
				"POST https://twcard.wise.com/twcard-data/v1/sensitive-card-data/details", "GET "+api+"/v3/spend/profiles/1/cards",
				"GET "+api+"/v3/profiles/1/subscriptions", "POST "+api+"/v3/profiles/1/subscriptions",
				"PUT "+api+"/v2/profiles/1/personal-profile", "POST "+api+"/auth/jose/request/public-keys",
				"DELETE "+api+"/v2/accounts/5", "GET "+api+"/v1/users/1/contact-email", "GET "+api+"/2026Q4/profiles",
				"GET https://api.transferwise.com/v2/profiles", "GET https://"+host+".evil.test/v2/profiles",
				"GET "+api+"/v2/profiles/%2e%2e/1", "GET "+api+"/v1/profiles/1/balance-statements/2/statement.html",
				"POST "+api+"/v1/transfers/9/cancel", "PATCH "+api+"/v1/transfers/9")
			recipe, err := r.Proxy.HTTPRecipe("GET", api+"/v2/profiles", nil)
			if err != nil {
				t.Fatal(err)
			}
			headers, err := recipe.Prepare(r.Context, http.Header{
				"Authorization": {"forged"}, "X-Http-Method-Override": {"DELETE"}, "X-Http-Method": {"DELETE"}, "X-Method-Override": {"DELETE"},
			})
			if err != nil {
				t.Fatal(err)
			}
			for _, name := range []string{"X-HTTP-Method-Override", "X-HTTP-Method", "X-Method-Override"} {
				if headers.Get(name) != "" {
					t.Fatalf("kept %s", name)
				}
			}
		}
	}
	if _, err := m.Resolve(nil, map[string]any{"api_host": "attacker.example"}, map[string]any{"token": "wise_fixture"}, "token"); err == nil {
		t.Fatal("accepted an environment host outside the options")
	}
}
