package main

import (
	"github.com/aibakery/houston-hub/interfaces"
	"github.com/aibakery/houston-hub/manifest"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// Each method exercises the actual shared resolver and native injection recipe.
// Provider execution is separately covered by the bundle's mocked Luau fixtures.
func TestEveryProviderAuthenticationAndTransport(t *testing.T) {
	paths, err := filepath.Glob("../../connectors/*/houston.json")
	if err != nil {
		t.Fatal(err)
	}
	endpoints := map[string][2]string{
		"attio": {"GET", "https://api.attio.com/v2/self"}, "granola": {"GET", "https://public-api.granola.ai/v1/notes"},
		"gmail": {"GET", "https://gmail.googleapis.com/gmail/v1/users/me/profile"}, "gdrive": {"GET", "https://www.googleapis.com/drive/v3/files"},
		"gcalendar": {"GET", "https://www.googleapis.com/calendar/v3/users/me/calendarList"}, "dropbox": {"POST", "https://api.dropboxapi.com/2/files/list_folder"},
		"slack": {"GET", "https://slack.com/api/auth.test"}, "fastmail": {"GET", "https://api.fastmail.com/jmap/session"},
	}
	for _, path := range paths {
		provider := filepath.Base(filepath.Dir(path))
		raw, err := os.ReadFile(path)
		if err != nil {
			t.Fatal(err)
		}
		m, err := manifest.Parse(raw)
		if err != nil {
			t.Fatal(err)
		}
		if _, err := interfaces.Resolve(m.Implements); err != nil {
			t.Fatal(err)
		}
		keys := m.MethodKeys()
		if len(keys) == 0 {
			keys = []string{""}
		}
		for _, method := range keys {
			t.Run(provider+"/"+method, func(t *testing.T) {
				publisher := map[string]any{}
				if len(m.Publisher) > 0 {
					publisher["client_id"] = "synthetic-public-client"
					publisher["client_secret"] = "synthetic-publisher-secret"
				}
				config := map[string]any{}
				input := map[string]any{}
				if provider == "slack" {
					config["workspace_id"] = "T_SYNTHETIC"
				}
				if m.Proxy[0].Protocol != "http" {
					config["host"] = "database.example.com"
					config["database"] = "sample"
					config["username"] = "reader"
					config["password"] = "synthetic-root-secret"
				}
				if method != "" && m.Auth[method].Type == "manual" {
					input["token"] = "synthetic-method-secret"
				}
				r, err := m.Resolve(publisher, config, input, method)
				if err != nil {
					t.Fatal(err)
				}
				for k, v := range r.PublicConfig {
					if m.Config[k].Type == "secret" || strings.Contains(strings.TrimSpace(stringValue(v)), "secret") {
						t.Fatalf("private value in runtime config: %s", k)
					}
				}
				if m.Proxy[r.ProxyIndex].Protocol == "http" {
					credential := "synthetic-method-secret"
					if m.Auth[method].Type == "oauth2" {
						credential = "synthetic-oauth-token"
						r.Context.Auth[method]["access_token"] = credential
						if len(r.Scopes) == 0 {
							t.Fatal("OAuth scopes missing")
						}
					}
					if err := m.RequireCredentials(r.Context); err != nil {
						t.Fatal(err)
					}
					ep := endpoints[provider]
					recipe, err := m.Proxy[r.ProxyIndex].HTTPRecipe(ep[0], ep[1])
					if err != nil {
						t.Fatal(err)
					}
					h, err := recipe.Prepare(r.Context, http.Header{"Authorization": []string{"caller-forgery"}})
					if err != nil {
						t.Fatal(err)
					}
					if h.Get("Authorization") != "Bearer "+credential {
						t.Fatalf("wrong injection %q", h.Get("Authorization"))
					}
					if _, err := m.Proxy[r.ProxyIndex].HTTPRecipe("GET", "https://unlisted.example.com/"); err == nil {
						t.Fatal("unlisted origin accepted")
					}
					if provider == "slack" {
						recipe, err := m.Proxy[r.ProxyIndex].HTTPRecipe("POST", "https://files.slack.com/upload/v1/signed")
						if err != nil {
							t.Fatal(err)
						}
						h, err := recipe.Prepare(r.Context, http.Header{"Authorization": []string{"caller-forgery"}})
						if err != nil || h.Get("Authorization") != "" {
							t.Fatalf("signed upload injected auth: %v %v", h, err)
						}
					}
				} else {
					db, err := m.Proxy[r.ProxyIndex].ResolveDatabase(r.Context)
					if err != nil {
						t.Fatal(err)
					}
					if db.Password != "synthetic-root-secret" || db.Host != "database.example.com" || db.TLSMode != "verify-full" {
						t.Fatalf("invalid native database recipe: %#v", db)
					}
					if provider == "clickhouse" {
						config["transport"] = "native"
						r, err = m.Resolve(publisher, config, input, method)
						if err != nil {
							t.Fatal(err)
						}
						db, err = m.Proxy[r.ProxyIndex].ResolveDatabase(r.Context)
						if err != nil || db.Port != 9440 {
							t.Fatalf("native ClickHouse port %d: %v", db.Port, err)
						}
					}
				}
			})
		}
	}
}
func stringValue(v any) string { s, _ := v.(string); return s }
