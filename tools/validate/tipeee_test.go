package main

import (
	"net/http"
	"net/url"
	"testing"
)

func TestTipeeeCreatorRoutesAndQueryCredentials(t *testing.T) {
	m := parseManifest(t, "../../connectors/tipeee/houston.json")
	for _, access := range []string{"read-only", "read-write"} {
		t.Run(access, func(t *testing.T) {
			r, err := m.Resolve(nil, map[string]any{"access": access}, map[string]any{"token": "synthetic +&token"}, "token")
			if err != nil {
				t.Fatal(err)
			}
			cases := []struct {
				method, path string
				write        bool
			}{
				{"GET", "/v2.0/credentials/me", true},
				{"GET", "/v2.0/projects/creator", true},
				{"GET", "/v2.0/projects/creator/campaigns/oct/subscriptions", false},
				{"GET", "/v2.0/project/unique?slug=creator", false},
				{"GET", "/v2.0/projects/creator/rewards_default", false},
				{"GET", "/v2.0/projects/creator/top/tippers", false},
				{"GET", "/v2.0/feed/users/creator/projects/art", false},
				{"PUT", "/v2.0/feed/users/creator/projects/art/read", true},
				{"PUT", "/v2.0/feed/users/creator/notifications/12/read", true},
				{"GET", "/v2.0/inbox/projects/art/subscription/12", true},
				{"GET", "/v2.0/projects/creator/admin/messages", true},
				{"POST", "/v2.0/projects/creator/admins/messages", true},
				{"GET", "/documents/payments/creator_2026.csv", false},
				{"GET", "/v2.0/inbox/threads/123/content", true},
				{"GET", "/v2.0/projects/creator/widgets", true},
				{"GET", "/documents/tippers/oct.xlsx?allTabs=1", true},
				{"POST", "/v2.0/projects/creator/rewards/12", true},
				{"PUT", "/v2.0/projects/creator/rewards/12/transition", true},
				{"PUT", "/v2.0/projects/creator/payout", true},
				{"DELETE", "/v2.0/threads/news/comments/12", true},
				{"POST", "/v2.0/inbox/contents/files", true},
				{"POST", "/v2.0/projects/creator/validation", true},
				{"POST", "/v2.0/projects/creator/tos/validation", true},
				{"PUT", "/v2.0/projects/creator/delete_email_request", true},
				{"POST", "/v2.0/projects/creator/pre_delete", true},
			}
			for _, c := range cases {
				recipe, err := r.Proxy.HTTPRecipe(c.method, "https://api.tipeee.com"+c.path, nil)
				allowed := !c.write || access == "read-write"
				if (err == nil) != allowed {
					t.Fatalf("%s %s: %v", c.method, c.path, err)
				}
				if !allowed {
					continue
				}
				prepared, err := recipe.PrepareURL(r.Context)
				if err != nil {
					t.Fatal(err)
				}
				parsed, err := url.Parse(prepared)
				if err != nil || parsed.Query().Get("access_token") != "synthetic +&token" {
					t.Fatalf("query credential not injected: %v", err)
				}
				h, err := recipe.Prepare(r.Context, http.Header{"Authorization": {"forged"}, "Cookie": {"session=forged"}, "X-Http-Method-Override": {"DELETE"}, "X-Http-Method": {"DELETE"}, "X-Method-Override": {"DELETE"}, "Accept": {"application/json"}})
				if err != nil || len(h) != 1 || h.Get("Accept") != "application/json" {
					t.Fatalf("unsafe caller headers: %v %v", h, err)
				}
			}
			for _, c := range [][2]string{
				{"GET", "https://api.tipeee.com.evil.example/v2.0/credentials/me"},
				{"GET", "http://api.tipeee.com/v2.0/credentials/me"},
				{"POST", "https://api.tipeee.com/oauth/v2/token"},
				{"GET", "https://api.tipeee.com/v2.0/projects/creator/apikey"},
				{"POST", "https://api.tipeee.com/v2.0/projects/creator/apikeys"},
				{"GET", "https://api.tipeee.com/v2.0/projects/creator/subscriptions/last"},
				{"POST", "https://api.tipeee.com/v2.0/projects/creator/simulate_events"},
				{"GET", "https://api.tipeee.com/v2.0/projects/../credentials/me"},
				{"POST", "https://api.tipeee.com/v2.0/projects/creator/tips"},
				{"DELETE", "https://api.tipeee.com/v2.0/credentials/me"},
			} {
				if _, err := r.Proxy.HTTPRecipe(c[0], c[1], nil); err == nil {
					t.Fatalf("forbidden route allowed: %v", c)
				}
			}
		})
	}
}
