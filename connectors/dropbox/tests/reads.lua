return {
	scenario = {config = {client_id = "fixture-app-key", client_secret = "fixture-private-secret"}, auth_method = "oauth", auth_config = {}},
	config = {access = "read-only"},
	configure = function()
		requests, responses = {}, {}
		fs = fixture.files()
		http = {request = function(req)
			table.insert(requests, req)
			assert(#responses > 0, "unexpected request: " .. req.url)
			local response = table.remove(responses, 1)
			return fixture.operation({statusCode = response.status or 200, headers = response.headers or {}, body = fixture.reader(response.body or "")})
		end}
	end,
	run = function(c)
		local API = "https://api.dropboxapi.com/2/"

		-- RPC routes POST the options as JSON and return Dropbox's JSON unchanged.
		responses = {{body = '{"entries":[{".tag":"file","name":"a.txt","id":"id:a"}],"cursor":"c1","has_more":true}'}, {body = '{"entries":[],"cursor":"c2","has_more":false}'}}
		local page = c.listFolder({path = "", recursive = true})
		local req = requests[1]
		assert(req.method == "POST" and req.url == API .. "files/list_folder" and req.headers["Content-Type"][1] == "application/json")
		local sent = json.decode(req.body)
		assert(sent.path == "" and sent.recursive == true)
		assert(page.entries[1].id == "id:a" and page.entries[1][".tag"] == "file" and page.cursor == "c1")
		local last = c.listFolderContinue({cursor = "c1"})
		assert(requests[2].url == API .. "files/list_folder/continue" and json.decode(requests[2].body).cursor == "c1")
		assert(json.encode(last.entries) == "[]", "empty entries must stay an array")

		-- Routes without arguments send no body.
		responses = {{body = '{"account_id":"dbid:1","email":"ada@example.com"}'}}
		assert(c.getCurrentAccount().email == "ada@example.com")
		assert(requests[3].url == API .. "users/get_current_account" and requests[3].body == nil and requests[3].headers == nil)
		assert(not pcall(c.getCurrentAccount, {extra = true}))
		assert(not pcall(c.listFolder, "/path"), "options must be a table")
		assert(#requests == 3, "invalid options reached Dropbox")

		-- Errors carry Dropbox's summary, user message and retry hint.
		responses = {
			{status = 409, body = '{"error_summary":"path/not_found/..","error":{".tag":"path","path":{".tag":"not_found"}},"user_message":{"text":"Nothing here","locale":"en"}}'},
			{status = 400, body = 'Error in call to API function "files/list_folder": request body: path: Specify the root folder as an empty string rather than as "/".'},
			{status = 429, headers = {["retry-after"] = {"7"}}, body = '{"error_summary":"too_many_requests/..","error":{"reason":{".tag":"too_many_requests"},"retry_after":7}}'},
		}
		local ok, err = pcall(c.getMetadata, {path = "/missing"})
		assert(not ok and string.find(tostring(err), "Dropbox HTTP 409: path/not_found/.. (Nothing here)", 1, true), tostring(err))
		assert(string.find(tostring(err), '"retryable":false', 1, true) and string.find(tostring(err), '"upstream_status":409', 1, true), tostring(err))
		ok, err = pcall(c.listFolder, {path = "/"})
		assert(not ok and string.find(tostring(err), "Specify the root folder", 1, true), tostring(err))
		ok, err = pcall(c.search, {query = "report"})
		assert(not ok and string.find(tostring(err), "too_many_requests", 1, true) and string.find(tostring(err), "Retry-After: 7", 1, true), tostring(err))
		assert(string.find(tostring(err), '"retryable":true', 1, true), tostring(err))
		responses = {{body = "<html>"}}
		assert(not pcall(c.getMetadata, {path = "/a"}), "accepted invalid JSON")

		-- statFile keeps the shared storage contract.
		assert(not pcall(c.statFile, ""))
		assert(not pcall(c.statFile, 42))
		assert(not pcall(c.statFile, "id:a", "extra"))
		assert(not pcall(c.statFile))
		local before = #requests
		responses = {{body = '{".tag":"file","id":"id:a","name":"a.txt","size":42}'}, {body = '{".tag":"folder","id":"id:d","name":"Docs"}'}}
		local file = c.statFile("id:a")
		assert(#requests == before + 1 and requests[#requests].url == API .. "files/get_metadata" and json.decode(requests[#requests].body).path == "id:a")
		assert(file.id == "id:a" and file.name == "a.txt" and file.size == 42 and file.isFolder == false)
		local folder = c.statFile("/Docs")
		assert(folder.isFolder and folder.size == nil)
		for _, size in {',"size":-1', ',"size":0.5', ',"size":9007199254740992', ',"size":"42"', ""} do
			responses = {{body = '{".tag":"file","id":"id:b","name":"b"' .. size .. '}'}}
			assert(not pcall(c.statFile, "id:b"), "accepted size " .. size)
		end

		-- Downloads stream to the session path; arguments travel in a header-safe Dropbox-API-Arg.
		local bytes = string.char(0, 255, 13, 10) .. "binary payload"
		responses = {{headers = {["dropbox-api-result"] = {'{"name":"Caf\\u00e9.txt","id":"id:c","size":18}'}}, body = bytes}}
		local saved = c.download({path = "/Café/😀\127.txt", session_path = "downloads/cafe.txt"})
		req = requests[#requests]
		assert(req.method == "POST" and req.url == "https://content.dropboxapi.com/2/files/download" and req.body == nil and req.headers["Content-Type"] == nil)
		local arg = req.headers["Dropbox-API-Arg"][1]
		assert(not string.find(arg, "[\127-\255]"), "Dropbox-API-Arg must be ASCII: " .. arg)
		assert(string.find(arg, "\\u00e9", 1, true) and string.find(string.lower(arg), "\\ud83d\\ude00\\u007f", 1, true), arg)
		local decoded = json.decode(arg)
		assert(decoded.path == "/Café/😀\127.txt" and decoded.session_path == nil)
		assert(saved.session_path == "downloads/cafe.txt" and saved.url == "https://houston.test/downloads/cafe.txt" and saved.size == #bytes)
		assert(saved.result.name == "Café.txt" and saved.result.id == "id:c")
		local fd = fs.open("downloads/cafe.txt", "r")
		assert(await(fd:readAll()) == bytes)
		await(fd:close())

		responses = {{headers = {["dropbox-api-result"] = {'{"export_metadata":{"name":"Notes.md"}}'}}, body = "# Notes"}}
		local exported = c.export({path = "/Notes.paper", export_format = "markdown", session_path = "notes.md"})
		assert(requests[#requests].url == "https://content.dropboxapi.com/2/files/export" and exported.size == 7 and exported.result.export_metadata.name == "Notes.md")
		responses = {{body = "no metadata"}}
		assert(not pcall(c.download, {path = "/a", session_path = "a"}), "accepted a download without Dropbox-API-Result")
		responses = {{status = 409, body = '{"error_summary":"path/not_file/.."}'}}
		ok, err = pcall(c.download, {path = "/Docs", session_path = "docs"})
		assert(not ok and string.find(tostring(err), "path/not_file", 1, true), tostring(err))
		-- The session file system refuses the path before anything reaches Dropbox.
		before = #requests
		ok, err = pcall(c.download, {path = "/a", session_path = "../outside"})
		assert(not ok and type(err) == "table" and err.code == "permission_denied", "accepted a session path outside the session")
		assert(#requests == before, "a refused session path reached Dropbox")
		assert(not pcall(c.download, {path = "/a"}), "download requires a session_path")
		assert(#requests == before)
		assert(#responses == 0)
	end,
}
