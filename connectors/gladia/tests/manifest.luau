return {
	contract = function(m)
		local api = "https://api.gladia.io"
		local job = api .. "/v2/transcription/45463597-20b7-4af7-b3b3-f5fb778203ab"
		local reads = {
			"GET " .. api .. "/v2/transcription",
			"GET " .. api .. "/v2/transcription?limit=10&status=done&status=error&kind=pre-recorded",
			"GET " .. job,
			"GET " .. job .. "/file",
		}
		local writes = {
			"POST " .. api .. "/v2/upload",
			"POST " .. api .. "/v2/transcription",
			"DELETE " .. job,
		}
		-- Each allowed route carries the key in x-gladia-key, replacing a caller's, and drops Authorization.
		local function keyed(r, routes)
			for _, route in routes do
				local method, href = string.match(route, "^(%S+) (.+)$")
				local recipe, err = m.recipe(r, method, href)
				if err ~= nil then
					m.fail("%s denied: %s", route, err)
				end
				m.rejectPreparedOverrides(recipe, r.Context, route)
				local headers, problem =
					m.prepare(recipe, r.Context, { Authorization = { "Bearer forged" }, ["x-gladia-key"] = { "forged" } })
				if
					problem ~= nil
					or m.header(headers, "x-gladia-key") ~= "gladia-fixture-key"
					or m.header(headers, "Authorization") ~= ""
				then
					m.fail("%s prepared %s: %s", route, headers, problem)
				end
			end
		end
		for _, access in { "read-only", "read-write" } do
			local r, err = m.resolve(nil, { access = access }, { token = "gladia-fixture-key" }, "api_key")
			assert(r and not err, tostring(err))
			keyed(r, reads)
			if access == "read-write" then
				keyed(r, writes)
			else
				m.routes(r, "", false, writes)
			end
			-- Routes the connector never calls stay closed at both access levels: the legacy and live
			-- APIs, history, other hosts and path tricks.
			m.routes(r, "", false, {
				"POST " .. api .. "/v2/pre-recorded",
				"GET " .. api .. "/v2/pre-recorded",
				"POST " .. api .. "/v2/live",
				"GET " .. api .. "/v2/live",
				"PATCH " .. api .. "/v2/live/45463597-20b7-4af7-b3b3-f5fb778203ab",
				"GET " .. api .. "/v1/history",
				"GET " .. api .. "/v1/models",
				"POST " .. api .. "/audio/text/audio-transcription",
				"PUT " .. job,
				"PATCH " .. job,
				"DELETE " .. api .. "/v2/transcription",
				"DELETE " .. job .. "/file",
				"GET " .. job .. "/file/extra",
				"GET " .. api .. "/v2/transcription/%2e%2e/file",
				"GET " .. api .. "/v2/upload",
				"GET https://api.gladia.io.example.com/v2/transcription",
				"GET https://app.gladia.io/apikeys",
				"GET http://api.gladia.io:8080/v2/transcription",
			})
		end
	end,
}
