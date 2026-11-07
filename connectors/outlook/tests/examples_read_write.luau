-- Every documented example runs as a real call against a permissive Graph mock.
local function run(c)
	local file = fs.open("report.pdf", "w")
	file:write("%PDF")
	await(file:close())
	local names = {}
	for name in c do table.insert(names, name) end
	table.sort(names)
	for _, name in names do fixture.example(name) end
	for _, name in {"listMessages", "getMessage"} do fixture.example(name, 2) end
	assert(calls >= #names + 2, "an example made no request")
end
return {
	scenario = {publisher = {client_id = "fixture-client", client_secret = "fixture-private-secret"}, config = {}, auth_method = "oauth", auth_config = {}},
	config = {access = "read-write"},
	configure = function()
		calls = 0
		fs = fixture.files()
		http = {request = function(req)
			calls += 1
			assert(string.find(req.url, "https://graph.microsoft.com/v1.0/me", 1, true) == 1, req.url)
			return fixture.operation({statusCode = 200, headers = {}, body = fixture.reader('{"id":"x","name":"x","isDraft":true,"value":[]}')})
		end}
	end,
	run = run,
}
