package main

import (
	"net/http"
	"os"

	"testing"

	"github.com/aibakery/houston-hub/manifest"
)

func notionManifest(t *testing.T) *manifest.Manifest {
	t.Helper()
	raw, err := os.ReadFile("../../connectors/notion/houston.json")
	if err != nil {
		t.Fatal(err)
	}
	m, err := manifest.Parse(raw)
	if err != nil {
		t.Fatal(err)
	}
	return m
}

func notionConnection(t *testing.T, m *manifest.Manifest, method, access string) *manifest.Resolved {
	t.Helper()
	config := map[string]any{"access": access}
	var input map[string]any
	if method == "oauth" {
		config = map[string]any{"access": access, "client_id": "notion-client", "client_secret": "notion-publisher-secret"}
	} else {
		input = map[string]any{"token": method + "-secret"}
	}
	r, err := m.Resolve(nil, config, input, method)
	if err != nil {
		t.Fatal(err)
	}
	if method == "oauth" {
		if err := m.RequireCredentials(r.Context); err == nil {
			t.Fatal("OAuth connection became usable before token exchange")
		}
		r.Context.Auth[method]["access_token"] = "oauth-secret"
	}
	if err := m.RequireCredentials(r.Context); err != nil {
		t.Fatal(err)
	}
	if r.PublicConfig["access"] != access || r.PublicConfig["client_secret"] != nil {
		t.Fatalf("unexpected public settings: %#v", r.PublicConfig)
	}
	return r
}

func TestNotionRegistrationAndAuthenticationSelection(t *testing.T) {
	m := notionManifest(t)
	for _, publisher := range []map[string]any{nil, {"client_id": "client"}, {"client_secret": "secret"}, {"client_id": "client", "client_secret": "secret"}} {
		draft, err := m.ResolveDraft(nil, publisher, nil, "")
		if err != nil {
			t.Fatal(err)
		}
		for _, method := range draft.Methods {
			want := method.Key != "oauth" || len(publisher) == 2
			eligible := method.Key != "oauth" || publisher["client_id"] != nil
			if method.Eligible != eligible || method.Available != want {
				t.Fatalf("publisher=%v method=%+v; available=%v", publisher, method, want)
			}
		}
		if len(publisher) != 2 {
			if _, err := m.Resolve(nil, publisher, nil, "oauth"); err == nil {
				t.Fatal("OAuth activated without complete publisher settings")
			}
		}
		secretField := false
		for _, field := range draft.ConfigFields {
			if field.Name == "client_secret" {
				secretField = true
				if field.Field.Type != "secret" {
					t.Fatal("active OAuth secret form field must be secret")
				}
			}
		}
		if secretField != (publisher["client_id"] != nil) {
			t.Fatal("OAuth client secret form did not follow client ID activation")
		}
		manual, err := m.Resolve(nil, publisher, map[string]any{"token": "manual-token"}, "token")
		if err != nil || m.RequireCredentials(manual.Context) != nil {
			t.Fatalf("manual connection depends on optional OAuth setup: %v", err)
		}
		if manual.PublicConfig["access"] != "read-only" {
			t.Fatal("new connection did not default to read-only")
		}
	}
	for _, method := range []string{"token", "admin"} {
		if _, err := m.Resolve(nil, nil, nil, method); err == nil {
			t.Fatal("manual authentication accepted missing token")
		}
	}
	publisher := map[string]any{"client_id": "client", "client_secret": "secret"}
	if _, err := m.Resolve(nil, publisher, map[string]any{"access_token": "caller-token"}, "oauth"); err == nil {
		t.Fatal("caller supplied a managed OAuth credential")
	}
}

