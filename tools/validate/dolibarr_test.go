package main

import (
	"net/http"
	"os"
	"regexp"
	"slices"
	"strings"
	"testing"

	"github.com/aibakery/houston-hub/manifest"
)

// assertDolibarrRoutes checks each "METHOD URL" route's access, and that allowed routes
// carry the key in DOLAPIKEY and drop forged credentials, entities and method overrides
// (Restler also reads http_method from cookies).
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
		headers, err := recipe.Prepare(r.Context, http.Header{"Dolapikey": {"forged"}, "Authorization": {"Bearer forged"},
			"X-Http-Method-Override": {"DELETE"}, "Dolapientity": {"2"}, "Cookie": {"http_method=DELETE"}})
		if err != nil || headers.Get("DOLAPIKEY") != key {
			t.Fatalf("credential injection for %s: %v %v", route, headers, err)
		}
		for _, name := range []string{"Authorization", "X-HTTP-Method-Override", "DOLAPIENTITY", "Cookie"} {
			if headers.Get(name) != "" {
				t.Fatalf("%s kept %s", route, name)
			}
		}
	}
}

// The proxy allows exactly the connector's endpoint tables at the root and below one or
// two folders, with writes only on read-write connections.
func TestDolibarrProxyMatchesEndpointTables(t *testing.T) {
	lua, err := os.ReadFile("../../connectors/dolibarr/connector.luau")
	if err != nil {
		t.Fatal(err)
	}
	// Each endpoint entry starts a line with its name, method and path in any order.
	field := regexp.MustCompile(`\b(method|path) = "([^"]+)"`)
	var want, got []string
	for _, line := range strings.Split(string(lua), "\n") {
		if !strings.Contains(line, `{name = "`) {
			continue
		}
		method, path, gate := "GET", "", ""
		for _, match := range field.FindAllStringSubmatch(line, -1) {
			if match[1] == "method" {
				method, gate = match[2], `{{ is config.access "read-write" }}`
			} else {
				path = match[2]
			}
		}
		if path == "" {
			t.Fatalf("endpoint entry without a path on its first line: %s", line)
		}
		for _, prefix := range []string{"", "/{base}", "/{base}/{sub}"} {
			want = append(want, method+" "+prefix+"/api/index.php"+path+" "+gate)
		}
	}
	for _, rule := range parseManifest(t, "../../connectors/dolibarr/houston.json").Proxy {
		for _, method := range rule.Match.Method {
			for _, path := range rule.Match.Path {
				got = append(got, method+" "+path+" "+rule.If)
			}
		}
	}
	slices.Sort(want)
	slices.Sort(got)
	if len(want) < 140 || !slices.Equal(got, want) {
		t.Errorf("proxy routes %v, endpoint tables %v", got, want)
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
		// Folder placeholders match any segment, so the proxy cannot refuse another script's
		// path info on the same host; the connector refuses .php install paths instead.
		assertDolibarrRoutes(t, r, key, true, "GET https://erp.example.com/index.php/api/index.php/status")
		assertDolibarrRoutes(t, r, key, false,
			"GET https://erp.example.com/a/b/c/api/index.php/status", "GET https://erp.example.com/api/status",
			"GET https://erp.example.com/index.php", "GET https://erp.example.com/api/index.php/",
			"GET https://www.erp.example.com/api/index.php/status", "GET https://erp.example.com.attacker.test/api/index.php/status",
			"GET https://erp.example.com:8443/api/index.php/status", "GET http://erp.example.com/api/index.php/status")
	}
}
