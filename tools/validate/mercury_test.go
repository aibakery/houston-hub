package main

import (
	"net/http"
	"os"
	"strings"
	"testing"

	"github.com/aibakery/houston-hub/manifest"
)

func TestMercuryAuthenticationAndTransportBoundaries(t *testing.T) {
	raw, err := os.ReadFile("../../connectors/mercury/houston.json")
	if err != nil {
		t.Fatal(err)
	}
	m, err := manifest.Parse(raw)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := m.Resolve(nil, nil, nil, "token"); err == nil {
		t.Fatal("accepted missing token")
	}
	for _, access := range []string{"read-only", "read-write"} {
		for _, reveal := range []bool{false, true} {
			r, err := m.Resolve(nil, map[string]any{"access": access, "reveal_card_details": reveal}, map[string]any{"token": "secret-token:fixture-private"}, "token")
			if err != nil {
				t.Fatal(err)
			}
			if err := m.RequireCredentials(r.Context); err != nil {
				t.Fatal(err)
			}
			for key, value := range r.PublicConfig {
				if strings.Contains(key, "token") || strings.Contains(strings.ToLower(key), "secret") || value == "secret-token:fixture-private" {
					t.Fatal("credential leaked into Lua public config")
				}
			}
			rules := m.Proxy.Select(r.ProxyIndices)
			assertRoute := func(method, url string, allowed bool) {
				t.Helper()
				caller := http.Header{"Authorization": {"forged"}}
				recipe, err := rules.HTTPRecipe(method, url, caller)
				if !allowed {
					if err == nil {
						t.Fatalf("access=%s reveal=%v allowed %s %s", access, reveal, method, url)
					}
					return
				}
				if err != nil {
					t.Fatal(err)
				}
				headers, err := recipe.Prepare(r.Context, caller)
				if err != nil || headers.Get("Authorization") != "Bearer secret-token:fixture-private" || caller.Get("Authorization") != "forged" {
					t.Fatalf("incorrect credential injection: %v", err)
				}
			}
			for _, path := range []string{
				"/accounts?limit=10", "/account/a/statements", "/account/a/transactions?offset=2",
				"/transactions?search=invoice%20%26%20rent", "/transaction/t", "/treasury", "/treasury/t/statements",
				"/statements/s/pdf", "/credit", "/safes", "/safes/s", "/safes/s/document",
				"/ar/invoices/i/pdf", "/ar/attachments/a", "/cards/c", "/users/u", "/webhooks/w",
			} {
				assertRoute("GET", "https://api.mercury.com/api/v1"+path, true)
			}
			for _, route := range [][2]string{
				{"POST", "/account/a/transactions"}, {"POST", "/account/a/request-send-money"},
				{"POST", "/transfer"}, {"POST", "/request-transfer"}, {"POST", "/recipients"},
				{"POST", "/recipients/invites"}, {"DELETE", "/recipient/r"},
				{"PATCH", "/transaction/t"}, {"POST", "/transaction/t/attachments"},
				{"POST", "/recipient/r/attachments"}, {"POST", "/ar/invoices"},
				{"POST", "/ar/invoices/i/cancel"}, {"DELETE", "/ar/customers/c"},
				{"POST", "/cards"}, {"POST", "/cards/c/freeze"}, {"POST", "/cards/c/unfreeze"},
				{"POST", "/cards/c/cancel"}, {"POST", "/webhooks/w/verify"}, {"DELETE", "/webhooks/w"},
			} {
				assertRoute(route[0], "https://api.mercury.com/api/v1"+route[1], access == "read-write")
			}
			assertRoute("GET", "https://vault-api.mercury.com/api/v1/cards/c/reveal", reveal)
			for _, route := range [][2]string{
				{"GET", "https://api.mercury.com/api/v1/cards/c/reveal"},
				{"POST", "https://vault-api.mercury.com/api/v1/cards/c/reveal"},
				{"GET", "https://vault-api.mercury.com/api/v1/accounts"},
				{"GET", "https://api.mercury.com.attacker.test/api/v1/accounts"},
				{"GET", "http://api.mercury.com/api/v1/accounts"},
				{"GET", "https://api.mercury.com:8443/api/v1/accounts"},
				{"GET", "https://api-sandbox.mercury.com/api/v1/accounts"},
				{"GET", "https://untrusted.s3.amazonaws.com/file"},
				{"POST", "https://api.mercury.com/api/v1/safes"},
				{"POST", "https://api.mercury.com/api/v1/safes/s/sign"},
				{"POST", "https://api.mercury.com/api/v1/request-send-money/r/approve"},
				{"POST", "https://api.mercury.com/api/v1/users"},
				{"GET", "https://api.mercury.com/api/v1/account/a"},
				{"GET", "https://api.mercury.com/api/v1/safes/%2e%2e/accounts"},
				{"POST", "https://api.mercury.com/oauth2/token"},
			} {
				assertRoute(route[0], route[1], false)
			}
		}
	}
	r, err := m.Resolve(nil, nil, map[string]any{"token": "fixture"}, "token")
	if err != nil || r.PublicConfig["access"] != "read-only" || r.PublicConfig["reveal_card_details"] != false {
		t.Fatalf("wrong defaults: %v, %v", r, err)
	}
}
