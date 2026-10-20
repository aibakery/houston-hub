package main

import (
	"encoding/base64"
	"net/http"
	"os"
	"testing"

	"github.com/aibakery/houston-hub/manifest"
)

func TestPrestaShopStoreHostAndAccessBoundaries(t *testing.T) {
	raw, err := os.ReadFile("../../connectors/prestashop/houston.json")
	if err != nil {
		t.Fatal(err)
	}
	m, err := manifest.Parse(raw)
	if err != nil {
		t.Fatal(err)
	}
	const key = "0123456789ABCDEF0123456789ABCDEF"
	for _, host := range []string{"", "https://shop.example.com", "shop.example.com/store", "*.example.com"} {
		if _, err := m.Resolve(nil, map[string]any{"store_host": host}, map[string]any{"token": key}, "key"); err == nil {
			t.Errorf("accepted store domain %q", host)
		}
	}
	if _, err := m.Resolve(nil, map[string]any{"store_host": "shop.example.com"}, map[string]any{"token": "short"}, "key"); err == nil {
		t.Error("accepted a key that is not 32 characters")
	}
	basic := "Basic " + base64.StdEncoding.EncodeToString([]byte(key+":"))
	for _, access := range []string{"read-only", "read-write"} {
		r, err := m.Resolve(nil, map[string]any{"access": access, "store_host": "Shop.Example.com"}, map[string]any{"token": key}, "key")
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
				t.Fatalf("access=%s denied %s %s: %v", access, method, url, err)
			}
			headers, err := recipe.Prepare(r.Context, caller)
			if err != nil || headers.Get("Authorization") != basic || caller.Get("Authorization") != "forged" {
				t.Fatalf("incorrect credential injection: %v", err)
			}
		}
		const api = "https://shop.example.com/api/"
		for _, path := range []string{
			"orders?display=full&limit=0%2C50", "orders/1", "order_details", "order_histories/2", "order_slip/3",
			"order_states", "order_carriers/4", "customers/5", "addresses", "carts/6", "products/7",
			"combinations", "categories/8", "stock_availables/9", "cart_rules", "languages",
		} {
			assertRoute("GET", api+path, true)
		}
		for _, route := range [][2]string{
			{"POST", "products"}, {"POST", "customers"}, {"POST", "order_histories?sendemail=1"},
			{"PATCH", "products/1"}, {"PATCH", "customers/1"}, {"PATCH", "order_carriers/1"}, {"PATCH", "stock_availables/1"},
			{"DELETE", "products/1"}, {"DELETE", "customers/1"},
		} {
			assertRoute(route[0], api+route[1], access == "read-write")
		}
		for _, route := range [][2]string{
			// Configuration values hold SMTP passwords and module secrets; employees hold password hashes.
			{"GET", api + "configurations"}, {"GET", api + "translated_configurations"}, {"GET", api + "employees/1"},
			{"GET", api + "shop_urls"}, {"GET", api + "images/customizations/1/1"}, {"GET", api}, {"GET", api + "orders/1/extra"},
			// The dispatcher entry point is never needed; /api paths reach it through the rewrite.
			{"GET", "https://shop.example.com/webservice/dispatcher.php?url=configurations"},
			{"PUT", api + "products/1"}, {"POST", api + "orders"}, {"PATCH", api + "orders/1"}, {"DELETE", api + "orders/1"},
			{"POST", api + "products/1"}, {"DELETE", api + "order_histories/1"}, {"HEAD", api + "orders"},
			// PrestaShop deletes every listed ID on a collection DELETE.
			{"DELETE", api + "products?id=%5B1%2C2%5D"}, {"DELETE", api + "customers"},
			{"GET", "https://www.shop.example.com/api/orders"},
			{"GET", "https://shop.example.com.attacker.test/api/orders"},
			{"GET", "https://shop.example.com:8443/api/orders"},
			{"GET", "http://shop.example.com/api/orders"},
			{"GET", api + "orders/%2e%2e/configurations"},
		} {
			assertRoute(route[0], route[1], false)
		}
	}
}
