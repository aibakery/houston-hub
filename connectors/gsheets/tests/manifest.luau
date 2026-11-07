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
			local api = "https://sheets.googleapis.com/v4/spreadsheets"
			for _, access in { "read-only", "read-write" } do
				local scope = "spreadsheets.readonly"
				if access == "read-write" then
					scope = "spreadsheets"
				end
				local r = google(access, { scope })
				m.routes(r, "Bearer fixture-token", true, {
					"GET " .. api .. "/s1?fields=sheets.properties",
					"GET " .. api .. "/s1/values/%27Q1%20Sales%27%21B2",
					"GET " .. api .. "/s1/values:batchGet?ranges=Q2%2FQ3%21A1",
					"GET " .. api .. "/s1/values/%2710%2F16%27%21A1",
					"GET " .. api .. "/s1/values/%27100%25%27%21A1",
				})
				local writes = {
					"POST " .. api,
					"POST " .. api .. "/s1:batchUpdate",
					"PUT " .. api .. "/s1/values/Sheet1%21B2?valueInputOption=RAW",
					"POST " .. api .. "/s1/values/Log%21A%3AD:append?valueInputOption=RAW",
					"POST " .. api .. "/s1/values/A1:clear",
					"POST " .. api .. "/s1/values:batchUpdate",
					"POST " .. api .. "/s1/values:batchClear",
					"PUT " .. api .. "/s1/values/%27Q2%2FQ3%27%21B2",
					"POST " .. api .. "/s1/values/%27Log%2F2026%27%21A%3AD:append",
				}
				m.routes(r, "Bearer fixture-token", (access == "read-write"), writes)
				m.routes(r, "Bearer fixture-token", false, {
					"POST https://oauth2.googleapis.com/token",
					"GET https://www.googleapis.com/drive/v3/files",
					"GET https://sheets.googleapis.com/v4/spreadsheets",
					"GET https://sheets.googleapis.com.evil.test/v4/spreadsheets/s1",
					"GET https://sheets.googleapis.com/v3/spreadsheets/s1",
					"DELETE " .. api .. "/s1",
					"PATCH " .. api .. "/s1/values/A1",
					"GET " .. api .. "/s1/developerMetadata/1",
					"POST " .. api .. "/s1/developerMetadata:search",
					"POST " .. api .. "/s1/sheets/0:copyTo",
					"POST " .. api .. "/s1/values:batchUpdateByDataFilter",
					"GET " .. api .. "/s1/values/%2e%2e/x",
					"GET " .. api .. "/s1/values/%2e%2e%2F%2e%2e%2Fdrive",
					"GET " .. api .. "/s1/values/%252e%252e%252Fx",
					"GET " .. api .. "/s1%2F..%2Fx/values/A1",
				})
				m.rejectOverrides(r, { "GET " .. api .. "/s1", "GET " .. api .. "/s1/values/A1" })
				if access == "read-write" then
					m.rejectOverrides(r, writes)
				end
			end
		end
		do
			local sheets = google("read-only", { "spreadsheets.readonly" })
			local spreadsheet = "https://sheets.googleapis.com/v4/spreadsheets/x"
			m.routes(sheets, "Bearer fixture-token", true, { "GET " .. spreadsheet })
			m.refused(sheets, "", { "POST " .. spreadsheet .. ":batchUpdate" })
			m.refused(sheets, "method override", { "GET " .. spreadsheet .. ":batchUpdate?$httpMethod=POST" })
		end
	end,
}
