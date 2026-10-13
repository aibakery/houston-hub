package main

import (
	"net/http"
	"os"
	"slices"
	"strings"
	"testing"

	"github.com/aibakery/houston-hub/manifest"
)

func TestLinkedInScopesAndAccessRoutes(t *testing.T) {
	raw, err := os.ReadFile("../../connectors/linkedin/houston.json")
	if err != nil {
		t.Fatal(err)
	}
	m, err := manifest.Parse(raw)
	if err != nil {
		t.Fatal(err)
	}
	read := []string{"GET https://api.linkedin.com/v2/userinfo"}
	writes := []string{
		"POST https://api.linkedin.com/rest/posts",
		"POST https://api.linkedin.com/rest/images?action=initializeUpload",
		"DELETE https://api.linkedin.com/rest/posts/urn%3Ali%3Ashare%3A7",
		"PUT https://www.linkedin.com/dms-uploads/C4E10AQ/uploaded-image/0?ut=signed",
	}
	denied := []string{
		"GET https://api.linkedin.com/rest/posts",
		"GET https://api.linkedin.com/v2/me",
		"DELETE https://api.linkedin.com/rest/images/urn%3Ali%3Aimage%3A1",
		"PUT https://api.linkedin.com/dms-uploads/C4E10AQ",
		"GET https://api.linkedin.com.evil.test/v2/userinfo",
	}
	for _, access := range []string{"read-only", "read-write"} {
		config := map[string]any{"access": access, "client_id": "fixture-client", "client_secret": "fixture-secret"}
		r, err := m.Resolve(nil, config, nil, "oauth")
		if err != nil {
			t.Fatal(err)
		}
		// LinkedIn joins scopes with commas in both the request and its token response.
		scopes := []string{"openid", "profile", "email"}
		if access == "read-write" {
			scopes = append(scopes, "w_member_social")
		}
		if !slices.Equal(r.Scopes, scopes) || m.Auth["oauth"].ScopeSeparator != "," {
			t.Fatalf("access=%s scopes %v", access, r.Scopes)
		}
		r.Context.Auth["oauth"]["access_token"] = "fixture-token"
		rules := r.Proxy
		check := func(route string, allowed bool) {
			t.Helper()
			method, url, _ := strings.Cut(route, " ")
			recipe, err := rules.HTTPRecipe(method, url, nil)
			if (err == nil) != allowed {
				t.Fatalf("access=%s %s allowed=%v: %v", access, route, err == nil, err)
			}
			if err != nil {
				return
			}
			headers, err := recipe.Prepare(r.Context, http.Header{"Authorization": {"forged"}})
			if err != nil || headers.Get("Authorization") != "Bearer fixture-token" {
				t.Fatalf("credential injection for %s: %v", route, err)
			}
		}
		for _, route := range read {
			check(route, true)
		}
		for _, route := range writes {
			check(route, access == "read-write")
		}
		for _, route := range denied {
			check(route, false)
		}
	}
}
