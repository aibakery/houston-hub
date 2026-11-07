return {
	contract = function(m)
		-- TestMercuryAuthenticationAndTransportBoundaries
		do
			do
				local _, err = m.resolve(nil, nil, nil, "token")
				if err == nil then
					m.fail("accepted missing token")
				end
			end
			for _, access in { "read-only", "read-write" } do
				for _, reveal in { false, true } do
					local r, err = m.resolve(
						nil,
						{ access = access, reveal_card_details = reveal },
						{ token = "secret-token:fixture-private" },
						"token"
					)
					assert(not err, tostring(err))
					do
						local err = m.credentials(r.Context)
						assert(not err, tostring(err))
					end
					for key, value in r.PublicConfig do
						if
							(
								(string.find(key, "token", 1, true) ~= nil)
								or (string.find(string.lower(key), "secret", 1, true) ~= nil)
							) or (value == "secret-token:fixture-private")
						then
							m.fail("credential leaked into Lua public config")
						end
					end
					local rules = r.Proxy
					local assertRoute = function(method, url, allowed)
						local caller = { Authorization = { "forged" } }
						local recipe, err = m.recipe(rules, method, url, caller)
						if not allowed then
							if err == nil then
								m.fail("access=%s reveal=%s allowed %s %s", access, reveal, method, url)
							end
							return
						end
						assert(not err, tostring(err))
						local headers, err = m.prepare(recipe, r.Context, caller)
						if
							(
								(err ~= nil)
								or (
									m.header(headers, "Authorization")
									~= "Bearer secret-token:fixture-private"
								)
							) or (m.header(caller, "Authorization") ~= "forged")
						then
							m.fail("incorrect credential injection: %s", err)
						end
					end
					for _, path in
						{
							"/accounts?limit=10",
							"/account/a/statements",
							"/account/a/transactions?offset=2",
							"/transactions?search=invoice%20%26%20rent",
							"/transaction/t",
							"/treasury",
							"/treasury/t/statements",
							"/statements/s/pdf",
							"/credit",
							"/safes",
							"/safes/s",
							"/safes/s/document",
							"/ar/invoices/i/pdf",
							"/ar/attachments/a",
							"/cards/c",
							"/users/u",
							"/webhooks/w",
						}
					do
						assertRoute("GET", "https://api.mercury.com/api/v1" .. path, true)
					end
					for _, route in
						{
							{ "POST", "/account/a/transactions" },
							{ "POST", "/account/a/request-send-money" },
							{ "POST", "/transfer" },
							{ "POST", "/request-transfer" },
							{ "POST", "/recipients" },
							{ "POST", "/recipients/invites" },
							{ "DELETE", "/recipient/r" },
							{ "PATCH", "/transaction/t" },
							{ "POST", "/transaction/t/attachments" },
							{ "POST", "/recipient/r/attachments" },
							{ "POST", "/ar/invoices" },
							{ "POST", "/ar/invoices/i/cancel" },
							{ "DELETE", "/ar/customers/c" },
							{ "POST", "/cards" },
							{ "POST", "/cards/c/freeze" },
							{ "POST", "/cards/c/unfreeze" },
							{ "POST", "/cards/c/cancel" },
							{ "POST", "/webhooks/w/verify" },
							{ "DELETE", "/webhooks/w" },
						}
					do
						assertRoute(
							route[1],
							"https://api.mercury.com/api/v1" .. route[2],
							(access == "read-write")
						)
					end
					assertRoute("GET", "https://vault-api.mercury.com/api/v1/cards/c/reveal", reveal)
					for _, route in
						{
							{ "GET", "https://api.mercury.com/api/v1/cards/c/reveal" },
							{ "POST", "https://vault-api.mercury.com/api/v1/cards/c/reveal" },
							{ "GET", "https://vault-api.mercury.com/api/v1/accounts" },
							{ "GET", "https://api.mercury.com.attacker.test/api/v1/accounts" },
							{ "GET", "http://api.mercury.com/api/v1/accounts" },
							{ "GET", "https://api.mercury.com:8443/api/v1/accounts" },
							{ "GET", "https://api-sandbox.mercury.com/api/v1/accounts" },
							{ "GET", "https://untrusted.s3.amazonaws.com/file" },
							{ "POST", "https://api.mercury.com/api/v1/safes" },
							{ "POST", "https://api.mercury.com/api/v1/safes/s/sign" },
							{ "POST", "https://api.mercury.com/api/v1/request-send-money/r/approve" },
							{ "POST", "https://api.mercury.com/api/v1/users" },
							{ "GET", "https://api.mercury.com/api/v1/account/a" },
							{ "GET", "https://api.mercury.com/api/v1/safes/%2e%2e/accounts" },
							{ "POST", "https://api.mercury.com/oauth2/token" },
						}
					do
						assertRoute(route[1], route[2], false)
					end
				end
			end
			local r, err = m.resolve(nil, nil, { token = "fixture" }, "token")
			if
				((err ~= nil) or (r.PublicConfig["access"] ~= "read-only"))
				or (r.PublicConfig["reveal_card_details"] ~= false)
			then
				m.fail("wrong defaults: %s, %s", r, err)
			end
		end
	end,
}
