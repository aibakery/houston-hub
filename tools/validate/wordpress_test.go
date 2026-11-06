package main

import (
	"encoding/base64"
	"net/http"
	"os"
	"testing"

	"github.com/aibakery/houston-hub/manifest"
)

func TestWordPressSiteHostAndAccessBoundaries(t *testing.T) {
	raw, err := os.ReadFile("../../connectors/wordpress/houston.json")
	if err != nil {
		t.Fatal(err)
	}
	m, err := manifest.Parse(raw)
	if err != nil {
		t.Fatal(err)
	}
	password := map[string]any{"username": "editor", "password": "abcd efgh ijkl mnop qrst uvwx"}
	for _, host := range []string{"", "https://blog.example.com", "blog.example.com/wp", "*.example.com"} {
		if _, err := m.Resolve(nil, map[string]any{"site_host": host}, password, "application_password"); err == nil {
			t.Errorf("accepted site domain %q", host)
		}
	}
	basic := "Basic " + base64.StdEncoding.EncodeToString([]byte("editor:abcd efgh ijkl mnop qrst uvwx"))
	for _, access := range []string{"read-only", "read-write"} {
		r, err := m.Resolve(nil, map[string]any{"access": access, "site_host": "Blog.Example.com"}, password, "application_password")
		if err != nil {
			t.Fatal(err)
		}
		if r.PublicConfig["site_host"] != "Blog.Example.com" || len(r.PublicConfig) != 2 {
			t.Fatalf("unexpected Lua config: %v", r.PublicConfig)
		}
		assertRoute := func(method, url string, allowed bool) {
			t.Helper()
			caller := http.Header{"Authorization": {"forged"}}
			recipe, err := r.Proxy.HTTPRecipe(method, url, caller)
			if !allowed {
				if err == nil {
					t.Fatalf("access=%s allowed %s %s", access, method, url)
				}
				return
			}
			if err != nil {
				t.Fatalf("access=%s denied %s %s: %v", access, method, url, err)
			}
			headers, err := recipe.Prepare(r.Context, caller)
			if err != nil || headers.Get("Authorization") != basic || caller.Get("Authorization") != "forged" {
				t.Fatalf("incorrect credential injection: %v", err)
			}
			assertPrepareRejectsMethodOverrides(t, recipe, r.Context, method+" "+url)
		}
		const api = "https://blog.example.com/wp-json/wp/v2"
		for _, path := range []string{
			"/posts?status%5B%5D=draft&context=edit", "/posts/1", "/posts/1/revisions", "/posts/1/revisions/2",
			"/pages", "/pages/1/revisions/2", "/media", "/media/3", "/categories/4", "/tags", "/comments?status=hold",
			"/comments/5", "/users", "/users/me", "/search?search=x", "/types/post", "/statuses", "/taxonomies/category",
		} {
			assertRoute("GET", api+path, true)
		}
		assertRoute("GET", api+"/settings", access == "read-write")
		for _, route := range [][2]string{
			{"POST", "/posts"}, {"POST", "/posts/1"}, {"DELETE", "/posts/1?force=true"}, {"POST", "/pages/2"},
			{"POST", "/media"}, {"POST", "/media/3"}, {"DELETE", "/media/3?force=true"}, {"POST", "/categories"},
			{"DELETE", "/tags/4?force=true"}, {"POST", "/comments/5"}, {"DELETE", "/comments/5"},
		} {
			assertRoute(route[0], api+route[1], access == "read-write")
		}
		// Plugins and themes run code on the site, application passwords are credentials, and
		// user changes can grant roles; batch requests would tunnel any route.
		for _, route := range [][2]string{
			{"GET", api + "/plugins"}, {"POST", api + "/plugins"}, {"GET", api + "/themes"},
			{"GET", api + "/users/me/application-passwords"}, {"POST", api + "/users/1/application-passwords"},
			{"GET", api + "/users/me/application-passwords/introspect"},
			{"POST", api + "/users"}, {"POST", api + "/users/1"}, {"DELETE", api + "/users/1"},
			{"POST", api + "/settings"}, {"POST", api + "/media/3/post-process"}, {"POST", api + "/posts/1/autosaves"},
			{"DELETE", api + "/posts/1/revisions/2"}, {"PUT", api + "/posts/1"}, {"PATCH", api + "/posts/1"},
			{"DELETE", api + "/posts"}, {"DELETE", api + "/comments"}, {"DELETE", api + "/media"},
			{"POST", "https://blog.example.com/wp-json/batch/v1"}, {"GET", api + "/block-directory/search"},
			{"POST", api + "/templates"}, {"POST", api + "/global-styles/1"}, {"GET", "https://blog.example.com/wp-json/"},
			{"GET", "https://blog.example.com/wp-json/wc/v3/orders"}, {"GET", "https://blog.example.com/wp-admin/"},
			{"GET", "https://blog.example.com/?rest_route=/wp/v2/posts"},
			{"GET", "https://www.blog.example.com/wp-json/wp/v2/posts"},
			{"GET", "https://blog.example.com.attacker.test/wp-json/wp/v2/posts"},
			{"GET", "https://blog.example.com:8443/wp-json/wp/v2/posts"},
			{"GET", "http://blog.example.com/wp-json/wp/v2/posts"},
			{"GET", api + "/posts/%2e%2e/users/1/application-passwords"},
		} {
			assertRoute(route[0], route[1], false)
		}
	}
}
