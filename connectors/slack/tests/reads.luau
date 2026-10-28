return {
	scenario = {publisher = {client_id = "fixture-client", client_secret = "fixture-private-secret"}, config = {}, auth_method = "oauth", auth_config = {}},
	config = {access = "read-only"},
	configure = function()
		requests, responses = {}, {}
		fs = fixture.files()
		http = {request = function(req)
			table.insert(requests, req)
			assert(#responses > 0, "unexpected request: " .. req.url)
			local response = table.remove(responses, 1)
			if type(response) == "string" then response = {body = response} end
			return fixture.operation({statusCode = response.status or 200, headers = response.headers or {}, body = fixture.reader(response.body)})
		end}
		function last() return requests[#requests].url end
		function rejected(fn, ...)
			local before = #requests
			local ok, err = pcall(fn, ...)
			assert(not ok and #requests == before, "invalid input reached Slack")
			return tostring(err)
		end
	end,
	run = function(slack)
		responses = {'{"ok":true,"messages":[{"ts":"1790000000.000001","text":"hi"}],"has_more":true,"response_metadata":{"next_cursor":"bmV4dA=="}}'}
		local history = slack.listMessages("C1", {oldest = "1780000000.000000"})
		assert(history.messages[1].ts == "1790000000.000001" and history.has_more and history.nextCursor == "bmV4dA==")
		assert(last() == "https://slack.com/api/conversations.history?channel=C1&limit=15&oldest=1780000000.000000")

		local opts = {cursor = "next+one", limit = 5}
		responses = {'{"ok":true,"messages":[],"has_more":false}'}
		local thread = slack.getThread("C1", "1790000000.000001", opts)
		assert(json.encode(thread.messages) == "[]" and thread.nextCursor == nil)
		assert(last() == "https://slack.com/api/conversations.replies?channel=C1&cursor=next%2Bone&limit=5&ts=1790000000.000001")
		assert(opts.channel == nil and opts.ts == nil, "options are not mutated")

		responses = {'{"ok":true,"messages":{"matches":[{"text":"hi"}],"total":3,"paging":{"page":1,"pages":3}}}'}
		local found = slack.searchMessages("in:#general hello", {count = 1})
		assert(found.total == 3 and found.nextPage == 2)
		assert(last() == "https://slack.com/api/search.messages?count=1&query=in%3A%23general%20hello&sort=timestamp&sort_dir=desc")

		responses = {'{"ok":true,"user_id":"U1"}', '{"ok":true,"messages":{"matches":[],"total":0,"paging":{"page":1,"pages":1}}}'}
		local mentions = slack.listMentions({query = "in:#general", page = 1})
		assert(json.encode(mentions.matches) == "[]" and mentions.nextPage == nil)
		assert(requests[#requests - 1].url == "https://slack.com/api/auth.test")
		assert(last() == "https://slack.com/api/search.messages?page=1&query=%3C%40U1%3E%20in%3A%23general&sort=timestamp&sort_dir=desc")

		responses = {'{"ok":true,"channel":{"id":"C1","name":"general"}}', '{"ok":true,"user":{"id":"U1"}}',
			'{"ok":true,"permalink":"https://acme.slack.com/archives/C1/p1"}', '{"ok":true,"members":["U1","U2"]}',
			'{"ok":true,"members":[{"id":"U1"}],"response_metadata":{"next_cursor":"dXNlcjpVMg=="}}', '{"ok":true,"members":[]}'}
		assert(slack.getChannel("C1").name == "general" and last() == "https://slack.com/api/conversations.info?channel=C1")
		assert(slack.getUser("U1").id == "U1" and last() == "https://slack.com/api/users.info?user=U1")
		assert(slack.getPermalink("C1", "1.2") == "https://acme.slack.com/archives/C1/p1")
		assert(last() == "https://slack.com/api/chat.getPermalink?channel=C1&message_ts=1.2")
		assert(#slack.listMembers("C1", {limit = 2}).members == 2 and last() == "https://slack.com/api/conversations.members?channel=C1&limit=2")
		local users = slack.listUsers()
		assert(users.members[1].id == "U1" and users.nextCursor == "dXNlcjpVMg==" and last() == "https://slack.com/api/users.list?limit=200")
		assert(json.encode(slack.listMembers("C2").members) == "[]" and last() == "https://slack.com/api/conversations.members?channel=C2")

		local file = '{"ok":true,"file":{"id":"F1","mimetype":"application/pdf","url_private_download":"https://files.slack.com/files-pri/T1-F1/download/report.pdf"}}'
		responses = {file, {body = "%PDF bytes", headers = {["content-type"] = {"application/pdf"}}}}
		local saved = slack.downloadFile("F1", "report.pdf")
		assert(requests[#requests - 1].url == "https://slack.com/api/files.info?file=F1")
		assert(last() == "https://files.slack.com/files-pri/T1-F1/download/report.pdf" and requests[#requests].headers == nil)
		assert(saved.path == "report.pdf" and saved.url == "https://houston.test/report.pdf" and saved.bytes == 10)
		local saved_file = fs.open("report.pdf", "r")
		assert(await(saved_file:readAll()) == "%PDF bytes")
		await(saved_file:close())

		responses = {file, {body = "<html>Sign in</html>", headers = {["content-type"] = {"text/html; charset=utf-8"}}}}
		local ok, err = pcall(slack.downloadFile, "F1", "signin.pdf")
		assert(not ok and string.find(tostring(err), "sign-in page", 1, true) and string.find(tostring(err), '"upstream_status":401', 1, true))
		local partial = fs.open("signin.pdf", "r")
		assert(await(partial:readAll()) == "", "a sign-in page was saved as the file")
		await(partial:close())

		responses = {file, {status = 403, body = "Forbidden"}}
		ok, err = pcall(slack.downloadFile, "F1", "denied.pdf")
		assert(not ok and string.find(tostring(err), "slack: HTTP 403", 1, true) and string.find(tostring(err), '"upstream_status":403', 1, true))

		assert(string.find(rejected(slack.getThread, "C1", 1790000000.000001), "thread timestamp must be", 1, true))
		assert(string.find(rejected(slack.listMessages, "", nil), "channel ID must be", 1, true))
		assert(string.find(rejected(slack.listMessages, "C1", {limit = {1}}), "limit must be", 1, true))
		assert(string.find(rejected(slack.listMessages, "C1", {latest = 1790000000.00001}), "latest must be", 1, true))
		assert(string.find(rejected(slack.listChannels, {cursor = ""}), "cursor must be", 1, true))
		assert(string.find(rejected(slack.searchMessages, "x", {query = "y"}), "unknown option query", 1, true))
		assert(string.find(rejected(slack.listMentions, {query = 7}), "query must be", 1, true))
		assert(string.find(rejected(slack.downloadFile, "F1", ""), "session path must be", 1, true))
		assert(#responses == 0)
	end,
}
