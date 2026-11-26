return {
	contract = function(m)
		-- m.endpointRules skips rules without headers.set, so compare the basic_auth rules here.
		local want, got = {}, {}
		for _, entry in m.endpoints() do
			table.insert(want, entry.method .. " /api" .. entry.path .. " " .. m.accessGate(entry.access))
		end
		for _, rule in m.raw.proxy do
			for _, method in rule.match.method do
				for _, path in rule.match.path do
					table.insert(got, method .. " " .. path .. " " .. (rule["if"] or ""))
				end
			end
		end
		m.sortedEqual(want, got)

		local api = "https://api.lemlist.com/api"
		local basic = "Basic " .. m.base64(":lemlist-key")
		for _, access in { "read", "write" } do
			local r, err = m.resolve(nil, {}, { token = "lemlist-key" }, "api_key", { data = access })
			assert(not err, tostring(err))
			m.routes(r, basic, true, {
				"GET " .. api .. "/campaigns?limit=100",
				"GET " .. api .. "/campaigns/cam_A1/leads",
				"GET " .. api .. "/v2/campaigns/cam_A1/stats?startDate=2026-11-01",
				"POST " .. api .. "/database/people",
				"POST " .. api .. "/v2/campaigns/stats/batch",
			})
			m.routes(r, basic, access == "write", {
				"GET " .. api .. "/team",
				"POST " .. api .. "/campaigns/cam_A1/start",
				"POST " .. api .. "/inbox/email",
				"PATCH " .. api .. "/campaigns/cam_A1",
				"PUT " .. api .. "/campaigns/cam_A1/senders",
				"DELETE " .. api .. "/contacts/ctc_A1",
			})
			m.routes(r, basic, false, {
				"POST " .. api .. "/team",
				"DELETE " .. api .. "/campaigns/cam_A1",
				"GET https://app.lemlist.com/api/campaigns",
				"GET https://api.lemlist.com.evil.test/api/campaigns",
				"GET " .. api .. "/campaigns/%2e%2e/team",
			})
			m.rejectOverrides(r, { "GET " .. api .. "/campaigns" })
		end
	end,
}
