return {
	scenario = {config = {client_id = "fixture-app-key", client_secret = "fixture-private-secret"}, auth_method = "oauth", auth_config = {}},
	config = {access = "read-write"},
	configure = function()
		requests, responses = {}, {}
		fs = fixture.files()
		local stat = fs.stat
		fs.stat = function(path)
			if path == "oversized.bin" then return fixture.operation({isFile = true, size = 150 * 1024 * 1024 + 1}) end
			return stat(path)
		end
		http = {request = function(req)
			table.insert(requests, req)
			assert(#responses > 0, "unexpected request: " .. req.url)
			local body = table.remove(responses, 1)
			return fixture.operation({statusCode = 200, headers = {["dropbox-api-result"] = {'{"id":"id:large","name":"large.bin"}'}}, body = body})
		end}
	end,
	run = function(c)
		-- A file larger than readAll's default limit must flow through native Reader/File streaming.
		local size = 8 * 1024 * 1024 + 17
		responses = {fixture.reader(string.rep("d", size))}
		local saved = c.download({path = "/large.bin", session_path = "large.bin"})
		assert(saved.size == size and saved.result.id == "id:large")
		assert(requests[1].url == "https://content.dropboxapi.com/2/files/download")
		local file = fs.open("large.bin", "r")
		local total = 0
		while true do
			local chunk = await(file:read(1024 * 1024))
			if chunk.done then break end
			assert(chunk.data == string.rep("d", #chunk.data), "downloaded bytes changed")
			total += #chunk.data
		end
		await(file:close())
		assert(total == size)

		local before = #requests
		local ok, err = pcall(c.upload, {path = "/oversized.bin", session_path = "oversized.bin"})
		assert(not ok and string.find(tostring(err), "at most 150 MiB", 1, true), tostring(err))
		assert(#requests == before, "oversized upload reached Dropbox")

		-- A native source failure surfaces at final close rather than returning a download URL.
		responses = {compression.gunzip(fixture.reader("not a gzip stream"))}
		ok, err = pcall(c.download, {path = "/broken.bin", session_path = "broken.bin"})
		assert(not ok, "a failed stream returned a successful download")
		assert(#requests == before + 1 and #responses == 0)
	end,
}
