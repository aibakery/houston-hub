return {
	scenario = {publisher = {client_id = "fixture-client", client_secret = "fixture-private-secret"}, config = {}, auth_method = "oauth", auth_config = {}},
	config = {access = "read-only"},
	configure = function()
		requests, responses = {}, {}
		http = {request = function(req)
			table.insert(requests, req)
			assert(#responses > 0, "unexpected request: " .. req.url)
			return fixture.operation({statusCode = 200, headers = {}, body = fixture.reader(table.remove(responses, 1))})
		end}
	end,
	run = function(c)
		local API = "https://forms.googleapis.com/v1/forms/"
		local names = {}
		for name in c do table.insert(names, name) end
		table.sort(names)
		assert(table.concat(names, ",") == "getForm,getResponse,listResponses", table.concat(names, ","))

		responses = {
			'{"formId":"1FaB_c-9","info":{"title":"Lunch"},"revisionId":"r1","items":[{"itemId":"i1","title":"Which day?","questionItem":{"question":{"questionId":"q1","choiceQuestion":{"type":"RADIO"}}}}]}',
			'{"formId":"f1","info":{"title":"Draft"}}',
		}
		local form = c.getForm({formId = "https://docs.google.com/forms/d/1FaB_c-9/edit#responses"})
		assert(form.items[1].questionItem.question.questionId == "q1" and form.revisionId == "r1")
		assert(requests[1].url == API .. "1FaB_c-9", requests[1].url)
		local empty = c.getForm({formId = "f1"})
		assert(json.encode(empty.items) == "[]" and requests[2].url == API .. "f1", requests[2].url)

		responses = {
			'{"responses":[{"responseId":"ACYD","lastSubmittedTime":"2026-10-20T09:00:00.123Z","answers":{"q1":{"questionId":"q1","textAnswers":{"answers":[{"value":"Tuesday"}]}}}}],"nextPageToken":"p2"}',
			'{}',
			'{"responseId":"ACYD","formId":"f1","answers":{}}',
		}
		local page = c.listResponses({formId = "https://docs.google.com/forms/u/1/d/f1/edit", filter = "timestamp > 2026-10-01T00:00:00Z", pageSize = 50})
		assert(page.responses[1].answers.q1.textAnswers.answers[1].value == "Tuesday" and page.nextPageToken == "p2")
		assert(requests[3].url == API .. "f1/responses?filter=timestamp%20%3E%202026-10-01T00%3A00%3A00Z&pageSize=50", requests[3].url)
		local none = c.listResponses({formId = "https://docs.google.com/a/example.com/forms/d/f1/edit", pageToken = "p2"})
		assert(json.encode(none.responses) == "[]" and requests[4].url == API .. "f1/responses?pageToken=p2", requests[4].url)
		assert(c.getResponse({formId = "f1", responseId = "ACYD"}).responseId == "ACYD")
		assert(requests[5].url == API .. "f1/responses/ACYD", requests[5].url)
		for _, req in requests do
			assert(req.method == "GET" and req.body == nil, req.method .. " " .. req.url)
			assert(req.headers == nil or req.headers.Authorization == nil, "connector set credentials")
		end

		local sent = #requests
		local invalid = {
			{},
			{formId = ""},
			{formId = ".."},
			{formId = "f/1"},
			{formId = "f1 x"},
			{formId = "https://docs.google.com/forms/d/e/1FAIpQLSc/viewform"},
			{formId = "https://forms.gle/abc123"},
			{formId = "https://docs.google.com.example.com/forms/d/f1/edit"},
			{formId = "https://example.com/?u=https://docs.google.com/forms/d/f1"},
			{formId = "https://docs.google.com/spreadsheets/d/s1/edit"},
			{formId = "https://docs.google.com/forms/#d/f1"},
			{formId = "https://docs.google.com/forms/d/f1.x/edit"},
			{formId = "f1", key = "api-key"},
			{formId = "f1", fields = "items"},
		}
		for _, args in invalid do
			assert(not pcall(c.getForm, args), "accepted " .. json.encode(args))
		end
		assert(not pcall(c.getForm, "f1"))
		assert(not pcall(c.getResponse, {formId = "f1"}), "getResponse requires responseId")
		assert(not pcall(c.getResponse, {formId = "f1", responseId = ".."}))
		assert(not pcall(c.getResponse, {formId = "f1", responseId = "a/b"}))
		assert(not pcall(c.listResponses, {formId = "f1", pageSize = 50, extra = true}))
		assert(not pcall(c.listResponses, {formId = "f1", filter = {key = "x"}}))
		assert(#requests == sent, "invalid input reached Google")
		assert(#responses == 0)
	end,
}