func TestNotionContentRoutesAndWriteBoundary(t *testing.T) {
	m := notionManifest(t)
	reads := [][2]string{
		{"GET", "/v1/pages/page-1/properties/f%5C%5C%3Ap"},
		{"GET", "/v1/pages/page-1/properties/a%2Fb"}, {"GET", "/v1/pages/page-1/properties/100%25"},
		{"GET", "/v1/users/me"}, {"GET", "/v1/pages/page-1/properties/title%3Aname?page_size=1"},
		{"GET", "/v1/pages/page-1/markdown"}, {"GET", "/v1/blocks/block-1/children"},
		{"GET", "/v1/file_uploads?status=uploaded"}, {"GET", "/v1/views/view-1/queries/query-1"},
		{"POST", "/v1/search"}, {"POST", "/v1/data_sources/source-1/query"},
		{"POST", "/v1/agents/query"}, {"POST", "/v1/sessions/session-1/events/query"},
		{"POST", "/v1/blocks/meeting_notes/query"},
	}
	writes := [][2]string{
		{"POST", "/v1/pages"}, {"POST", "/v1/pages/page-1/move"},
		{"POST", "/v1/file_uploads/file-1/send"}, {"POST", "/v1/file_uploads/file-1/complete"},
		{"POST", "/v1/databases"}, {"POST", "/v1/data_sources"},
		{"PATCH", "/v1/pages/page-1/markdown"}, {"PATCH", "/v1/blocks/block-1/children"},
		{"DELETE", "/v1/blocks/block-1"}, {"DELETE", "/v1/comments/comment-1"},
		{"POST", "/v1/sessions/session-1/cancel"}, {"PATCH", "/v1/agents/agent-1/credit_limit"},
	}
	for _, method := range []string{"token", "oauth"} {
		for _, access := range []string{"read-only", "read-write"} {
			t.Run(method+"/"+access, func(t *testing.T) {
				r := notionConnection(t, m, method, access)
				// Inactive saved methods must never supply fallback credentials.
				r.Context.Auth["admin"] = map[string]any{"token": "inactive-admin"}
				if method == "oauth" {
					r.Context.Auth["token"] = map[string]any{"token": "inactive-token"}
				}
				for _, route := range append(append([][2]string{}, reads...), writes...) {
					allowed := access == "read-write"
					for _, read := range reads {
						allowed = allowed || route == read
					}
					assertNotionRoute(t, m, r, route, allowed, method+"-secret", "2026-03-11")
				}
				for _, route := range [][2]string{
					{"GET", "/v1/search"}, {"PUT", "/v1/pages/page-1"},
					{"POST", "/v1/users"}, {"DELETE", "/v1/file_uploads/file-1"},
					{"GET", "/v1/oauth/token"}, {"POST", "/v1/oauth/revoke"},
					{"GET", "/admin/v1/analytics/reports"}, {"POST", "/admin/v1/legal_holds"},
				} {
					assertNotionRoute(t, m, r, route, false, "", "")
				}
			})
		}
	}
}

func assertNotionRoute(t *testing.T, m *manifest.Manifest, r *manifest.Resolved, route [2]string, allowed bool, credential, version string) {
	t.Helper()
	caller := http.Header{"Authorization": {"forged"}, "Notion-Version": {"old"}}
	recipe, err := m.Proxy.Select(r.ProxyIndices).HTTPRecipe(route[0], "https://api.notion.com"+route[1], caller)
	if !allowed {
		if err == nil {
			t.Fatalf("unexpectedly allowed %v", route)
		}
		return
	}
	if err != nil {
		t.Fatalf("denied %v: %v", route, err)
	}
	headers, err := recipe.Prepare(r.Context, caller)
	if err != nil || headers.Get("Authorization") != "Bearer "+credential || headers.Get("Notion-Version") != version {
		t.Fatalf("wrong injection for %v: %v, %v", route, headers, err)
	}
	if caller.Get("Authorization") != "forged" || caller.Get("Notion-Version") != "old" {
		t.Fatal("header preparation mutated caller's headers")
	}
}

