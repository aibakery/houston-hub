package main

import (
	"encoding/base64"
	"net/http"
	"os"
	"testing"

	"github.com/aibakery/houston-hub/manifest"
)

func TestWooCommerceStoreHostAndAccessBoundaries(t *testing.T) {
	raw, err := os.ReadFile("../../connectors/woocommerce/houston.json")
	if err != nil {
		t.Fatal(err)
	}
	m, err := manifest.Parse(raw)
	if err != nil {
		t.Fatal(err)
	}
	keys := map[string]any{"consumer_key": "ck_fixture", "consumer_secret": "cs_fixture"}
	for _, host := range []string{"", "https://shop.example.com", "shop.example.com/store", "*.example.com"} {
		if _, err := m.Resolve(nil, map[string]any{"store_host": host}, keys, "keys"); err == nil {
			t.Errorf("accepted store domain %q", host)
		}
	}
	basic := "Basic " + base64.StdEncoding.EncodeToString([]byte("ck_fixture:cs_fixture"))
	for _, access := range []string{"read-only", "read-write"} {
		r, err := m.Resolve(nil, map[string]any{"access": access, "store_host": "Shop.Example.com"}, keys, "keys")
		if err != nil {
			t.Fatal(err)
		}
		if r.PublicConfig["store_host"] != "Shop.Example.com" || len(r.PublicConfig) != 2 {
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
				t.Fatal(err)
			}
			headers, err := recipe.Prepare(r.Context, caller)
			if err != nil || headers.Get("Authorization") != basic || caller.Get("Authorization") != "forged" {
				t.Fatalf("incorrect credential injection: %v", err)
			}
		}
		const api = "https://shop.example.com/wp-json/wc/v3"
		for _, path := range []string{"/orders?status%5B%5D=processing", "/orders/1/notes", "/reports/sales", "/data/currencies/current"} {
			assertRoute("GET", api+path, true)
		}
		for _, route := range [][2]string{{"POST", "/orders"}, {"PUT", "/orders/1"}, {"DELETE", "/products/1?force=true"}, {"POST", "/products/batch"}, {"PUT", "/system_status/tools/clear_transients"}} {
			assertRoute(route[0], api+route[1], access == "read-write")
		}
		for _, route := range [][2]string{
			{"PATCH", api + "/orders/1"},
			{"GET", "https://shop.example.com/wp-json/wp/v2/users"},
			{"GET", "https://shop.example.com/wp-json/wc/v2/orders"},
			{"GET", "https://shop.example.com/wp-admin/"},
			{"GET", "https://www.shop.example.com/wp-json/wc/v3/orders"},
			{"GET", "https://shop.example.com.attacker.test/wp-json/wc/v3/orders"},
			{"GET", "https://shop.example.com:8443/wp-json/wc/v3/orders"},
			{"GET", "http://shop.example.com/wp-json/wc/v3/orders"},
			{"GET", api + "/orders/%2e%2e/%2e%2e/users"},
		} {
			assertRoute(route[0], route[1], false)
		}
	}
}
