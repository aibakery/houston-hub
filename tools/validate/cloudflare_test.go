package main

import "testing"

// Cloudflare tokens carry their own permissions, but the proxy still allows writes only on
// read-write connections, and never token, member, script-content or zone-level changes.
func TestCloudflareAccessRoutes(t *testing.T) {
	m := parseManifest(t, "../../connectors/cloudflare/houston.json")
	const api = "https://api.cloudflare.com/client/v4"
	const account = api + "/accounts/0123456789abcdef0123456789abcdef"
	const zone = api + "/zones/023e105f4ecef8ad9ca31a8372d0c353"
	const record = zone + "/dns_records/372e67954025e0ba6aaa6d586b9e0b59"
	const script = account + "/workers/scripts/api"
	const pages = account + "/pages/projects/site"
	for _, access := range []string{"read-only", "read-write"} {
		r, err := m.Resolve(nil, map[string]any{"access": access}, map[string]any{"token": "cfut_fixture"}, "token")
		if err != nil {
			t.Fatal(err)
		}
		assertRoutes(t, r, "cfut_fixture", true,
			"GET "+api+"/accounts?page=2&per_page=50", "GET "+account, "GET "+api+"/zones?name=example.com&type=full,partial",
			"GET "+zone, "GET "+zone+"/dns_records?type=CNAME&per_page=1000", "GET "+record,
			"POST "+api+"/graphql", "GET "+account+"/workers/scripts?tags=prod%3Ayes", "GET "+script+"/deployments?per_page=5",
			"GET "+script+"/versions?deployable=true", "GET "+script+"/versions/bcf48806-b317-4351-9ee7-36e7d557d4de",
			"GET "+account+"/pages/projects", "GET "+pages, "GET "+pages+"/deployments?env=production", "GET "+pages+"/deployments/4f0b3a52",
			"GET "+pages+"/deployments/4f0b3a52/history/logs", "GET "+account+"/r2/buckets?cursor=YXNzZXRz", "GET "+account+"/r2/buckets/assets")
		assertRoutes(t, r, "cfut_fixture", access == "read-write",
			"POST "+zone+"/dns_records", "PATCH "+record, "DELETE "+record, "POST "+zone+"/purge_cache",
			"POST "+script+"/deployments", "POST "+pages+"/deployments/4f0b3a52/rollback")
		// Tokens and their values, members, script code and secrets, other writes, other hosts and
		// dot segments stay denied.
		assertRoutes(t, r, "cfut_fixture", false,
			"GET "+api+"/user", "GET "+api+"/user/tokens", "GET "+api+"/user/tokens/verify", "GET "+account+"/tokens",
			"GET "+account+"/tokens/abc/value", "PUT "+account+"/tokens/abc/value", "POST "+account+"/tokens", "GET "+account+"/members",
			"GET "+script, "PUT "+script, "DELETE "+script, "GET "+script+"/content", "GET "+script+"/secrets", "PUT "+script+"/secrets",
			"POST "+script+"/versions", "DELETE "+script+"/deployments/6d4b3a52", "GET "+script+"/settings",
			"PUT "+record, "POST "+zone+"/dns_records/batch", "POST "+zone+"/dns_records/import",
			"PATCH "+zone, "DELETE "+zone, "POST "+api+"/zones", "PATCH "+zone+"/settings/ssl", "GET "+zone+"/settings",
			"POST "+pages+"/deployments", "DELETE "+pages+"/deployments/4f0b3a52", "POST "+pages+"/deployments/4f0b3a52/retry",
			"PATCH "+pages, "DELETE "+pages, "POST "+account+"/r2/buckets", "DELETE "+account+"/r2/buckets/assets",
			"GET "+account+"/r2/buckets/assets/objects", "GET "+zone+"/dns_records/%2e%2e", "GET "+api+"/zones/..",
			"PUT "+api+"/graphql", "GET https://api.cloudflare.com/client/v3/zones", "GET https://dash.cloudflare.com/api/v4/zones",
			"GET https://api.cloudflare.com.example.com/client/v4/zones", "GET http://api.cloudflare.com/client/v4/zones",
			"GET https://api.cloudflare.com:8443/client/v4/zones", "GET https://cloudflare.com/client/v4/zones")
	}
}
