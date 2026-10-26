package main

import (
	"net/http"
	"os"
	"regexp"
	"slices"
	"strings"
	"testing"

	"github.com/aibakery/houston-hub/manifest"
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
				"GET "+api+"/repos/o/r/releases/tags/app%2Fv1", "GET "+api+"/repos/o/r/git/trees/feature%2Fx", "GET "+api+"/search/code?q=x", "GET "+api+"/repos/o/r/actions/jobs/1/logs",
				"GET "+api+"/repos/o/r/contents/test%2Ffolder%2525with%20percentage%23%2Findex.js", "GET "+api+"/repos/o/r/branches/fix%2F100%25")
			assertRoutes(t, r, "fixture-token", access == "read-write",
				"POST "+api+"/repos/o/r/issues", "PATCH "+api+"/repos/o/r/pulls/1", "PUT "+api+"/repos/o/r/pulls/1/merge",
				"PUT "+api+"/repos/o/r/contents/docs%2Fa.md", "DELETE "+api+"/repos/o/r/contents/docs%2Fa.md",
				"PATCH "+api+"/repos/o/r/git/refs/heads%2Fx", "DELETE "+api+"/repos/o/r/git/refs/heads%2Fx",
				"DELETE "+api+"/repos/o/r/issues/1/labels/area%2Fui", "POST "+api+"/repos/o/r/branches/old%2Fname/rename",
				"DELETE "+api+"/repos/o/r/issues/1/labels/50%25%20done", "PATCH "+api+"/repos/o/r/labels/100%25")
			// Repository deletion, administration, secrets and credential endpoints stay denied.
			assertRoutes(t, r, "fixture-token", false,
				"DELETE "+api+"/repos/o/r", "PATCH "+api+"/repos/o/r", "POST "+api+"/graphql", "GET "+api+"/repos/o/r/actions/secrets", "GET "+api+"/repos/o/r/actions/secrets/public-key",
				"GET "+api+"/repos/o/r/hooks", "GET "+api+"/repos/o/r/keys", "PUT "+api+"/repos/o/r/collaborators/u",
				"POST "+api+"/applications/abc/token", "DELETE "+api+"/installation/token", "POST "+api+"/credentials/revoke",
				"GET "+api+"/authorizations", "POST https://github.com/login/oauth/access_token", "GET https://api.github.com.evil.test/user",
				"GET "+api+"/repos/o/r/contents/%2e%2e%2fsecrets", "GET "+api+"/repos/o/r/branches/a%2F..%2F..%2Fhooks",
				"GET "+api+"/repos/o/r/issues/1%2F..%2F2", "GET "+api+"/repos/o/r/contents/%252e%252e%252fsecrets", "POST "+api+"/repos/o/r/branches/a/protection",
				"PATCH "+api+"/repos/o/r/issues/1/labels/x", "GET "+api+"/repos/o/r/git/refs/heads", "GET https://uploads.github.com/repos/o/r/releases/1/assets", "POST https://uploads.github.com/repos/o/r/releases/1/assets?name=a.zip",
				"POST https://codeload.github.com/o/r/legacy.tar.gz/main")
			// Signed downloads never receive the token.
			for _, url := range []string{"https://codeload.github.com/o/r/legacy.tar.gz/refs/heads/feature/x?token=SIGNED",
				"https://release-assets.githubusercontent.com/github-production-release-asset/1/abc?sig=SIGNED",
				"https://productionresultssa12.blob.core.windows.net/actions-results/a/logs.txt?sig=SIGNED",
				"https://pipelinesghubeus6.actions.githubusercontent.com/x/logs.zip?sig=SIGNED",
				"https://gist.githubusercontent.com/o/aa5a315d61ae9438b18d/raw/3a0f86fb/big%20data.json"} {
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

// Each endpoint's credential rule must use its host, and slash-capable parameters
// (Lua's OPAQUE set) must be opaque; signed downloads have one credential-free rule.
func TestGitHubRulesMatchEndpointHostsAndOpaqueParameters(t *testing.T) {
	raw, err := os.ReadFile("../../connectors/github/connector.luau")
	if err != nil {
		t.Fatal(err)
	}
	lua := string(raw)
	opaque := map[string]bool{}
	set := regexp.MustCompile(`local OPAQUE = table\.freeze\(\{([^}]*)\}\)`).FindStringSubmatch(lua)
	if set == nil {
		t.Fatal("OPAQUE set not found")
	}
	for _, m := range regexp.MustCompile(`(\w+) = true`).FindAllStringSubmatch(set[1], -1) {
		opaque[m[1]] = true
	}
	entry := regexp.MustCompile(`(?ms)^\t\w+ = \{method = "([A-Z]+)", path = "([^"]+)"(.*?)about = "[^"]*"\},$`)
	param := regexp.MustCompile(`\{(\w+)\}`)
	var want, got []string
	for _, m := range entry.FindAllStringSubmatch(lua, -1) {
		var names []string
		for _, p := range param.FindAllStringSubmatch(m[2], -1) {
			if opaque[p[1]] {
				names = append(names, p[1])
			}
		}
		slices.Sort(names)
		want = append(want, m[1]+" api.github.com "+m[2]+" "+strings.Join(names, ","))
	}
	if entries := strings.Count(lua, "= {method = "); len(want) != entries {
		t.Fatalf("matched %d of %d endpoint entries", len(want), entries)
	}
	var free []manifest.Proxy
	for _, rule := range parseManifest(t, "../../connectors/github/houston.json").Proxy {
		if rule.Action.Headers.Set["Authorization"] == "" {
			free = append(free, rule)
			continue
		}
		names := slices.Clone(rule.Match.OpaquePathParameters)
		slices.Sort(names)
		for _, host := range rule.Match.Host {
			for _, method := range rule.Match.Method {
				for _, path := range rule.Match.Path {
					got = append(got, method+" "+host+" "+path+" "+strings.Join(names, ","))
				}
			}
		}
	}
	slices.Sort(want)
	slices.Sort(got)
	if !slices.Equal(got, want) {
		t.Errorf("proxy routes %v, endpoint table %v", got, want)
	}
	hosts := []string{"codeload.github.com", "release-assets.githubusercontent.com", "objects.githubusercontent.com",
		"objects-origin.githubusercontent.com", "github-releases.githubusercontent.com", "gist.githubusercontent.com", "*.actions.githubusercontent.com", "*.blob.core.windows.net"}
	if len(free) != 1 || !slices.Equal(free[0].Match.Host, hosts) || !slices.Equal(free[0].Match.Method, []string{"GET"}) ||
		!slices.Equal(free[0].Action.Headers.Remove, []string{"Authorization"}) {
		t.Fatalf("credential-free download rules %+v", free)
	}
}
