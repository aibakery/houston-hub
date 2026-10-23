return {
	scenario = {publisher = {client_id = "fixture-app-key", client_secret = "fixture-private-secret"}, auth_method = "oauth", granted_scopes = {"account_info.read", "files.metadata.read", "files.content.read", "sharing.read", "file_requests.read", "files.content.write", "sharing.write", "file_requests.write"}},
	config = {access = "read-write"},
	configure = function()
		requests, responses = {}, {}
		fs = fixture.files()
		http = {request = function(req)
			for name in req.headers or {} do assert(string.lower(name) ~= "authorization", "credentials belong to the proxy") end
			table.insert(requests, req)
			if req.body ~= nil and type(req.body) ~= "string" then
				local captured = fs.open("captured-upload", "w")
				captured:write(req.body)
				await(captured:close())
				local input = fs.open("captured-upload", "r")
				req.body = await(input:readAll())
				await(input:close())
			end
			assert(#responses > 0, "unexpected request: " .. req.url)
			local response = table.remove(responses, 1)
			return fixture.operation({statusCode = response.status or 200, headers = response.headers or {}, body = fixture.reader(response.body or "")})
		end}
	end,
	run = function(c)
		local API = "https://api.dropboxapi.com/2/"
		local expected = {}
		for _, name in {
			"getCurrentAccount", "getSpaceUsage", "getAccount", "getMetadata",
			"listFolder", "listFolderContinue", "listFolderGetLatestCursor", "search",
			"searchContinue", "listRevisions", "getTemporaryLink", "download",
			"downloadZip", "export", "getPreview", "getThumbnail",
			"createFolder", "upload", "saveUrl", "saveUrlCheckJobStatus",
			"move", "copy", "delete", "restore",
			"moveBatch", "moveBatchCheck", "copyBatch", "copyBatchCheck",
			"deleteBatch", "deleteBatchCheck", "listSharedLinks", "getSharedLinkMetadata",
			"getSharedLinkFile", "createSharedLinkWithSettings", "modifySharedLinkSettings", "revokeSharedLink",
			"listSharedFolders", "listSharedFoldersContinue", "listMountableFolders", "listMountableFoldersContinue",
			"getSharedFolderMetadata", "listFolderMembers", "listFolderMembersContinue", "shareFolder",
			"checkShareJobStatus", "addFolderMember", "updateFolderMember", "removeFolderMember",
			"checkRemoveMemberJobStatus", "unshareFolder", "checkJobStatus", "mountFolder",
			"unmountFolder", "relinquishFolderMembership", "listReceivedFiles", "listReceivedFilesContinue",
			"getSharedFileMetadata", "listFileMembers", "listFileMembersContinue", "addFileMember",
			"removeFileMember", "unshareFile", "relinquishFileMembership", "listFileRequests",
			"listFileRequestsContinue", "getFileRequest", "createFileRequest", "updateFileRequest",
			"deleteFileRequest", "statFile",
		} do
			expected[name] = true
			assert(type(c[name]) == "function", "read-write lacks " .. name)
		end
		for name in c do assert(name == "help" or expected[name], "read-write exposes " .. name) end

		-- Uploads stream the session file with the arguments in Dropbox-API-Arg.
		local bytes = string.char(0, 255) .. "report"
		local input = fs.open("uploads/report.pdf", "w")
		input:write(bytes)
		await(input:close())
		responses = {{body = '{"id":"id:up","name":"report.pdf","rev":"015f"}'}}
		local uploaded = c.upload({path = "/Reports/report.pdf", mode = "overwrite", session_path = "uploads/report.pdf"})
		local req = requests[1]
		assert(uploaded.id == "id:up")
		assert(req.method == "POST" and req.url == "https://content.dropboxapi.com/2/files/upload" and req.body == bytes)
		assert(req.headers["Content-Type"][1] == "application/octet-stream")
		local arg = json.decode(req.headers["Dropbox-API-Arg"][1])
		assert(arg.path == "/Reports/report.pdf" and arg.mode == "overwrite" and arg.session_path == nil)
		assert(not pcall(c.upload, {path = "/Reports/report.pdf"}), "upload requires a session_path")
		assert(not pcall(c.upload, {path = "/Reports", session_path = "uploads"}), "uploaded a directory")
		assert(#requests == 1)

		-- Writes post Dropbox's arguments unchanged, including nested unions and arrays.
		responses = {{body = '{".tag":"async_job_id","async_job_id":"job-1"}'}, {body = '{".tag":"complete","entries":[]}'}}
		local job = c.moveBatch({entries = {{from_path = "/a", to_path = "/b/a"}}, autorename = true})
		assert(requests[2].url == API .. "files/move_batch_v2" and job.async_job_id == "job-1")
		local sent = json.decode(requests[2].body)
		assert(sent.entries[1].from_path == "/a" and sent.entries[1].to_path == "/b/a" and sent.autorename == true)
		local status = c.moveBatchCheck({async_job_id = "job-1"})
		assert(requests[3].url == API .. "files/move_batch/check_v2" and status[".tag"] == "complete" and json.encode(status.entries) == "[]")

		-- A null result is a success; a list result stays a list.
		responses = {{body = "null"}, {body = '[{"member":{".tag":"email","email":"bo@example.com"},"result":{".tag":"success"}}]'}}
		assert(c.revokeSharedLink({url = "https://www.dropbox.com/s/abc/a.txt"}).success == true)
		assert(requests[4].url == API .. "sharing/revoke_shared_link")
		local added = c.addFileMember({file = "id:a", members = {{[".tag"] = "email", email = "bo@example.com"}}, quiet = true})
		assert(added[1].result[".tag"] == "success" and added[1].member.email == "bo@example.com")
		sent = json.decode(requests[5].body)
		assert(sent.members[1][".tag"] == "email" and sent.quiet == true)

		responses = {{status = 409, body = '{"error_summary":"shared_link_already_exists/..","error":{".tag":"shared_link_already_exists"}}'}}
		local ok, err = pcall(c.createSharedLinkWithSettings, {path = "/a.txt"})
		assert(not ok and string.find(tostring(err), "shared_link_already_exists", 1, true), tostring(err))
		-- Dropbox asks callers to retry contended writes.
		responses = {{status = 409, body = '{"error_summary":"path/too_many_write_operations/.."}'}}
		ok, err = pcall(c.move, {from_path = "/a", to_path = "/b"})
		assert(not ok and string.find(tostring(err), '"retryable":true', 1, true), tostring(err))
		assert(#responses == 0)
	end,
}
