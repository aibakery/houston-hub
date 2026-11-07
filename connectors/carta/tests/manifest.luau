return {
	contract = function(m)
		do
			local readScopes = {
				"read_user_info",
				"read_issuer_info",
				"read_issuer_capitalizationtablesummary",
				"read_issuer_stakeholdercapitalizationtable",
				"read_issuer_shareclasses",
				"read_issuer_stakeholders",
				"read_issuer_securities",
				"read_issuer_valuations",
				"read_issuer_securitiestemplates",
				"read_issuer_interests",
				"read_issuer_draftsecurities",
				"read_corporation_info",
				"read_compensation_benchmarks",
				"read_opencaptables",
				"read_investor_firms",
				"read_investor_funds",
				"read_investor_investments",
				"read_investor_capitalizationtables",
				"read_investor_stakeholdercapitalizationtable",
				"read_investor_securities",
				"read_investor_cashbalances",
				"read_investor_fundperformance",
				"read_investor_partners",
				"read_portfolio_info",
				"read_portfolio_securities",
				"read_portfolio_issuervaluations",
				"read_portfolio_transactions",
				"read_portfolio_fundinvestmentdocuments",
			}
			local writeScopes = {
				"readwrite_issuer_securities",
				"readwrite_issuer_draftsecurities",
				"readwrite_issuer_secondarytransactions",
				"readwrite_draftissuers",
				"readwrite_opencaptables",
				"readwrite_file_upload",
				"readwrite_investor_capitalcalls",
				"readwrite_investor_carriedinterest",
				"readwrite_investor_managementfees",
			}
			for method, login in
				{
					carta = "https://login.app.carta.com",
					own_app = "https://login.app.carta.com",
					playground = "https://login.playground.carta.team",
				}
			do
				if
					(m.raw.auth[method].authorize_url ~= login .. "/o/authorize/")
					or (m.raw.auth[method].token_url ~= login .. "/o/access_token/")
				then
					m.fail(
						"%s endpoints %s %s",
						method,
						m.raw.auth[method].authorize_url,
						m.raw.auth[method].token_url
					)
				end
				for _, access in { "read-only", "read-write" } do
					local config = { access = access }
					local publisher = { client_id = "houston-client", client_secret = "houston-secret" }
					if method ~= "carta" then
						config["own_app"], config["client_id"], config["client_secret"], publisher =
							true, "fixture-client", "fixture-secret", nil
					end
					local r, err = m.resolve(publisher, config, nil, method)
					assert(not err, tostring(err))
					local scopes = readScopes
					if access == "read-write" then
						scopes = m.concat(readScopes, writeScopes)
					end
					if not (m.equal(r.Scopes, scopes)) then
						m.fail("%s access=%s scopes %s", method, access, r.Scopes)
					end
					local token = "carta-" .. method
					r.Context.Auth[method].access_token = token
					for _, api in
						{ "https://api.carta.com/v1alpha1", "https://api.playground.carta.team/v1alpha1" }
					do
						m.routes(r, "Bearer " .. token, true, {
							"GET " .. api .. "/user",
							"GET " .. api .. "/issuers?pageSize=50",
							"GET " .. api .. "/issuers/7/stakeholders/611/equitySummary",
							"GET " .. api .. "/investors/firms/F/funds/-/metrics",
							"GET " .. api .. "/portfolios/P/fundInvestmentDocuments/D:download",
							"POST " .. api .. "/issuers/7/securities:stockSplitChanges",
						})
						m.routes(r, "Bearer " .. token, (access == "read-write"), {
							"GET " .. api .. "/investors/firms/F/funds/U/capitalCalls/C",
							"GET " .. api .. "/investors/firms/F/funds/U/managementFees/M",
							"GET " .. api .. "/issuers/7/secondaryTransactions/S",
							"GET " .. api .. "/draftIssuers/D",
							"POST " .. api .. "/investors/firms/F/funds/U/capitalCalls",
							"POST " .. api .. "/investors/firms/F/funds/U/capitalCalls/C:adjust",
							"POST " .. api .. "/issuers/7/optionExercises/E:updateTaxWithholding",
							"POST " .. api .. "/issuers/7/secondaryTransactions/S:finalize",
							"POST " .. api .. "/draftIssuers",
							"POST " .. api .. "/files:upload",
						})
						m.routes(r, "Bearer " .. token, false, {
							"POST " .. api .. "/issuers",
							"DELETE " .. api .. "/issuers/7",
							"PATCH " .. api .. "/issuers/7/stakeholders/611",
							"GET " .. api .. "/issuers/7/unlisted",
							"POST " .. api .. "/issuers/7/securities:otherVerb",
							"GET " .. api .. "/issuers/%2e%2e/user",
							"GET https://api.carta.com/v1/issuers",
						})
					end
					m.routes(r, "Bearer " .. token, false, {
						"POST https://login.app.carta.com/o/access_token/",
						"POST https://login.playground.carta.team/o/revoke_token/",
						"GET https://login.app.carta.com/o/userinfo/",
						"GET https://app.carta.com/v1alpha1/user",
						"GET https://mock-api.carta.com/v1alpha1/user",
						"GET https://api.carta.com.example.com/v1alpha1/user",
						"GET https://crm-public-api.app.carta.com/v1/me",
					})
				end
			end
		end
		do
			local carta, err = m.resolve(
				{ client_id = "houston-client", client_secret = "houston-secret" },
				{ access = "read-only" },
				nil,
				"carta"
			)
			assert(not err, tostring(err))
			carta.Context.Auth["carta"].access_token = "carta-token"
			m.rejectOverrides(carta, {
				"GET https://api.carta.com/v1alpha1/issuers/7",
				"POST https://api.carta.com/v1alpha1/issuers/7/securities:stockSplitChanges",
			})
			local cartaWrites, err = m.resolve(
				{ client_id = "houston-client", client_secret = "houston-secret" },
				{ access = "read-write" },
				nil,
				"carta"
			)
			assert(not err, tostring(err))
			cartaWrites.Context.Auth["carta"].access_token = "carta-token"
			m.rejectOverrides(cartaWrites, {
				"POST https://api.carta.com/v1alpha1/draftIssuers",
				"GET https://api.carta.com/v1alpha1/draftIssuers/D1",
			})
		end
	end,
}
