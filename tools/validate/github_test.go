package main

import (
	"net/http"
	"testing"
)

func TestGitHubAuthenticationAndAccessRoutes(t *testing.T) {
	m := parseManifest(t, "../../connectors/github/houston.json")
	const api = "https://api.github.com"
	publisher := map[string]any{"client_id": "Iv23liFixture", "client_secret": "fixture-client-secret"}
	for _, method := range []string{"oauth", "token"} {
		for _, access := range []string{"read-only", "read-write"} {
			input := map[string]any{"token": "fixture-token"}
			if method == "oauth" {
				input = nil
			}
			r, err := m.Resolve(publisher, map[string]any{"access": access}, input, method)
			if err != nil {
				t.Fatal(err)
			}
			if len(r.Scopes) != 0 {
				t.Fatalf("GitHub App sign-in requests no scopes, got %v", r.Scopes)
			}
			if method == "oauth" {
				r.Context.Auth[method]["access_token"] = "fixture-token"
			}
			assertRoutes(t, r, "fixture-token", true,
				"GET "+api+"/user", "GET "+api+"/repos/o/r/issues?state=open", "GET "+api+"/repos/o/r/branches/feature%2Fx",
				"GET "+api+"/repos/o/r/contents/src%2Fmain.go?ref=release%2F1", "GET "+api+"/repos/o/r/compare/main...feature%2Fx",
				"GET "+api+"/repos/o/r/commits/feature%2Fx/check-runs", "GET "+api+"/repos/o/r/git/ref/heads%2Ffeature%2Fx",
				"GET "+api+"/repos/o/r/releases/tags/app%2Fv1", "GET "+api+"/repos/o/r/git/trees/feature%2Fx", "GET "+api+"/search/code?q=x", "GET "+api+"/repos/o/r/actions/jobs/1/logs")
			assertRoutes(t, r, "fixture-token", access == "read-write",
				"POST "+api+"/repos/o/r/issues", "PATCH "+api+"/repos/o/r/pulls/1", "PUT "+api+"/repos/o/r/pulls/1/merge",
				"PUT "+api+"/repos/o/r/contents/docs%2Fa.md", "DELETE "+api+"/repos/o/r/contents/docs%2Fa.md",
				"PATCH "+api+"/repos/o/r/git/refs/heads%2Fx", "DELETE "+api+"/repos/o/r/git/refs/heads%2Fx",
				"DELETE "+api+"/repos/o/r/issues/1/labels/area%2Fui", "POST "+api+"/repos/o/r/branches/old%2Fname/rename",
				"POST https://uploads.github.com/repos/o/r/releases/1/assets?name=a.zip")
			// Repository deletion, administration, secrets and credential endpoints stay denied.
			assertRoutes(t, r, "fixture-token", false,
				"DELETE "+api+"/repos/o/r", "PATCH "+api+"/repos/o/r", "POST "+api+"/graphql", "GET "+api+"/repos/o/r/actions/secrets", "GET "+api+"/repos/o/r/actions/secrets/public-key",
				"GET "+api+"/repos/o/r/hooks", "GET "+api+"/repos/o/r/keys", "PUT "+api+"/repos/o/r/collaborators/u",
				"POST "+api+"/applications/abc/token", "DELETE "+api+"/installation/token", "POST "+api+"/credentials/revoke",
				"GET "+api+"/authorizations", "POST https://github.com/login/oauth/access_token", "GET https://api.github.com.evil.test/user",
				"GET "+api+"/repos/o/r/contents/%2e%2e%2fsecrets", "GET "+api+"/repos/o/r/branches/a%2F..%2F..%2Fhooks",
				"GET "+api+"/repos/o/r/issues/1%2F..%2F2", "POST "+api+"/repos/o/r/branches/a/protection",
				"PATCH "+api+"/repos/o/r/issues/1/labels/x", "GET "+api+"/repos/o/r/git/refs/heads", "GET https://uploads.github.com/repos/o/r/releases/1/assets",
				"POST https://codeload.github.com/o/r/legacy.tar.gz/main")
			// Signed downloads never receive the token.
			for _, url := range []string{"https://codeload.github.com/o/r/legacy.tar.gz/refs/heads/feature/x?token=SIGNED",
				"https://release-assets.githubusercontent.com/github-production-release-asset/1/abc?sig=SIGNED",
				"https://productionresultssa12.blob.core.windows.net/actions-results/a/logs.txt?sig=SIGNED",
				"https://pipelinesghubeus6.actions.githubusercontent.com/x/logs.zip?sig=SIGNED"} {
				recipe, err := r.Proxy.HTTPRecipe("GET", url, nil)
				if err != nil {
					t.Fatal(url, err)
				}
				headers, err := recipe.Prepare(r.Context, http.Header{"Authorization": {"forged"}})
				if err != nil || headers.Get("Authorization") != "" {
					t.Fatalf("signed download %s kept credentials: %v %v", url, headers, err)
				}
			}
		}
	}
}
