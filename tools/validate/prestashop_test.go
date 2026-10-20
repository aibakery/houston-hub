package main

import (
	"encoding/base64"
	"testing"
)

func TestPrestaShopStoreHostAndAccessBoundaries(t *testing.T) {
	m := parseManifest(t, "../../connectors/prestashop/houston.json")
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
	const api = "https://shop.example.com/api/"
	for _, access := range []string{"read-only", "read-write"} {
		r, err := m.Resolve(nil, map[string]any{"access": access, "store_host": "Shop.Example.com"}, map[string]any{"token": key}, "key")
		if err != nil {
			t.Fatal(err)
		}
		if r.PublicConfig["store_host"] != "Shop.Example.com" || len(r.PublicConfig) != 2 {
			t.Fatalf("unexpected Lua config: %v", r.PublicConfig)
		}
		assertAuthorizedRoutes(t, r, basic, true,
			"GET "+api+"orders?display=full&limit=0%2C50", "GET "+api+"orders/1", "GET "+api+"order_details",
			"GET "+api+"order_histories/2", "GET "+api+"order_slip/3", "GET "+api+"order_states", "GET "+api+"order_carriers/4",
			"GET "+api+"customers/5", "GET "+api+"addresses", "GET "+api+"carts/6", "GET "+api+"products/7",
			"GET "+api+"combinations", "GET "+api+"categories/8", "GET "+api+"stock_availables/9", "GET "+api+"cart_rules",
			"GET "+api+"languages")
		assertAuthorizedRoutes(t, r, basic, access == "read-write",
			"POST "+api+"products", "POST "+api+"customers", "POST "+api+"order_histories?sendemail=1",
			"PATCH "+api+"products/1", "PATCH "+api+"customers/1", "PATCH "+api+"order_carriers/1", "PATCH "+api+"stock_availables/1",
			"DELETE "+api+"products/1", "DELETE "+api+"customers/1")
		assertAuthorizedRoutes(t, r, basic, false,
			// Configuration values hold SMTP passwords and module secrets; employees hold password hashes.
			"GET "+api+"configurations", "GET "+api+"translated_configurations", "GET "+api+"employees/1",
			"GET "+api+"shop_urls", "GET "+api+"images/customizations/1/1", "GET "+api, "GET "+api+"orders/1/extra",
			// The dispatcher entry point is never needed; /api paths reach it through the rewrite.
			"GET https://shop.example.com/webservice/dispatcher.php?url=configurations",
			"PUT "+api+"products/1", "POST "+api+"orders", "PATCH "+api+"orders/1", "DELETE "+api+"orders/1",
			"POST "+api+"products/1", "DELETE "+api+"order_histories/1", "HEAD "+api+"orders",
			// PrestaShop deletes every listed ID on a collection DELETE.
			"DELETE "+api+"products?id=%5B1%2C2%5D", "DELETE "+api+"customers",
			"GET https://www.shop.example.com/api/orders", "GET https://shop.example.com.attacker.test/api/orders",
			"GET https://shop.example.com:8443/api/orders", "GET http://shop.example.com/api/orders",
			"GET "+api+"orders/%2e%2e/configurations")
	}
}
