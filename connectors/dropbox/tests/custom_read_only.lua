return {
	scenario = {config = {client_id = "fixture-app-key", client_secret = "fixture-private-secret"}, auth_method = "oauth", auth_config = {}, caller_access = "read-only"},
	config = {access = "custom", path_access = '{"/Reports":"read-only","/Incoming":"read-write"}'},
	configure = function()
		requests = {}
		http = {request = function(req)
			table.insert(requests, req)
			assert(req.url == "https://api.dropboxapi.com/2/files/get_metadata")
			local path = string.lower(json.decode(req.body).path)
			return fixture.operation({statusCode = 200, headers = {}, body = fixture.reader(json.encode({[".tag"] = "folder", path_lower = path, name = "folder", id = "id:" .. path}))})
		end}
	end,
	run = function(c)
		for _, name in {"upload", "createFolder", "move", "copy", "delete", "restore", "getCurrentAccount", "listSharedLinks", "listFileRequests"} do assert(c[name] == nil, "Read-only custom connection exposes " .. name) end
		assert(c.getMetadata({path = "/Incoming"}).path_lower == "/incoming", "Caller narrowing lost configured folder access")
		assert(not pcall(c.getMetadata, {path = "/Outside"}), "Caller narrowing widened custom access to the full account")
	end,
}
