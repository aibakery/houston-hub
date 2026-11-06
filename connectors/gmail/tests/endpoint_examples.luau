return {
	scenario = {publisher = {client_id = "fixture-client", client_secret = "fixture-private-secret"}, config = {}, auth_method = "oauth", auth_config = {}},
	config = {access = "read-write"},
	configure = function()
		requests, responses = {}, {}
		http = {request = function(req)
			table.insert(requests, req)
			assert(#responses > 0, "unexpected request: " .. req.url)
			local response = table.remove(responses, 1)
			return fixture.operation({statusCode = response.status or 200, headers = {}, body = fixture.reader(response.body or "")})
		end}
	end,
	run = function()
		local API = "https://gmail.googleapis.com/gmail/v1/users/me"
		local cases = {
			{name = "getProfile", method = "GET", path = "/profile", response = '{"emailAddress":"me@example.com","historyId":"9"}'},
			{name = "listLabels", method = "GET", path = "/labels", response = '{"labels":[{"id":"INBOX","name":"INBOX"}]}'},
			{name = "getLabel", method = "GET", path = "/labels/Label_1", response = '{"id":"Label_1","name":"Projects"}'},
			{name = "listThreads", method = "GET", path = "/threads?q=is%3Aunread&maxResults=10", response = '{"threads":[{"id":"t1"}]}'},
			{name = "listDrafts", method = "GET", path = "/drafts?maxResults=10", response = '{"drafts":[{"id":"d1"}]}'},
			{name = "listHistory", method = "GET", path = "/history?startHistoryId=9&historyTypes=messageAdded", response = '{"history":[{"id":"10"}],"historyId":"10"}'},
			{name = "listSendAs", method = "GET", path = "/settings/sendAs", response = '{"sendAs":[{"sendAsEmail":"me@example.com"}]}'},
			{name = "trashMessage", method = "POST", path = "/messages/m1/trash", response = '{"id":"m1","labelIds":["TRASH"]}'},
			{name = "untrashMessage", method = "POST", path = "/messages/m1/untrash", response = '{"id":"m1","labelIds":["INBOX"]}'},
			{name = "trashThread", method = "POST", path = "/threads/t1/trash", response = '{"id":"t1","messages":[{"id":"m1","labelIds":["TRASH"]}]}'},
			{name = "untrashThread", method = "POST", path = "/threads/t1/untrash", response = '{"id":"t1","messages":[{"id":"m1","labelIds":["INBOX"]}]}'},
			{name = "createLabel", method = "POST", path = "/labels", body = '{"labelListVisibility":"labelShow","messageListVisibility":"show","name":"Projects/Release"}', response = '{"id":"Label_1","name":"Projects/Release"}'},
			{name = "updateLabel", method = "PATCH", path = "/labels/Label_1", body = '{"name":"Projects/Archive"}', response = '{"id":"Label_1","name":"Projects/Archive"}'},
			{name = "deleteLabel", method = "DELETE", path = "/labels/Label_1", status = 204},
		}
		for _, case in cases do
			responses = {{body = case.response, status = case.status}}
			fixture.example(case.name)
			local req = requests[#requests]
			assert(req.method == case.method and req.url == API .. case.path, case.name .. ": " .. req.method .. " " .. req.url)
			assert(req.body == case.body, case.name .. ": " .. tostring(req.body))
		end
		assert(#responses == 0 and #requests == #cases)
	end,
}
