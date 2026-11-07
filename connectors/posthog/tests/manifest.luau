return {
	contract = function(m)
		-- TestPostHogReadOnlyRoutes
		do
			do
				local _, err = m.resolve(nil, nil, nil, "token")
				if err == nil then
					m.fail("accepted missing personal API key")
				end
			end
			do
				local _, err = m.resolve(
					nil,
					{ region = "posthog.example.com" },
					{ token = "phx_fixture" },
					"token"
				)
				if err == nil then
					m.fail("accepted a host outside the cloud regions")
				end
			end
			for region, other in
				{ ["us.posthog.com"] = "eu.posthog.com", ["eu.posthog.com"] = "us.posthog.com" }
			do
				local r, err = m.resolve(nil, { region = region }, { token = "phx_fixture" }, "token")
				assert(not err, tostring(err))
				local host = "https://" .. region
				local project = host .. "/api/projects/12345"
				m.routes(r, "Bearer phx_fixture", true, {
					"GET " .. host .. "/api/organizations/?limit=100",
					"GET " .. host .. "/api/organizations/@current/projects/?limit=100",
					"GET "
						.. host
						.. "/api/organizations/0188430e-316e-0000-51a6-fd646548690e/projects/?limit=100&offset=100",
					"GET " .. project .. "/events/?event=%24pageview&limit=100",
					"GET " .. project .. "/persons/?search=ana&limit=100",
					"GET " .. project .. "/insights/?basic=true&limit=100",
					"GET " .. project .. "/insights/AaVQ8Ijw/?refresh=blocking",
					"GET " .. project .. "/feature_flags/?active=true&limit=50",
					"GET " .. host .. "/api/projects/@current/events/?limit=1",
					"POST " .. project .. "/query/",
				})
				m.routes(r, "Bearer phx_fixture", false, {
					"POST " .. project .. "/insights/",
					"PATCH " .. project .. "/insights/1/",
					"DELETE " .. project .. "/persons/1/",
					"POST " .. project .. "/feature_flags/",
					"PATCH " .. project .. "/feature_flags/1/",
					"GET " .. project .. "/feature_flags/1/",
					"GET " .. project .. "/query/abc/",
					"DELETE " .. project .. "/query/abc/",
					"GET " .. project .. "/query/",
					"POST " .. project .. "/events/",
					"GET " .. project .. "/events/018f/",
					"GET " .. project .. "/persons/1/",
					"GET " .. host .. "/api/projects/",
					"GET " .. project .. "/",
					"GET " .. host .. "/api/users/@me/",
					"GET " .. host .. "/api/personal_api_keys/",
					"POST " .. host .. "/api/organizations/",
					"GET " .. project .. "/events",
					"GET " .. project .. "/insights/%2e%2e/",
					"GET " .. host .. "/api/environments/12345/events/",
					"POST https://us.i.posthog.com/i/v0/e/",
					"POST https://eu.i.posthog.com/batch/",
					"POST https://us.i.posthog.com/flags/",
					"GET https://app.posthog.com/api/projects/12345/events/",
					"GET https://us.posthog.com.example.com/api/organizations/",
					"GET http://us.posthog.com:8080/api/organizations/",
					"GET https://" .. other .. "/api/organizations/",
					"POST https://" .. other .. "/api/projects/12345/query/",
				})
			end
		end
	end,
}
