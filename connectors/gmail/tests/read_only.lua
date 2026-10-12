return {
	scenario = {publisher = {client_id = "fixture-client", client_secret = "fixture-private-secret"}, config = {}, auth_method = "oauth", auth_config = {}},
	config = {access = "read-only"},
	configure = function()
		http = {request = function(req)
			assert(req.url == "https://gmail.googleapis.com/gmail/v1/users/me/labels", req.url)
			return fixture.operation({statusCode = 200, headers = {}, body = fixture.reader('{"labels":[]}')})
		end}
	end,
	run = function(c)
		for _, name in {"sendMessage", "createDraft", "updateDraft", "sendDraft", "deleteDraft", "modifyMessage", "batchModifyMessages", "trashMessage", "untrashMessage", "modifyThread", "trashThread", "untrashThread", "createLabel", "updateLabel", "deleteLabel"} do
			assert(c[name] == nil, "read-only leaked " .. name)
		end
		for _, name in {"getProfile", "listLabels", "listMessages", "listThreads", "listDrafts", "listHistory", "listSendAs", "getMessage", "getMessages", "getThread", "getDraft", "getAttachment", "listMailFolders"} do
			assert(type(c[name]) == "function", "missing " .. name)
		end
		assert(not pcall(c.listMailFolders, "unexpected"))
		local folders = c.listMailFolders()
		assert(json.encode(folders) == "[]", "empty folders must remain a JSON array")
	end,
}
