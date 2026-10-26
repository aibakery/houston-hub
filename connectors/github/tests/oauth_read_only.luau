return {
	scenario = {publisher = {client_id = "Iv23liFixture", client_secret = "fixture-client-secret"}, config = {}, auth_method = "oauth", auth_config = {}},
	configure = function()
		requests = {}
		http = {request = function(req)
			table.insert(requests, req)
			return fixture.operation({statusCode = 200, headers = {},
				body = fixture.reader('{"total_count":1,"installations":[{"id":7,"account":{"login":"octo-org"}}]}')})
		end}
	end,
	run = function(github)
		local names = {}
		for name in github do if name ~= "help" then table.insert(names, name) end end
		assert(#names == 96, "wrong read-only surface for Connect with GitHub: " .. #names)
		assert(github.listNotifications == nil and github.createIssue == nil)
		local installations = github.listInstallations({per_page = 100})
		assert(requests[1].method == "GET" and requests[1].url == "https://api.github.com/user/installations?per_page=100")
		assert(requests[1].headers.Authorization == nil and installations.installations[1].account.login == "octo-org")
	end,
}
