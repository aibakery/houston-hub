return {
	contract = function(m)
		local function google(access, scopes)
			local r, err = m.resolve(
				{ client_id = "publisher-client", client_secret = "publisher-secret" },
				{ access = access },
				nil,
				"oauth"
			)
			assert(r and not err, tostring(err))
			local want = { "https://www.googleapis.com/auth/userinfo.email" }
			for _, scope in scopes do
				table.insert(want, "https://www.googleapis.com/auth/" .. scope)
			end
			assert(m.equal(r.Scopes, want), "requested OAuth scopes")
			r.Context.Auth.oauth.access_token = "fixture-token"
			return r
		end
		do
			local api = "https://slides.googleapis.com/v1/presentations"
			for _, access in { "read-only", "read-write" } do
				local scope = "presentations.readonly"
				if access == "read-write" then
					scope = "presentations"
				end
				local r = google(access, { scope })
				local reads = {
					"GET " .. api .. "/p1",
					"GET " .. api .. "/1PrE_x-9?fields=presentationId%2Ctitle%2CrevisionId%2Cslides",
					"GET " .. api .. "/p1?commentsViewMode=COMMENTS_VIEW_MODE_INCLUDED",
					"GET " .. api .. "/p1/pages/g1",
					"GET " .. api .. "/p1/pages/q3%3Asummary",
					"GET " .. api .. "/p1/pages/g1/thumbnail",
					"GET "
						.. api
						.. "/p1/pages/SLIDES_API1_0/thumbnail?thumbnailProperties.thumbnailSize=SMALL",
				}
				m.routes(r, "Bearer fixture-token", true, reads)
				m.rejectOverrides(r, reads)
				local writes = { "POST " .. api, "POST " .. api .. "/p1:batchUpdate" }
				m.routes(r, "Bearer fixture-token", (access == "read-write"), writes)
				if access == "read-write" then
					m.rejectOverrides(r, writes)
				end
				m.routes(r, "Bearer fixture-token", false, {
					"POST https://oauth2.googleapis.com/token",
					"GET https://www.googleapis.com/drive/v3/files",
					"GET https://slides.googleapis.com.evil.test/v1/presentations/p1",
					"GET https://content.googleapis.com/v1/presentations/p1",
					"GET https://slides.googleapis.com/v2/presentations/p1",
					"GET https://docs.googleapis.com/v1/documents/p1",
					"GET " .. api,
					"DELETE " .. api .. "/p1",
					"PATCH " .. api .. "/p1",
					"PUT " .. api .. "/p1",
					"POST " .. api .. "/p1/batchUpdate",
					"GET " .. api .. "/p1/pages",
					"POST " .. api .. "/p1/pages/g1",
					"POST " .. api .. "/p1/pages/g1/thumbnail",
					"GET " .. api .. "/p1/pages/g1/thumbnail/x",
					"GET " .. api .. "/p1/comments",
					"GET " .. api .. "/%2e%2e/p1",
					"GET " .. api .. "/p1%2F..%2Fx",
					"GET " .. api .. "/p1/pages/%2e%2e/thumbnail",
					"GET " .. api .. "/p1/pages/g1%2Fthumbnail",
					"GET " .. api .. "/p1/pages/%252e%252e",
					"POST https://slides.googleapis.com/batch",
					"POST https://slides.googleapis.com/batch/slides/v1",
				})
			end
		end
	end,
}
