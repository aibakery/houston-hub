return {
	contract = function(m)
		-- TestSentryAccessRoutes
		do
			for _, hosts in { { "us.sentry.io", "de.sentry.io" }, { "de.sentry.io", "us.sentry.io" } } do
				local api, other = "https://" .. hosts[1] .. "/api/0", "https://" .. hosts[2] .. "/api/0"
				local org = api .. "/organizations/acme"
				for _, access in { "read-only", "read-write" } do
					local r, err = m.resolve(
						nil,
						{ access = access, region = hosts[1], organization = "acme" },
						{ token = "sntryu_fixture" },
						"token"
					)
					assert(not err, tostring(err))
					m.routes(r, "Bearer sntryu_fixture", true, {
						"GET " .. api .. "/organizations/?owner=true",
						"GET " .. org .. "/?detailed=0",
						"GET " .. org .. "/projects/?cursor=0%3A100%3A0",
						"GET " .. api .. "/projects/acme/web/",
						"GET " .. org .. "/teams/",
						"GET " .. org .. "/members/?query=email%3Aada%40example.com",
						"GET " .. org .. "/issues/?query=is%3Aunresolved&project=42&project=43",
						"GET " .. org .. "/issues/WEB-1A/",
						"GET " .. org .. "/issues/1001/tags/browser/",
						"GET " .. org .. "/issues/1001/events/?full=true",
						"GET " .. org .. "/issues/1001/events/latest/",
						"GET " .. org .. "/issues/1001/comments/",
						"GET " .. api .. "/projects/acme/web/events/c0ffee00c0ffee00c0ffee00c0ffee00/",
						"GET " .. org .. "/releases/?health=1",
						"GET " .. org .. "/releases/web%401.2.0%2B45/",
						"GET " .. org .. "/sessions/?field=sum%28session%29",
					})
					m.routes(
						r,
						"Bearer sntryu_fixture",
						(access == "read-write"),
						{ "PUT " .. org .. "/issues/1001/", "POST " .. org .. "/issues/WEB-1A/comments/" }
					)
					m.routes(r, "Bearer sntryu_fixture", false, {
						"PUT " .. org .. "/issues/?id=1001",
						"DELETE " .. org .. "/issues/1001/",
						"DELETE " .. org .. "/issues/?id=1001",
						"PUT " .. api .. "/projects/acme/web/issues/?id=1001",
						"PUT " .. api .. "/issues/1001/",
						"POST " .. api .. "/issues/1001/comments/",
						"PUT " .. org .. "/issues/1001/comments/5/",
						"DELETE " .. org .. "/issues/1001/comments/5/",
						"POST " .. org .. "/issues/1001/",
						"POST " .. org .. "/releases/",
						"PUT " .. org .. "/releases/web/",
						"DELETE " .. org .. "/releases/web/",
						"PUT " .. org .. "/",
						"GET " .. api .. "/api-tokens/",
						"POST " .. api .. "/api-tokens/",
						"GET " .. api .. "/projects/acme/web/keys/",
						"GET " .. org .. "/org-auth-tokens/",
						"GET " .. api .. "/sentry-apps/houston/api-tokens/",
						"GET " .. org .. "/integrations/",
						"GET " .. api .. "/projects/acme/web/events/e1/attachments/",
						"GET " .. org .. "/issues/1001/events/latest/json/",
						"GET " .. org .. "/issues/%2e%2e/",
						"GET " .. other .. "/organizations/acme/issues/",
						"GET https://sentry.io/api/0/organizations/acme/issues/",
						"GET https://" .. hosts[1] .. ".example.com/api/0/organizations/",
						"GET http://" .. hosts[1] .. ":8080/api/0/organizations/",
						"POST https://" .. hosts[1] .. "/oauth/token/",
					})
				end
			end
		end
	end,
}
