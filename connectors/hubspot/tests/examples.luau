-- Every documented example runs as a real call against a permissive HubSpot mock; read-write
-- documents every operation.
local MORE = {listObjects = 2, getObject = 2, searchObjects = 3, listOwners = 2, createObject = 3, updateObject = 3}
local function run(c)
	local names = {}
	for name in c do table.insert(names, name) end
	table.sort(names)
	local count = 0
	for _, name in names do
		for index = 1, MORE[name] or 1 do
			fixture.example(name, index)
			count += 1
		end
	end
	assert(#names == 18 and calls == count, "an example made no request, or more than one")
end
local function configure()
	calls = 0
	http = {request = function(req)
		calls += 1
		assert(string.find(req.url, "https://api.hubapi.com/crm/", 1, true) == 1, req.url)
		return fixture.operation({statusCode = 200, headers = {}, body = fixture.reader('{"id":"1","results":[],"total":0}')})
	end}
end
local scenario = {publisher = {client_id = "fixture-client", client_secret = "fixture-private-secret"}, config = {}, auth_method = "oauth", auth_config = {}}
return {scenario = scenario, config = {access = "read-write"}, configure = configure, run = run}
