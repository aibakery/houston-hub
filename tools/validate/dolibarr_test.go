package main

import (
	"net/http"
	"strings"
	"testing"

	"github.com/aibakery/houston-hub/manifest"
)

// assertDolibarrRoutes checks each "METHOD URL" route's access, and that allowed
// routes carry the key in DOLAPIKEY and drop forged credentials and method overrides.
func assertDolibarrRoutes(t *testing.T, r *manifest.Resolved, key string, allowed bool, routes ...string) {
	t.Helper()
	for _, route := range routes {
		method, url, _ := strings.Cut(route, " ")
		recipe, err := r.Proxy.HTTPRecipe(method, url, nil)
		if (err == nil) != allowed {
			t.Fatalf("%s allowed=%v: %v", route, err == nil, err)
		}
		if err != nil {
			continue
		}
		headers, err := recipe.Prepare(r.Context, http.Header{"Dolapikey": {"forged"}, "Authorization": {"Bearer forged"}, "X-Http-Method-Override": {"DELETE"}})
		if err != nil || headers.Get("DOLAPIKEY") != key || headers.Get("Authorization") != "" || headers.Get("X-HTTP-Method-Override") != "" {
			t.Fatalf("credential injection for %s: %v %v", route, headers, err)
		}
	}
}

func TestDolibarrHostInstallPathAndAccessBoundaries(t *testing.T) {
	m := parseManifest(t, "../../connectors/dolibarr/houston.json")
	const key = "Zx81Kq0PnB2vLm4TcR7wYs9dHf3jGa6E"
	for _, host := range []string{"", "https://erp.example.com", "example.com/dolibarr", "*.example.com"} {
		if _, err := m.Resolve(nil, map[string]any{"host": host}, map[string]any{"token": key}, "key"); err == nil {
			t.Errorf("accepted Dolibarr domain %q", host)
		}
	}
	for _, access := range []string{"read-only", "read-write"} {
		r, err := m.Resolve(nil, map[string]any{"access": access, "host": "ERP.Example.com", "install_path": "/dolibarr"}, map[string]any{"token": key}, "key")
		if err != nil {
			t.Fatal(err)
		}
		if r.PublicConfig["host"] != "ERP.Example.com" || r.PublicConfig["install_path"] != "/dolibarr" || len(r.PublicConfig) != 3 {
			t.Fatalf("unexpected Lua config: %v", r.PublicConfig)
		}
		// Dolibarr is served at the root of a domain or in one or two folders.
		for _, api := range []string{"https://erp.example.com/api/index.php", "https://erp.example.com/dolibarr/api/index.php", "https://erp.example.com/dolibarr/htdocs/api/index.php"} {
			assertDolibarrRoutes(t, r, key, true,
				"GET "+api+"/status", "GET "+api+"/thirdparties?limit=100&page=0", "GET "+api+"/thirdparties/12", "GET "+api+"/contacts/3",
				"GET "+api+"/products/9/stock", "GET "+api+"/warehouses", "GET "+api+"/stockmovements", "GET "+api+"/categories/2",
				"GET "+api+"/orders/7", "GET "+api+"/invoices/42/payments", "GET "+api+"/proposals", "GET "+api+"/shipments/1",
				"GET "+api+"/supplierorders", "GET "+api+"/supplierinvoices/5/payments", "GET "+api+"/bankaccounts/1/lines",
				"GET "+api+"/bankaccounts/1/balance", "GET "+api+"/setup/dictionary/payment_types")
			assertDolibarrRoutes(t, r, key, access == "read-write",
				"POST "+api+"/thirdparties", "PUT "+api+"/thirdparties/12", "POST "+api+"/contacts", "PUT "+api+"/contacts/3",
				"POST "+api+"/products", "PUT "+api+"/products/9", "POST "+api+"/stockmovements", "POST "+api+"/orders",
				"POST "+api+"/orders/7/lines", "POST "+api+"/orders/7/validate", "POST "+api+"/orders/7/close", "POST "+api+"/invoices",
				"POST "+api+"/invoices/createfromorder/7", "POST "+api+"/invoices/42/lines", "POST "+api+"/invoices/42/validate",
				"POST "+api+"/invoices/42/payments")
			assertDolibarrRoutes(t, r, key, false,
				// /login returns or regenerates a key; users, setup and documents expose credentials, configuration and backups.
				"GET "+api+"/login?login=admin&password=x", "POST "+api+"/login", "GET "+api+"/users/info", "GET "+api+"/users/1",
				"GET "+api+"/users/1/setGroup/1", "GET "+api+"/setup/conf/MAIN_MAIL_SMTPS_PW", "GET "+api+"/setup/company",
				"GET "+api+"/documents/download?modulepart=admin_temp", "GET "+api+"/explorer/swagger.json",
				// GET routes that change data.
				"GET "+api+"/thirdparties/1/generateBankAccountDocument/1/sepamandate", "GET "+api+"/accountancy/exportdata",
				"GET "+api+"/thirdparties/1/bankaccounts", "GET "+api+"/mailings/clone/1",
				"DELETE "+api+"/invoices/42", "DELETE "+api+"/thirdparties/12", "PUT "+api+"/thirdparties/12/merge/13",
				"POST "+api+"/contacts/3/createUser", "PUT "+api+"/invoices/42", "POST "+api+"/invoices/42/settopaid",
				"POST "+api+"/thirdparties/12", "PUT "+api+"/orders/7", "HEAD "+api+"/invoices", "PATCH "+api+"/products/9",
				"GET "+api+"/invoices/%2e%2e/users/1")
		}
		assertDolibarrRoutes(t, r, key, false,
			"GET https://erp.example.com/a/b/c/api/index.php/status", "GET https://erp.example.com/api/status",
			"GET https://erp.example.com/index.php", "GET https://erp.example.com/api/index.php/",
			"GET https://www.erp.example.com/api/index.php/status", "GET https://erp.example.com.attacker.test/api/index.php/status",
			"GET https://erp.example.com:8443/api/index.php/status", "GET http://erp.example.com/api/index.php/status")
	}
}
