package main

import (
	"regexp"
	"slices"
	"strings"
	"testing"
)

func TestMetaAccessRoutes(t *testing.T) {
	m := parseManifest(t, "../../connectors/meta/houston.json")
	const api = "https://graph.facebook.com/v26.0"
	for _, access := range []string{"read-only", "read-write"} {
		r, err := m.Resolve(nil, map[string]any{"access": access}, map[string]any{"token": "EAAPAGE"}, "token")
		if err != nil {
			t.Fatal(err)
		}
		// Query strings play no part in matching; the table-driven test below covers every route.
		assertRoutes(t, r, "EAAPAGE", true,
			"GET "+api+"/me?fields=id%2Cname", "GET "+api+"/me/conversations?platform=instagram",
			"GET "+api+"/ig_hashtag_search?user_id=1&q=bread", "GET "+api+"/t_1/messages?after=QUZU")
		// Graph ignores method-override headers today; every credentialed route drops them anyway.
		assertStripsMethodOverrides(t, r, "GET "+api+"/me/feed")
		if access == "read-write" {
			assertStripsMethodOverrides(t, r, "POST "+api+"/me/feed", "DELETE "+api+"/101_1", "GET "+api+"/1/content_publishing_limit",
				"POST https://graph-video.facebook.com/v26.0/me/videos")
		}
		// Token, permission and account endpoints, ads, batch on the root, other versions and
		// hosts, and unlisted edges get no credential. Expanded fields can still reach other
		// edges of an allowed node, so Lua refuses fields naming a token and drops token fields.
		assertRoutes(t, r, "EAAPAGE", false,
			"GET "+api+"/me/accounts", "GET "+api+"/oauth/access_token", "GET "+api+"/me/permissions",
			"GET "+api+"/me/subscribed_apps", "POST "+api+"/me/subscribed_apps", "GET "+api+"/act_1/ads",
			"POST "+api+"/", "GET "+api+"/", "POST "+api+"/me/videos", "PUT "+api+"/101_1", "DELETE "+api+"/101_1/comments",
			"GET https://graph.facebook.com/v25.0/me", "GET https://graph.facebook.com/me", "GET https://graph.instagram.com/v26.0/me",
			"GET https://graph.facebook.com.evil.test/v26.0/me", "GET https://www.facebook.com/v26.0/dialog/oauth",
			"POST https://rupload.facebook.com/ig-api-upload/v26.0/1", "GET https://graph-video.facebook.com/v26.0/me",
			"POST https://graph-video.facebook.com/v26.0/me/feed", "GET "+api+"/%2e%2e/me/accounts", "GET "+api+"/me%2Faccounts")
	}
}

// Every endpoint-table entry has a route, gated like its export (writes, and reads marked
// write = true, only on read-write connections), and every credentialed route serves an entry.
func TestMetaRoutesMatchEndpointTable(t *testing.T) {
	_, entries := endpointTable(t, "meta")
	placeholder := regexp.MustCompile(`\{\w+\}`)
	firstSegment := regexp.MustCompile(`^/[^/]+`)
	host := func(entry endpointEntry) string {
		if strings.Contains(entry.rest, "host = VIDEO_API") {
			return "graph-video.facebook.com"
		}
		return "graph.facebook.com"
	}
	m := parseManifest(t, "../../connectors/meta/houston.json")
	var want, got []string
	for _, entry := range entries {
		// The first segment is always a node: an ID, me or ig_hashtag_search.
		want = append(want, entry.method+" "+host(entry)+"/v26.0"+placeholder.ReplaceAllString(firstSegment.ReplaceAllString(entry.path, "/{id}"), "{id}"))
	}
	for _, rule := range m.Proxy {
		for _, h := range rule.Match.Host {
			for _, method := range rule.Match.Method {
				for _, path := range rule.Match.Path {
					got = append(got, method+" "+h+path)
				}
			}
		}
	}
	slices.Sort(want)
	want = slices.Compact(want)
	slices.Sort(got)
	if !slices.Equal(got, want) {
		t.Errorf("proxy routes %v, endpoint table %v", got, want)
	}
	for _, access := range []string{"read-only", "read-write"} {
		r, err := m.Resolve(nil, map[string]any{"access": access}, map[string]any{"token": "EAAPAGE"}, "token")
		if err != nil {
			t.Fatal(err)
		}
		for _, entry := range entries {
			route := entry.method + " https://" + host(entry) + "/v26.0" + placeholder.ReplaceAllString(entry.path, "101_1")
			assertRoutes(t, r, "EAAPAGE", !entry.write || access == "read-write", route)
		}
	}
}
