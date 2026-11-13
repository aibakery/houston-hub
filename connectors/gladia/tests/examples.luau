-- Every documented example runs as a real call against a permissive Gladia mock.
return {
	scenario = {publisher = {}, config = {}, auth_method = "api_key", auth_config = {token = "gladia-fixture-key"}},
	config = {access = "read-write"},
	configure = function()
		calls = 0
		fs = fixture.files()
		local multipart = http.multipart
		http = {multipart = multipart, request = function(req)
			calls += 1
			if req.body ~= nil and type(req.body) ~= "string" then await(req.body:readAll()) end
			assert(string.match(req.url, "^https://api%.gladia%.io/v2/") ~= nil, req.url)
			return fixture.operation({statusCode = 200, headers = {}, body = fixture.reader(
				'{"id":"45463597-20b7-4af7-b3b3-f5fb778203ab","status":"done","items":[],"audio_url":"https://api.gladia.io/file/1","result_url":"https://api.gladia.io/v2/transcription/45463597-20b7-4af7-b3b3-f5fb778203ab"}')})
		end}
	end,
	run = function(c)
		local file = fs.open("meeting.m4a", "w")
		file:write("fake-m4a-bytes")
		await(file:close())
		local names = {}
		for name in c do if name ~= "help" then table.insert(names, name) end end
		table.sort(names)
		for _, name in names do fixture.example(name) end
		assert(calls == #names, "an example made no request")
	end,
}
