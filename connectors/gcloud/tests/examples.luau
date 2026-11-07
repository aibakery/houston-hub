-- Every documented example runs as a real call against a permissive Google mock.
return {
	scenario = {publisher = {client_id = "fixture-client", client_secret = "fixture-private-secret"}, config = {}, auth_method = "oauth", auth_config = {}},
	config = {access = "read-write"},
	configure = function()
		calls = 0
		fs = fixture.files()
		http = {request = function(req)
			calls += 1
			assert(string.match(req.url, "^https://[a-z]+%.googleapis%.com/"), req.url)
			return fixture.operation({statusCode = 200, headers = {}, body = fixture.reader('{"name":"x","template":{"containers":[{"image":"old"}]}}')})
		end}
	end,
	run = function(c)
		local file = fs.open("report.csv", "w")
		file:write("a,b\n")
		await(file:close())
		local names = {}
		for name in c do table.insert(names, name) end
		table.sort(names)
		for _, name in names do fixture.example(name) end
		-- updateRunServiceImage reads the service before patching it.
		assert(calls == #names + 1, "an example made no request")
	end,
}
