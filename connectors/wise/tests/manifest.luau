return {
	contract = function(m)
		-- TestWiseAccessRoutes
		do
			local quote = "2d0b3b6e-6f1c-4c43-9c6a-1b6a0f4f3a10"
			for _, hosts in
				{ { "api.wise.com", "api.wise-sandbox.com" }, { "api.wise-sandbox.com", "api.wise.com" } }
			do
				local host, api, other = hosts[1], "https://" .. hosts[1], "https://" .. hosts[2]
				for _, access in { "read-only", "read-write" } do
					local r, err = m.resolve(
						nil,
						{ access = access, api_host = host },
						{ token = "wise_fixture" },
						"token"
					)
					assert(not err, tostring(err))
					m.routes(r, "Bearer wise_fixture", true, {
						"GET " .. api .. "/v1/me",
						"GET " .. api .. "/v2/profiles",
						"GET " .. api .. "/v4/profiles/1/balances?types=STANDARD",
						"GET " .. api .. "/v1/profiles/1/total-funds/EUR",
						"GET " .. api .. "/v1/profiles/1/activities?size=100",
						"GET " .. api .. "/v1/profiles/1/balance-statements/2/statement.json?currency=EUR",
						"GET " .. api .. "/v1/profiles/1/balance-statements/2/statement.mt940",
						"GET " .. api .. "/v1/transfers?profile=1",
						"GET " .. api .. "/v1/transfers/9/receipt.pdf",
						"GET " .. api .. "/v3/profiles/1/quotes/" .. quote,
						"GET " .. api .. "/v1/quotes/" .. quote .. "/account-requirements",
						"GET " .. api .. "/v2/accounts?profileId=1",
						"GET " .. api .. "/v1/rates",
					})
					for _, rule in m.raw.proxy do
						for _, method in rule.match.method do
							for _, path in rule.match.path do
								local route = method .. " " .. api .. (string.gsub(path, "{[%w_]+}", quote))
								if method == "GET" then
									m.routes(r, "Bearer wise_fixture", true, { route })
									continue
								end
								m.routes(r, "Bearer wise_fixture", (access == "read-write"), { route })
							end
						end
					end
					m.routes(r, "Bearer wise_fixture", false, {
						"GET " .. other .. "/v2/profiles",
						"POST " .. api .. "/oauth/token",
						"GET " .. api .. "/v1/user/pin",
						"POST " .. api .. "/v1/one-time-token/pin/verify",
						"GET " .. api .. "/v1/identity/one-time-token/status",
						"POST https://twcard.wise.com/twcard-data/v1/sensitive-card-data/details",
						"GET " .. api .. "/v3/spend/profiles/1/cards",
						"GET " .. api .. "/v3/profiles/1/subscriptions",
						"POST " .. api .. "/v3/profiles/1/subscriptions",
						"PUT " .. api .. "/v2/profiles/1/personal-profile",
						"POST " .. api .. "/auth/jose/request/public-keys",
						"DELETE " .. api .. "/v2/accounts/5",
						"GET " .. api .. "/v1/users/1/contact-email",
						"GET " .. api .. "/2026Q4/profiles",
						"GET https://api.transferwise.com/v2/profiles",
						"GET https://" .. host .. ".evil.test/v2/profiles",
						"GET " .. api .. "/v2/profiles/%2e%2e/1",
						"GET " .. api .. "/v1/profiles/1/balance-statements/2/statement.html",
						"POST " .. api .. "/v1/transfers/9/cancel",
						"PATCH " .. api .. "/v1/transfers/9",
					})
					m.rejectOverrides(r, { "GET " .. api .. "/v2/profiles" })
				end
			end
			do
				local _, err = m.resolve(
					nil,
					{ api_host = "attacker.example" },
					{ token = "wise_fixture" },
					"token"
				)
				if (err == nil) or not (string.find(tostring(err), "api_host", 1, true) ~= nil) then
					m.fail("accepted an environment host outside the options: %s", err)
				end
			end
		end
	end,
}
