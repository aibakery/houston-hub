-- Every documented example runs as a real call against a permissive lemlist mock; Write access
-- documents every operation.
return {
	scenario = {publisher = {}, config = {}, access = {data = "write"}, auth_method = "api_key", auth_config = {token = "lemlist_fixture_key"}},
	configure = function()
		calls = 0
		http = {request = function(req)
			calls += 1
			assert(string.find(req.url, "https://api.lemlist.com/api/", 1, true) == 1, req.url)
			assert(req.headers.Authorization == nil, "the proxy injects the key")
			return fixture.operation({statusCode = 200, headers = {}, body = fixture.reader("{}")})
		end}
	end,
	run = function(lemlist)
		local names = {}
		for name in lemlist do table.insert(names, name) end
		table.sort(names)
		assert(#names == 182, "wrong surface: " .. #names)
		for _, name in names do
			local before = calls
			local ok, err = pcall(fixture.example, name)
			assert(ok, name .. ": " .. tostring(err))
			assert(calls == before + 1, name .. " example made " .. (calls - before) .. " requests")
		end
	end,
}
