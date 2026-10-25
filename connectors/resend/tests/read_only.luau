return {
	scenario = {publisher = {}, config = {}, auth_method = "api_key", auth_config = {token = "re_fixture"}},
	configure = function()
		requests = {}
		payload = '{"object":"list","has_more":false,"data":[]}'
		cdn = ""
		fs = fixture.files()
		http = {request = function(req)
			table.insert(requests, req)
			local body = if string.find(req.url, "^https://api%.resend%.com/") then payload else cdn
			return fixture.operation({statusCode = 200, headers = {}, body = fixture.reader(body)})
		end}
	end,
	run = function(resend)
		local API = "https://api.resend.com"
		local NULL = json.decode("null")
		local function last() return requests[#requests] end
		local function rejected(fn, expected)
			local before = #requests
			local ok, err = pcall(fn)
			assert(not ok and string.find(tostring(err), expected, 1, true), "wrong validation error: " .. tostring(err))
			assert(#requests == before, "invalid input reached Resend")
		end

		local names = {}
		for name in resend do if name ~= "help" then table.insert(names, name) end end
		assert(#names == 57, "wrong read-only surface: " .. #names)
		for _, name in {"sendEmail", "sendBatchEmails", "updateEmail", "cancelEmail", "shareEmail", "createDomain", "verifyDomain",
			"createContact", "createContactImport", "addContactToSegment", "sendBroadcast", "createWebhook", "rotateWebhookSigningSecret",
			"replayWebhookEvent", "sendEvent", "addSuppression", "removeSuppressions", "getWebhook", "getLog", "createInbox", "updateInboxAgent",
			"updateThread", "deleteThread", "setThreadLabels", "replyToThreadEmail", "forwardThreadEmail", "createDraft", "sendDraft"} do
			assert(resend[name] == nil, "read-only leaked " .. name)
		end
		assert(resend.listWebhooks and resend.listLogs and resend.getWebhookEvent and resend.getUsage and resend.searchThreads and resend.getThreadEmail,
			"reads without secrets stay available")
		assert(#requests == 0, "initialization reached Resend")

		-- Lists always page: limit defaults to Resend's maximum, and arrays stay arrays.
		local empty = resend.listEmails()
		assert(last().method == "GET" and last().url == API .. "/emails?limit=100" and last().body == nil, last().url)
		assert(last().headers.Accept[1] == "application/json" and last().headers["User-Agent"] == nil)
		assert(last().headers.Authorization == nil and last().headers["Idempotency-Key"] == nil)
		assert(empty.has_more == false and json.encode(empty.data) == "[]")

		payload = '{"object":"list","has_more":true,"data":[{"id":"e1","to":["ana@example.com"],"cc":null,"last_event":"delivered"}]}'
		local opts = {limit = 20, after = "4ef9a417-02e9-4d39-ad75-9611e0fcc33c"}
		local page = resend.listEmails(opts)
		assert(last().url == API .. "/emails?limit=20&after=4ef9a417-02e9-4d39-ad75-9611e0fcc33c", last().url)
		assert(opts.limit == 20 and opts.after ~= nil, "options were modified")
		assert(page.has_more and page.data[1].to[1] == "ana@example.com" and page.data[1].cc == NULL)

		resend.listContacts({segment_id = "s1", before = "c9"})
		assert(last().url == API .. "/contacts?segment_id=s1&limit=100&before=c9", last().url)
		resend.listWebhookEvents({webhook_id = "w1", after = "msg_2"})
		assert(last().url == API .. "/webhooks/w1/events?limit=100&after=msg_2", last().url)
		rejected(function() resend.listWebhookEvents({webhook_id = "w1", before = "msg_2"}) end, "has no option before")

		payload = '{"object":"email","id":"e1","html":"<p>Hi</p>","last_event":"opened"}'
		assert(resend.getEmail({email_id = "e1"}).last_event == "opened" and last().url == API .. "/emails/e1")
		resend.getContact({contact_id = "ana+news@example.com"})
		assert(last().url == API .. "/contacts/ana%2Bnews%40example.com", last().url)
		resend.getContact({contact_id = "o'brien!@example.com"})
		assert(last().url == API .. "/contacts/o%27brien%21%40example.com", last().url)
		resend.getTemplate({template_id = "welcome-email"})
		assert(last().url == API .. "/templates/welcome-email")
		resend.getEvent({identifier = "user.created"})
		assert(last().url == API .. "/events/user.created")
		resend.getSuppression({suppression = "bounce@example.com"})
		assert(last().url == API .. "/suppressions/bounce%40example.com", last().url)
		resend.getReceivedEmail({email_id = "r1", html_format = "cid"})
		assert(last().url == API .. "/emails/receiving/r1?html_format=cid", last().url)
		resend.getEmailMetrics({start_date = "2026-10-01", metrics = "delivered,opened", dimensions = "period", timezone = "Europe/Paris"})
		assert(last().url == API .. "/emails/metrics?start_date=2026-10-01&timezone=Europe%2FParis&metrics=delivered%2Copened&dimensions=period", last().url)
		resend.listBroadcastRecipients({broadcast_id = "b1", type = "bounced", bounce_type = "permanent"})
		assert(last().url == API .. "/broadcasts/b1/recipients?type=bounced&bounce_type=permanent&limit=100", last().url)
		resend.getUsage()
		assert(last().url == API .. "/usage", last().url)

		-- Inboxes take an ID or address, and multi-value filters are comma-joined arrays.
		resend.listThreads({inbox_id = "support@acme.com", folders = {"inbox", "sent"}, labels = {"l1"}, read = false})
		assert(last().url == API .. "/inboxes/support%40acme.com/threads?folders=inbox,sent&labels=l1&read=false&limit=100", last().url)
		resend.searchThreads({inbox_id = "i1", query = '"order 1041" refund', from = {"ana@example.com", "Bo, B"}, has_attachment = true, start_date = "2026-09-01"})
		assert(last().url == API .. "/inboxes/i1/threads/search?query=%22order%201041%22%20refund&from=ana%40example.com,Bo%2C%20B&has_attachment=true&start_date=2026-09-01&limit=100", last().url)
		resend.listThreadEmails({inbox_id = "i1", thread_id = "t1", after = "e9"})
		assert(last().url == API .. "/inboxes/i1/threads/t1/emails?limit=100&after=e9", last().url)
		resend.getThreadEmail({inbox_id = "i1", thread_id = "t1", email_id = "e1"})
		assert(last().url == API .. "/inboxes/i1/threads/t1/emails/e1" and last().body == nil)
		resend.listInboxLabels({inbox_id = "i1"})
		assert(last().url == API .. "/inboxes/i1/labels", last().url)
		resend.getEmailMetrics({metrics = {"delivered", "opened"}})
		assert(last().url == API .. "/emails/metrics?metrics=delivered,opened", last().url)

		-- Invalid input never reaches the network.
		rejected(function() resend.getEmail({}) end, "email_id must be an ID")
		rejected(function() resend.getEmail({email_id = "../api-keys"}) end, "email_id must be an ID")
		rejected(function() resend.getEmail({email_id = ".."}) end, "email_id must be an ID")
		rejected(function() resend.getEmail({email_id = "a/b"}) end, "email_id must be an ID")
		rejected(function() resend.getEmail({email_id = "a\\b"}) end, "email_id must be an ID")
		rejected(function() resend.getEmail({email_id = "%2e%2e"}) end, "email_id must be an ID")
		rejected(function() resend.getEmail({email_id = ""}) end, "email_id must be an ID")
		rejected(function() resend.getEmail({email_id = "e1\n"}) end, "email_id must be an ID")
		rejected(function() resend.getEmail({email_id = 42}) end, "email_id must be an ID")
		rejected(function() resend.listBroadcastRecipients({broadcast_id = "b1"}) end, "type is required")
		rejected(function() resend.listEmails({bogus = 1}) end, "listEmails has no option bogus")
		rejected(function() resend.listEmails({limit = {x = 1}}) end, "limit must be an array, not an object")
		rejected(function() resend.listThreads({inbox_id = "i1", folders = {}}) end, "folders must not be an empty array")
		rejected(function() resend.listThreads({inbox_id = "i1", labels = {{"l1"}}}) end, "labels must be a string, boolean, number or array of those")
		rejected(function() resend.listThreads({folders = {"inbox"}}) end, "inbox_id must be an ID")
		rejected(function() resend.getThread({inbox_id = "i1", thread_id = "../../api-keys"}) end, "thread_id must be an ID")
		rejected(function() resend.listEmails("e1") end, "opts must be an object")
		rejected(function() resend.listEmails({"e1"}) end, "opts must have named fields")
		rejected(function() resend.getEmailAttachment({email_id = "e1", attachment_id = "a1", path = ""}) end, "path must be a session file path")

		-- Without path an attachment is Resend's JSON; with path it is also saved, without the API key.
		local attachment = '{"object":"attachment","id":"a1","filename":"invoice.pdf","size":6,"download_url":"https://inbound-cdn.resend.com/t1/attachments/a1?signature=s1","expires_at":"2026-10-15T12:00:00Z"}'
		payload = attachment
		local before = #requests
		local meta = resend.getReceivedEmailAttachment({email_id = "r1", attachment_id = "a1"})
		assert(#requests == before + 1 and meta.download_url == "https://inbound-cdn.resend.com/t1/attachments/a1?signature=s1")
		local bytes = string.char(0, 255) .. "%PDF\r\n"
		cdn = bytes
		local saved = resend.getReceivedEmailAttachment({email_id = "r1", attachment_id = "a1", path = "mail/invoice.pdf"})
		assert(#requests == before + 3, "attachment download made extra requests")
		assert(requests[before + 2].url == API .. "/emails/receiving/r1/attachments/a1")
		local download = last()
		assert(download.method == "GET" and download.url == "https://inbound-cdn.resend.com/t1/attachments/a1?signature=s1")
		assert(download.headers == nil and download.body == nil)
		assert(saved.path == "mail/invoice.pdf" and saved.url == "https://houston.test/mail/invoice.pdf" and saved.size == #bytes)
		assert(saved.attachment.filename == "invoice.pdf" and saved.attachment.id == "a1")
		local fd = fs.open("mail/invoice.pdf", "r")
		assert(await(fd:readAll()) == bytes)
		await(fd:close())

		payload = '{"object":"attachment","id":"a2","filename":"logo.png","download_url":"https://outbound-cdn.resend.com/t1/attachments/a2?signature=s2"}'
		cdn = "png"
		local sent = resend.getEmailAttachment({email_id = "e1", attachment_id = "a2", path = "logo.png"})
		assert(requests[#requests - 1].url == API .. "/emails/e1/attachments/a2" and last().url == "https://outbound-cdn.resend.com/t1/attachments/a2?signature=s2")
		assert(sent.size == 3 and sent.attachment.id == "a2")

		payload = '{"object":"attachment","id":"a3"}'
		before = #requests
		local ok, err = pcall(function() resend.getEmailAttachment({email_id = "e1", attachment_id = "a3", path = "missing.bin"}) end)
		assert(not ok and string.find(tostring(err), "no attachment download_url", 1, true), tostring(err))
		assert(#requests == before + 1, "missing download_url reached the network")
	end,
}
