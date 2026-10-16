return {
	scenario = {publisher = {client_id = "fixture-app-key", client_secret = "fixture-private-secret"}, auth_method = "oauth", auth_config = {}, caller_access = "read-write"},
	config = {access = "custom", path_access = '{"/Reports":"read-only","/Incoming":"read-write","/Incoming/Approved":"read-only","/Équipe":"read-write","/Incoming/k":"read-only"}'},
	configure = function()
		requests, responses, metadataOverride = {}, {}, nil
		fs = fixture.files()
		local native = houston
		local tokens, count = {}, 0
		houston = table.clone(native)
		houston.seal = function(value)
			count += 1
			local token = "protected:" .. tostring(count)
			tokens[token] = json.encode(value)
			return token
		end
		houston.unseal = function(token)
			assert(type(token) == "string" and tokens[token], "Invalid continuation token")
			return json.decode(tokens[token])
		end
		local folders = {["/reports"] = true, ["/incoming"] = true, ["/incoming/approved"] = true, ["/incoming/k"] = true, ["/équipe"] = true, ["/outside"] = true}
		local files = {["/reports/report.txt"] = true, ["/incoming/draft.txt"] = true, ["/incoming/approved/approved.txt"] = true,
			["/incoming/k/secret.txt"] = true, ["/équipe/café.txt"] = true, ["/outside/secret.txt"] = true}
		http = {request = function(req)
			table.insert(requests, req)
			local response
			if string.find(req.url, "files/get_metadata", 1, true) then
				local path = json.decode(req.body).path
				path = string.gsub(string.gsub(string.lower(path), "É", "é"), "K", "k")
				if metadataOverride then response = metadataOverride(path)
				elseif path == "rev:abcdef123" then response = {body = '{".tag":"file","path_lower":"/reports/report.txt","name":"report.txt","id":"id:report","size":6}'}
				elseif path == "rev:deadbeef123" then response = {body = '{".tag":"file","path_lower":"/outside/secret.txt","name":"secret.txt","id":"id:secret","size":6}'}
				elseif folders[path] or files[path] then response = {body = json.encode({[".tag"] = if folders[path] then "folder" else "file", path_lower = path, name = string.match(path, "[^/]+$"), id = "id:" .. path, size = if files[path] then 6 else nil})}
				else response = {status = 409, body = '{"error_summary":"path/not_found/.."}'} end
			else
				assert(#responses > 0, "Unexpected request: " .. req.url)
				response = table.remove(responses, 1)
			end
			return fixture.operation({statusCode = response.status or 200, headers = response.headers or {}, body = fixture.reader(response.body or "")})
		end}
	end,
	run = function(c)
		local makePolicy = require("lib/policy.lua")
		for _, raw in {"{", "{}", "[]", '["read-only"]', '{"/Reports":"write"}', '{"/Reports":true}', '{"relative":"read-only"}', '{"/Reports/":"read-only"}'} do
			assert(not pcall(makePolicy, raw, function() error("Invalid config reached Dropbox") end), "Accepted invalid folder policy " .. raw)
		end
		local aliases = makePolicy('{"/Reports":"read-write","/REPORTS":"read-only"}', function() return {[".tag"] = "folder", path_lower = "/reports"} end)
		assert(not pcall(aliases.prepare, "listFolder", {path = "/Reports"}), "Accepted conflicting case aliases")
		local missing = makePolicy('{"/Missing":"read-only"}', function() return nil end)
		assert(not pcall(missing.prepare, "listFolder", {path = "/Missing"}), "Accepted an unavailable policy root")
		local readOnly = makePolicy('{"/Reports":"read-only"}', function() error("Pure policy construction reached Dropbox") end)
		assert(not readOnly.writable, "All-read-only folder policy exports writes")
		local expected = {}
		for _, name in {"getMetadata", "statFile", "listFolder", "listFolderContinue", "listFolderGetLatestCursor", "search", "searchContinue", "listRevisions",
			"getTemporaryLink", "download", "downloadZip", "export", "getPreview", "getThumbnail", "createFolder", "upload", "move", "copy", "delete", "restore"} do
			expected[name] = true
			assert(type(c[name]) == "function", "Missing scoped operation " .. name)
		end
		for name in c do assert(expected[name], "Custom connection exposes " .. name) end
		local function reject(fn, args)
			assert(not pcall(fn, args), "Unsafe custom operation succeeded")
		end
		for _, fn in {c.getMetadata, c.delete, c.upload, c.createFolder} do
			local errors = {}
			for _, path in {"/Outside/secret.txt", "/Outside/missing.txt", "/Missing/child/file.txt"} do
				local ok, err = pcall(fn, {path = path, session_path = if fn == c.upload then "source.txt" else nil})
				assert(not ok)
				table.insert(errors, tostring(err))
			end
			assert(errors[1] == errors[2] and errors[1] == errors[3], "Folder denial revealed whether an outside path exists")
		end
		local revisionErrors = {}
		for _, rev in {"deadbeef123", "abcdef999"} do
			local ok, err = pcall(c.restore, {path = "/Incoming/new.txt", rev = rev})
			assert(not ok)
			table.insert(revisionErrors, tostring(err))
		end
		assert(revisionErrors[1] == revisionErrors[2], "Restore denial revealed whether an outside revision exists")
		local function mutations()
			local count = 0
			for _, req in requests do
				if not string.find(req.url, "files/get_metadata", 1, true) then count += 1 end
			end
			return count
		end
		local report = c.statFile("/REPORTS/report.txt")
		assert(report.name == "report.txt" and report.size == 6)
		assert(c.statFile("/Équipe/café.txt").name == "café.txt")
		for _, path in {"", "/", "/Outside/secret.txt", "/ReportsElsewhere/x", "id:secret", "ns:123/reports/report.txt", "rev:abcdef123", "/Incoming/../Outside/secret.txt", "/Incoming//draft.txt", "/Incoming /draft.txt", "/Incoming\\draft.txt"} do reject(c.getMetadata, {path = path}) end
		for _, path in {"/Reports/report.txt", "/Incoming/Approved/approved.txt", "/Incoming/K/secret.txt", "/Incoming", "/Outside/secret.txt"} do reject(c.delete, {path = path}) end
		reject(c.move, {from_path = "/Incoming", to_path = "/Équipe/archive"})
		reject(c.copy, {from_path = "/Reports", to_path = "/Incoming"})
		reject(c.move, {from_path = "/Reports/report.txt", to_path = "/Incoming/report.txt"})
		reject(c.upload, {path = "/Incoming/Approved/new.txt", session_path = "source.txt"})
		reject(c.createFolder, {path = "/Incoming/new/deep"})
		reject(c.createFolder, {path = "/Incoming/new", autorename = true})
		reject(c.listFolder, {path = "/Reports", shared_link = {url = "https://dropbox.test/shared"}})
		reject(c.search, {query = "secret"})
		reject(c.search, {query = "secret", options = {path = "/Outside"}})
		reject(c.search, {query = "secret", options = {path = "/Reports", account_id = "other"}})
		reject(c.download, {path = "/Reports/report.txt", rev = "deadbeef123", session_path = "bad.txt"})
		reject(c.listRevisions, {path = "/Reports/report.txt", mode = "id"})
		reject(c.restore, {path = "/Incoming/new.txt", rev = "deadbeef123"})
		reject(c.listFolderContinue, {cursor = "raw-dropbox-cursor"})
		assert(mutations() == 0, "Unsafe input reached a content or mutation endpoint")

		responses = {{body = '{"entries":[{".tag":"file","path_lower":"/reports/report.txt","id":"id:report","name":"report.txt","size":6}],"cursor":"provider-list-1","has_more":true}'}}
		local page = c.listFolder({path = "/Reports", recursive = true, include_deleted = true})
		assert(page.entries[1].name == "report.txt" and page.cursor ~= "provider-list-1")
		local listToken = page.cursor
		reject(c.listFolderContinue, {cursor = listToken .. "tampered"})
		reject(c.searchContinue, {cursor = listToken})
		responses = {{body = '{"entries":[],"cursor":"provider-list-2","has_more":false}'}}
		page = c.listFolderContinue({cursor = listToken})
		assert(json.decode(requests[#requests].body).cursor == "provider-list-1" and json.encode(page.entries) == "[]")
		responses = {{body = '{"entries":[{".tag":"file","path_lower":"/outside/secret.txt","name":"secret.txt"}],"cursor":"provider-list-3","has_more":false}'}}
		reject(c.listFolderContinue, {cursor = page.cursor})
		responses = {{body = '{"entries":[{".tag":"file","path_lower":"/incoming/draft.txt","name":"draft.txt"}],"cursor":"provider-list-3","has_more":false}'}}
		reject(c.listFolderContinue, {cursor = page.cursor})
		responses = {{body = '{"cursor":"latest-provider"}'}}
		local latest = c.listFolderGetLatestCursor({path = "/Reports"})
		assert(latest.cursor ~= "latest-provider")
		responses = {{body = '{"matches":[{"metadata":{".tag":"metadata","metadata":{".tag":"file","path_lower":"/reports/report.txt","name":"report.txt"}}}],"cursor":"search-provider","has_more":true}'}}
		local search = c.search({query = "report", options = {path = "/Reports"}})
		assert(search.cursor ~= "search-provider" and search.matches[1].metadata.metadata.name == "report.txt")
		responses = {{body = '{"matches":[],"has_more":false}'}}
		assert(c.searchContinue({cursor = search.cursor}).has_more == false)
		responses = {{body = '{"entries":[{".tag":"file","path_lower":"/reports/report.txt","rev":"abcdef123"}],"is_deleted":false,"has_more":false}'}}
		assert(c.listRevisions({path = "/Reports/report.txt"}).entries[1].rev == "abcdef123")

		local source = fs.open("source.txt", "w")
		source:write("source")
		await(source:close())
		responses = {{body = '{".tag":"file","path_lower":"/incoming/new.txt","name":"new.txt","id":"id:new","size":6}'}}
		assert(c.upload({path = "/Incoming/NEW.txt", session_path = "source.txt"}).name == "new.txt")
		assert(json.decode(requests[#requests].headers["Dropbox-API-Arg"][1]).path == "/incoming/NEW.txt")
		responses = {{body = '{"metadata":{".tag":"folder","path_lower":"/incoming/new","name":"new","id":"id:new"}}'}}
		assert(c.createFolder({path = "/Incoming/New"}).metadata.name == "new")
		for _, name in {"move", "copy"} do
			responses = {{body = '{"metadata":{".tag":"file","path_lower":"/équipe/draft.txt","name":"draft.txt","id":"id:draft","size":6}}'}}
			assert(c[name]({from_path = "/Incoming/draft.txt", to_path = "/Équipe/draft.txt"}).metadata.name == "draft.txt")
		end
		responses = {{body = '{"metadata":{".tag":"file","path_lower":"/incoming/draft.txt","name":"draft.txt","id":"id:draft","size":6}}'}}
		assert(c.delete({path = "/Incoming/draft.txt"}).metadata.name == "draft.txt")
		responses = {{body = '{".tag":"file","path_lower":"/incoming/restored.txt","name":"restored.txt","id":"id:restored","size":6}'}}
		assert(c.restore({path = "/Incoming/restored.txt", rev = "abcdef123"}).name == "restored.txt")
		responses = {{body = '{"metadata":{".tag":"file","path_lower":"/reports/report.txt","name":"report.txt"},"link":"https://dropbox.test/download"}'}}
		assert(c.getTemporaryLink({path = "/Reports/report.txt"}).link == "https://dropbox.test/download")
		for _, name in {"download", "getPreview", "getThumbnail"} do
			responses = {{headers = {["dropbox-api-result"] = {'{".tag":"file","path_lower":"/reports/report.txt","name":"report.txt"}'}}, body = "secret"}}
			assert(c[name]({path = "/Reports/report.txt", session_path = name .. ".txt"}).size == 6)
		end
		responses = {{headers = {["dropbox-api-result"] = {'{"metadata":{".tag":"folder","path_lower":"/reports","name":"Reports"}}'}}, body = "zip"}}
		assert(c.downloadZip({path = "/Reports", session_path = "reports.zip"}).size == 3)
		responses = {{headers = {["dropbox-api-result"] = {'{"file_metadata":{".tag":"file","path_lower":"/reports/report.txt","name":"report.txt"},"export_metadata":{"name":"report.md"}}'}}, body = "text"}}
		assert(c.export({path = "/Reports/report.txt", session_path = "report.md"}).size == 4)
		responses = {{headers = {["dropbox-api-result"] = {'{".tag":"file","path_lower":"/outside/secret.txt","name":"secret.txt"}'}}, body = "MUST NOT ESCAPE"}}
		reject(c.download, {path = "/Reports/report.txt", session_path = "refused.txt"})
		assert(await(fs.stat("refused.txt")).size == 0, "Unauthorized bytes escaped to the session filesystem")
		assert(#responses == 0)
	end,
}
