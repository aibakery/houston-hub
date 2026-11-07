return {
	scenario = {publisher = {client_id = "fixture-client", client_secret = "fixture-private-secret"}, config = {}, auth_method = "oauth", auth_config = {}},
	config = {access = "custom"},
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
		local function last() return requests[#requests] end
		local names = {}
		for name in c do table.insert(names, name) end
		table.sort(names)
		assert(table.concat(names, ",") == "addAttachment,createDraft,createForward,createReply,createReplyAll,deleteMessage,getAttachment,getMailFolder,getMessage,getProfile,listAttachments,listMailFolders,listMessages,updateMessage", "read and draft got " .. table.concat(names, ","))

		local file = fs.open("notes.txt", "w")
		file:write("hello")
		await(file:close())
		file = fs.open("logo.bin", "w")
		file:write(string.char(0, 255))
		await(file:close())

		-- Session files become base64 fileAttachments in the draft itself.
		responses = {{status = 201, body = '{"id":"D1","isDraft":true}'}}
		local draft = c.createDraft({subject = "Q3", body = {contentType = "Text", content = "Notes attached"},
			toRecipients = {{emailAddress = {address = "ana@example.com"}}}, attachments = {"notes.txt", {path = "logo.bin", name = "logo.png", contentType = "image/png"}}})
		assert(draft.id == "D1" and last().method == "POST" and last().url == API .. "/messages", last().url)
		assert(last().headers["Content-Type"][1] == "application/json")
		local sent = json.decode(last().body)
		assert(sent.subject == "Q3" and sent.toRecipients[1].emailAddress.address == "ana@example.com")
		assert(sent.attachments[1]["@odata.type"] == "#microsoft.graph.fileAttachment" and sent.attachments[1].name == "notes.txt" and sent.attachments[1].contentBytes == "aGVsbG8=" and sent.attachments[1].contentType == nil)
		assert(sent.attachments[2].name == "logo.png" and sent.attachments[2].contentType == "image/png" and sent.attachments[2].contentBytes == "AP8=")

		-- Reply and forward drafts.
		responses = {{status = 201, body = '{"id":"D2","isDraft":true}'}, {status = 201, body = '{"id":"D3"}'}, {status = 201, body = '{"id":"D4"}'}}
		assert(c.createReply({id = "M1", comment = "Thanks!"}).id == "D2")
		assert(last().url == API .. "/messages/M1/createReply" and json.decode(last().body).comment == "Thanks!")
		c.createReplyAll({id = "M1"})
		assert(last().url == API .. "/messages/M1/createReplyAll" and last().body == "{}", last().body)
		c.createForward({id = "M1", toRecipients = {{emailAddress = {address = "bo@example.com"}}}})
		assert(last().url == API .. "/messages/M1/createForward" and json.decode(last().body).toRecipients[1].emailAddress.address == "bo@example.com")

		-- Changes apply only to drafts: Houston checks isDraft first.
		responses = {{body = '{"isDraft":true}'}, {body = '{"id":"D1","subject":"Q3 v2"}'}}
		assert(c.updateMessage({id = "D1", subject = "Q3 v2"}).subject == "Q3 v2")
		assert(requests[#requests - 1].method == "GET" and requests[#requests - 1].url == API .. "/messages/D1?$select=isDraft")
		assert(last().method == "PATCH" and last().url == API .. "/messages/D1" and json.decode(last().body).subject == "Q3 v2" and json.decode(last().body).id == nil)
		responses = {{body = '{"isDraft":true}'}, {status = 201, body = '{"id":"A1","name":"notes.txt"}'}}
		assert(c.addAttachment({messageId = "D1", path = "notes.txt"}).id == "A1")
		assert(last().url == API .. "/messages/D1/attachments" and json.decode(last().body).contentBytes == "aGVsbG8=")
		responses = {{body = '{"isDraft":true}'}, {status = 204}}
		assert(c.deleteMessage({id = "D1"}).success and last().method == "DELETE" and last().url == API .. "/messages/D1")
		for _, call in {
			function() return c.updateMessage({id = "M1", isRead = true}) end,
			function() return c.deleteMessage({id = "M1"}) end,
			function() return c.addAttachment({messageId = "M1", path = "notes.txt"}) end,
		} do
			responses = {{body = '{"isDraft":false}'}}
			local before = #requests
			local ok, err = pcall(call)
			assert(not ok and string.find(tostring(err), "only drafts", 1, true), tostring(err))
			assert(#requests == before + 1 and last().method == "GET", "a non-draft was changed")
		end

		-- Attachments are checked before anything is sent.
		local big = fs.open("big.bin", "w")
		big:write(string.rep("x", 3000000))
		await(big:close())
		local near = fs.open("near.bin", "w")
		near:write(string.rep("x", 2900000))
		await(near:close())
		local before = #requests
		for _, call in {
			function() return c.createDraft({subject = "x", attachments = {"big.bin"}}) end,
			-- Under 3 MB of files, but with a large body the request would exceed 4 MB.
			function() return c.createDraft({body = {contentType = "Text", content = string.rep("b", 200000)}, attachments = {"near.bin"}}) end,
			function() return c.createDraft({subject = "x", attachments = {"missing.txt"}}) end,
			function() return c.createDraft({subject = "x", attachments = "notes.txt"}) end,
			function() return c.createDraft({subject = "x", attachments = {{name = "x"}}}) end,
			function() return c.createDraft({}) end,
			function() return c.updateMessage({id = "D1"}) end,
			function() return c.updateMessage({id = "D1", attachments = {"notes.txt"}}) end,
			function() return c.addAttachment({messageId = "D1", path = "big.bin"}) end,
			function() return c.deleteMessage({id = "D1", permanent = true}) end,
			function() return c.createReply({}) end,
			-- Extended MAPI properties could turn a draft into a sent or received message.
			function() return c.createDraft({subject = "x", singleValueExtendedProperties = {{id = "Integer 0x0E07", value = "1"}}}) end,
			function() return c.updateMessage({id = "D1", multiValueExtendedProperties = {}}) end,
			function() return c.createReply({id = "M1", message = {singleValueExtendedProperties = {}}}) end,
		} do assert(not pcall(call)) end
		assert(#requests == before, "invalid drafts reached Graph")
		assert(#responses == 0)
	end,
}
