return {
	scenario = {publisher = {client_id = "fixture-client", client_secret = "fixture-private-secret"}, config = {}, auth_method = "oauth", auth_config = {}},
	config = {access = "read-write"},
	configure = function()
		requests, responses = {}, {}
		fs = fixture.files()
		http = {request = function(req)
			table.insert(requests, req)
			if req.body ~= nil and type(req.body) ~= "string" then req.body = await(req.body:readAll()) end
			assert(#responses > 0, "unexpected request: " .. req.url)
			local response = table.remove(responses, 1)
			return fixture.operation({statusCode = response.status or 200, headers = response.headers or {}, body = fixture.reader(response.body or "")})
		end}
	end,
	run = function(c)
		local API = "https://www.googleapis.com/drive/v3"
		responses = {{body = '{"files":[{"id":"f1"}],"nextPageToken":"next+1"}'}, {body = '{"files":[]}'}}
		local page = c.listFiles({q = "name contains 'a b'", pageToken = "start+1"})
		assert(page.nextPageToken == "next+1" and page.files[1].id == "f1")
		local url = requests[1].url
		assert(string.sub(url, 1, #API + 7) == API .. "/files?" and string.find(url, "q=name%20contains%20%27a%20b%27", 1, true) and string.find(url, "pageToken=start%2B1", 1, true), url)
		assert(string.find(url, "supportsAllDrives=true", 1, true) and string.find(url, "includeItemsFromAllDrives=true", 1, true) and string.find(url, "fields=nextPageToken%2CincompleteSearch%2Cfiles%28id%2Cname", 1, true), url)
		c.listFiles({fields = "files(id)", includeItemsFromAllDrives = false})
		assert(string.find(requests[2].url, "fields=files%28id%29", 1, true) and string.find(requests[2].url, "includeItemsFromAllDrives=false", 1, true), requests[2].url)

		assert(not pcall(c.statFile, ""))
		assert(not pcall(c.statFile, 42))
		assert(not pcall(c.statFile, "file", "extra"))
		assert(not pcall(c.statFile))
		assert(#requests == 2, "bad arguments reached Google")
		responses = {{body = '{"id":"f1","name":"Report","mimeType":"text/plain","size":"42"}'}, {body = '{"id":"dir","name":"Folder","mimeType":"application/vnd.google-apps.folder"}'}}
		local file = c.statFile("f1")
		assert(file.id == "f1" and file.name == "Report" and file.size == 42 and file.isFolder == false)
		assert(requests[3].url == API .. "/files/f1?fields=id%2Cname%2CmimeType%2Csize&supportsAllDrives=true", requests[3].url)
		local folder = c.statFile("dir")
		assert(folder.isFolder and folder.size == nil)
		for _, size in {'"-1"', '"0.5"', '"9007199254740992"', '"big"'} do
			responses = {{body = '{"id":"bad","name":"Bad","size":' .. size .. '}'}}
			assert(not pcall(c.statFile, "bad"), "accepted size " .. size)
		end

		local bytes = string.char(0, 255, 13, 10) .. "binary payload"
		responses = {{body = bytes}, {body = "# Notes"}}
		local saved = c.downloadFile({fileId = "f:1", path = "downloads/report.bin"})
		assert(requests[#requests].url == API .. "/files/f%3A1?alt=media&supportsAllDrives=true", requests[#requests].url)
		assert(saved.path == "downloads/report.bin" and saved.url == "https://houston.test/downloads/report.bin" and saved.size == #bytes)
		local fd = fs.open("downloads/report.bin", "r")
		assert(await(fd:readAll()) == bytes)
		await(fd:close())
		local exported = c.exportFile({fileId = "doc", mimeType = "text/markdown", path = "notes.md"})
		assert(requests[#requests].url == API .. "/files/doc/export?mimeType=text%2Fmarkdown" and exported.size == 7)
		responses = {{status = 403, body = '{"error":{"code":403,"message":"Only files with binary content can be downloaded.","errors":[{"reason":"fileNotDownloadable"}]}}'}}
		local ok, err = pcall(c.downloadFile, {fileId = "doc", path = "doc.bin"})
		assert(not ok and string.find(tostring(err), "fileNotDownloadable", 1, true), tostring(err))
		assert(not pcall(c.downloadFile, {fileId = "f1"}), "download requires a path")
		local sent = #requests
		for _, id in {"f/1", "..", "f%2F1", "f\\1", "f\t1"} do
			local rejected, problem = pcall(c.downloadFile, {fileId = id, path = "x.bin"})
			assert(not rejected and problem.code == "invalid_argument" and string.find(problem.message, "fileId must be one", 1, true))
			assert(not pcall(c.statFile, id))
		end
		assert(#requests == sent, "invalid IDs must not reach the network")

		local upload = fs.open("uploads/report.pdf", "w")
		upload:write(bytes)
		await(upload:close())
		local session = "https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable&upload_id=xyz"
		responses = {{headers = {location = {session}}}, {body = '{"id":"up","name":"report.pdf"}'}}
		local created = c.uploadFile({path = "uploads/report.pdf", parents = {"dir"}, contentType = "application/pdf"})
		assert(created.id == "up")
		local start, put = requests[#requests - 1], requests[#requests]
		assert(start.method == "POST" and string.find(start.url, "https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable&supportsAllDrives=true&fields=", 1, true) == 1, start.url)
		assert(start.headers["X-Upload-Content-Type"][1] == "application/pdf")
		local metadata = json.decode(start.body)
		assert(metadata.name == "report.pdf" and metadata.parents[1] == "dir" and metadata.path == nil and metadata.contentType == nil)
		assert(put.method == "PUT" and put.url == session and put.body == bytes and put.headers["Content-Type"][1] == "application/pdf")
		responses = {{headers = {location = {session}}}, {body = '{"id":"up"}'}}
		c.uploadFile({path = "uploads/report.pdf", fileId = "up"})
		start = requests[#requests - 1]
		assert(start.method == "PATCH" and string.find(start.url, "/upload/drive/v3/files/up?", 1, true) and start.body == "{}", start.body)
		responses = {{}}
		assert(not pcall(c.uploadFile, {path = "uploads/report.pdf"}), "upload without a session URL")

		responses = {{body = '{"id":"moved"}'}, {status = 204}}
		c.updateFile({fileId = "f1", addParents = "dir", name = "Renamed"})
		local update = requests[#requests]
		assert(update.method == "PATCH" and string.find(update.url, API .. "/files/f1?addParents=dir", 1, true) and json.decode(update.body).name == "Renamed")
		assert(c.deletePermission({fileId = "f1", permissionId = "p1"}).success)
		assert(requests[#requests].url == API .. "/files/f1/permissions/p1?supportsAllDrives=true")
		assert(#responses == 0)
	end,
}
