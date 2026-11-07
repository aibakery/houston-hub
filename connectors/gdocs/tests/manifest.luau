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
			local api = "https://docs.googleapis.com/v1/documents"
			for _, access in { "read-only", "read-write" } do
				local scope = "documents.readonly"
				if access == "read-write" then
					scope = "documents"
				end
				local r = google(access, { scope })
				local reads = {
					"GET " .. api .. "/d1?includeTabsContent=true",
					"GET " .. api .. "/1DoC_x-9?fields=documentId%2Ctitle%2CrevisionId%2Ctabs",
				}
				m.routes(r, "Bearer fixture-token", true, reads)
				m.rejectOverrides(r, reads)
				local writes = { "POST " .. api, "POST " .. api .. "/d1:batchUpdate" }
				m.routes(r, "Bearer fixture-token", (access == "read-write"), writes)
				if access == "read-write" then
					m.rejectOverrides(r, writes)
				end
				m.routes(r, "Bearer fixture-token", false, {
					"POST https://oauth2.googleapis.com/token",
					"GET https://www.googleapis.com/drive/v3/files",
					"GET https://docs.googleapis.com.evil.test/v1/documents/d1",
					"GET https://content.googleapis.com/v1/documents/d1",
					"GET https://docs.googleapis.com/v2/documents/d1",
					"GET " .. api,
					"DELETE " .. api .. "/d1",
					"PATCH " .. api .. "/d1",
					"PUT " .. api .. "/d1",
					"GET " .. api .. "/d1/tabs",
					"GET " .. api .. "/%2e%2e/d1",
					"GET " .. api .. "/d1%2F..%2Fx",
					"POST " .. api .. "/d1/batchUpdate",
					"POST https://docs.googleapis.com/batch",
					"POST https://docs.googleapis.com/batch/docs/v1",
				})
			end
		end
	end,
}
