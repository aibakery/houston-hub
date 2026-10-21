return {
	scenario = {publisher = {client_id = "fixture-client", client_secret = "fixture-private-secret"}, config = {}, auth_method = "oauth", auth_config = {}},
	config = {access = "read-write"},
	configure = function()
		requests, responses = {}, {}
		http = {request = function(req)
			table.insert(requests, req)
			assert(#responses > 0, "unexpected request: " .. req.url)
			return fixture.operation({statusCode = 200, headers = {}, body = fixture.reader(table.remove(responses, 1))})
		end}
	end,
	run = function(c)
		local API = "https://docs.googleapis.com/v1/documents"
		local names = {}
		for name in c do table.insert(names, name) end
		table.sort(names)
		assert(table.concat(names, ",") == "batchUpdate,createDocument,getDocument,getDocumentText", table.concat(names, ","))
		local function same(a, b)
			if type(a) ~= "table" or type(b) ~= "table" then return a == b end
			for key, value in a do if not same(value, b[key]) then return false end end
			for key in b do if a[key] == nil then return false end end
			return true
		end
		local function sent(href, body)
			local req = requests[#requests]
			assert(req.method == "POST" and req.url == href, req.method .. " " .. req.url)
			assert(req.headers["Content-Type"][1] == "application/json" and req.headers.Authorization == nil)
			assert(same(json.decode(req.body), body), req.body)
		end

		responses = {'{"documentId":"new","title":"Minutes","revisionId":"r1"}', '{"documentId":"untitled"}'}
		assert(c.createDocument({title = "Minutes"}).documentId == "new")
		sent(API, {title = "Minutes"})
		assert(c.createDocument().documentId == "untitled")
		assert(requests[#requests].body == "{}", requests[#requests].body)

		responses = {'{"documentId":"d1","replies":[{"replaceAllText":{"occurrencesChanged":2}},{}],"writeControl":{"requiredRevisionId":"r2"}}'}
		local edits = {
			{replaceAllText = {containsText = {text = "{{client}}", matchCase = true}, replaceText = "Acme"}},
			{insertText = {endOfSegmentLocation = {tabId = "t.1"}, text = "\nNext steps"}},
		}
		local reply = c.batchUpdate({documentId = "https://docs.google.com/document/d/d1/edit?tab=t.1", requests = edits, writeControl = {requiredRevisionId = "r1"}})
		assert(reply.replies[1].replaceAllText.occurrencesChanged == 2 and reply.writeControl.requiredRevisionId == "r2")
		sent(API .. "/d1:batchUpdate", {requests = edits, writeControl = {requiredRevisionId = "r1"}})

		responses = {'{"documentId":"d1","replies":[{"insertComment":{"commentThread":{"commentId":"c1","anchorId":"a1"}}}],"suggestionResponses":[{}],"commentUpdateState":"ALL_SAVED"}'}
		local comment = {{insertComment = {content = "Check this figure", range = {startIndex = 5, endIndex = 9}}}}
		assert(c.batchUpdate({documentId = "d1", requests = comment, writeControl = {writeMode = "SUGGEST"}}).commentUpdateState == "ALL_SAVED")
		sent(API .. "/d1:batchUpdate", {requests = comment, writeControl = {writeMode = "SUGGEST"}})

		-- Google's system parameters stay out of the URL; Google rejects them as unknown body fields.
		responses = {'{"documentId":"d1","replies":[{}]}'}
		local page = {{insertPageBreak = {endOfSegmentLocation = {}}}}
		c.batchUpdate({documentId = "d1", requests = page, key = "k", access_token = "t", alt = "media", fields = "x"})
		sent(API .. "/d1:batchUpdate", {requests = page, key = "k", access_token = "t", alt = "media", fields = "x"})
		assert(string.find(requests[#requests].body, '"endOfSegmentLocation":{}', 1, true), requests[#requests].body)

		local count = #requests
		assert(not pcall(c.createDocument, {documentId = "d1", title = "Copy"}), "createDocument assigns the documentId")
		assert(not pcall(c.createDocument, "Minutes"))
		assert(not pcall(c.batchUpdate, {documentId = "d1"}), "batchUpdate requires requests")
		assert(not pcall(c.batchUpdate, {documentId = "d1", requests = {}}))
		assert(not pcall(c.batchUpdate, {documentId = "d1", requests = "x"}))
		assert(not pcall(c.batchUpdate, {documentId = "d1", requests = {insertText = {text = "x"}}}))
		assert(not pcall(c.batchUpdate, {requests = page}), "batchUpdate requires documentId")
		assert(not pcall(c.batchUpdate, {documentId = "d/1", requests = page}))
		assert(not pcall(c.batchUpdate, {documentId = "https://docs.google.com/document/d/e/2PACX-1vR/pub", requests = page}))
		assert(#requests == count, "invalid input reached Google")
		assert(#responses == 0)
	end,
}
