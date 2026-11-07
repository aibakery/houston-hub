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
			local api = "https://forms.googleapis.com/v1/forms"
			for _, access in { "read-only", "read-write" } do
				local scope = "forms.body.readonly"
				if access == "read-write" then
					scope = "forms.body"
				end
				local r = google(access, { scope, "forms.responses.readonly" })
				local reads = {
					"GET " .. api .. "/f1",
					"GET " .. api .. "/f1/responses?filter=timestamp%20%3E%202026-10-01T00%3A00%3A00Z",
					"GET " .. api .. "/f1/responses/ACYD",
				}
				m.routes(r, "Bearer fixture-token", true, reads)
				m.rejectOverrides(r, reads)
				local writes = {
					"POST " .. api .. "?unpublished=true",
					"POST " .. api .. "/f1:batchUpdate",
					"POST " .. api .. "/f1:setPublishSettings",
				}
				m.routes(r, "Bearer fixture-token", (access == "read-write"), writes)
				if access == "read-write" then
					m.rejectOverrides(r, writes)
				end
				m.routes(r, "Bearer fixture-token", false, {
					"POST https://oauth2.googleapis.com/token",
					"GET https://www.googleapis.com/drive/v3/files",
					"GET https://forms.googleapis.com.evil.test/v1/forms/f1",
					"GET https://content.googleapis.com/v1/forms/f1",
					"GET https://forms.googleapis.com/v2/forms/f1",
					"GET " .. api,
					"DELETE " .. api .. "/f1",
					"PATCH " .. api .. "/f1",
					"PUT " .. api .. "/f1",
					"GET " .. api .. "/f1/watches",
					"POST " .. api .. "/f1/watches",
					"POST " .. api .. "/f1/watches/w1:renew",
					"DELETE " .. api .. "/f1/watches/w1",
					"POST " .. api .. "/f1/responses",
					"DELETE " .. api .. "/f1/responses/ACYD",
					"GET " .. api .. "/%2e%2e/f1",
					"GET " .. api .. "/f1%2F..%2Fwatches",
					"GET " .. api .. "/f1/responses/%2e%2e",
				})
			end
		end
	end,
}
