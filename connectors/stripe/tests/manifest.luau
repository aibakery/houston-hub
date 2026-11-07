return {
	contract = function(m)
		-- TestStripeAccessRoutes
		do
			local api = "https://api.stripe.com"
			local files = "https://files.stripe.com"
			for _, access in { "read-only", "read-write" } do
				local r, err = m.resolve(nil, { access = access }, { token = "rk_test_fixture" }, "token")
				assert(not err, tostring(err))
				m.routes(r, "Bearer rk_test_fixture", true, {
					"GET " .. api .. "/v1/account",
					"GET " .. api .. "/v1/balance",
					"GET " .. api .. "/v1/customers?limit=10",
					"GET " .. api .. "/v1/customers/search?query=email",
					"GET " .. api .. "/v1/invoices/in_1/lines",
					"GET " .. api .. "/v1/payment_intents/pi_1",
					"GET " .. api .. "/v1/files/file_1",
					"GET " .. files .. "/v1/files/file_1/contents",
				})
				m.routes(r, "Bearer rk_test_fixture", (access == "read-write"), {
					"POST " .. api .. "/v1/payment_intents",
					"POST " .. api .. "/v1/payment_intents/pi_1/confirm",
					"POST " .. api .. "/v1/refunds",
					"POST " .. api .. "/v1/payouts",
					"POST " .. api .. "/v1/invoices/in_1/send",
					"DELETE " .. api .. "/v1/customers/cus_1",
					"DELETE " .. api .. "/v1/subscriptions/sub_1",
					"POST " .. files .. "/v1/files",
				})
				m.routes(r, "Bearer rk_test_fixture", false, {
					"POST " .. api .. "/v1/files",
					"GET " .. api .. "/v1/files/file_1/contents",
					"POST " .. files .. "/v1/refunds",
					"GET " .. api .. "/v1/api_keys",
					"POST " .. api .. "/oauth/token",
					"GET " .. api .. "/v1/atlas/companies",
					"POST " .. api .. "/v1/accounts",
					"GET " .. api .. "/v1/accounts/acct_1",
					"GET " .. api .. "/v1/webhook_endpoints",
					"GET https://dashboard.stripe.com/atlas",
					"GET https://api.stripe.com.evil.test/v1/balance",
					"GET https://files.stripe.com.evil.test/v1/files/file_1/contents",
					"GET " .. api .. "/v1/customers/%2e%2e/balance",
					"PUT " .. api .. "/v1/customers/cus_1",
					"GET " .. api .. "/v2/core/accounts",
				})
				for _, rule in m.raw.proxy do
					if (m.count(rule.match.host) ~= 1) or (m.count(rule.match.method) ~= 1) then
						m.fail("unexpected broad Stripe rule")
					end
				end
				local recipe, err = m.recipe(r, "GET", api .. "/v1/balance", nil)
				assert(not err, tostring(err))
				m.rejectPreparedOverrides(recipe, r.Context, "GET " .. api .. "/v1/balance")
				local headers, err = m.prepare(recipe, r.Context, {
					Authorization = { "forged" },
					["Stripe-Version"] = { "old" },
					["Stripe-Account"] = { "acct_other" },
					["Stripe-Context"] = { "acct_other" },
				})
				assert(not err, tostring(err))
				if
					(m.header(headers, "Stripe-Version") ~= "2026-09-30.endive")
					or (m.header(headers, "Authorization") ~= "Bearer rk_test_fixture")
				then
					m.fail(headers)
				end
				for _, header in { "Stripe-Account", "Stripe-Context" } do
					if m.header(headers, header) ~= "" then
						m.fail("kept %s", header)
					end
				end
			end
		end
	end,
}
