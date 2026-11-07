return {
	contract = function(m)
		-- TestAssessFirstAccessRoutes
		do
			local token = "fixture-af-token"
			local c, pm, g =
				"/ab4699c9169d469c81082accfbe91584",
				"/1d9c92277e264fe49a4ce330e51e6ac7",
				"/786a70ccd1454e83bfae271ffa721c0d"
			do
				local _, err = m.resolve(nil, nil, nil, "token")
				if err == nil then
					m.fail("accepted missing token")
				end
			end
			do
				local _, err = m.resolve(nil, { api_host = "attacker.example" }, { token = token }, "token")
				if (err == nil) or not (string.find(tostring(err), "api_host", 1, true) ~= nil) then
					m.fail("accepted an environment host outside the options: %s", err)
				end
			end
			for _, hosts in
				{
					{ "app.assessfirst.com", "simu.assessfirst.com" },
					{ "simu.assessfirst.com", "app.assessfirst.com" },
				}
			do
				local host, other = hosts[1], hosts[2]
				local api = "https://" .. host .. "/betty-V2"
				for _, access in { "custom", "read-only", "read-write" } do
					local r, err = m.resolve(
						nil,
						{ access = access, api_host = host },
						{ token = token },
						"token"
					)
					assert(not err, tostring(err))
					if
						((m.count(r.PublicConfig) ~= 2) or (r.PublicConfig["access"] ~= access))
						or (r.PublicConfig["api_host"] ~= host)
					then
						m.fail("unexpected Lua config: %s", r.PublicConfig)
					end
					local assert = function(allowed, ...)
						local routes = { ... }
						for _, route in routes do
							local method, url, _ = m.cut(route, " ")
							local recipe, err = m.recipe(r, method, url, nil)
							if (err == nil) ~= allowed then
								m.fail("%s %s allowed=%s: %s", access, route, (err == nil), err)
							end
							if err ~= nil then
								continue
							end
							m.rejectPreparedOverrides(recipe, r.Context, access .. " " .. route)
							local headers, err = m.prepare(recipe, r.Context, { ["Af-Token"] = { "forged" } })
							if (err ~= nil) or (m.header(headers, "AF-Token") ~= token) then
								m.fail("credential injection for %s: %s %s", route, headers, err)
							end
						end
					end
					assert(
						true,
						"GET " .. api .. "/candidates?email=a%40example.com&page=2",
						"GET " .. api .. "/candidate" .. c .. "/completion?pm_uuid=x",
						"GET " .. api .. "/predictive-models",
						"GET " .. api .. "/groups",
						"GET " .. api .. "/groups" .. g .. "/users"
					)
					assert(
						(access ~= "custom"),
						"GET " .. api .. "/locales",
						"GET " .. api .. "/candidate" .. c,
						"GET " .. api .. "/candidate" .. c .. "/scores",
						"GET " .. api .. "/candidate" .. c .. "/synthesis",
						"GET " .. api .. "/candidate" .. c .. "/reports",
						"GET " .. api .. "/candidate" .. c .. "/report/20?pm_uuid=x",
						"GET " .. api .. "/candidate" .. c .. "/adequacies" .. pm,
						"GET " .. api .. "/candidate" .. c .. "/career/top",
						"GET " .. api .. "/candidate" .. c .. "/init-voice" .. pm,
						"GET " .. api .. "/onepager/candidate" .. c .. "/results",
						"GET " .. api .. "/benchmarks",
						"GET " .. api .. "/recruiters",
						"GET " .. api .. "/webhooks"
					)
					assert(
						(access == "read-write"),
						"POST " .. api .. "/candidate/send-invitation",
						"POST " .. api .. "/candidate",
						"POST " .. api .. "/candidate" .. c .. "/init-voice" .. pm,
						"POST " .. api .. "/webhooks",
						"DELETE " .. api .. "/webhooks" .. g,
						"POST " .. api .. "/groups",
						"DELETE " .. api .. "/groups" .. g,
						"POST " .. api .. "/groups" .. g .. "/user" .. c,
						"DELETE " .. api .. "/groups" .. g .. "/user" .. c
					)
					assert(
						false,
						"GET " .. api .. "/candidate/iframe/token/assessment",
						"GET https://" .. host .. "/betty/consents",
						"POST https://" .. host .. "/betty/users",
						"GET https://" .. other .. "/betty-V2/locales",
						"GET https://report.assessfirst.com/report/summary_report" .. c,
						"GET https://" .. host .. ".attacker.test/betty-V2/locales",
						"GET http://" .. host .. "/betty-V2/locales",
						"GET https://" .. host .. ":8443/betty-V2/locales",
						"PUT " .. api .. "/groups" .. g,
						"PATCH " .. api .. "/webhooks" .. g,
						"DELETE " .. api .. "/candidate" .. c,
						"GET " .. api .. "/candidate/%2e%2e/recruiters"
					)
				end
			end
		end
	end,
}
