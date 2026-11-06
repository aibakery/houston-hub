-- Read-only connections expose only reads; each forwards one native command.
return {
	scenario = {publisher = {}, auth_method = "", auth_config = {}, config = {host = "imap.example.com", username = "ada@example.com", password = "fixture-password"}},
	config = {access = "read-only"},
	configure = function()
		requests, replies = {}, {}
		fs = fixture.files()
		imap = {command = function(request)
			table.insert(requests, request)
			assert(#replies > 0, "unexpected command " .. tostring(request.command))
			return fixture.operation(table.remove(replies, 1))
		end}
	end,
	run = function(c)
		for _, name in {"setFlags", "moveMessages", "trashMessages", "createFolder", "createDraft", "updateDraft", "deleteDraft"} do
			assert(c[name] == nil, "read-only leaked " .. name)
		end

		assert(not pcall(c.listMailFolders, "unexpected"))
		assert(not pcall(c.listMailFolders, {folder = "INBOX"}), "list takes no options")
		assert(not pcall(c.listMailFolders, {}, "Archive"), "list takes one argument at most")
		assert(#requests == 0, "rejected calls never reach the server")
		replies = {json.decode("[]")}
		assert(json.encode(c.listMailFolders()) == "[]", "empty folders must remain a JSON array")
		local fields = 0
		for _ in requests[1] do fields += 1 end
		assert(requests[1].command == "list" and fields == 1, "list takes no options")
		replies = {{{id = "INBOX", name = "INBOX", role = "inbox"}, {id = "INBOX/Receipts", name = "Receipts", parentId = "INBOX"}}}
		local folders = c.listMailFolders({})
		assert(#folders == 2 and folders[1].role == "inbox" and folders[2].parentId == "INBOX", json.encode(folders))
		assert(requests[2].command == "list")

		local opts = {folder = "Archive/2026", unread = true, maxResults = 20}
		replies = {{messages = json.decode("[]")}, {messages = {{id = "7:43:INBOX"}, {id = "7:42:INBOX"}}, nextPageToken = "7:42:INBOX"}}
		assert(json.encode(c.listMessages(opts).messages) == "[]")
		local search = requests[3]
		assert(search.command == "search" and search.folder == "Archive/2026" and search.unread == true and search.maxResults == 20)
		assert(opts.command == nil, "the caller's options must not change")
		local page = c.listMessages({unread = true, maxResults = 2, pageToken = "7:44:INBOX"})
		assert(#page.messages == 2 and page.messages[1].id == "7:43:INBOX" and page.nextPageToken == "7:42:INBOX", json.encode(page))
		assert(requests[4].command == "search" and requests[4].pageToken == "7:44:INBOX" and requests[4].unread == true)

		replies = {{{id = "7:42:INBOX", subject = "Hello"}}}
		assert(c.getMessage({id = "7:42:INBOX", maxBodyBytes = 0}).subject == "Hello")
		local fetch = requests[5]
		assert(fetch.command == "fetch" and fetch.id == nil and #fetch.ids == 1 and fetch.ids[1] == "7:42:INBOX" and fetch.maxBodyBytes == 0)
		assert(not pcall(c.getMessage, {}), "id is required")
		assert(not pcall(c.getMessage, {id = "7:42:INBOX", ids = {"7:43:INBOX"}}), "getMessage takes one id")
		assert(not pcall(c.listMessages, "INBOX"), "options must be a table")
		assert(#requests == 5, "rejected calls never reach the server")

		replies = {{path = "files/report.pdf", size = 3, mimeType = "application/pdf", filename = "report.pdf"}}
		local saved = c.getAttachment({messageId = "7:42:INBOX", attachmentId = "2", path = "files/report.pdf"})
		local download = requests[6]
		assert(download.command == "download" and download.messageId == "7:42:INBOX" and download.attachmentId == "2" and download.path == "files/report.pdf")
		assert(saved.path == "files/report.pdf" and saved.url == "https://houston.test/files/report.pdf" and saved.size == 3, json.encode(saved))

		replies = {{{id = "7:42:INBOX", body = "<p>Hello</p>"}}, {{id = "7:42:INBOX", body = "Hello"}}}
		assert(c.getMessage({id = "7:42:INBOX", bodyFormat = "html"}).body == "<p>Hello</p>")
		assert(requests[7].bodyFormat == "html" and requests[7].command == "fetch")
		assert(c.getMessages({ids = {"7:42:INBOX"}, bodyFormat = "text"})[1].body == "Hello")
		assert(requests[8].bodyFormat == "text" and requests[8].ids[1] == "7:42:INBOX")
		assert(#requests == 8)
	end,
}
