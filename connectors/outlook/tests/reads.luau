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
		local API = "https://graph.microsoft.com/v1.0/me"
		local LIST = "$select=id%2Csubject%2Cfrom%2CtoRecipients%2CccRecipients%2CreceivedDateTime%2CsentDateTime%2CisRead%2CisDraft%2ChasAttachments%2Cimportance%2Cflag%2Ccategories%2CconversationId%2CparentFolderId%2CbodyPreview%2CwebLink"
		local function last() return requests[#requests] end
		local function fails(expected: {string}, fn: (...any) -> any, ...: any)
			local ok, err = pcall(fn, ...)
			assert(not ok, "call succeeded")
			for _, text in expected do assert(string.find(tostring(err), text, 1, true), "missing " .. text .. " in " .. tostring(err)) end
		end
		local names = {}
		for name in c do table.insert(names, name) end
		table.sort(names)
		assert(table.concat(names, ",") == "getAttachment,getMailFolder,getMessage,getProfile,listAttachments,listMailFolders,listMessages", "read-only got " .. table.concat(names, ","))

		responses = {{body = '{"id":"u1","mail":null,"userPrincipalName":"ana@outlook.com"}'}, {body = '{"id":"AAMkInbox","unreadItemCount":3}'}}
		assert(c.getProfile().userPrincipalName == "ana@outlook.com")
		assert(last().url == API .. "?$select=id%2CdisplayName%2Cmail%2CuserPrincipalName", last().url)
		assert(c.getMailFolder({id = "inbox"}).unreadItemCount == 3 and last().url == API .. "/mailFolders/inbox", last().url)

		-- Lists default to text bodies and summary fields, and always carry a value array.
		local nextLink = "https://graph.microsoft.com/v1.0/me/mailFolders('inbox')/messages?%24select=id&%24top=2&%24skip=2"
		responses = {
			{body = '{"value":[{"id":"m1","subject":"Hi"}],"@odata.nextLink":"' .. nextLink .. '"}'},
			{body = '{"value":[]}'}, {body = '{}'},
		}
		local page = c.listMessages({folderId = "inbox", filter = "isRead eq false", top = 2})
		assert(page.value[1].id == "m1" and page["@odata.nextLink"] == nextLink)
		assert(last().url == API .. "/mailFolders/inbox/messages?" .. LIST .. "&$filter=isRead%20eq%20false&$top=2", last().url)
		assert(last().headers.Prefer[1] == 'outlook.body-content-type="text"')
		-- Graph names the folder by OData key in nextLink; the route takes its path form.
		assert(#c.listMessages({nextLink = nextLink}).value == 0)
		assert(last().url == API .. "/mailFolders/inbox/messages?%24select=id&%24top=2&%24skip=2", last().url)
		local empty = c.listMessages({search = 'from:ana "Q3 plan" dir\\', bodyFormat = "html"})
		assert(json.encode(empty.value) == "[]" and last().headers.Prefer[1] == 'outlook.body-content-type="html"')
		assert(last().url == API .. "/messages?" .. LIST .. "&$search=%22from%3Aana%20%5C%22Q3%20plan%5C%22%20dir%5C%5C%22", last().url)

		-- Bodies are capped on a UTF-8 boundary.
		local body = "h" .. "é" .. string.rep("x", 10)
		responses = {{body = json.encode({id = "AAMk-_=", body = {contentType = "text", content = body}})}, {body = json.encode({value = {{id = "m2", body = {contentType = "text", content = "short"}}}})}}
		local message = c.getMessage({id = "AAMk-_=", maxBodyBytes = 2})
		assert(message.body.content == "h" and message.bodyTruncated == true, message.body.content)
		assert(last().url == API .. "/messages/AAMk-_%3D" and last().headers.Prefer[1] == 'outlook.body-content-type="text"', last().url)
		responses = {{body = json.encode({id = "m3", body = {content = "ab" .. utf8.char(0x1F600) .. "c"}})}}
		assert(c.getMessage({id = "m3", maxBodyBytes = 4}).body.content == "ab", "a 4-byte character was split")
		responses = {{body = json.encode({id = "m4", body = {content = "ok"}, uniqueBody = {content = string.rep("u", 10)}})}}
		local unique = c.getMessage({id = "m4", select = "body,uniqueBody", maxBodyBytes = 4})
		assert(unique.uniqueBody.content == "uuuu" and unique.body.content == "ok" and unique.bodyTruncated == true, "uniqueBody was not capped")
		responses = {{body = json.encode({value = {{id = "m2", body = {contentType = "text", content = "short"}}}})}}
		page = c.listMessages({select = {"id", "body"}, maxBodyBytes = 0})
		assert(page.value[1].body.content == "short" and page.value[1].bodyTruncated == false)
		assert(last().url == API .. "/messages?$select=id,body", last().url)

		responses = {{body = '{"value":[{"id":"A1","name":"invoice.pdf","size":12,"contentBytes":"JVBERg=="}]}'}, {body = "%PDF-1.7 bytes"}}
		local attachments = c.listAttachments({messageId = "m1", select = "id,name,contentBytes"})
		assert(attachments.value[1].name == "invoice.pdf" and attachments.value[1].contentBytes == nil, "attachment bytes came back inline")
		responses = {{body = '{"value":[]}'}, {body = "%PDF-1.7 bytes"}}
		assert(json.encode(c.listAttachments({messageId = "m1"}).value) == "[]")
		assert(last().url == API .. "/messages/m1/attachments?$select=id%2Cname%2CcontentType%2Csize%2CisInline%2ClastModifiedDateTime", last().url)
		local saved = c.getAttachment({messageId = "m1", attachmentId = "A1=", path = "mail/invoice.pdf"})
		assert(last().url == API .. "/messages/m1/attachments/A1%3D/$value", last().url)
		assert(saved.path == "mail/invoice.pdf" and saved.size == 14 and saved.url == "https://houston.test/mail/invoice.pdf")
		local fd = fs.open("mail/invoice.pdf", "r")
		assert(await(fd:readAll()) == "%PDF-1.7 bytes")
		await(fd:close())

		-- Every folder, nested names joined with '/', sorted by ID; pages and children follow Graph's links.
		responses = {
			{body = '{"value":[{"id":"F2","displayName":"Inbox","childFolderCount":1},{"id":"F9","displayName":"Archive","childFolderCount":0}],"@odata.nextLink":"https://graph.microsoft.com/v1.0/me/mailFolders?%24top=100&%24skip=2"}'},
			{body = '{"value":[{"id":"F5","displayName":"Sent Items"}]}'},
			{body = '{"value":[{"id":"F3","displayName":"Projects","childFolderCount":0}],"@odata.nextLink":"https://graph.microsoft.com/v1.0/me/mailFolders('.."'F2'"..')/childFolders?%24top=100&%24skip=1"}'},
			{body = '{"value":[{"id":"F4","displayName":"Clients"}]}'},
		}
		local folders = c.listMailFolders()
		assert(json.encode(folders) == '[{"id":"F2","name":"Inbox"},{"id":"F3","name":"Inbox/Projects"},{"id":"F4","name":"Inbox/Clients"},{"id":"F5","name":"Sent Items"},{"id":"F9","name":"Archive"}]', json.encode(folders))
		local tail = #requests
		assert(requests[tail - 3].url == API .. "/mailFolders?$top=100&$select=id,displayName,childFolderCount", requests[tail - 3].url)
		assert(requests[tail - 2].url == API .. "/mailFolders?%24top=100&%24skip=2", requests[tail - 2].url)
		assert(requests[tail - 1].url == API .. "/mailFolders/F2/childFolders?$top=100&$select=id,displayName,childFolderCount", requests[tail - 1].url)
		-- Graph names the parent by OData key in the child page link; the route takes its path form.
		assert(requests[tail].url == API .. "/mailFolders/F2/childFolders?%24top=100&%24skip=1", requests[tail].url)
		responses = {{body = '{"value":[]}'}}
		assert(json.encode(c.listMailFolders()) == "[]")
		-- $skip paging can repeat a folder when the mailbox changes between pages.
		responses = {{body = '{"value":[{"id":"F1","displayName":"a"}],"@odata.nextLink":"https://graph.microsoft.com/v1.0/me/mailFolders?%24skip=1"}'}, {body = '{"value":[{"id":"F1","displayName":"a"},{"id":"F2","displayName":"b"}]}'}}
		assert(json.encode(c.listMailFolders()) == '[{"id":"F1","name":"a"},{"id":"F2","name":"b"}]')
		for _, invalid in {'{"value":[{"id":"","displayName":"x"}]}', '{"value":[{"id":"F1"}]}'} do
			responses = {{body = invalid}}
			fails({"invalid folder metadata"}, c.listMailFolders)
		end

		-- Invalid input never reaches Graph.
		local sent = #requests
		for _, call in {
			function() return c.listMailFolders({}) end,
			function() return c.listMessages({bodyFormat = "rtf"}) end,
			function() return c.listMessages({maxBodyBytes = -1}) end,
			function() return c.listMessages({folderId = "a/b"}) end,
			function() return c.listMessages({folder = "inbox"}) end,
			function() return c.listMessages({nextLink = nextLink, top = 5}) end,
			function() return c.listMessages({nextLink = "https://graph.microsoft.com.evil.example/v1.0/me/messages"}) end,
			function() return c.listMessages({top = {}}) end,
			function() return c.listMessages({nextLink = API .. "/messages?%24skip=10&%24expand=attachments"}) end,
			-- A nextLink must page the same list: another route could return signed links or bytes.
			function() return c.listMessages({nextLink = API .. "/mailFolders?%24skip=10"}) end,
			function() return c.listMessages({nextLink = API .. "/messages/m1/attachments?%24skip=1"}) end,
			function() return c.listMessages({nextLink = API .. "/messages?$skip=10#x"}) end,
			function() return c.getMessage({}) end,
			function() return c.getMessage({id = ".."}) end,
			function() return c.getMailFolder({id = "inbox", top = 1}) end,
			function() return c.getAttachment({messageId = "m1", attachmentId = "A1"}) end,
			function() return c.listAttachments({messageId = "m%2F1"}) end,
		} do assert(not pcall(call)) end
		assert(#requests == sent, "invalid input reached Graph")

		-- Graph errors keep the status, code and message; throttling is retryable.
		responses = {{status = 404, body = '{"error":{"code":"ErrorItemNotFound","message":"The specified object was not found in the store.","innerError":{"request-id":"r1"}}}'}}
		fails({"Microsoft Graph HTTP 404 (ErrorItemNotFound): The specified object was not found in the store.", '"retryable":false'}, c.getMessage, {id = "gone"})
		responses = {{status = 429, headers = {["retry-after"] = {"3"}}, body = '{"error":{"code":"ApplicationThrottled","message":"Too many requests"}}'}}
		fails({"HTTP 429 (ApplicationThrottled)", "Retry-After: 3", '"retryable":true'}, c.listMessages)
		responses = {{status = 404, body = '{"error":{"code":"ErrorItemNotFound","message":"gone"}}'}}
		fails({"HTTP 404", '"retryable":false'}, c.getAttachment, {messageId = "m1", attachmentId = "A1", path = "x.pdf"})
		responses = {{status = 504}}
		fails({"Microsoft Graph HTTP 504", '"retryable":true'}, c.getProfile)
		assert(#responses == 0)
	end,
}
