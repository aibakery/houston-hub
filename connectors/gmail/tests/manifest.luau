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
			local api = "https://gmail.googleapis.com/gmail/v1/users/me"
			local upload = "https://gmail.googleapis.com/upload/gmail/v1/users/me"
			for access, scopes in
				{
					["read-only"] = { "gmail.readonly" },
					custom = { "gmail.readonly", "gmail.compose" },
					["read-write"] = { "gmail.modify" },
				}
			do
				do
					local r = google(access, scopes)
					local reads = {
						"GET " .. api .. "/profile",
						"GET " .. api .. "/labels",
						"GET " .. api .. "/labels/Label_1",
						"GET " .. api .. "/messages?q=is%3Aunread",
						"GET " .. api .. "/messages/m1?format=full",
						"GET " .. api .. "/messages/m1/attachments/a1",
						"GET " .. api .. "/threads",
						"GET " .. api .. "/threads/t1",
						"GET " .. api .. "/drafts",
						"GET " .. api .. "/drafts/d1",
						"GET " .. api .. "/history?startHistoryId=1",
						"GET " .. api .. "/settings/sendAs",
					}
					m.routes(r, "Bearer fixture-token", true, reads)
					m.rejectOverrides(r, reads)
					local drafts = {
						"POST " .. upload .. "/drafts?uploadType=multipart",
						"PUT " .. upload .. "/drafts/d1?uploadType=multipart",
						"DELETE " .. api .. "/drafts/d1",
					}
					m.routes(r, "Bearer fixture-token", (access ~= "read-only"), drafts)
					if access ~= "read-only" then
						m.rejectOverrides(r, drafts)
					end
					local writes = {
						"POST " .. api .. "/messages/batchModify",
						"POST " .. api .. "/messages/m1/modify",
						"POST " .. api .. "/messages/m1/trash",
						"POST " .. api .. "/messages/m1/untrash",
						"POST " .. api .. "/threads/t1/modify",
						"POST " .. api .. "/threads/t1/trash",
						"POST " .. api .. "/threads/t1/untrash",
						"POST " .. api .. "/labels",
						"PATCH " .. api .. "/labels/Label_1",
						"DELETE " .. api .. "/labels/Label_1",
						"POST " .. api .. "/drafts/send",
						"POST " .. upload .. "/messages/send?uploadType=multipart",
					}
					m.routes(r, "Bearer fixture-token", (access == "read-write"), writes)
					if access == "read-write" then
						m.rejectOverrides(r, writes)
					end
					m.routes(r, "Bearer fixture-token", false, {
						"POST https://oauth2.googleapis.com/token",
						"GET https://www.googleapis.com/drive/v3/files",
						"GET https://gmail.googleapis.com.evil.test/gmail/v1/users/me/profile",
						"GET https://www.googleapis.com/gmail/v1/users/me/profile",
						"GET https://gmail.googleapis.com/gmail/v1/users/other@example.com/profile",
						"POST https://gmail.googleapis.com/batch/gmail/v1",
						"DELETE " .. api .. "/messages/m1",
						"POST " .. api .. "/messages/batchDelete",
						"DELETE " .. api .. "/threads/t1",
						"POST " .. api .. "/messages/import",
						"POST " .. api .. "/messages",
						"POST " .. api .. "/messages/send",
						"POST " .. upload .. "/drafts/send?uploadType=multipart",
						"POST " .. upload .. "/drafts/d1?uploadType=multipart",
						"POST " .. upload .. "/messages/import",
						"POST " .. upload .. "/messages",
						"PUT " .. api .. "/labels/Label_1",
						"PUT " .. api .. "/drafts/d1",
						"POST " .. api .. "/drafts",
						"POST " .. api .. "/watch",
						"POST " .. api .. "/stop",
						"GET " .. api .. "/settings/forwardingAddresses",
						"POST " .. api .. "/settings/filters",
						"PUT " .. api .. "/settings/vacation",
						"POST " .. api .. "/settings/sendAs",
						"GET " .. api .. "/messages/%2e%2e/profile",
						"GET " .. api .. "/messages/m1%2F..%2Fx",
					})
				end
			end
		end
		do
			local gmail = google("custom", { "gmail.readonly", "gmail.compose" })
			local api = "https://gmail.googleapis.com/gmail/v1/users/me"
			local upload = "https://gmail.googleapis.com/upload/gmail/v1/users/me"
			m.routes(
				gmail,
				"Bearer fixture-token",
				true,
				{ "GET " .. api .. "/drafts/abc", "PUT " .. upload .. "/drafts/abc?uploadType=multipart" }
			)
			for _, name in { "$httpMethod", "%24httpMethod" } do
				m.refused(gmail, "method override", {
					"GET " .. api .. "/drafts/send?" .. name .. "=POST",
					"GET " .. api .. "/messages/send?" .. name .. "=POST",
					"PUT " .. upload .. "/drafts/send?" .. name .. "=POST",
				})
			end
			m.refused(gmail, "", {
				"POST " .. api .. "/drafts/send",
				"POST " .. api .. "/messages/send",
				"POST " .. upload .. "/messages/send?uploadType=multipart",
			})
		end
	end,
}
