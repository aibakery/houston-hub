return {
	scenario = {publisher = {client_id = "fixture-client", client_secret = "fixture-private-secret"}, config = {}, auth_method = "oauth", auth_config = {}},
	config = {access = "read-write"},
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
		assert(table.concat(names, ",") == "addAttachment,createDraft,createForward,createMailFolder,createReply,createReplyAll,deleteMessage,forward,getAttachment,getMailFolder,getMessage,getProfile,listAttachments,listMailFolders,listMessages,moveMessage,reply,replyAll,sendDraft,sendMail,updateMessage", "read-write got " .. table.concat(names, ","))

		local file = fs.open("report.csv", "w")
		file:write("a,b\n1,2\n")
		await(file:close())

		responses = {{status = 202}}
		assert(c.sendMail({message = {subject = "Report", body = {contentType = "Text", content = "Attached."},
			toRecipients = {{emailAddress = {address = "ana@example.com", name = "Ana"}}}, attachments = {"report.csv"}}, saveToSentItems = false}).success)
		assert(last().method == "POST" and last().url == API .. "/sendMail", last().url)
		local body = json.decode(last().body)
		assert(body.saveToSentItems == false and body.message.subject == "Report" and body.message.attachments[1].contentBytes == "YSxiCjEsMgo=")

		-- Sending a draft posts an empty body, as Graph requires Content-Length: 0.
		responses = {{status = 202}, {status = 202}, {status = 202}, {status = 202}}
		assert(c.sendDraft({id = "D1"}).success and last().url == API .. "/messages/D1/send" and last().body == "")
		c.reply({id = "M1", comment = "On it.", message = {attachments = {"report.csv"}}})
		body = json.decode(last().body)
		assert(last().url == API .. "/messages/M1/reply" and body.comment == "On it." and body.message.attachments[1].contentBytes == "YSxiCjEsMgo=")
		c.replyAll({id = "M1", comment = "Thanks all"})
		assert(last().url == API .. "/messages/M1/replyAll")
		c.forward({id = "M1", toRecipients = {{emailAddress = {address = "bo@example.com"}}}, comment = "FYI"})
		body = json.decode(last().body)
		assert(last().url == API .. "/messages/M1/forward" and body.toRecipients[1].emailAddress.address == "bo@example.com" and body.id == nil)

		-- Read-write changes any message without a draft check.
		responses = {{body = '{"id":"M1","isRead":true}'}, {status = 204}, {status = 201, body = '{"id":"M1-moved"}'}}
		assert(c.updateMessage({id = "M1", isRead = true, flag = {flagStatus = "flagged"}}).isRead)
		assert(last().method == "PATCH" and last().url == API .. "/messages/M1" and json.decode(last().body).flag.flagStatus == "flagged")
		assert(c.deleteMessage({id = "M1"}).success and last().method == "DELETE")
		assert(c.moveMessage({id = "M2", destinationId = "archive"}).id == "M1-moved")
		assert(last().url == API .. "/messages/M2/move" and json.decode(last().body).destinationId == "archive")

		responses = {{status = 201, body = '{"id":"F1","displayName":"Clients"}'}, {status = 201, body = '{"id":"F2"}'}}
		c.createMailFolder({displayName = "Clients"})
		assert(last().url == API .. "/mailFolders" and json.decode(last().body).displayName == "Clients")
		c.createMailFolder({displayName = "Acme", parentId = "F1"})
		assert(last().url == API .. "/mailFolders/F1/childFolders" and json.decode(last().body).parentId == nil)

		local before = #requests
		for _, call in {
			function() return c.sendMail({}) end,
			function() return c.sendMail({message = {}}) end,
			function() return c.sendMail({message = {subject = "x"}, cc = "ana@example.com"}) end,
			function() return c.sendDraft({id = "D1", comment = "x"}) end,
			function() return c.createMailFolder({}) end,
			function() return c.moveMessage({id = "a/b", destinationId = "archive"}) end,
		} do assert(not pcall(call)) end
		assert(#requests == before, "invalid writes reached Graph")

		-- A failed send is reported without retrying; it may still have been accepted.
		responses = {{status = 503, headers = {["retry-after"] = {"10"}}, body = '{"error":{"code":"ServiceUnavailable","message":"Try later"}}'}}
		local ok, err = pcall(c.sendMail, {message = {subject = "x"}})
		assert(not ok and string.find(tostring(err), "HTTP 503 (ServiceUnavailable): Try later; Retry-After: 10", 1, true) and string.find(tostring(err), '"retryable":false', 1, true), tostring(err))
		assert(#requests == before + 1 and #responses == 0)
	end,
}
