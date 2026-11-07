return {
	contract = function(m)
		local dockerhubManifest = "../../connectors/dockerhub/houston.json"
		-- TestDockerHubPublicRoutes
		do
			local r, err = m.resolve(nil, nil, nil, "")
			assert(not err, tostring(err))
			local api = "https://hub.docker.com/v2"
			local nginx = api .. "/namespaces/library/repositories/nginx"
			m.routes(r, "", true, {
				"GET "
					.. api
					.. "/namespaces/docker/repositories?name=desk&ordering=-pull_count&page=2&page_size=100",
				"GET " .. nginx,
				"GET " .. nginx .. "/tags?name=alpine&page=3",
				"GET " .. nginx .. "/tags/latest",
				"GET " .. api .. "/namespaces/bitnami/repositories/redis/tags/7.4.2-debian-12-r0",
			})
			m.routes(r, "", false, {
				"HEAD " .. nginx,
				"HEAD " .. nginx .. "/tags/latest",
				"DELETE " .. nginx .. "/tags/latest",
				"PATCH " .. nginx,
				"POST " .. api .. "/namespaces/docker/repositories",
				"PATCH " .. nginx .. "/immutabletags",
				"POST " .. nginx .. "/immutabletags/verify",
				"GET " .. nginx .. "/tags/",
				"POST " .. api .. "/auth/token",
				"POST " .. api .. "/users/login",
				"POST " .. api .. "/users/2fa-login",
				"GET " .. api .. "/access-tokens",
				"GET " .. api .. "/user/",
				"GET " .. api .. "/user/orgs/",
				"GET " .. api .. "/orgs/docker/members",
				"GET " .. api .. "/orgs/docker/groups",
				"GET " .. api .. "/orgs/docker/access-tokens",
				"GET " .. api .. "/auditlogs/docker",
				"GET " .. api .. "/scim/2.0/Users",
				"GET " .. api .. "/repositories/library/nginx/",
				"DELETE " .. api .. "/repositories/library/nginx/tags/latest/",
				"PATCH " .. api .. "/repositories/library/nginx/",
				"GET " .. api .. "/search/repositories/?query=nginx",
				"GET " .. api .. "/namespaces/library/repositories/%2e%2e/tags",
				"GET " .. api .. "/namespaces/library%2Fnginx/repositories",
				"GET https://registry-1.docker.io/v2/library/nginx/tags/list",
				"GET https://auth.docker.io/token?service=registry.docker.io",
				"GET https://api.scout.docker.com/v1/repositories",
				"GET https://hub.docker.com.example.com/v2/namespaces/docker/repositories",
				"GET https://docker.com/v2/namespaces/docker/repositories",
				"GET http://hub.docker.com:8080/v2/namespaces/docker/repositories",
			})
		end
	end,
}
