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
			local api = "https://www.googleapis.com/drive/v3"
			local upload = "https://www.googleapis.com/upload/drive/v3"
			for _, access in { "read-only", "read-write" } do
				local scope = "drive.readonly"
				if access == "read-write" then
					scope = "drive"
				end
				local r = google(access, { scope })
				local reads = {
					"GET " .. api .. "/about?fields=user",
					"GET " .. api .. "/files?q=trashed%3Dfalse",
					"GET " .. api .. "/files/f1",
					"GET " .. api .. "/files/f1?alt=media",
					"GET " .. api .. "/files/f1/export?mimeType=text%2Fplain",
					"GET " .. api .. "/files/f1/permissions",
					"GET " .. api .. "/drives",
				}
				m.routes(r, "Bearer fixture-token", true, reads)
				m.rejectOverrides(r, reads)
				local writes = {
					"POST " .. api .. "/files",
					"PATCH " .. api .. "/files/f1",
					"POST " .. api .. "/files/f1/copy",
					"DELETE " .. api .. "/files/f1",
					"POST " .. api .. "/files/f1/permissions",
					"DELETE " .. api .. "/files/f1/permissions/p1",
					"POST " .. upload .. "/files?uploadType=resumable",
					"PATCH " .. upload .. "/files/f1?uploadType=resumable",
					"PUT " .. upload .. "/files?uploadType=resumable&upload_id=xyz",
					"PUT " .. upload .. "/files/f1?uploadType=resumable&upload_id=xyz",
				}
				m.routes(r, "Bearer fixture-token", (access == "read-write"), writes)
				m.routes(
					r,
					"Bearer fixture-token",
					(access == "read-write"),
					{ "DELETE " .. api .. "/files/trash" }
				)
				if access == "read-write" then
					m.rejectOverrides(r, writes)
				end
				m.routes(r, "Bearer fixture-token", false, {
					"POST https://oauth2.googleapis.com/token",
					"GET https://www.googleapis.com/calendar/v3/calendars/primary",
					"GET https://www.googleapis.com.evil.test/drive/v3/files",
					"GET https://content.googleapis.com/drive/v3/files",
					"POST https://www.googleapis.com/batch/drive/v3",
					"POST " .. api .. "/drives",
					"DELETE " .. api .. "/drives/d1",
					"PATCH " .. api .. "/files/f1/permissions/p1",
					"POST " .. api .. "/files/f1/watch",
					"POST " .. api .. "/changes/watch",
					"GET " .. api .. "/changes",
					"POST " .. api .. "/files/f1/comments",
					"GET " .. api .. "/files/f1/revisions",
					"PUT " .. api .. "/files/f1",
					"POST " .. api .. "/files/generateIds",
					"GET " .. api .. "/files/f1/permissions/p1",
					"POST " .. upload .. "/files/f1",
					"GET " .. upload .. "/files/f1",
					"GET " .. api .. "/files/%2e%2e/about",
					"GET " .. api .. "/files/f1%2F..%2Fx",
				})
			end
		end
		do
			local drive = google("read-only", { "drive.readonly" })
			m.routes(
				drive,
				"Bearer fixture-token",
				true,
				{ "GET https://www.googleapis.com/drive/v3/files/x" }
			)
			m.refused(
				drive,
				"method override",
				{ "GET https://www.googleapis.com/drive/v3/files/x?$httpMethod=PATCH" }
			)
		end
	end,
}
