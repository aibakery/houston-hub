return {
	contract = function(m)
		-- TestGitHubAuthenticationAndAccessRoutes
		do
			local api = "https://api.github.com"
			local publisher = { client_id = "Iv23liFixture", client_secret = "fixture-client-secret" }
			for _, method in { "oauth", "token" } do
				for _, access in { "read-only", "read-write" } do
					local input = { token = "fixture-token" }
					if method == "oauth" then
						input = nil
					end
					local r, err = m.resolve(publisher, { access = access }, input, method)
					assert(not err, tostring(err))
					if m.count(r.Scopes) ~= 0 then
						m.fail("GitHub App sign-in requests no scopes, got %s", r.Scopes)
					end
					if method == "oauth" then
						r.Context.Auth[method].access_token = "fixture-token"
					end
					m.routes(r, "Bearer fixture-token", true, {
						"GET " .. api .. "/user",
						"GET " .. api .. "/repos/o/r/issues?state=open",
						"GET " .. api .. "/repos/o/r/branches/feature%2Fx",
						"GET " .. api .. "/repos/o/r/contents/src%2Fmain.go?ref=release%2F1",
						"GET " .. api .. "/repos/o/r/compare/main...feature%2Fx",
						"GET " .. api .. "/repos/o/r/commits/feature%2Fx/check-runs",
						"GET " .. api .. "/repos/o/r/git/ref/heads%2Ffeature%2Fx",
						"GET " .. api .. "/repos/o/r/releases/tags/app%2Fv1",
						"GET " .. api .. "/repos/o/r/git/trees/feature%2Fx",
						"GET " .. api .. "/search/code?q=x",
						"GET " .. api .. "/repos/o/r/actions/jobs/1/logs",
						"GET "
							.. api
							.. "/repos/o/r/contents/test%2Ffolder%2525with%20percentage%23%2Findex.js",
						"GET " .. api .. "/repos/o/r/branches/fix%2F100%25",
						"GET " .. api .. "/users/octocat/events",
						"GET " .. api .. "/user/starred?sort=updated",
						"GET " .. api .. "/repos/o/r/pulls/comments/1",
					})
					m.routes(r, "Bearer fixture-token", (access == "read-write"), {
						"POST " .. api .. "/repos/o/r/issues",
						"PATCH " .. api .. "/repos/o/r/pulls/1",
						"PUT " .. api .. "/repos/o/r/pulls/1/merge",
						"PUT " .. api .. "/repos/o/r/contents/docs%2Fa.md",
						"DELETE " .. api .. "/repos/o/r/contents/docs%2Fa.md",
						"PATCH " .. api .. "/repos/o/r/git/refs/heads%2Fx",
						"DELETE " .. api .. "/repos/o/r/git/refs/heads%2Fx",
						"DELETE " .. api .. "/repos/o/r/issues/1/labels/area%2Fui",
						"POST " .. api .. "/repos/o/r/branches/old%2Fname/rename",
						"DELETE " .. api .. "/repos/o/r/issues/1/labels/50%25%20done",
						"PATCH " .. api .. "/repos/o/r/labels/100%25",
						"PUT " .. api .. "/user/starred/o/r",
						"DELETE " .. api .. "/user/starred/o/r",
						"POST " .. api .. "/repos/o/r/commits/c1/comments",
						"PATCH " .. api .. "/repos/o/r/pulls/comments/1",
					})
					m.routes(r, "Bearer fixture-token", false, {
						"DELETE " .. api .. "/repos/o/r",
						"PATCH " .. api .. "/repos/o/r",
						"POST " .. api .. "/graphql",
						"GET " .. api .. "/repos/o/r/actions/secrets",
						"GET " .. api .. "/repos/o/r/actions/secrets/public-key",
						"GET " .. api .. "/repos/o/r/hooks",
						"GET " .. api .. "/repos/o/r/keys",
						"PUT " .. api .. "/repos/o/r/collaborators/u",
						"POST " .. api .. "/applications/abc/token",
						"DELETE " .. api .. "/installation/token",
						"POST " .. api .. "/credentials/revoke",
						"GET " .. api .. "/authorizations",
						"POST https://github.com/login/oauth/access_token",
						"GET https://api.github.com.evil.test/user",
						"GET " .. api .. "/repos/o/r/contents/%2e%2e%2fsecrets",
						"GET " .. api .. "/repos/o/r/branches/a%2F..%2F..%2Fhooks",
						"GET " .. api .. "/repos/o/r/issues/1%2F..%2F2",
						"GET " .. api .. "/repos/o/r/contents/%252e%252e%252fsecrets",
						"POST " .. api .. "/repos/o/r/branches/a/protection",
						"PATCH " .. api .. "/repos/o/r/issues/1/labels/x",
						"GET " .. api .. "/repos/o/r/git/refs/heads",
						"GET https://uploads.github.com/repos/o/r/releases/1/assets",
						"POST https://uploads.github.com/repos/o/r/releases/1/assets?name=a.zip",
						"POST https://codeload.github.com/o/r/legacy.tar.gz/main",
					})
					for _, url in
						{
							"https://codeload.github.com/o/r/legacy.tar.gz/refs/heads/feature/x?token=SIGNED",
							"https://release-assets.githubusercontent.com/github-production-release-asset/1/abc?sig=SIGNED",
							"https://productionresultssa12.blob.core.windows.net/actions-results/a/logs.txt?sig=SIGNED",
							"https://pipelinesghubeus6.actions.githubusercontent.com/x/logs.zip?sig=SIGNED",
							"https://gist.githubusercontent.com/o/aa5a315d61ae9438b18d/raw/3a0f86fb/big%20data.json",
						}
					do
						local recipe, err = m.recipe(r, "GET", url, nil)
						if err ~= nil then
							m.fail(url, err)
						end
						local headers, err = m.prepare(recipe, r.Context, { Authorization = { "forged" } })
						if (err ~= nil) or (m.header(headers, "Authorization") ~= "") then
							m.fail("signed download %s kept credentials: %s %s", url, headers, err)
						end
					end
				end
			end
		end
	end,
}
