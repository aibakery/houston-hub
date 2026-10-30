package main

import "testing"

// RevenueCat keys carry their own permissions, but the proxy still allows writes only on
// read-write connections, and never refunds, cancellations, deletions of customers or
// offerings, attributes or keys.
func TestRevenueCatAccessRoutes(t *testing.T) {
	m := parseManifest(t, "../../connectors/revenuecat/houston.json")
	api := "https://api.revenuecat.com/v2"
	p := api + "/projects/proj1ab2c3d4"
	for _, access := range []string{"read-only", "read-write"} {
		r, err := m.Resolve(nil, map[string]any{"access": access}, map[string]any{"token": "sk_fixture"}, "token")
		if err != nil {
			t.Fatal(err)
		}
		assertRoutes(t, r, "sk_fixture", true,
			"GET "+api+"/projects", "GET "+p+"/apps?limit=100", "GET "+p+"/apps/app1", "GET "+p+"/customers?search=ada%40example.com",
			"GET "+p+"/customers/%24RCAnonymousID%3Aabc?expand=attributes", "GET "+p+"/customers/user-1/subscriptions?environment=production",
			"GET "+p+"/customers/user-1/purchases", "GET "+p+"/customers/user-1/active_entitlements", "GET "+p+"/subscriptions/sub1",
			"GET "+p+"/subscriptions/sub1/entitlements", "GET "+p+"/purchases/purch1", "GET "+p+"/products?app_id=app1", "GET "+p+"/products/prod1",
			"GET "+p+"/entitlements", "GET "+p+"/entitlements/entl1", "GET "+p+"/entitlements/entl1/products", "GET "+p+"/offerings?expand=items.package",
			"GET "+p+"/offerings/ofrng1", "GET "+p+"/offerings/ofrng1/packages", "GET "+p+"/packages/pkge1", "GET "+p+"/packages/pkge1/products",
			"GET "+p+"/metrics/overview?currency=EUR")
		assertRoutes(t, r, "sk_fixture", access == "read-write",
			"POST "+p+"/customers/user-1/actions/grant_entitlement", "POST "+p+"/customers/user-1/actions/revoke_granted_entitlement",
			"POST "+p+"/offerings", "POST "+p+"/offerings/ofrng1",
			"POST "+p+"/offerings/ofrng1/packages", "POST "+p+"/packages/pkge1",
			"POST "+p+"/packages/pkge1/actions/attach_products", "POST "+p+"/packages/pkge1/actions/detach_products", "DELETE "+p+"/packages/pkge1")
		assertRoutes(t, r, "sk_fixture", false,
			"DELETE "+p+"/customers/user-1", "POST "+p+"/customers", "POST "+p+"/customers/user-1/actions/transfer",
			"POST "+p+"/customers/user-1/actions/assign_offering", "GET "+p+"/customers/user-1/attributes", "POST "+p+"/customers/user-1/attributes",
			"GET "+p+"/customers/user-1/aliases", "GET "+p+"/customers/user-1/invoices", "GET "+p+"/customers/user-1/invoices/inv1/file",
			"POST "+p+"/subscriptions/sub1/actions/refund", "POST "+p+"/subscriptions/sub1/actions/cancel", "POST "+p+"/subscriptions/sub1/actions/extend",
			"GET "+p+"/subscriptions/sub1/authenticated_management_url", "POST "+p+"/purchases/purch1/actions/refund", "DELETE "+p+"/offerings/ofrng1", "POST "+p+"/offerings/ofrng1/actions/archive", "POST "+p+"/offerings/ofrng1/actions/unarchive",
			"DELETE "+p+"/products/prod1", "POST "+p+"/products", "POST "+p+"/entitlements", "PUT "+p+"/offerings/ofrng1", "PATCH "+p+"/packages/pkge1",
			"GET "+p+"/apps/app1/public_api_keys", "GET "+p+"/apps/app1/store_kit_config", "POST "+api+"/projects", "GET "+p+"/charts/mrr",
			"GET "+p+"/customers/%2e%2e/subscriptions", "GET "+p+"/customers/a%2Fb", "GET "+p, "GET https://api.revenuecat.com/v1/subscribers/user-1",
			"GET https://api.revenuecat.com.example.com/v2/projects", "GET http://api.revenuecat.com:8080/v2/projects", "GET https://app.revenuecat.com/v2/projects")
	}
}
