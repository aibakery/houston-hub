return {
	scenario = {publisher = {client_id = "fixture-client", client_secret = "fixture-private-secret"}, config = {}, auth_method = "oauth", auth_config = {}, caller_access = "read-write"},
	config = {access = "custom"},
	configure = function()
		requests, responses = {}, {}
		http = {request = function(req)
			table.insert(requests, req)
			assert(#responses > 0, "unexpected request: " .. req.url)
			return fixture.operation({statusCode = 200, headers = {}, body = fixture.reader(table.remove(responses, 1))})
		end}
	end,
	run = function(c)
		local API = "https://gmail.googleapis.com/gmail/v1/users/me"
		local UPLOAD = "https://gmail.googleapis.com/upload/gmail/v1/users/me"
		local names = {}
		for name in c do table.insert(names, name) end
		table.sort(names)
		assert(table.concat(names, ",") == "createDraft,deleteDraft,getAttachment,getDraft,getLabel,getMessage,getMessages,getProfile,getThread,listDrafts,listHistory,listLabels,listMailFolders,listMessages,listSendAs,listThreads,updateDraft", "read and draft got " .. table.concat(names, ","))

		responses = {'{"id":"d1","message":{"id":"m1","threadId":"t1"}}'}
		assert(c.createDraft({to = "ana@example.com", subject = "Monday follow-up", text = "Hi Ana"}).id == "d1")
		local req = requests[#requests]
		assert(req.method == "POST" and req.url == UPLOAD .. "/drafts?uploadType=multipart", req.url)
		assert(string.find(req.body, "\r\nTo: ana@example.com\r\n", 1, true) and string.find(req.body, "\r\nSubject: Monday follow-up\r\n", 1, true), req.body)

		responses = {'{"id":"d1"}'}
		c.updateDraft({id = "d1", to = "ana@example.com", subject = "Monday follow-up", html = "<p>Hi Ana</p>"})
		req = requests[#requests]
		assert(req.method == "PUT" and req.url == UPLOAD .. "/drafts/d1?uploadType=multipart" and string.find(req.body, "text/html", 1, true), req.url)

		responses = {""}
		assert(c.deleteDraft({id = "d1"}).success == true)
		req = requests[#requests]
		assert(req.method == "DELETE" and req.url == API .. "/drafts/d1" and req.body == nil, req.url)
		assert(#requests == 3 and #responses == 0)
	end,
}
