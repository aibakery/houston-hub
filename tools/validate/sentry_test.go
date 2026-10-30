package main

import "testing"

// Sentry tokens carry their own scopes, but the proxy still allows writes only on read-write
// connections, and only on the connection's region host.
func TestSentryAccessRoutes(t *testing.T) {
	m := parseManifest(t, "../../connectors/sentry/houston.json")
	for _, hosts := range [][2]string{{"us.sentry.io", "de.sentry.io"}, {"de.sentry.io", "us.sentry.io"}} {
		api, other := "https://"+hosts[0]+"/api/0", "https://"+hosts[1]+"/api/0"
		org := api + "/organizations/acme"
		for _, access := range []string{"read-only", "read-write"} {
			r, err := m.Resolve(nil, map[string]any{"access": access, "region": hosts[0], "organization": "acme"}, map[string]any{"token": "sntryu_fixture"}, "token")
			if err != nil {
				t.Fatal(err)
			}
			assertRoutes(t, r, "sntryu_fixture", true,
				"GET "+api+"/organizations/?owner=true", "GET "+org+"/?detailed=0", "GET "+org+"/projects/?cursor=0%3A100%3A0",
				"GET "+api+"/projects/acme/web/", "GET "+org+"/teams/", "GET "+org+"/members/?query=email%3Aada%40example.com",
				"GET "+org+"/issues/?query=is%3Aunresolved&project=42&project=43", "GET "+org+"/issues/WEB-1A/", "GET "+org+"/issues/1001/tags/browser/",
				"GET "+org+"/issues/1001/events/?full=true", "GET "+org+"/issues/1001/events/latest/", "GET "+org+"/issues/1001/comments/",
				"GET "+api+"/projects/acme/web/events/c0ffee00c0ffee00c0ffee00c0ffee00/", "GET "+org+"/releases/?health=1",
				"GET "+org+"/releases/web%401.2.0%2B45/", "GET "+org+"/sessions/?field=sum%28session%29")
			assertRoutes(t, r, "sntryu_fixture", access == "read-write",
				"PUT "+org+"/issues/1001/", "POST "+org+"/issues/WEB-1A/comments/")
			// Bulk changes, deletion, other writes, tokens, keys and the other region stay denied.
			assertRoutes(t, r, "sntryu_fixture", false,
				"PUT "+org+"/issues/?id=1001", "DELETE "+org+"/issues/1001/", "DELETE "+org+"/issues/?id=1001",
				"PUT "+api+"/projects/acme/web/issues/?id=1001", "PUT "+api+"/issues/1001/", "POST "+api+"/issues/1001/comments/",
				"PUT "+org+"/issues/1001/comments/5/", "DELETE "+org+"/issues/1001/comments/5/", "POST "+org+"/issues/1001/",
				"POST "+org+"/releases/", "PUT "+org+"/releases/web/", "DELETE "+org+"/releases/web/", "PUT "+org+"/",
				"GET "+api+"/api-tokens/", "POST "+api+"/api-tokens/", "GET "+api+"/projects/acme/web/keys/", "GET "+org+"/org-auth-tokens/",
				"GET "+api+"/sentry-apps/houston/api-tokens/", "GET "+org+"/integrations/", "GET "+api+"/projects/acme/web/events/e1/attachments/",
				"GET "+org+"/issues/1001/events/latest/json/", "GET "+org+"/issues/%2e%2e/", "GET "+other+"/organizations/acme/issues/",
				"GET https://sentry.io/api/0/organizations/acme/issues/", "GET https://"+hosts[0]+".example.com/api/0/organizations/",
				"GET http://"+hosts[0]+":8080/api/0/organizations/", "POST https://"+hosts[0]+"/oauth/token/")
		}
	}
}
