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
		for _, name in {"setFlags", "moveMessages", "trashMessages", "createFolder"} do
			assert(c[name] == nil, "read-only leaked " .. name)
		end

		assert(not pcall(c.listMailFolders, "unexpected"))
		replies = {json.decode("[]")}
		assert(json.encode(c.listMailFolders()) == "[]", "empty folders must remain a JSON array")
		local fields = 0
		for _ in requests[1] do fields += 1 end
		assert(requests[1].command == "list" and fields == 1, "list takes no options")

		local opts = {folder = "Archive/2026", unread = true, maxResults = 20}
		replies = {{messages = json.decode("[]")}}
		assert(json.encode(c.listMessages(opts).messages) == "[]")
		local search = requests[2]
		assert(search.command == "search" and search.folder == "Archive/2026" and search.unread == true and search.maxResults == 20)
		assert(opts.command == nil, "the caller's options must not change")

		replies = {{{id = "7:42:INBOX", subject = "Hello"}}}
		assert(c.getMessage({id = "7:42:INBOX", maxBodyBytes = 0}).subject == "Hello")
		local fetch = requests[3]
		assert(fetch.command == "fetch" and fetch.id == nil and #fetch.ids == 1 and fetch.ids[1] == "7:42:INBOX" and fetch.maxBodyBytes == 0)
		assert(not pcall(c.getMessage, {}), "id is required")
		assert(not pcall(c.listMessages, "INBOX"), "options must be a table")
		assert(#requests == 3)

		replies = {{path = "files/report.pdf", size = 3, mimeType = "application/pdf", filename = "report.pdf"}}
		local saved = c.getAttachment({messageId = "7:42:INBOX", attachmentId = "2", path = "files/report.pdf"})
		local download = requests[4]
		assert(download.command == "download" and download.messageId == "7:42:INBOX" and download.attachmentId == "2" and download.path == "files/report.pdf")
		assert(saved.path == "files/report.pdf" and saved.url == "https://houston.test/files/report.pdf" and saved.size == 3, json.encode(saved))

		replies = {{{id = "7:42:INBOX", body = "<p>Hello</p>"}}, {{id = "7:42:INBOX", body = "Hello"}}}
		assert(c.getMessage({id = "7:42:INBOX", bodyFormat = "html"}).body == "<p>Hello</p>")
		assert(requests[5].bodyFormat == "html" and requests[5].command == "fetch")
		assert(c.getMessages({ids = {"7:42:INBOX"}, bodyFormat = "text"})[1].body == "Hello")
		assert(requests[6].bodyFormat == "text" and requests[6].ids[1] == "7:42:INBOX")
	end,
}
