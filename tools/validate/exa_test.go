package main

import (
	"net/http"
	"testing"
)

// Exa keys reach every endpoint of the team, including billed agent runs and key management,
// so the proxy sends the key only to the four read endpoints, as x-api-key.
func TestExaRoutes(t *testing.T) {
	r, err := parseManifest(t, "../../connectors/exa/houston.json").Resolve(nil, nil, map[string]any{"token": "exa-fixture-key"}, "api_key")
	if err != nil {
		t.Fatal(err)
	}
	const api = "https://api.exa.ai"
	dropped := []string{"Authorization", "X-HTTP-Method-Override", "X-HTTP-Method", "X-Method-Override"}
	for _, path := range []string{"/search", "/contents", "/findSimilar", "/answer"} {
		recipe, err := r.Proxy.HTTPRecipe("POST", api+path, nil)
		if err != nil {
			t.Fatalf("POST %s denied: %v", path, err)
		}
		caller := http.Header{"Content-Type": {"application/json"}, "X-Api-Key": {"forged"}}
		for _, name := range dropped {
			caller.Set(name, "Bearer forged")
		}
		headers, err := recipe.Prepare(r.Context, caller)
		if err != nil || headers.Get("x-api-key") != "exa-fixture-key" || headers.Get("Content-Type") != "application/json" {
			t.Fatalf("POST %s prepared %v: %v", path, headers, err)
		}
		for _, name := range dropped {
			if headers.Get(name) != "" {
				t.Fatalf("%s reached Exa on %s", name, path)
			}
		}
	}
	assertAuthorizedRoutes(t, r, "", false,
		"GET "+api+"/search", "POST "+api+"/search/x", "POST "+api+"/research/v1", "POST "+api+"/agent/runs",
		"GET "+api+"/agent/runs/run_1", "POST "+api+"/monitors", "POST "+api+"/batches", "POST "+api+"/chat/completions",
		"POST "+api+"/responses", "GET "+api+"/v0/teams/me", "POST "+api+"/v0/websets", "POST "+api+"/websets/v0/websets",
		"GET "+api+"/team-management/api-keys", "POST "+api+"/%2e%2e/agent/runs", "POST "+api+"/contents/%2e%2e/agent/runs",
		"POST https://api.exa.ai.example.com/search", "POST http://api.exa.ai:8080/search", "POST https://exa.ai/search",
		"POST https://mcp.exa.ai/mcp", "GET https://dashboard.exa.ai/api-keys", "POST https://admin-api.exa.ai/team-management/api-keys")
}
