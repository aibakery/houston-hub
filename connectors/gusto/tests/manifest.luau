return {
	contract = function(m)
		-- TestGustoAccessRoutes
		do
			for method, origin in { gusto = "gusto.com", own_app = "gusto.com", demo = "gusto-demo.com" } do
				local a = m.raw.auth[method]
				if
					(
						(
							(a.authorize_url ~= "https://app." .. origin .. "/oauth/authorize")
							or (a.token_url ~= "https://api." .. origin .. "/oauth/token")
						) or (a.pkce ~= "none")
					) or not a.require_refresh
				then
					m.fail("%s endpoints %s %s %s", method, a.authorize_url, a.token_url, a.pkce)
				end
				for _, access in { "read-only", "read-write" } do
					local config = { access = access }
					local publisher = { client_id = "houston-client", client_secret = "houston-secret" }
					if method ~= "gusto" then
						config["own_app"], config["client_id"], config["client_secret"], publisher =
							true, "fixture-client", "fixture-secret", nil
					end
					local r, err = m.resolve(publisher, config, nil, method)
					assert(not err, tostring(err))
					if m.count(r.Scopes) ~= 0 then
						m.fail("%s requests scopes %s", method, r.Scopes)
					end
					local token = "gusto-" .. method
					r.Context.Auth[method].access_token = token
					for _, api in { "https://api.gusto.com/v1", "https://api.gusto-demo.com/v1" } do
						m.routes(r, "Bearer " .. token, true, {
							"GET " .. api .. "/token_info",
							"GET " .. api .. "/companies/c1/employees?include=custom_fields&page=1&per=100",
							"GET " .. api .. "/companies/c1/payrolls/p1?include=taxes",
							"GET " .. api .. "/companies/c1/pay_schedules/assignments",
							"POST " .. api .. "/payrolls/p1/reports/general_ledger",
							"POST " .. api .. "/payrolls/p1/employees/e1/calculate_accruing_time_off_hours",
						})
						m.routes(r, "Bearer " .. token, (access == "read-write"), {
							"POST " .. api .. "/companies/c1/employees",
							"PUT " .. api .. "/employees/e1",
							"DELETE " .. api .. "/employees/e1",
							"PUT " .. api .. "/companies/c1/payrolls/p1/prepare",
							"PUT " .. api .. "/companies/c1/payrolls/p1",
							"PATCH " .. api .. "/employees/e1/section603_high_earner_statuses/2026",
							"DELETE " .. api .. "/time_tracking/time_sheets/t1?version=v1",
						})
						m.routes(r, "Bearer " .. token, false, {
							"PUT " .. api .. "/companies/c1/payrolls/p1/submit",
							"PUT " .. api .. "/companies/c1/payrolls/p1/calculate",
							"PUT " .. api .. "/companies/c1/payrolls/p1/cancel",
							"POST " .. api .. "/companies/c1/payrolls",
							"POST " .. api .. "/companies/c1/contractor_payments",
							"PUT " .. api .. "/contractor_payments/cp1/fund",
							"GET " .. api .. "/webhook_subscriptions",
							"GET " .. api .. "/events",
							"POST " .. api .. "/provision",
							"POST " .. api .. "/companies/c1/disconnect_app_integration",
							"GET " .. api .. "/employees/e1/bank_accounts",
							"PATCH " .. api .. "/employees/e1",
							"PUT " .. api .. "/companies/c1",
							"GET " .. api .. "/employees/%2e%2e/token_info",
						})
					end
					m.routes(r, "Bearer " .. token, false, {
						"POST https://api.gusto.com/oauth/token",
						"POST https://api.gusto-demo.com/oauth/revoke",
						"GET https://app.gusto.com/v1/token_info",
						"GET https://mcp.api.gusto.com/v1/token_info",
						"GET https://api.gusto.com.example.com/v1/token_info",
						"GET https://api.gusto.com/v2/token_info",
					})
				end
			end
		end
		-- TestGustoRoutesRejectMethodOverrides
		do
			local r, err = m.resolve(
				{ client_id = "houston-client", client_secret = "houston-secret" },
				{ access = "read-write" },
				nil,
				"gusto"
			)
			assert(not err, tostring(err))
			r.Context.Auth["gusto"].access_token = "gusto-token"
			m.rejectOverrides(r, {
				"GET https://api.gusto.com/v1/employees/e1",
				"POST https://api.gusto.com/v1/payrolls/p1/reports/general_ledger",
				"POST https://api.gusto.com/v1/companies/c1/employees",
				"PUT https://api.gusto.com/v1/employees/e1",
				"PATCH https://api.gusto.com/v1/employees/e1/section603_high_earner_statuses/2026",
				"DELETE https://api.gusto.com/v1/employees/e1",
			})
		end
	end,
}
