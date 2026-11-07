return {
	contract = function(m)
		-- TestGranolaReadOnlyRoutes
		do
			do
				local _, err = m.resolve(nil, nil, nil, "token")
				if err == nil then
					m.fail("accepted missing API key")
				end
			end
			local r, err = m.resolve(nil, nil, { token = "grn_fixture" }, "token")
			assert(not err, tostring(err))
			local api = "https://public-api.granola.ai/v1"
			m.routes(r, "Bearer grn_fixture", true, {
				"GET " .. api .. "/notes?created_after=2026-10-01&page_size=30",
				"GET " .. api .. "/notes/not_1d3tmYTlCICgjy?include=transcript",
				"GET " .. api .. "/notes/not_1d3tmYTlCICgjy/transcript?cursor=c1",
				"GET " .. api .. "/folders",
				"GET " .. api .. "/spaces",
			})
			m.routes(r, "Bearer grn_fixture", false, {
				"POST " .. api .. "/notes",
				"DELETE " .. api .. "/notes/not_1d3tmYTlCICgjy",
				"HEAD " .. api .. "/notes",
				"GET " .. api .. "/webhook-endpoints",
				"POST " .. api .. "/webhook-endpoints",
				"GET " .. api .. "/audit",
				"GET " .. api .. "/legal-holds",
				"GET " .. api .. "/notes/%2e%2e/transcript",
				"GET " .. api .. "/folders/fol_4y6LduVdwSKC27",
				"GET https://api.granola.ai/v1/notes",
				"GET https://public-api.granola.ai.example.com/v1/notes",
				"GET https://mcp.granola.ai/mcp",
				"GET http://public-api.granola.ai:8080/v1/notes",
			})
		end
	end,
}
