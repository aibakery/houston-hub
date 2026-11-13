-- Every documented example runs as a real call against a permissive HubSpot mock; read-write
-- documents every operation. Each operation's examples come from its help record: indexes are tried
-- until the record has no more, so a new example cannot be skipped.
local function run(c)
	local names = {}
	for name in c do table.insert(names, name) end
	table.sort(names)
	local count = 0
	for _, name in names do
		local index = 1
		while true do
			local ok, err = pcall(fixture.example, name, index)
			if not ok then
				assert(index > 1 and string.find(tostring(err), "example index out of range", 1, true), name .. " example " .. index .. ": " .. tostring(err))
				break
			end
			count += 1
			index += 1
		end
	end
	assert(calls == count, "an example made no request, or more than one")
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
