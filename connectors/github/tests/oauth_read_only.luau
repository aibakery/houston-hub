return {
	scenario = {publisher = {client_id = "Iv23liFixture", client_secret = "fixture-client-secret"}, config = {}, auth_method = "oauth", auth_config = {}},
	configure = function()
		requests = {}
		http = {request = function(req)
			table.insert(requests, req)
			local body = if string.find(req.url, "/repositories", 1, true) then '{"total_count":1,"repositories":[{"id":42,"name":"Hello-World"}]}' else '{"total_count":1,"installations":[{"id":7,"account":{"login":"octo-org"}}]}'
			return fixture.operation({statusCode = 200, headers = {},
				body = fixture.reader(body)})
		end}
	end,
	run = function(github)
		local names = {}
		for name in github do if name ~= "help" then table.insert(names, name) end end
		assert(#names == 96, "wrong read-only surface for Connect with GitHub: " .. #names)
		assert(github.listNotifications == nil and github.createIssue == nil)
		local installations = fixture.example("listInstallations")
		assert(requests[1].method == "GET" and requests[1].url == "https://api.github.com/user/installations?per_page=20")
		assert(requests[1].headers.Authorization == nil and installations.installations[1].account.login == "octo-org")
		local repositories = fixture.example("listInstallationRepos")
		assert(requests[2].method == "GET" and requests[2].url == "https://api.github.com/user/installations/42/repositories?per_page=20")
		assert(repositories.repositories[1].name == "Hello-World" and requests[2].headers.Authorization == nil)
	end,
}
