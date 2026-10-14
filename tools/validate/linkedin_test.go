package main

import (
	"net/http"
	"os"
	"slices"
	"strings"
	"testing"

	"github.com/aibakery/houston-hub/manifest"
)

func linkedInManifest(t *testing.T) *manifest.Manifest {
	t.Helper()
	raw, err := os.ReadFile("../../connectors/linkedin/houston.json")
	if err != nil {
		t.Fatal(err)
	}
	m, err := manifest.Parse(raw)
	if err != nil {
		t.Fatal(err)
	}
	return m
}

// Houston's LinkedIn app serves every connection, so users only choose an access
// level and authorize their account.
func TestLinkedInPublisherOwnedClient(t *testing.T) {
	m := linkedInManifest(t)
	if !m.Auth["oauth"].PublisherClient() {
		t.Fatal("LinkedIn OAuth client must belong to the publication")
	}
	for _, publisher := range []map[string]any{nil, {"client_id": "client"}, {"client_id": "client", "client_secret": "secret"}} {
		draft, err := m.ResolveDraft(publisher, nil, nil, "")
		if err != nil {
			t.Fatal(err)
		}
		for _, field := range draft.ConfigFields {
			if field.Name != "access" {
				t.Fatalf("connection form asks for %s", field.Name)
			}
		}
		want := len(publisher) == 2
		if len(draft.Methods) != 1 || draft.Methods[0].Available != want {
			t.Fatalf("publisher=%v methods=%+v; available=%v", publisher, draft.Methods, want)
		}
	}
	publisher := map[string]any{"client_id": "client", "client_secret": "secret"}
	if _, err := m.Resolve(publisher, map[string]any{"client_id": "own-client", "client_secret": "own-secret"}, nil, "oauth"); err == nil {
		t.Fatal("connection replaced the publication's OAuth client")
	}
	r, err := m.Resolve(publisher, nil, nil, "oauth")
	if err != nil {
		t.Fatal(err)
	}
	if r.PublicConfig["access"] != "read-only" || len(r.PublicConfig) != 1 {
		t.Fatalf("unexpected public settings: %#v", r.PublicConfig)
	}
}

func TestLinkedInScopesAndAccessRoutes(t *testing.T) {
	m := linkedInManifest(t)
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
		publisher := map[string]any{"client_id": "fixture-client", "client_secret": "fixture-secret"}
		r, err := m.Resolve(publisher, map[string]any{"access": access}, nil, "oauth")
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
