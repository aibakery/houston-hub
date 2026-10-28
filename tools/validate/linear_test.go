package main

import (
	"net/http"
	"slices"
	"testing"
)

// Read-only connections send queries with GET, which Linear refuses for mutations, so only
// read-write connections may POST. API keys go bare in Authorization; OAuth tokens as Bearer.
func TestLinearScopesAndAccessRoutes(t *testing.T) {
	m := parseManifest(t, "../../connectors/linear/houston.json")
	const api = "https://api.linear.app/graphql"
	for _, method := range []string{"token", "oauth"} {
		for _, access := range []string{"read-only", "read-write"} {
			config := map[string]any{"access": access}
			input := map[string]any{"token": "lin_api_fixture"}
			if method == "oauth" {
				config["client_id"], config["client_secret"], input = "fixture-client", "fixture-secret", nil
			}
			r, err := m.Resolve(nil, config, input, method)
			if err != nil {
				t.Fatal(err)
			}
			authorization := "lin_api_fixture"
			if method == "oauth" {
				// Linear always grants read and replies with space-separated scopes, so each access
				// level requests one scope.
				scopes := []string{"read"}
				if access == "read-write" {
					scopes = []string{"write"}
				}
				if !slices.Equal(r.Scopes, scopes) {
					t.Fatalf("access=%s scopes %v", access, r.Scopes)
				}
				authorization = "Bearer lin_oauth_fixture"
				r.Context.Auth["oauth"]["access_token"] = "lin_oauth_fixture"
			}
			assertAuthorizedRoutes(t, r, authorization, true,
				"GET "+api+"?query=%7Bviewer%7Bid%7D%7D", "GET "+api)
			assertAuthorizedRoutes(t, r, authorization, access == "read-write", "POST "+api)
			assertAuthorizedRoutes(t, r, authorization, false,
				"PUT "+api, "DELETE "+api, "POST https://api.linear.app/oauth/token", "POST https://api.linear.app/oauth/revoke",
				"GET https://api.linear.app/graphql/x", "GET https://linear.app/graphql", "GET https://uploads.linear.app/o1/file",
				"GET https://api.linear.app.example.com/graphql", "GET http://api.linear.app:8080/graphql")
			recipe, err := r.Proxy.HTTPRecipe("GET", api, nil)
			if err != nil {
				t.Fatal(err)
			}
			headers, err := recipe.Prepare(r.Context, http.Header{"X-Http-Method-Override": {"POST"}, "X-Http-Method": {"POST"}, "X-Method-Override": {"POST"}})
			if err != nil || headers.Get("X-HTTP-Method-Override") != "" || headers.Get("X-HTTP-Method") != "" || headers.Get("X-Method-Override") != "" {
				t.Fatalf("method override kept on a read: %v", err)
			}
		}
	}
}
