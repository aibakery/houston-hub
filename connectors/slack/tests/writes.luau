return {
	scenario = {publisher = {client_id = "fixture-client", client_secret = "fixture-private-secret"}, config = {}, auth_method = "oauth", auth_config = {}},
	config = {access = "read-write"},
	configure = function()
		requests, responses = {}, {}
		fs = fixture.files()
		local upload = fs.open("reports/q3.txt", "w")
		upload:write("hello slack")
		await(upload:close())
		await(fs.open("reports/empty.txt", "w"):close())
		http = {request = function(req)
			if req.body ~= nil and type(req.body) ~= "string" then req.wire = await(req.body:readAll()) end
			table.insert(requests, req)
			assert(#responses > 0, "unexpected request: " .. req.url)
			local response = table.remove(responses, 1)
			if type(response) == "string" then response = {body = response} end
			return fixture.operation({statusCode = response.status or 200, headers = {}, body = fixture.reader(response.body)})
		end}
		function sent(index)
			local req = requests[index]
			assert(req.method == "POST" and req.headers["Content-Type"][1] == "application/json; charset=utf-8")
			assert(req.headers.Authorization == nil, "credentials stay in the proxy")
			return json.decode(req.body)
		end
	end,
	run = function(slack)
		for _, name in {"postMessage", "reply", "updateMessage", "deleteMessage", "openConversation", "addReaction", "removeReaction", "uploadFile"} do
			assert(type(slack[name]) == "function", name .. " is exported with read-write access")
		end

		local opts = {blocks = {{type = "section", text = {type = "mrkdwn", text = "*Hi*"}}}, unfurl_links = false}
		responses = {'{"ok":true,"channel":"C1","ts":"1.000002","message":{"text":"Hello"}}'}
		assert(slack.reply("C1", "1.000001", "Hello", opts).ts == "1.000002")
		local body = sent(1)
		assert(requests[1].url == "https://slack.com/api/chat.postMessage")
		assert(body.channel == "C1" and body.thread_ts == "1.000001" and body.text == "Hello" and body.unfurl_links == false)
		assert(body.blocks[1].text.text == "*Hi*" and opts.channel == nil and opts.text == nil, "options are not mutated")

		responses = {'{"ok":true,"channel":"C1","ts":"1.000003"}', '{"ok":true,"channel":"C1","ts":"1.000003","text":"Edited"}',
			'{"ok":true,"channel":"C1","ts":"1.000003"}', '{"ok":true,"channel":{"id":"G1"}}', '{"ok":true}', '{"ok":true}'}
		slack.postMessage("C1", "Hi")
		body = sent(2)
		assert(requests[2].url == "https://slack.com/api/chat.postMessage" and body.channel == "C1" and body.text == "Hi" and body.thread_ts == nil)
		slack.updateMessage("C1", "1.000003", "Edited")
		body = sent(3)
		assert(requests[3].url == "https://slack.com/api/chat.update" and body.ts == "1.000003" and body.text == "Edited")
		slack.deleteMessage("C1", "1.000003")
		assert(requests[4].url == "https://slack.com/api/chat.delete" and sent(4).ts == "1.000003")
		assert(slack.openConversation({"U1", "U2"}).id == "G1")
		assert(requests[5].url == "https://slack.com/api/conversations.open" and sent(5).users == "U1,U2")
		slack.addReaction("C1", "1.000003", "thumbsup")
		body = sent(6)
		assert(requests[6].url == "https://slack.com/api/reactions.add" and body.timestamp == "1.000003" and body.name == "thumbsup")
		slack.removeReaction("C1", "1.000003", "thumbsup")
		assert(requests[7].url == "https://slack.com/api/reactions.remove" and sent(7).name == "thumbsup")

		responses = {'{"ok":true,"upload_url":"https://files.slack.com/upload/v1/signed","file_id":"F1"}', "OK - 11",
			'{"ok":true,"files":[{"id":"F1","title":"Q3"}]}'}
		local uploaded = slack.uploadFile("reports/q3.txt", {channel = "C1", thread_ts = "1.000001", text = "Q3 numbers", title = "Q3", alt_text = "Report"})
		assert(uploaded.files[1].id == "F1")
		assert(requests[8].method == "POST" and requests[8].url == "https://slack.com/api/files.getUploadURLExternal")
		assert(requests[8].headers["Content-Type"][1] == "application/x-www-form-urlencoded")
		assert(requests[8].body == "alt_txt=Report&filename=q3.txt&length=11")
		assert(requests[9].url == "https://files.slack.com/upload/v1/signed" and requests[9].wire == "hello slack")
		assert(requests[9].headers["Content-Type"][1] == "application/octet-stream" and requests[9].headers.Authorization == nil)
		body = sent(10)
		assert(requests[10].url == "https://slack.com/api/files.completeUploadExternal")
		assert(body.files[1].id == "F1" and body.files[1].title == "Q3" and body.channel_id == "C1"
			and body.thread_ts == "1.000001" and body.initial_comment == "Q3 numbers")

		responses = {'{"ok":true,"upload_url":"https://files.slack.com/upload/v1/private","file_id":"F2"}', "OK", '{"ok":true,"files":[{"id":"F2"}]}'}
		slack.uploadFile("reports/q3.txt")
		assert(requests[11].body == "filename=q3.txt&length=11")
		body = sent(13)
		assert(body.files[1].title == "q3.txt" and body.channel_id == nil, "an unshared upload stays private")

		responses = {'{"ok":true,"upload_url":"https://files.slack.com/upload/v1/expired","file_id":"F3"}', {status = 404, body = "Not Found"}}
		local ok, err = pcall(slack.uploadFile, "reports/q3.txt", {channel = "C1"})
		assert(not ok and string.find(tostring(err), "slack: HTTP 404", 1, true) and #requests == 15, "a failed upload is not completed")
		responses = {'{"ok":true,"upload_url":"https://files.slack.com/upload/v1/signed","file_id":"F4"}', "OK", '{"ok":false,"error":"channel_not_found"}'}
		ok, err = pcall(slack.uploadFile, "reports/q3.txt", {channel = "C404"})
		assert(not ok and string.find(tostring(err), "slack: channel_not_found", 1, true) and #requests == 18)

		local before = #requests
		for _, case in {
			{function() slack.postMessage("C1", "Hi", {username = "someone-else"}) end, "unknown option username"},
			{function() slack.postMessage("C1", "Hi", {icon_url = "https://example.com/a.png"}) end, "unknown option icon_url"},
			{function() slack.reply("C1", "1.0", "Hi", {thread_ts = "2.0"}) end, "unknown option thread_ts"},
			{function() slack.postMessage("C1", "") end, "message text must be"},
			{function() slack.openConversation({"U1", ""}) end, "user ID 2 must be"},
			{function() slack.uploadFile("reports/q3.txt", {channel = 5}) end, "channel must be"},
			{function() slack.uploadFile("missing.txt") end, "not_found"},
			{function() slack.uploadFile("reports/empty.txt") end, "nonempty session file"},
			{function() slack.uploadFile("reports/q3.txt", {thread_ts = "1.0"}) end, "need channel"},
			{function() slack.uploadFile("reports/q3.txt", {text = "hi"}) end, "need channel"},
			{function() slack.postMessage("C1", "Hi", {thread_ts = 1790000000.00001}) end, "thread_ts must be"},
		} do
			local ok, err = pcall(case[1])
			local message = if type(err) == "table" then json.encode(err) else tostring(err)
			assert(not ok and string.find(message, case[2], 1, true), message)
		end
		assert(#requests == before and #responses == 0, "invalid input reached Slack")
	end,
}