func TestNotionAdminRouteSeparation(t *testing.T) {
	m := notionManifest(t)
	for _, access := range []string{"read-only", "read-write"} {
		r := notionConnection(t, m, "admin", access)
		r.Context.Auth["token"] = map[string]any{"token": "inactive-token"}
		for _, route := range [][2]string{
			{"GET", "/admin/v1/analytics/reports"}, {"GET", "/admin/v1/legal_holds/hold-1/spaces/space-1/pages"},
			{"GET", "/admin/v1/spaces/space-1/groups/group-1/members"},
		} {
			assertNotionRoute(t, m, r, route, true, "admin-secret", "2026-06-01")
		}
		for _, route := range [][2]string{
			{"POST", "/admin/v1/legal_holds/hold-1/export"}, {"PATCH", "/admin/v1/spaces/space-1/groups/group-1"},
			{"PUT", "/admin/v1/spaces/space-1/agents/agent-1/credit_limit"},
			{"DELETE", "/admin/v1/spaces/space-1/personal_access_tokens/bot-1"},
		} {
			assertNotionRoute(t, m, r, route, access == "read-write", "admin-secret", "2026-06-01")
		}
		for _, route := range [][2]string{
			{"GET", "/v1/users/me"}, {"POST", "/v1/search"}, {"POST", "/v1/pages"},
			{"PUT", "/admin/v1/legal_holds/hold-1"}, {"DELETE", "/admin/v1/spaces/space-1/users"},
		} {
			assertNotionRoute(t, m, r, route, false, "", "")
		}
	}
}

func TestNotionDownloadBoundaries(t *testing.T) {
	m := notionManifest(t)
	for _, method := range []string{"token", "oauth", "admin"} {
		r := notionConnection(t, m, method, "read-only")
		rules := m.Proxy.Select(r.ProxyIndices)
		for _, url := range []string{
			"https://s3.us-west-2.amazonaws.com/secure.notion-static.com/folder/100%25%2Ffile.pdf?X-Amz-Signature=exact%2Fvalue",
			"https://prod-files-secure.s3.us-west-2.amazonaws.com/workspace/100%25.pdf",
			"https://s3.us-west-2.amazonaws.com/secure.notion-static.com/file.pdf?X-Amz-Signature=signed",
			"https://s3-us-west-2.amazonaws.com/public.notion-static.com/file.pdf",
			"https://prod-files-secure.s3.us-west-2.amazonaws.com/workspace/file.pdf",
			"https://prod-files-secure-euc1.s3.eu-central-1.amazonaws.com/workspace/file.pdf",
			"https://prod-files-secure-apne1.s3.ap-northeast-1.amazonaws.com/workspace/file.pdf",
			"https://notion-production-snapshots-2.s3.us-west-2.amazonaws.com/export.zip",
			"https://file.notion.so/f/f/file.pdf", "https://file.notion.com/f/f/file.pdf",
		} {
			caller := http.Header{"Authorization": {"must-not-leak"}, "Notion-Version": {"must-not-leak"}}
			recipe, err := rules.HTTPRecipe("GET", url, caller)
			if err != nil {
				t.Fatal(err)
			}
			headers, err := recipe.Prepare(r.Context, caller)
			if err != nil || headers.Get("Authorization") != "" || headers.Get("Notion-Version") != "" || recipe.URL != url {
				t.Fatalf("download credentials or signed URL changed: %v, %v", headers, err)
			}
			if _, err := rules.HTTPRecipe("POST", url, caller); err == nil {
				t.Fatalf("upload allowed to download-only URL %s", url)
			}
		}
		for _, url := range []string{
			"https://s3.us-west-2.amazonaws.com/unrelated-bucket/file.pdf",
			"https://s3.us-west-2.amazonaws.com/secure.notion-static.com.evil/file.pdf",
			"https://s3.us-west-2.amazonaws.com/secure.notion-static.com/%2e%2e/unrelated/file.pdf",
			"https://s3.us-west-2.amazonaws.com/secure.notion-static.com/file%2F..%2Fescape",
			"https://prod-files-secure.s3.us-west-2.amazonaws.com.attacker.test/file.pdf",
			"https://arbitrary-bucket.s3.us-west-2.amazonaws.com/file.pdf",
			"http://file.notion.so/file.pdf", "https://file.notion.so:8443/file.pdf",
			"https://api.notion.com.attacker.test/v1/users/me", "https://api.notion.com/v1/unknown",
		} {
			if _, err := rules.HTTPRecipe("GET", url, nil); err == nil {
				t.Fatalf("untrusted route accepted: %s", url)
			}
		}
	}
}
