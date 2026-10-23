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
		local API = "https://slides.googleapis.com/v1/presentations"
		local names = {}
		for name in c do table.insert(names, name) end
		table.sort(names)
		assert(table.concat(names, ",") == "batchUpdate,createPresentation,getPage,getPresentation,getPresentationText,getThumbnail", table.concat(names, ","))
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

		responses = {'{"presentationId":"new","title":"Q3","revisionId":"r1","slides":[{"objectId":"p"}]}', '{"presentationId":"untitled"}'}
		local created = c.createPresentation({title = "Q3"})
		assert(created.presentationId == "new" and created.slides[1].objectId == "p")
		sent(API, {title = "Q3"})
		assert(c.createPresentation().slides == nil)
		assert(requests[#requests].body == "{}", requests[#requests].body)

		responses = {'{"presentationId":"p1","replies":[{"createSlide":{"objectId":"q3_summary"}},{}],"writeControl":{"requiredRevisionId":"r2"}}'}
		local edits = {
			{createSlide = {objectId = "q3_summary", slideLayoutReference = {predefinedLayout = "TITLE_AND_BODY"},
				placeholderIdMappings = {{layoutPlaceholder = {type = "TITLE"}, objectId = "q3_summary_title"}}}},
			{insertText = {objectId = "q3_summary_title", text = "Q3 results"}},
		}
		local reply = c.batchUpdate({presentationId = "https://docs.google.com/presentation/d/p1/edit#slide=id.g1", requests = edits, writeControl = {requiredRevisionId = "r1"}})
		assert(reply.replies[1].createSlide.objectId == "q3_summary" and reply.writeControl.requiredRevisionId == "r2")
		sent(API .. "/p1:batchUpdate", {requests = edits, writeControl = {requiredRevisionId = "r1"}})

		responses = {'{"presentationId":"p1","replies":[{"insertComment":{"commentThread":{"commentId":"c1","anchorId":"a1"}}}],"commentUpdateState":"ALL_SAVED"}'}
		local comment = {{insertComment = {content = "Update this chart", objectId = "g1"}}}
		assert(c.batchUpdate({presentationId = "p1", requests = comment}).commentUpdateState == "ALL_SAVED")
		sent(API .. "/p1:batchUpdate", {requests = comment})

		-- Google's system parameters stay out of the URL; Google rejects them as unknown body fields.
		responses = {'{"presentationId":"p1","replies":[{}]}'}
		local clear = {{deleteText = {objectId = "g1", textRange = {type = "ALL"}}}}
		c.batchUpdate({presentationId = "p1", requests = clear, key = "k", access_token = "t", alt = "media", fields = "x"})
		sent(API .. "/p1:batchUpdate", {requests = clear, key = "k", access_token = "t", alt = "media", fields = "x"})

		local count = #requests
		assert(not pcall(c.createPresentation, "Q3"))
		assert(not pcall(c.createPresentation, {presentationId = "p1", title = "Copy"}), "createPresentation assigns the presentationId")
		assert(not pcall(c.batchUpdate, {presentationId = "p1"}), "batchUpdate requires requests")
		assert(not pcall(c.batchUpdate, {presentationId = "p1", requests = {}}))
		assert(not pcall(c.batchUpdate, {presentationId = "p1", requests = "x"}))
		assert(not pcall(c.batchUpdate, {presentationId = "p1", requests = {deleteObject = {objectId = "g1"}}}))
		assert(not pcall(c.batchUpdate, {requests = clear}), "batchUpdate requires presentationId")
		assert(not pcall(c.batchUpdate, {presentationId = "p/1", requests = clear}))
		assert(not pcall(c.batchUpdate, {presentationId = "https://docs.google.com/presentation/d/e/2PACX-1vS/pub", requests = clear}))
		assert(#requests == count, "invalid input reached Google")
		assert(#responses == 0)
	end,
}
