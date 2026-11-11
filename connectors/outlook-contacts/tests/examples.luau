-- Every documented example runs as a real call against a permissive Graph mock; read-write documents
-- every operation.
local function run(c)
	local names = {}
	for name in c do table.insert(names, name) end
	table.sort(names)
	for _, name in names do fixture.example(name) end
	local second = {"listContactFolders", "listContacts", "getContact", "createContact", "createContactFolder"}
	for _, name in second do fixture.example(name, 2) end
	assert(calls == #names + #second, "an example made no request, or more than one")
end
local function configure()
	calls = 0
	http = {request = function(req)
		calls += 1
		assert(string.find(req.url, "https://graph.microsoft.com/v1.0/me/", 1, true) == 1, req.url)
		return fixture.operation({statusCode = 200, headers = {}, body = fixture.reader('{"id":"x","value":[]}')})
	end}
end
local scenario = {publisher = {client_id = "fixture-client", client_secret = "fixture-private-secret"}, config = {}, auth_method = "oauth", auth_config = {}}
return {scenario = scenario, config = {access = "read-write"}, configure = configure, run = run}
