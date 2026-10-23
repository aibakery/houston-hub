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
		local API = "https://forms.googleapis.com/v1/forms"
		local names = {}
		for name in c do table.insert(names, name) end
		table.sort(names)
		assert(table.concat(names, ",") == "batchUpdate,createForm,getForm,getResponse,listResponses,setPublishSettings", table.concat(names, ","))
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

		responses = {'{"formId":"new","info":{"title":"Lunch"},"responderUri":"https://docs.google.com/forms/d/e/1FAIpQL/viewform"}', '{"formId":"live"}'}
		local created = c.createForm({info = {title = "Lunch"}})
		assert(created.formId == "new" and json.encode(created.items) == "[]")
		sent(API .. "?unpublished=true", {info = {title = "Lunch"}})
		c.createForm({info = {title = "Live"}, unpublished = false})
		sent(API .. "?unpublished=false", {info = {title = "Live"}})

		responses = {'{"replies":[{"createItem":{"itemId":"i1","questionId":["q1"]}}],"writeControl":{"requiredRevisionId":"r2"}}'}
		local requestsBody = {{createItem = {item = {title = "Which day?", questionItem = {question = {required = true, choiceQuestion = {type = "RADIO", options = {{value = "Tuesday"}}}}}}, location = {index = 0}}}}
		local reply = c.batchUpdate({formId = "https://docs.google.com/forms/d/f1/edit", requests = requestsBody, writeControl = {requiredRevisionId = "r1"}})
		assert(reply.replies[1].createItem.questionId[1] == "q1")
		sent(API .. "/f1:batchUpdate", {requests = requestsBody, writeControl = {requiredRevisionId = "r1"}})

		responses = {'{"formId":"f1","publishSettings":{"publishState":{"isPublished":true,"isAcceptingResponses":false}}}'}
		local closed = c.setPublishSettings({formId = "f1", publishSettings = {publishState = {isPublished = true, isAcceptingResponses = false}}, updateMask = "publish_state"})
		assert(closed.publishSettings.publishState.isAcceptingResponses == false)
		sent(API .. "/f1:setPublishSettings", {publishSettings = {publishState = {isPublished = true, isAcceptingResponses = false}}, updateMask = "publish_state"})

		-- Google's system parameters stay out of the URL; Google rejects them as unknown body fields.
		responses = {'{"replies":[{}]}'}
		c.batchUpdate({formId = "f1", requests = {{deleteItem = {location = {index = 2}}}}, key = "k", access_token = "t", alt = "media"})
		sent(API .. "/f1:batchUpdate", {requests = {{deleteItem = {location = {index = 2}}}}, key = "k", access_token = "t", alt = "media"})

		local count = #requests
		assert(not pcall(c.createForm, {formId = "f1", info = {title = "Copy"}}), "createForm assigns the formId")
		assert(not pcall(c.createForm, {info = {title = "Lunch"}, unpublished = {mode = "draft"}}))
		assert(not pcall(c.batchUpdate, {formId = "f1"}), "batchUpdate requires requests")
		assert(not pcall(c.batchUpdate, {formId = "f1", requests = {}}))
		assert(not pcall(c.batchUpdate, {formId = "f1", requests = "x"}))
		assert(not pcall(c.batchUpdate, {formId = "f1", requests = {deleteItem = {}}}))
		assert(not pcall(c.batchUpdate, {formId = "https://docs.google.com/forms/d/e/1FAIpQL/viewform", requests = {{deleteItem = {location = {index = 0}}}}}))
		assert(not pcall(c.createForm, {}), "createForm requires info")
		assert(not pcall(c.createForm, {info = "Lunch"}))
		assert(not pcall(c.setPublishSettings, {formId = "f1"}), "setPublishSettings requires publishSettings")
		assert(not pcall(c.setPublishSettings, {formId = "f1", publishSettings = {}}))
		assert(not pcall(c.setPublishSettings, {formId = "f1", publishSettings = {{isPublished = true}}}))
		assert(not pcall(c.setPublishSettings, {publishSettings = {}}))
		assert(not pcall(c.setPublishSettings, {formId = "f/1", publishSettings = {}}))
		assert(#requests == count, "invalid input reached Google")
		assert(#responses == 0)
	end,
}
