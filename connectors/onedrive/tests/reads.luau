return {
	scenario = {publisher = {client_id = "fixture-client", client_secret = "fixture-private-secret"}, config = {}, auth_method = "oauth", auth_config = {}},
	config = {access = "read-only"},
	configure = function()
		requests, responses = {}, {}
		fs = fixture.files()
		http = {request = function(req)
			assert(req.headers == nil or req.headers.Authorization == nil, "the proxy injects Authorization")
			table.insert(requests, req)
			assert(#responses > 0, "unexpected request: " .. req.url)
			local response = table.remove(responses, 1)
			return fixture.operation({statusCode = response.status or 200, headers = response.headers or {}, body = fixture.reader(response.body or "")})
		end}
	end,
	run = function(c)
		local function fails(expected: {string}, fn: (...any) -> any, ...: any)
			local ok, err = pcall(fn, ...)
			assert(not ok, "call succeeded")
			for _, text in expected do assert(string.find(tostring(err), text, 1, true), "missing " .. text .. " in " .. tostring(err)) end
		end
		local API = "https://graph.microsoft.com/v1.0/me"
		local SELECT = "$select=id%2Cname%2Csize%2Cfile%2Cfolder%2Cpackage%2CparentReference%2CcreatedDateTime%2ClastModifiedDateTime%2CwebUrl"
		local names = {}
		for name in c do table.insert(names, name) end
		table.sort(names)
		assert(table.concat(names, ",") == "downloadFile,getDrive,getItem,listChildren,listPermissions,searchItems,statFile", "read-only got " .. table.concat(names, ","))

		responses = {{body = '{"id":"d1","driveType":"personal"}'}}
		assert(c.getDrive().driveType == "personal")
		assert(requests[1].url == API .. "/drive" and requests[1].method == "GET", requests[1].url)

		-- Lists keep Graph's page, drop preauthenticated links and always carry a value array.
		local next = "https://graph.microsoft.com/v1.0/me/drive/root/children?$skiptoken=MjAx"
		responses = {
			{body = '{"value":[{"id":"f1","name":"a.txt","@microsoft.graph.downloadUrl":"https://contoso-my.sharepoint.com/download.aspx?tempauth=secret"}],"@odata.nextLink":"' .. next .. '"}'},
			{body = '{"value":[]}'}, {body = '{}'},
		}
		local page = c.listChildren()
		assert(requests[2].url == API .. "/drive/root/children?" .. SELECT, requests[2].url)
		assert(page.value[1].id == "f1" and page.value[1]["@microsoft.graph.downloadUrl"] == nil and page["@odata.nextLink"] == next)
		local last = c.listChildren({nextLink = next})
		assert(requests[3].url == next and #last.value == 0)
		local empty = c.listChildren({itemId = "D4648F06C91D9D3D!54927", top = 50, orderby = "name"})
		assert(requests[4].url == API .. "/drive/items/D4648F06C91D9D3D%2154927/children?" .. SELECT .. "&$top=50&$orderby=name", requests[4].url)
		assert(type(empty.value) == "table" and #empty.value == 0 and json.encode(empty.value) == "[]")

		-- Business accounts may answer with drive-keyed nextLinks; keys become path segments.
		responses = {{body = '{"value":[]}'}}
		c.listChildren({nextLink = "https://graph.microsoft.com/v1.0/drives('b!x-1')/items('01ABC')/children?%24skiptoken=UGFn"})
		assert(requests[5].url == "https://graph.microsoft.com/v1.0/drives/b!x-1/items/01ABC/children?%24skiptoken=UGFn", requests[5].url)

		responses = {{body = '{"id":"f2","name":"Q3 report.pdf","@microsoft.graph.downloadUrl":"https://x.files.1drv.com/y","@content.downloadUrl":"https://x.files.1drv.com/z"}'}, {body = '{"id":"root"}'}, {body = '{"id":"f1"}'}}
		local item = c.getItem({path = "/Documents/Q3 report.pdf"})
		assert(item.id == "f2" and item["@microsoft.graph.downloadUrl"] == nil and item["@content.downloadUrl"] == nil)
		assert(requests[6].url == API .. "/drive/root:/Documents/Q3%20report.pdf:?" .. SELECT, requests[6].url)
		c.getItem()
		assert(requests[7].url == API .. "/drive/root?" .. SELECT, requests[7].url)
		c.getItem({itemId = "f1", select = {"id", "name"}})
		assert(requests[8].url == API .. "/drive/items/f1?$select=id,name", requests[8].url)

		responses = {{body = '{"value":[{"id":"s1"}]}'}}
		assert(c.searchItems({q = "O'Brien plan", top = 5}).value[1].id == "s1")
		assert(requests[9].url == API .. "/drive/root/search(q='O%27%27Brien%20plan')?" .. SELECT .. "&$top=5", requests[9].url)

		responses = {{body = '{"value":[{"id":"p1","roles":["read"]}]}'}}
		assert(c.listPermissions({itemId = "f1"}).value[1].id == "p1")
		assert(requests[10].url == API .. "/drive/items/f1/permissions", requests[10].url)
		-- Graph may name the search function with its namespace in nextLinks.
		responses = {{body = '{"value":[]}'}}
		local ns = API .. "/drive/root/microsoft.graph.search(q='x')?$skiptoken=1"
		assert(#c.searchItems({nextLink = ns}).value == 0 and requests[11].url == ns, requests[11].url)

		-- Invalid input never reaches Graph.
		local sent = #requests
		for _, call in {
			function() return c.getItem({path = "Documents/../secret"}) end,
			-- OneDrive names have no colon, which would end path-based addressing early.
			function() return c.getItem({path = "photo.jpg:/thumbnails"}) end,
			function() return c.getItem({itemId = "f1", path = "a"}) end,
			function() return c.getItem({itemId = "f/1"}) end,
			function() return c.listChildren({itemId = ".."}) end,
			function() return c.listChildren({nextLink = next, top = 5}) end,
			function() return c.listChildren({nextLink = "https://evil.example/v1.0/me/drive/root/children"}) end,
			function() return c.listChildren({filter = "x"}) end,
			-- A nextLink must page the same list, carrying only paging options: thumbnails or an $expand
			-- would return signed links.
			function() return c.listChildren({nextLink = API .. "/drive/root:/photo.jpg:/thumbnails"}) end,
			function() return c.listChildren({nextLink = API .. "/drive/root/thumbnails"}) end,
			function() return c.searchItems({nextLink = API .. "/drive/root/children?$skiptoken=1"}) end,
			function() return c.listChildren({nextLink = API .. "/drive/root?$expand=children"}) end,
			function() return c.listChildren({nextLink = API .. "/drive/items/f1/children?%24skiptoken=a&%24Expand=thumbnails"}) end,
			function() return c.searchItems({nextLink = API .. "/drive/root/children?%2524expand=x"}) end,
			function() return c.downloadFile({itemId = "f1", path = "x.jpg", format = "jpg"}) end,
			function() return c.searchItems({q = "a/b"}) end,
			function() return c.searchItems({}) end,
			function() return c.listPermissions({}) end,
			function() return c.statFile() end,
			function() return c.statFile("f1", "extra") end,
			function() return c.statFile("") end,
			function() return c.downloadFile({itemId = "f1"}) end,
		} do assert(not pcall(call)) end
		assert(#requests == sent, "invalid input reached Graph")

		responses = {{body = '{"id":"f1","name":"Report","size":42,"file":{}}'}, {body = '{"id":"dir","name":"Folder","size":900,"folder":{"childCount":2}}'}}
		local file = c.statFile("f1")
		assert(file.id == "f1" and file.name == "Report" and file.size == 42 and file.isFolder == false)
		assert(requests[sent + 1].url == API .. "/drive/items/f1?$select=id,name,size,folder", requests[sent + 1].url)
		local folder = c.statFile("dir")
		assert(folder.isFolder and folder.size == nil)
		for _, size in {"-1", "0.5", "9007199254740992", '"42"'} do
			responses = {{body = '{"id":"bad","name":"Bad","size":' .. size .. '}'}}
			assert(not pcall(c.statFile, "bad"), "accepted size " .. size)
		end

		-- Content redirects to a preauthenticated host, fetched without credentials.
		local bytes = string.char(0, 255, 13, 10) .. "binary payload"
		local signed = "https://contoso-my.sharepoint.com/personal/ana/_layouts/15/download.aspx?UniqueId=1&tempauth=abc"
		responses = {{status = 302, headers = {location = {signed}}}, {body = bytes}}
		local saved = c.downloadFile({itemId = "f1", path = "downloads/report.bin"})
		assert(requests[#requests - 1].url == API .. "/drive/items/f1/content" and requests[#requests].url == signed)
		assert(saved.path == "downloads/report.bin" and saved.url == "https://houston.test/downloads/report.bin" and saved.size == #bytes)
		local fd = fs.open("downloads/report.bin", "r")
		assert(await(fd:readAll()) == bytes)
		await(fd:close())
		responses = {{status = 302, headers = {location = {"https://my.microsoftpersonalcontent.com/y/abc"}}}, {body = "%PDF"}}
		assert(c.downloadFile({itemId = "f1", path = "report.pdf", format = "pdf"}).size == 4)
		assert(requests[#requests - 1].url == API .. "/drive/items/f1/content?format=pdf", requests[#requests - 1].url)
		for _, location in {"https://evil.example/download", "https://sharepoint.com.evil.example/x", "http://contoso.sharepoint.com/x"} do
			sent = #requests
			responses = {{status = 302, headers = {location = {location}}}}
			fails({"unexpected host", "\"retryable\":false"}, c.downloadFile, {itemId = "f1", path = "x.bin"})
			assert(#requests == sent + 1, location)
		end
		responses = {{status = 302}}
		fails({"without a location"}, c.downloadFile, {itemId = "f1", path = "x.bin"})
		responses = {{body = "direct"}, {status = 302, headers = {location = {"https://Contoso-My.SharePoint.com/x"}}}, {body = "upper"}}
		assert(c.downloadFile({itemId = "f1", path = "direct.bin"}).size == 6, "a direct 200 saves the body")
		assert(c.downloadFile({itemId = "f1", path = "upper.bin"}).size == 5 and requests[#requests].url == "https://Contoso-My.SharePoint.com/x")
		-- A failed signed link is retryable with a fresh one, and leaves no file behind.
		responses = {{status = 302, headers = {location = {signed}}}, {status = 403, body = "expired"}}
		fails({"download link failed with HTTP 403; call again for a fresh link", "\"retryable\":true"}, c.downloadFile, {itemId = "f1", path = "expired.bin"})
		assert(not await(fs.exists("expired.bin")), "a failed download published a file")
		responses = {{status = 404, body = "{}"}}
		fails({"HTTP 404"}, c.downloadFile, {itemId = "f1", path = "downloads/report.bin"})
		fd = fs.open("downloads/report.bin", "r")
		assert(await(fd:readAll()) == bytes, "a failed download replaced the previous file")
		await(fd:close())

		-- Graph errors keep the status, code and message; throttling is retryable.
		responses = {{status = 404, body = '{"error":{"code":"itemNotFound","message":"The resource could not be found.","innerError":{"request-id":"r1"}}}'}}
		fails({"Microsoft Graph HTTP 404 (itemNotFound): The resource could not be found.", "\"retryable\":false"}, c.getItem, {itemId = "missing"})
		responses = {{status = 429, headers = {["retry-after"] = {"7"}}, body = '{"error":{"code":"TooManyRequests","message":"Slow down"}}'}}
		fails({"Microsoft Graph HTTP 429 (TooManyRequests): Slow down; Retry-After: 7", "\"retryable\":true"}, c.listChildren)
		responses = {{status = 503, body = "<html>unavailable</html>"}}
		fails({"Microsoft Graph HTTP 503", "\"retryable\":true"}, c.searchItems, {q = "x"})
		responses = {{status = 200, body = "[1]"}}
		fails({"invalid JSON object"}, c.getDrive)
		responses = {{status = 507, body = '{"error":{"code":"quotaLimitReached","message":"Insufficient Storage"}}'}}
		fails({"HTTP 507 (quotaLimitReached)", "\"retryable\":false"}, c.getDrive)
		assert(#responses == 0)
	end,
}
