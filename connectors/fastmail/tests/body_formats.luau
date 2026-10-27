return {
	scenario = {auth_config = {token = "fixture-private-token"}, auth_method = "token", config = {}, publisher = {}},
	config = {access = "read-only"},
	configure = function()
		requests, messages = {}, {}
		http = {request = function(req)
			table.insert(requests, req)
			local data
			if req.method == "GET" then
				local mail = "urn:ietf:params:jmap:mail"
				data = {primaryAccounts = {[mail] = "u1"}, accounts = {u1 = {}}, capabilities = {[mail] = {}}, apiUrl = "https://api.fastmail.com/jmap/api/"}
			else
				local call = json.decode(req.body).methodCalls[1]
				data = {methodResponses = {{call[1], {list = if call[1] == "Thread/get" then {{id = "t1", emailIds = {"m1"}}} else messages}, call[3]}}}
			end
			return fixture.operation({statusCode = 200, headers = {}, body = fixture.reader(json.encode(data))})
		end}
	end,
	run = function(c)
		local function raw(plain, html, truncated)
			return {id = "m1", preview = "Preview", textBody = {{partId = "p", type = "text/plain"}}, htmlBody = {{partId = "h", type = "text/html"}},
				bodyValues = {p = if plain ~= nil then {value = plain, isTruncated = truncated == true} else nil, h = if html ~= nil then {value = html} else nil}}
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
			{plain = "  ", html = "<p>HTML</p>", truncated = true, want = "  ", wantTruncated = true},
			{plain = "Text", html = "<p>HTML</p>", truncated = true, format = "html", want = "<p>HTML</p>"},
		} do
			messages = {raw(case.plain, case.html, case.truncated)}
			local m = c.getMessage({id = "m1", bodyFormat = case.format})
			assert(m.body == case.want, "body mismatch: " .. json.encode(m.body))
			assert(m.bodyTruncated == (case.wantTruncated == true), "selected body truncation")
			local args = json.decode(requests[#requests].body).methodCalls[1][2]
			assert(args.fetchTextBodyValues == (case.format ~= "html") and args.fetchHTMLBodyValues == (case.format ~= "text"))
		end
		messages = {raw("Plain", "<p>HTML</p>")}
		assert(c.getMessages({ids = {"m1"}, bodyFormat = "html"})[1].body == "<p>HTML</p>")
		assert(c.getThread({id = "t1", bodyFormat = "html"}).messages[1].body == "<p>HTML</p>")
		assert(c.getMessage("m1", {bodyFormat = "html"}).body == "<p>HTML</p>")
		assert(c.getMessages({"m1"}, {bodyFormat = "html"})[1].body == "<p>HTML</p>")
		messages[1].textBody = {{partId = "h", type = "text/html"}}
		assert(c.getMessage({id = "m1", bodyFormat = "text"}).body == "", "JMAP textBody can contain HTML")
		assert(c.getMessage({id = "m1"}).body == "<p>HTML</p>")
		messages[1].htmlBody = {{partId = "p", type = "text/plain"}, {partId = "h", type = "text/html"}}
		assert(c.getMessage({id = "m1", bodyFormat = "html"}).body == "<p>HTML</p>")
		messages[1].textBody = messages[1].htmlBody
		assert(c.getMessage({id = "m1"}).body == "Plain\n<p>HTML</p>", "automatic rendering must retain mixed body parts")
		for _, format in {"", "markdown", false, 3} do
			local count = #requests
			assert(not pcall(c.getMessage, {id = "m1", bodyFormat = format}))
			assert(not pcall(c.getMessages, {ids = {"m1"}, bodyFormat = format}))
			assert(not pcall(c.getThread, {id = "t1", bodyFormat = format}))
			assert(#requests == count, "invalid body format reached Fastmail")
		end
	end,
}
