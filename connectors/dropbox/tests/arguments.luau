return {
	scenario = {publisher = {client_id = "fixture-app-key", client_secret = "fixture-private-secret"}, auth_method = "oauth"},
	config = {access = "read-write"},
	configure = function()
		requests = {}
		http = {request = function(req)
			table.insert(requests, req)
			return fixture.operation({statusCode = 200, headers = {}, body = fixture.reader('{".tag":"async_job_id","async_job_id":"job"}')})
		end}
	end,
	run = function(c)
		for _, case in {
			{"getMetadata", {}}, {"listFolder", {}}, {"listFolderContinue", {cursor = false}},
			{"search", {query = 42}}, {"getAccount", {account_id = {}}},
			{"download", {session_path = "unused"}}, {"upload", {session_path = "unused"}},
			{"move", {from_path = "/a"}}, {"moveBatch", {entries = "bad"}},
			{"modifySharedLinkSettings", {url = "https://dropbox.com/s/a", settings = false}},
			{"updateFolderMember", {shared_folder_id = "1", member = true, access_level = "viewer"}},
			{"removeFolderMember", {shared_folder_id = "1", member = {['.tag'] = "email", email = "a@example.com"}}},
			{"getFileRequest", {id = json.null}}, {"createFileRequest", {title = "Uploads"}},
			{"deleteFileRequest", {ids = 4}}, {"listFolder", {"/a"}},
		} do
			assert(not pcall(c[case[1]], case[2]), "accepted invalid arguments for " .. case[1])
		end
		assert(#requests == 0, "invalid arguments reached Dropbox")
		-- False is a required value, and Dropbox union strings/objects and empty arrays survive encoding.
		c.removeFolderMember({shared_folder_id = "1", member = {['.tag'] = "email", email = "a@example.com"}, leave_a_copy = false})
		assert(json.decode(requests[1].body).leave_a_copy == false)
		c.updateFolderMember({shared_folder_id = "1", member = {['.tag'] = "dropbox_id", dropbox_id = "dbid:a"}, access_level = "viewer"})
		assert(json.decode(requests[2].body).access_level == "viewer")
		c.deleteFileRequest({ids = json.decode('[]')})
		assert(json.encode(json.decode(requests[3].body).ids) == "[]")
	end,
}
