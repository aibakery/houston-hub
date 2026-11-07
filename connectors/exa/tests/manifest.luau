return {
	contract = function(m)
		-- TestExaRoutes
		do
			local r, err = m.resolve(nil, nil, { token = "exa-fixture-key" }, "api_key")
			assert(not err, tostring(err))
			local api = "https://api.exa.ai"
			local dropped = { "Authorization" }
			for _, path in { "/search", "/contents", "/findSimilar", "/answer" } do
				local recipe, err = m.recipe(r, "POST", api .. path, nil)
				if err ~= nil then
					m.fail("POST %s denied: %s", path, err)
				end
				m.rejectPreparedOverrides(recipe, r.Context, "POST " .. path)
				local caller = { ["Content-Type"] = { "application/json" }, ["X-Api-Key"] = { "forged" } }
				for _, name in dropped do
					caller[name] = { "Bearer forged" }
				end
				local headers, err = m.prepare(recipe, r.Context, caller)
				if
					((err ~= nil) or (m.header(headers, "x-api-key") ~= "exa-fixture-key"))
					or (m.header(headers, "Content-Type") ~= "application/json")
				then
					m.fail("POST %s prepared %s: %s", path, headers, err)
				end
				for _, name in dropped do
					if m.header(headers, name) ~= "" then
						m.fail("%s reached Exa on %s", name, path)
					end
				end
			end
			m.routes(r, "", false, {
				"GET " .. api .. "/search",
				"POST " .. api .. "/search/x",
				"POST " .. api .. "/research/v1",
				"POST " .. api .. "/agent/runs",
				"GET " .. api .. "/agent/runs/run_1",
				"POST " .. api .. "/monitors",
				"POST " .. api .. "/batches",
				"POST " .. api .. "/chat/completions",
				"POST " .. api .. "/responses",
				"GET " .. api .. "/v0/teams/me",
				"POST " .. api .. "/v0/websets",
				"POST " .. api .. "/websets/v0/websets",
				"GET " .. api .. "/team-management/api-keys",
				"POST " .. api .. "/%2e%2e/agent/runs",
				"POST " .. api .. "/contents/%2e%2e/agent/runs",
				"POST https://api.exa.ai.example.com/search",
				"POST http://api.exa.ai:8080/search",
				"POST https://exa.ai/search",
				"POST https://mcp.exa.ai/mcp",
				"GET https://dashboard.exa.ai/api-keys",
				"POST https://admin-api.exa.ai/team-management/api-keys",
			})
		end
	end,
}
