return {
	contract = function(m)
		-- TestMetaAccessRoutes
		do
			local api = "https://graph.facebook.com/v26.0"
			for _, access in { "read-only", "read-write" } do
				local r, err = m.resolve(nil, { access = access }, { token = "EAAPAGE" }, "token")
				assert(not err, tostring(err))
				m.routes(r, "Bearer EAAPAGE", true, {
					"GET " .. api .. "/me?fields=id%2Cname",
					"GET " .. api .. "/me/conversations?platform=instagram",
					"GET " .. api .. "/ig_hashtag_search?user_id=1&q=bread",
					"GET " .. api .. "/t_1/messages?after=QUZU",
				})
				m.rejectOverrides(
					r,
					{ "GET " .. api .. "/me/feed", "GET " .. api .. "/1/content_publishing_limit" }
				)
				if access == "read-write" then
					m.rejectOverrides(r, {
						"POST " .. api .. "/me/feed",
						"DELETE " .. api .. "/101_1",
						"POST https://graph-video.facebook.com/v26.0/me/videos",
					})
				end
				m.routes(r, "Bearer EAAPAGE", false, {
					"GET " .. api .. "/me/accounts",
					"GET " .. api .. "/oauth/access_token",
					"GET " .. api .. "/me/permissions",
					"GET " .. api .. "/me/subscribed_apps",
					"POST " .. api .. "/me/subscribed_apps",
					"GET " .. api .. "/act_1/ads",
					"POST " .. api .. "/",
					"GET " .. api .. "/",
					"POST " .. api .. "/me/videos",
					"PUT " .. api .. "/101_1",
					"DELETE " .. api .. "/101_1/comments",
					"GET https://graph.facebook.com/v25.0/me",
					"GET https://graph.facebook.com/me",
					"GET https://graph.instagram.com/v26.0/me",
					"GET https://graph.facebook.com.evil.test/v26.0/me",
					"GET https://www.facebook.com/v26.0/dialog/oauth",
					"POST https://rupload.facebook.com/ig-api-upload/v26.0/1",
					"GET https://graph-video.facebook.com/v26.0/me",
					"POST https://graph-video.facebook.com/v26.0/me/feed",
					"GET " .. api .. "/%2e%2e/me/accounts",
					"GET " .. api .. "/me%2Faccounts",
				})
			end
		end
	end,
}
