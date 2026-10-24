return {
	scenario = {publisher = {client_id = "fixture-client", client_secret = "fixture-private-secret"}, config = {}, auth_method = "oauth", auth_config = {}},
	config = {access = "read-write"},
	configure = function()
		requests, responses = {}, {}
		http = {request = function(req)
			table.insert(requests, req)
			assert(req.method == "POST" and req.headers.Authorization == nil)
			assert(#responses > 0, "unexpected request: " .. req.url)
			local response = table.remove(responses, 1)
			return fixture.operation({statusCode = response.status or 200, headers = {}, body = fixture.reader(response.body or "")})
		end}
	end,
	run = function(c)
		local API = "https://gmail.googleapis.com/gmail/v1/users/me"
		responses = {{body = '{"id":"m1","labelIds":["INBOX","STARRED"]}'}, {body = '{"id":"m1","labelIds":["INBOX","STARRED","UNREAD"]}'}, {status = 204}, {body = '{"id":"t1","messages":[{"id":"m1","labelIds":["INBOX"]}]}'} }
		local read = c.modifyMessage({id = "m1", removeLabelIds = {"UNREAD"}})
		assert(read.id == "m1" and read.labelIds[2] == "STARRED")
		assert(requests[1].url == API .. "/messages/m1/modify" and requests[1].body == '{"removeLabelIds":["UNREAD"]}')
		local unread = c.modifyMessage({id = "m1", addLabelIds = {"UNREAD"}})
		assert(unread.labelIds[3] == "UNREAD")
		assert(requests[2].url == API .. "/messages/m1/modify" and requests[2].body == '{"addLabelIds":["UNREAD"]}')
		assert(c.batchModifyMessages({ids = {"m1", "m2"}, removeLabelIds = {"UNREAD"}}).success)
		assert(requests[3].url == API .. "/messages/batchModify")
		local batch = json.decode(requests[3].body)
		assert(#batch.ids == 2 and batch.ids[1] == "m1" and batch.ids[2] == "m2" and #batch.removeLabelIds == 1 and batch.removeLabelIds[1] == "UNREAD" and batch.addLabelIds == nil)
		local thread = c.modifyThread({id = "t1", removeLabelIds = {"UNREAD"}})
		assert(thread.id == "t1" and thread.messages[1].id == "m1")
		assert(requests[4].url == API .. "/threads/t1/modify" and requests[4].body == '{"removeLabelIds":["UNREAD"]}')
		responses = {{status = 403, body = '{"error":{"message":"Insufficient permissions","status":"PERMISSION_DENIED"}}'}}
		local ok, err = pcall(c.modifyMessage, {id = "m1", removeLabelIds = {"UNREAD"}})
		assert(not ok and string.find(tostring(err), "PERMISSION_DENIED", 1, true))
		assert(#requests == 5 and #responses == 0, "failed writes must not be replayed")
	end,
}
