-- Gmail bodies are unpadded base64url.
local function b64(s)
	return (string.gsub(require("lib/base64.luau").encode(s), "[+/=]", {["+"] = "-", ["/"] = "_", ["="] = ""}))
end
return {
	scenario = {publisher = {client_id = "fixture-client", client_secret = "fixture-private-secret"}, config = {}, auth_method = "oauth", auth_config = {}},
	config = {access = "read-only"},
	configure = function()
		requests, responses = {}, {}
		http = {request = function(req)
			table.insert(requests, req)
			assert(#responses > 0, "unexpected request: " .. req.url)
			local response = table.remove(responses, 1)
			return fixture.operation({statusCode = response.status or 200, headers = response.headers or {}, body = fixture.reader(response.body or "")})
		end}
	end,
	run = function(c)
		local API = "https://gmail.googleapis.com/gmail/v1/users/me"
		responses = {{body = '{"resultSizeEstimate":0}'}, {body = '{"messages":[{"id":"m1","threadId":"t1"}],"nextPageToken":"next+1"}'}}
		local empty = c.listMessages({q = "from:ana@example.com is:unread"})
		assert(json.encode(empty.messages) == "[]", "absent lists must be empty arrays")
		assert(requests[1].url == API .. "/messages?q=from%3Aana%40example.com%20is%3Aunread", requests[1].url)
		local page = c.listMessages({labelIds = {"INBOX", "UNREAD"}, maxResults = 2, pageToken = "start+1"})
		assert(page.nextPageToken == "next+1" and page.messages[1].id == "m1")
		assert(requests[2].url == API .. "/messages?labelIds=INBOX&labelIds=UNREAD&maxResults=2&pageToken=start%2B1", requests[2].url)

		local full = {
			id = "m1", threadId = "t1", labelIds = {"INBOX"}, snippet = "Hello", internalDate = "1760000000000",
			payload = {mimeType = "multipart/mixed", headers = {
				{name = "From", value = "Ana <ana@example.com>"}, {name = "To", value = "me@example.com"},
				{name = "Subject", value = "Plans"}, {name = "Message-ID", value = "<a1@example.com>"}, {name = "Received", value = "from mx"},
			}, parts = {
				{mimeType = "multipart/alternative", parts = {
					{mimeType = "text/plain", body = {size = 12, data = b64("Héllo there!")}},
					{mimeType = "text/html", body = {size = 20, data = b64("<p>Héllo there!</p>")}},
				}},
				{mimeType = "image/png", filename = "", headers = {{name = "Content-ID", value = "<logo@x>"}}, body = {attachmentId = "inline1", size = 10}},
				{mimeType = "application/pdf", filename = "plan.pdf", headers = {{name = "Content-Disposition", value = "attachment; filename=\"plan.pdf\""}}, body = {attachmentId = "att1", size = 2048}},
				{mimeType = "text/plain", filename = "notes.txt", body = {attachmentId = "att2", size = 5}},
			}},
		}
		responses = {{body = json.encode(full)}}
		local message = c.getMessage({id = "m1"})
		assert(requests[3].url == API .. "/messages/m1?format=full", requests[3].url)
		assert(message.from == "Ana <ana@example.com>" and message.to == "me@example.com" and message.subject == "Plans" and message.messageId == "<a1@example.com>")
		assert(message.body == "Héllo there!" and message.bodyTruncated == false and message.payload == nil)
		assert(#message.attachments == 3 and message.attachments[1].id == "inline1" and message.attachments[1].inline and message.attachments[1].contentId == "logo@x")
		assert(message.attachments[2].filename == "plan.pdf" and not message.attachments[2].inline and message.attachments[2].size == 2048)
		assert(message.attachments[3].filename == "notes.txt", "named text parts are attachments, not bodies")
		assert(message.labelIds[1] == "INBOX" and #message.headers == 5)

		local latin = {id = "m2", threadId = "t2", payload = {mimeType = "text/html", headers = {}, body = {data = b64("caf" .. string.char(233) .. " <b>ok</b>")}}}
		responses = {{body = json.encode(latin)}}
		message = c.getMessage({id = "m2", maxBodyBytes = 4})
		assert(message.body == "caf" and message.bodyTruncated, "truncation keeps whole UTF-8 characters: " .. message.body)
		assert(json.encode(message.attachments) == "[]" and message.from == nil)
		responses = {{body = json.encode(latin)}}
		assert(c.getMessage({id = "m2", maxBodyBytes = 0}).body == "café <b>ok</b>")
		responses = {{body = '{"id":"m3","threadId":"t3","snippet":"Just a snippet"}'}}
		message = c.getMessage({id = "m3", format = "minimal"})
		assert(message.body == "Just a snippet" and string.find(requests[#requests].url, "format=minimal", 1, true))

		local ids = {}
		responses = {}
		for i = 1, 12 do
			table.insert(ids, "id" .. i)
			table.insert(responses, {body = json.encode({id = "id" .. i, threadId = "t", payload = {headers = {{name = "Subject", value = "S" .. i}}}})})
		end
		local before = #requests
		local batch = c.getMessages({ids = ids, format = "metadata", metadataHeaders = {"Subject"}})
		assert(#batch == 12 and #requests == before + 12)
		for i = 1, 12 do assert(batch[i].id == "id" .. i and batch[i].subject == "S" .. i) end
		assert(requests[before + 1].url == API .. "/messages/id1?format=metadata&metadataHeaders=Subject", requests[before + 1].url)

		responses = {{body = json.encode({id = "t1", historyId = "9", messages = {full, latin}})}, {body = json.encode({id = "d1", message = full})}}
		local thread = c.getThread({id = "t1"})
		assert(thread.id == "t1" and #thread.messages == 2 and thread.messages[1].body == "Héllo there!" and thread.messages[2].body == "café <b>ok</b>")
		local draft = c.getDraft({id = "d1"})
		assert(draft.id == "d1" and draft.message.subject == "Plans")

		responses = {{body = '{"labels":[{"id":"Label_2","name":"Work","type":"user"},{"id":"INBOX","name":"INBOX","type":"system"}]}'}}
		local folders = c.listMailFolders()
		assert(#folders == 2 and folders[1].id == "INBOX" and folders[2].name == "Work" and folders[2].type == nil)
		responses = {{body = '{"labels":[{"id":"A","name":"One"},{"id":"A","name":"Two"}]}'}}
		assert(not pcall(c.listMailFolders), "duplicate label IDs accepted")

		local count = #requests
		for _, call in {
			function() return c.getMessage({}) end, function() return c.getMessage("m1") end, function() return c.getMessage({id = "m1", format = "raw"}) end,
			function() return c.getMessage({id = "m1", maxBodyBytes = -1}) end, function() return c.getMessage({id = "m1", extra = true}) end,
			function() return c.getMessages({ids = {}}) end, function() return c.getMessages({ids = {"a", ""}}) end,
			function() return c.getMessage({id = ".."}) end, function() return c.getMessage({id = "m/1"}) end, function() return c.getMessages({ids = {"a", "b%2Fc"}}) end, function() return c.getMessages({ids = {"a", nil, "c"}}) end,
			function() return c.listMessages({unknown = 1}) end,
		} do assert(not pcall(call)) end
		assert(#requests == count, "invalid input reached Google")

		responses = {{status = 403, body = '{"error":{"code":403,"message":"Request had insufficient authentication scopes.","status":"PERMISSION_DENIED","errors":[{"reason":"insufficientPermissions"}]}}'}}
		local ok, err = pcall(c.getProfile)
		assert(not ok and string.find(tostring(err), "insufficient authentication scopes", 1, true) and string.find(tostring(err), "PERMISSION_DENIED", 1, true), tostring(err))
		assert(#responses == 0)
	end,
}
