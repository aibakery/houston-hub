return {
	scenario = {publisher = {client_id = "fixture-client", client_secret = "fixture-private-secret"}, config = {}, auth_method = "oauth", auth_config = {}},
	config = {access = "read-write"},
	configure = function()
		requests, responses = {}, {}
		fs = fixture.files()
		http = {request = function(req)
			assert(req.headers == nil or req.headers.Authorization == nil, "the proxy injects Authorization")
			table.insert(requests, req)
			if req.body ~= nil and type(req.body) ~= "string" then req.body = await(req.body:readAll()) end
			assert(#responses > 0, "unexpected request: " .. req.url)
			local response = table.remove(responses, 1)
			return fixture.operation({statusCode = response.status or 200, headers = response.headers or {}, body = fixture.reader(response.body or "")})
		end}
	end,
	run = function(c)
		local API = "https://graph.microsoft.com/v1.0/me"
		local names = {}
		for name in c do table.insert(names, name) end
		table.sort(names)
		assert(table.concat(names, ",") == "copyItem,createFolder,createLink,deleteItem,deletePermission,downloadFile,getDrive,getItem,invite,listChildren,listPermissions,searchItems,statFile,updateItem,uploadFile", "read-write got " .. table.concat(names, ","))

		local bytes = string.char(0, 255) .. "quarterly figures"
		local file = fs.open("uploads/report.pdf", "w")
		file:write(bytes)
		await(file:close())
		local function last() return requests[#requests] end

		-- New files go to a folder by name; an existing name gets a numbered copy unless told otherwise.
		responses = {{status = 201, body = '{"id":"up","name":"report.pdf","@microsoft.graph.downloadUrl":"https://x.files.1drv.com/y"}'}}
		local created = c.uploadFile({path = "uploads/report.pdf", contentType = "application/pdf"})
		assert(created.id == "up" and created["@microsoft.graph.downloadUrl"] == nil)
		assert(last().method == "PUT" and last().url == API .. "/drive/root:/report.pdf:/content?@microsoft.graph.conflictBehavior=rename", last().url)
		assert(last().body == bytes and last().headers["Content-Type"][1] == "application/pdf")
		responses = {{status = 201, body = '{"id":"up2"}'}, {body = '{"id":"F1"}'}}
		c.uploadFile({path = "uploads/report.pdf", parentId = "D4648F06C91D9D3D!101", name = "Q3 plan.pdf", conflictBehavior = "replace"})
		assert(last().url == API .. "/drive/items/D4648F06C91D9D3D%21101:/Q3%20plan.pdf:/content?@microsoft.graph.conflictBehavior=replace", last().url)
		assert(last().headers["Content-Type"][1] == "application/octet-stream")
		c.uploadFile({path = "uploads/report.pdf", itemId = "F1"})
		assert(last().method == "PUT" and last().url == API .. "/drive/items/F1/content", last().url)

		responses = {{status = 201, body = '{"id":"dir","folder":{"childCount":0}}'}, {status = 201, body = '{"id":"sub"}'}}
		c.createFolder({name = "Reports"})
		assert(last().method == "POST" and last().url == API .. "/drive/root/children", last().url)
		local body = json.decode(last().body)
		assert(body.name == "Reports" and body["@microsoft.graph.conflictBehavior"] == "fail" and string.find(last().body, '"folder":{}', 1, true), last().body)
		c.createFolder({name = "2026", parentId = "dir", conflictBehavior = "rename"})
		assert(last().url == API .. "/drive/items/dir/children" and json.decode(last().body)["@microsoft.graph.conflictBehavior"] == "rename")

		responses = {{body = '{"id":"F1","name":"Renamed.pdf"}'}, {status = 202, headers = {location = {"https://api.onedrive.com/monitor/abc"}}}, {status = 204}}
		assert(c.updateItem({itemId = "F1", name = "Renamed.pdf", parentReference = {id = "dir"}}).name == "Renamed.pdf")
		assert(last().method == "PATCH" and string.find(last().url, API .. "/drive/items/F1?$select=id%2Cname", 1, true) == 1, last().url)
		body = json.decode(last().body)
		assert(body.name == "Renamed.pdf" and body.parentReference.id == "dir" and body.itemId == nil and body.select == nil)
		assert(c.copyItem({itemId = "F1", parentReference = {driveId = "d1", id = "dir"}, name = "Copy.pdf"}).success)
		assert(last().method == "POST" and last().url == API .. "/drive/items/F1/copy" and json.decode(last().body).name == "Copy.pdf" and json.decode(last().body).parentReference.driveId == "d1")
		assert(c.deleteItem({itemId = "F1"}).success)
		assert(last().method == "DELETE" and last().url == API .. "/drive/items/F1" and last().body == nil)

		responses = {{status = 201, body = '{"id":"p1","link":{"webUrl":"https://1drv.ms/x"}}'}, {body = '{"value":[{"id":"p2"}]}'}, {status = 204}}
		assert(c.createLink({itemId = "F1", type = "view", scope = "anonymous"}).link.webUrl == "https://1drv.ms/x")
		assert(last().url == API .. "/drive/items/F1/createLink" and json.decode(last().body).scope == "anonymous")
		c.invite({itemId = "F1", recipients = {{email = "ana@example.com"}}, roles = {"read"}, sendInvitation = false})
		body = json.decode(last().body)
		assert(last().url == API .. "/drive/items/F1/invite" and body.recipients[1].email == "ana@example.com" and body.sendInvitation == false)
		assert(c.deletePermission({itemId = "F1", permissionId = "p1"}).success)
		assert(last().method == "DELETE" and last().url == API .. "/drive/items/F1/permissions/p1")

		-- Invalid writes never reach Graph.
		local sent = #requests
		for _, call in {
			function() return c.uploadFile({path = "uploads/report.pdf", conflictBehavior = "overwrite"}) end,
			function() return c.uploadFile({path = "uploads/report.pdf", itemId = "F1", name = "x.pdf"}) end,
			function() return c.uploadFile({path = "uploads/report.pdf", parentId = "a/b"}) end,
			function() return c.uploadFile({path = "uploads/report.pdf", name = ".."}) end,
			function() return c.uploadFile({path = "uploads/report.pdf", name = "a:b.pdf"}) end,
			function() return c.uploadFile({path = "uploads/report.pdf", description = "x"}) end,
			function() return c.uploadFile({path = "uploads/missing.pdf"}) end,
			function() return c.uploadFile({}) end,
			function() return c.createFolder({}) end,
			function() return c.createFolder({name = "x", conflictBehavior = "merge"}) end,
			function() return c.updateItem({itemId = "../root"}) end,
			function() return c.deletePermission({itemId = "F1"}) end,
		} do assert(not pcall(call)) end
		assert(#requests == sent, "invalid writes reached Graph")

		-- A failed write reports Graph's error without retrying.
		responses = {{status = 409, body = '{"error":{"code":"nameAlreadyExists","message":"Name already exists"}}'}}
		local ok, err = pcall(c.createFolder, {name = "Reports"})
		assert(not ok and string.find(tostring(err), "Microsoft Graph HTTP 409 (nameAlreadyExists)", 1, true) and string.find(tostring(err), '"retryable":false', 1, true), tostring(err))
		assert(#requests == sent + 1 and #responses == 0)
	end,
}
