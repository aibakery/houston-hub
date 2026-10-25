package main

import (
	"net/http"
	"testing"
)

func TestResendAccessRoutes(t *testing.T) {
	m := parseManifest(t, "../../connectors/resend/houston.json")
	const api = "https://api.resend.com"
	for _, access := range []string{"read-only", "read-write"} {
		r, err := m.Resolve(nil, map[string]any{"access": access}, map[string]any{"token": "re_fixture"}, "api_key")
		if err != nil {
			t.Fatal(err)
		}
		assertRoutes(t, r, "re_fixture", true,
			"GET "+api+"/emails?limit=100", "GET "+api+"/emails/e1", "GET "+api+"/emails/receiving/r1/attachments/a1",
			"GET "+api+"/contacts/ana%2Bnews%40example.com", "GET "+api+"/suppressions/o%27brien%40example.com",
			"GET "+api+"/webhooks", "GET "+api+"/webhooks/w1/events/msg_1",
			"GET "+api+"/logs", "GET "+api+"/api-keys", "GET "+api+"/segments/s1/contacts", "GET "+api+"/usage",
			"GET "+api+"/inboxes/support%40acme.com/threads/search?query=refund&folders=inbox,sent",
			"GET "+api+"/inboxes/i1/threads/t1/emails/e1", "GET "+api+"/inboxes/i1/agent")
		// Webhook and log reads return signing secrets and logged request bodies.
		assertRoutes(t, r, "re_fixture", access == "read-write",
			"GET "+api+"/webhooks/w1", "GET "+api+"/logs/l1",
			"POST "+api+"/emails", "POST "+api+"/emails/batch", "POST "+api+"/emails/e1/share", "PATCH "+api+"/emails/e1",
			"POST "+api+"/contacts/imports", "DELETE "+api+"/contacts/c1", "POST "+api+"/broadcasts/b1/send",
			"POST "+api+"/webhooks/w1/signing-secret/rotate", "POST "+api+"/suppressions/batch/remove",
			"POST "+api+"/inboxes/i1/threads/t1/emails/e1/reply", "POST "+api+"/inboxes/i1/drafts/d1/send", "PATCH "+api+"/inboxes/i1/threads/t1",
			"PUT "+api+"/inboxes/i1/threads/t1/labels", "DELETE "+api+"/inboxes/i1/threads/t1/labels/l1")
		// API key creation returns a credential and changes could revoke the connection's own key;
		// OAuth and audiences (deprecated) are not exposed.
		assertRoutes(t, r, "re_fixture", false,
			"POST "+api+"/api-keys", "PATCH "+api+"/api-keys/k1", "DELETE "+api+"/api-keys/k1",
			"GET "+api+"/oauth/grants", "DELETE "+api+"/oauth/grants/g1", "POST "+api+"/oauth/token", "POST "+api+"/oauth/register",
			"GET "+api+"/audiences", "POST "+api+"/email", "PUT "+api+"/emails/e1", "PUT "+api+"/inboxes/i1/threads/t1",
			"GET https://resend.com/api-keys", "GET https://api.resend.com.example.com/emails", "GET https://eu.api.resend.com/emails",
			"GET "+api+"/emails/%2e%2e/api-keys")

		// Signed attachment links reach Resend's CDN hosts without the API key.
		for _, url := range []string{"https://inbound-cdn.resend.com/t1/attachments/a1?signature=s", "https://outbound-cdn.resend.com/t1/attachments/a1?signature=s"} {
			recipe, err := r.Proxy.HTTPRecipe("GET", url, nil)
			if err != nil {
				t.Fatal(err)
			}
			headers, err := recipe.Prepare(r.Context, http.Header{"Authorization": {"forged"}})
			if err != nil || headers.Get("Authorization") != "" {
				t.Fatalf("%s carried credentials: %v %v", url, headers, err)
			}
			if _, err := r.Proxy.HTTPRecipe("POST", url, nil); err == nil {
				t.Fatalf("POST %s allowed", url)
			}
		}
		if _, err := r.Proxy.HTTPRecipe("GET", "https://cdn.resend.com/brand/resend-icon-black.svg", nil); err == nil {
			t.Fatal("unlisted Resend host allowed")
		}

		// Read-only GETs cannot be turned into writes with a method override.
		recipe, err := r.Proxy.HTTPRecipe("GET", api+"/emails", nil)
		if err != nil {
			t.Fatal(err)
		}
		headers, err := recipe.Prepare(r.Context, http.Header{"X-HTTP-Method-Override": {"POST"}})
		if err != nil || headers.Get("X-HTTP-Method-Override") != "" {
			t.Fatalf("method override kept: %v %v", headers, err)
		}
	}
}
