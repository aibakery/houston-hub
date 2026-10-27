local function encoded(value)
	return require("lib/base64.luau").encode(value)
end

return {
	scenario = {publisher = {client_id = "fixture-client", client_secret = "fixture-private-secret"}, config = {}, auth_method = "oauth", auth_config = {}},
	config = {access = "read-only"},
	configure = function()
		requests, responses = {}, {}
		http = {request = function(req)
			table.insert(requests, req)
			assert(#responses > 0, "unexpected request: " .. req.url)
			return fixture.operation({statusCode = 200, headers = {}, body = fixture.reader(json.encode(table.remove(responses, 1)))})
		end}
	end,
	run = function(c)
		local function raw(plain, html)
			local parts = {}
			if plain ~= nil then table.insert(parts, {mimeType = "text/plain", body = {data = encoded(plain)}}) end
			if html ~= nil then table.insert(parts, {mimeType = "text/html", body = {data = encoded(html)}}) end
			return {id = "newsletter", snippet = "Preview", payload = {mimeType = "multipart/alternative", parts = parts}}
		end
		for _, case in {
			{plain = "\r\n", html = "<p>Newsletter</p>", want = "<p>Newsletter</p>"},
			{plain = " \t\r\n", html = "<p>Newsletter</p>", format = "auto", want = "<p>Newsletter</p>"},
			{plain = "", html = "<p>Newsletter</p>", want = "<p>Newsletter</p>"},
			{plain = utf8.char(0xA0, 0x2003), html = "<p>Newsletter</p>", want = "<p>Newsletter</p>"},
			{plain = "  Text\n", html = "<p>Newsletter</p>", want = "  Text\n"},
			{plain = "Text", html = "  <p>HTML</p>\n", format = "html", want = "  <p>HTML</p>\n"},
			{plain = "\r\n", html = "<p>Newsletter</p>", format = "text", want = "\r\n"},
			{html = "<p>Newsletter</p>", format = "text", want = ""},
			{plain = "Text", format = "html", want = ""},
			{plain = " \n", html = "\r\n", want = "Preview"},
			{plain = "   Text", html = "<p>HTML</p>", limit = 2, want = "  ", truncated = true},
			{plain = "\r\n", html = "<p>HTML</p>", limit = 4, want = "<p>H", truncated = true},
		} do
			responses = {raw(case.plain, case.html)}
			local m = c.getMessage({id = "newsletter", bodyFormat = case.format, maxBodyBytes = case.limit})
			assert(m.body == case.want, "body mismatch: " .. json.encode(m.body))
			assert(m.bodyTruncated == (case.truncated == true), "selected body truncation")
			assert(requests[#requests].url == "https://gmail.googleapis.com/gmail/v1/users/me/messages/newsletter?format=full")
		end

		local full = raw("Plain", "<p>HTML</p>")
		responses = {full, {id = "thread", messages = {full}}, {id = "draft", message = full}}
		assert(c.getMessages({ids = {"newsletter"}, bodyFormat = "html"})[1].body == "<p>HTML</p>")
		assert(c.getThread({id = "thread", bodyFormat = "html"}).messages[1].body == "<p>HTML</p>")
		assert(c.getDraft({id = "draft", bodyFormat = "html"}).message.body == "<p>HTML</p>")
		responses = {{id = "newsletter", snippet = "Preview"}}
		assert(c.getMessage({id = "newsletter", format = "metadata", bodyFormat = "html"}).body == "")

		full = raw("\r\n", nil)
		table.insert(full.payload.parts, {mimeType = "text/plain", body = {data = encoded("Later text")}})
		responses = {full}
		assert(c.getMessage({id = "newsletter"}).body == "Later text")
		full = raw("\r\n", nil)
		table.insert(full.payload.parts, {mimeType = "text/html", body = {attachmentId = "body1", size = 100}})
		responses = {full, {data = encoded("<p>External HTML</p>")}}
		local external = c.getMessage({id = "newsletter"})
		assert(external.body == "<p>External HTML</p>" and #external.attachments == 0)
		assert(requests[#requests].url == "https://gmail.googleapis.com/gmail/v1/users/me/messages/newsletter/attachments/body1")
		full.payload.parts[2].body.data = ""
		for _, format in {"auto", "html"} do
			responses = {full, {data = encoded("<p>External HTML</p>")}}
			assert(c.getMessage({id = "newsletter", bodyFormat = format}).body == "<p>External HTML</p>")
		end
		responses = {full}
		assert(c.getMessage({id = "newsletter", bodyFormat = "text"}).body == "\r\n")
		assert(#responses == 0)
		for _, format in {"", "markdown", false, 3} do
			local count = #requests
			assert(not pcall(c.getMessage, {id = "newsletter", bodyFormat = format}))
			assert(not pcall(c.getMessages, {ids = {"newsletter"}, bodyFormat = format}))
			assert(not pcall(c.getThread, {id = "thread", bodyFormat = format}))
			assert(not pcall(c.getDraft, {id = "draft", bodyFormat = format}))
			assert(#requests == count, "invalid body format reached Google")
		end
	end,
}
