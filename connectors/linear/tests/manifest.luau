return {
	contract = function(m)
		-- TestLinearScopesAndAccessRoutes
		do
			local api = "https://api.linear.app/graphql"
			for _, method in { "token", "oauth" } do
				for _, access in { "read-only", "read-write" } do
					local config = { access = access }
					local input = { token = "lin_api_fixture" }
					if method == "oauth" then
						config["client_id"], config["client_secret"], input =
							"fixture-client", "fixture-secret", nil
					end
					local r, err = m.resolve(nil, config, input, method)
					assert(not err, tostring(err))
					local authorization = "lin_api_fixture"
					if method == "oauth" then
						local scopes = { "read" }
						if access == "read-write" then
							scopes = { "write" }
						end
						if not (m.equal(r.Scopes, scopes)) then
							m.fail("access=%s scopes %s", access, r.Scopes)
						end
						authorization = "Bearer lin_oauth_fixture"
						r.Context.Auth["oauth"].access_token = "lin_oauth_fixture"
					end
					m.routes(
						r,
						authorization,
						true,
						{ "GET " .. api .. "?query=%7Bviewer%7Bid%7D%7D", "GET " .. api }
					)
					m.routes(r, authorization, (access == "read-write"), { "POST " .. api })
					m.routes(r, authorization, false, {
						"PUT " .. api,
						"DELETE " .. api,
						"POST https://api.linear.app/oauth/token",
						"POST https://api.linear.app/oauth/revoke",
						"GET https://api.linear.app/graphql/x",
						"GET https://linear.app/graphql",
						"GET https://uploads.linear.app/o1/file",
						"GET https://api.linear.app.example.com/graphql",
						"GET http://api.linear.app:8080/graphql",
					})
					m.rejectOverrides(r, { "GET " .. api })
				end
			end
		end
	end,
}
