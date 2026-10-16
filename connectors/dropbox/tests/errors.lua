return {
	scenario = {config = {client_id = "fixture-app-key", client_secret = "fixture-private-secret"}, auth_method = "oauth", auth_config = {}},
	config = {access = "read-write"},
	configure = function()
		requests, responses = {}, {}
		fs = fixture.files()
		http = {request = function(req)
			table.insert(requests, req)
			for name in req.headers or {} do assert(string.lower(name) ~= "authorization", "credentials belong to the proxy") end
			if req.body ~= nil and type(req.body) ~= "string" then
				local source = req.body
				assert(await(source:readAll()) == "upload")
				await(source:close())
			end
			assert(#responses > 0, "unexpected request: " .. req.url)
			local response = table.remove(responses, 1)
			return fixture.operation({statusCode = response.status or 200, headers = {}, body = fixture.reader(response.body)})
		end}
	end,
	run = function(c)
		-- Error snippets stay bounded even when the upstream response exceeds readAll's limit.
		responses = {{status = 503, body = "service unavailable: " .. string.rep("x", 8 * 1024 * 1024) .. "UNREAD_TAIL"}}
		local ok, err = pcall(c.getMetadata, {path = "/report"})
		local message = tostring(err)
		assert(not ok and string.find(message, "Dropbox HTTP 503: service unavailable:", 1, true), message)
		assert(string.find(message, '"retryable":true', 1, true) and string.find(message, '"upstream_status":503', 1, true), message)
		assert(#message < 1500 and not string.find(message, "UNREAD_TAIL", 1, true), "upstream error body was not bounded")

		local input = fs.open("upload.txt", "w")
		input:write("upload")
		await(input:close())
		-- Ordinary RPC and upload results must contain structured JSON, never a fabricated success.
		for _, body in {"", " \n\t", "null", "42", "true", '"ok"'} do
			for _, name in {"getMetadata", "upload"} do
				responses = {{body = body}}
				local args = if name == "upload" then {path = "/upload.txt", session_path = "upload.txt"} else {path = "/report"}
				ok, err = pcall(c[name], args)
				message = tostring(err)
				assert(not ok and string.find(message, "Dropbox returned invalid JSON", 1, true), name .. " accepted " .. body .. ": " .. message)
				assert(string.find(message, '"retryable":false', 1, true) and string.find(message, '"upstream_status":200', 1, true), message)
			end
		end

		-- Only these documented void-result routes turn JSON null into a success object.
		for name, args in {
			revokeSharedLink = {url = "https://www.dropbox.com/s/abc/report.txt"},
			addFolderMember = {shared_folder_id = "123", members = {{member = {[".tag"] = "email", email = "ada@example.com"}, access_level = "viewer"}}},
			unmountFolder = {shared_folder_id = "123"},
			unshareFile = {file = "id:report"},
			relinquishFileMembership = {file = "id:report"},
		} do
			responses = {{body = " \nnull\t "}}
			assert(c[name](args).success == true, name .. " rejected its null result")
			responses = {{body = ""}}
			assert(not pcall(c[name], args), name .. " accepted a missing result")
		end
		assert(#responses == 0)
	end,
}
