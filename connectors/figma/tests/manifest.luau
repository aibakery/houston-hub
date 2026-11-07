return {
	contract = function(m)
		local assertFigmaRoutes = function(r, header, value, allowed, ...)
			local routes = { ... }
			for _, route in routes do
				local method, url, _ = m.cut(route, " ")
				local recipe, err = m.recipe(r, method, url, nil)
				if (err == nil) ~= allowed then
					m.fail("%s allowed=%s: %s", route, (err == nil), err)
				end
				if err ~= nil then
					continue
				end
				local headers, err = m.prepare(
					recipe,
					r.Context,
					{ Authorization = { "forged" }, ["X-Figma-Token"] = { "forged" } }
				)
				local other = "Authorization"
				if header == other then
					other = "X-Figma-Token"
				end
				if
					((err ~= nil) or (m.header(headers, header) ~= value)) or (m.header(headers, other) ~= "")
				then
					m.fail("credential injection for %s: %s %s", route, headers, err)
				end
			end
		end
		-- TestFigmaScopesAndAccessRoutes
		do
			local readScopes = {
				"current_user:read",
				"file_content:read",
				"file_metadata:read",
				"file_versions:read",
				"file_comments:read",
				"library_assets:read",
				"library_content:read",
				"team_library_content:read",
				"projects:read",
			}
			local api, key = "https://api.figma.com", "aBcDeFgHiJkLmNoPqRsTuV12"
			local entries = m.endpoints()
			local ids = { file_key = key, team_id = "123", project_id = "77", comment_id = "7", key = "abc" }
			for _, method in { "token", "oauth" } do
				for _, access in { "read-only", "read-write" } do
					local config = { access = access }
					local input = { token = "figd_fixture" }
					local header, value = "X-Figma-Token", "figd_fixture"
					if method == "oauth" then
						config["client_id"], config["client_secret"], input =
							"fixture-client", "fixture-secret", nil
					end
					local r, err = m.resolve(nil, config, input, method)
					assert(not err, tostring(err))
					if method == "oauth" then
						local scopes = readScopes
						if access == "read-write" then
							scopes = m.concat(table.clone(readScopes), { "file_comments:write" })
						end
						if not (m.equal(r.Scopes, scopes)) then
							m.fail("access=%s scopes %s", access, r.Scopes)
						end
						header, value = "Authorization", "Bearer figu_fixture"
						r.Context.Auth["oauth"].access_token = "figu_fixture"
					end
					for _, entry in entries do
						assertFigmaRoutes(
							r,
							header,
							value,
							(not entry.write or (access == "read-write")),
							entry.method .. " " .. api .. (string.gsub(entry.path, "{([%w_]+)}", ids))
						)
					end
					assertFigmaRoutes(
						r,
						"Authorization",
						"",
						true,
						"GET https://figma-alpha-api.s3.us-west-2.amazonaws.com/images/u1"
					)
					assertFigmaRoutes(
						r,
						header,
						value,
						false,
						"GET " .. api .. "/v1/files/" .. key .. "/variables/local",
						"POST " .. api .. "/v1/files/" .. key .. "/variables",
						"POST " .. api .. "/v1/files/" .. key .. "/duplicate",
						"GET " .. api .. "/v1/files/" .. key .. "/dev_resources",
						"POST " .. api .. "/v1/dev_resources",
						"GET " .. api .. "/v2/webhooks",
						"POST " .. api .. "/v2/webhooks",
						"GET " .. api .. "/v2/webhooks/1/requests",
						"POST " .. api .. "/v1/teams/123/invites",
						"GET " .. api .. "/v1/activity_logs",
						"GET " .. api .. "/v1/payments",
						"POST " .. api .. "/v1/oauth/token",
						"POST " .. api .. "/v1/oauth/refresh",
						"PUT " .. api .. "/v1/files/" .. key .. "/comments",
						"POST " .. api .. "/v1/files/" .. key .. "/comments/7",
						"GET " .. api .. "/v1/files/%2e%2e/comments",
						"GET https://www.figma.com/api/v1/me",
						"GET https://api.figma.com.example.com/v1/me",
						"GET https://figma-alpha-api.s3.us-west-2.amazonaws.com/other/u1",
						"PUT https://figma-alpha-api.s3.us-west-2.amazonaws.com/images/u1",
						"GET https://s3-alpha-sig.figma.com/img/a/b/c"
					)
				end
			end
		end
	end,
}
