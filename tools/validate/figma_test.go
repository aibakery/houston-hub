package main

import (
	"net/http"
	"slices"
	"strings"
	"testing"

	"github.com/aibakery/houston-hub/manifest"
)

// assertFigmaRoutes checks each "METHOD URL" route is allowed or denied, and that allowed routes
// carry only the connection's credential: X-Figma-Token for personal tokens, Bearer for OAuth.
func assertFigmaRoutes(t *testing.T, r *manifest.Resolved, header, value string, allowed bool, routes ...string) {
	t.Helper()
	for _, route := range routes {
		method, url, _ := strings.Cut(route, " ")
		recipe, err := r.Proxy.HTTPRecipe(method, url, nil)
		if (err == nil) != allowed {
			t.Fatalf("%s allowed=%v: %v", route, err == nil, err)
		}
		if err != nil {
			continue
		}
		headers, err := recipe.Prepare(r.Context, http.Header{"Authorization": {"forged"}, "X-Figma-Token": {"forged"}})
		other := "Authorization"
		if header == other {
			other = "X-Figma-Token"
		}
		if err != nil || headers.Get(header) != value || headers.Get(other) != "" {
			t.Fatalf("credential injection for %s: %v %v", route, headers, err)
		}
	}
}

func TestFigmaScopesAndAccessRoutes(t *testing.T) {
	m := parseManifest(t, "../../connectors/figma/houston.json")
	readScopes := []string{"current_user:read", "file_content:read", "file_metadata:read", "file_versions:read", "file_comments:read",
		"library_assets:read", "library_content:read", "team_library_content:read", "projects:read"}
	const api, key = "https://api.figma.com", "aBcDeFgHiJkLmNoPqRsTuV12"
	_, entries := endpointTable(t, "figma")
	ids := strings.NewReplacer("{file_key}", key, "{team_id}", "123", "{project_id}", "77", "{comment_id}", "7", "{key}", "abc")
	for _, method := range []string{"token", "oauth"} {
		for _, access := range []string{"read-only", "read-write"} {
			config := map[string]any{"access": access}
			input := map[string]any{"token": "figd_fixture"}
			header, value := "X-Figma-Token", "figd_fixture"
			if method == "oauth" {
				config["client_id"], config["client_secret"], input = "fixture-client", "fixture-secret", nil
			}
			r, err := m.Resolve(nil, config, input, method)
			if err != nil {
				t.Fatal(err)
			}
			if method == "oauth" {
				scopes := readScopes
				if access == "read-write" {
					scopes = append(slices.Clone(readScopes), "file_comments:write")
				}
				if !slices.Equal(r.Scopes, scopes) {
					t.Fatalf("access=%s scopes %v", access, r.Scopes)
				}
				header, value = "Authorization", "Bearer figu_fixture"
				r.Context.Auth["oauth"]["access_token"] = "figu_fixture"
			}
			// Every endpoint of the connector's table is routed for both methods, writes only on read-write.
			for _, entry := range entries {
				assertFigmaRoutes(t, r, header, value, !entry.write || access == "read-write", entry.method+" "+api+ids.Replace(entry.path))
			}
			// Renders download from the public bucket without any credential.
			assertFigmaRoutes(t, r, "Authorization", "", true, "GET https://figma-alpha-api.s3.us-west-2.amazonaws.com/images/u1")
			// Variables, duplication, dev resources, webhooks (their passcodes), team administration,
			// token endpoints and other hosts are not exposed.
			assertFigmaRoutes(t, r, header, value, false,
				"GET "+api+"/v1/files/"+key+"/variables/local", "POST "+api+"/v1/files/"+key+"/variables", "POST "+api+"/v1/files/"+key+"/duplicate",
				"GET "+api+"/v1/files/"+key+"/dev_resources", "POST "+api+"/v1/dev_resources", "GET "+api+"/v2/webhooks", "POST "+api+"/v2/webhooks",
				"GET "+api+"/v2/webhooks/1/requests", "POST "+api+"/v1/teams/123/invites", "GET "+api+"/v1/activity_logs", "GET "+api+"/v1/payments",
				"POST "+api+"/v1/oauth/token", "POST "+api+"/v1/oauth/refresh", "PUT "+api+"/v1/files/"+key+"/comments",
				"POST "+api+"/v1/files/"+key+"/comments/7", "GET "+api+"/v1/files/%2e%2e/comments", "GET https://www.figma.com/api/v1/me",
				"GET https://api.figma.com.example.com/v1/me", "GET https://figma-alpha-api.s3.us-west-2.amazonaws.com/other/u1",
				"PUT https://figma-alpha-api.s3.us-west-2.amazonaws.com/images/u1", "GET https://s3-alpha-sig.figma.com/img/a/b/c")
		}
	}
}
