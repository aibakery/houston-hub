package main

import "testing"

func TestMetaAccessRoutes(t *testing.T) {
	m := parseManifest(t, "../../connectors/meta/houston.json")
	const api = "https://graph.facebook.com/v26.0"
	for _, access := range []string{"read-only", "read-write"} {
		r, err := m.Resolve(nil, map[string]any{"access": access}, map[string]any{"token": "EAAPAGE"}, "token")
		if err != nil {
			t.Fatal(err)
		}
		assertRoutes(t, r, "EAAPAGE", true,
			"GET "+api+"/me?fields=id%2Cname", "GET "+api+"/me/feed?limit=25", "GET "+api+"/101_1/comments",
			"GET "+api+"/me/insights?metric=page_media_view", "GET "+api+"/me/conversations?platform=instagram",
			"GET "+api+"/t_1/messages", "GET "+api+"/17841400000000001/media", "GET "+api+"/ig_hashtag_search?user_id=1&q=bread",
			"GET "+api+"/17843853986012965/recent_media?user_id=1")
		assertRoutes(t, r, "EAAPAGE", access == "read-write",
			"POST "+api+"/me/feed", "POST "+api+"/101_1", "POST "+api+"/101_1/comments", "POST "+api+"/me/messages",
			"POST "+api+"/me/photos", "POST "+api+"/17841400000000001/media", "POST "+api+"/17841400000000001/media_publish",
			"POST "+api+"/17860000000000001/replies", "DELETE "+api+"/101_1",
			"POST https://graph-video.facebook.com/v26.0/me/videos", "GET "+api+"/17841400000000001/content_publishing_limit")
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
