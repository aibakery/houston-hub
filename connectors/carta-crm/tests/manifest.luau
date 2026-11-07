return {
	contract = function(m)
		do
			local r, err = m.resolve(nil, { access = "read-write" }, { token = "crm-key" }, "token")
			assert(not err, tostring(err))
			local api = "https://crm-public-api.app.carta.com/v1"
			for _, route in
				{
					"PATCH " .. api .. "/deals/batch",
					"DELETE " .. api .. "/deals/batch",
					"PATCH " .. api .. "/contacts/classifier-prompt",
					"PATCH " .. api .. "/deals/pipelines",
					"PATCH " .. api .. "/fundraisings/stages",
					"DELETE " .. api .. "/notes/folders",
					"DELETE " .. api .. "/contacts/merge",
					"GET " .. api .. "/contacts/classifier-prompt",
					"GET " .. api .. "/deals/custom-fields",
					"GET " .. api .. "/email-campaigns/stats",
				}
			do
				local method, url, _ = m.cut(route, " ")
				local recipe, err = m.recipe(r, method, url, nil)
				assert(not err, tostring(err))
				local headers, err = m.prepare(recipe, r.Context, {})
				if (err ~= nil) or (m.header(headers, "Authorization") ~= "") then
					m.fail("%s received the key: %s", route, err)
				end
			end
			for _, route in
				{
					"PATCH " .. api .. "/deals/65a1b2c3d4e5f60718293a4b",
					"GET " .. api .. "/deals/pipelines",
					"GET " .. api .. "/companies/fields",
					"POST " .. api .. "/deals/search",
				}
			do
				local method, url, _ = m.cut(route, " ")
				local recipe, err = m.recipe(r, method, url, nil)
				assert(not err, tostring(err))
				do
					local headers, err = m.prepare(recipe, r.Context, {})
					if (err ~= nil) or (m.header(headers, "Authorization") ~= "crm-key") then
						m.fail("%s lost the key: %s", route, err)
					end
				end
			end
		end
		do
			local crm, err = m.resolve(nil, { access = "read-write" }, { token = "crm-key" }, "token")
			assert(not err, tostring(err))
			local api = "https://crm-public-api.app.carta.com/v1"
			m.rejectOverrides(crm, {
				"GET " .. api .. "/deals/65a1b2c3d4e5f60718293a4b",
				"POST " .. api .. "/companies/search",
				"POST " .. api .. "/contacts",
				"PATCH " .. api .. "/deals/65a1b2c3d4e5f60718293a4b",
			})
		end
	end,
}
