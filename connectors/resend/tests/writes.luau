return {
	scenario = {publisher = {}, config = {access = "read-write"}, auth_method = "api_key", auth_config = {token = "re_fixture"}},
	configure = function()
		requests = {}
		status = 200
		payload = '{"id":"49a3999c-0ce1-4ea6-ab68-afcd6dc2e794"}'
		fs = fixture.files()
		local multipart = http.multipart
		http = {multipart = multipart, request = function(req)
			if req.body ~= nil and type(req.body) ~= "string" then req.body = await(req.body:readAll()) end
			table.insert(requests, req)
			return fixture.operation({statusCode = status, headers = {}, body = fixture.reader(payload)})
		end}
	end,
	run = function(resend)
		local API = "https://api.resend.com"
		local function last() return requests[#requests] end
		local function rejected(fn, expected)
			local before = #requests
			local ok, err = pcall(fn)
			assert(not ok and string.find(tostring(err), expected, 1, true), "wrong validation error: " .. tostring(err))
			assert(#requests == before, "invalid input reached Resend")
		end

		local count = 0
		for name in resend do if name ~= "help" then count += 1 end end
		assert(count == 133, "wrong read-write surface: " .. count)
		assert(resend.getWebhook and resend.getLog and resend.sendEmail and resend.createContactImport)

		-- The idempotency key travels as a header, never in the body.
		local email = {from = "Acme <hello@acme.com>", to = {"ana@example.com"}, subject = "Welcome", html = "<p>Hi</p>",
			tags = {{name = "category", value = "welcome"}}, headers = {["X-Entity-Ref-ID"] = "123"}, idempotency_key = "welcome/ana"}
		local sent = resend.sendEmail(email)
		assert(sent.id == "49a3999c-0ce1-4ea6-ab68-afcd6dc2e794")
		local req = last()
		assert(req.method == "POST" and req.url == API .. "/emails" and req.headers.Authorization == nil)
		assert(req.headers["Content-Type"][1] == "application/json" and req.headers["Idempotency-Key"][1] == "welcome/ana")
		local body = json.decode(req.body)
		assert(body.idempotency_key == nil and body.from == "Acme <hello@acme.com>" and body.to[1] == "ana@example.com" and body.subject == "Welcome")
		assert(body.tags[1].name == "category" and body.headers["X-Entity-Ref-ID"] == "123")
		assert(string.find(req.body, '"to":["ana@example.com"]', 1, true), req.body)
		assert(email.idempotency_key == "welcome/ana", "options were modified")

		resend.sendEmail({from = "hello@acme.com", to = "ana@example.com", subject = "Hi", text = "Hello", scheduled_at = "in 1 hour"})
		assert(last().headers["Idempotency-Key"] == nil and json.decode(last().body).scheduled_at == "in 1 hour")
		rejected(function() resend.sendEmail({from = "a@acme.com", idempotency_key = ""}) end, "idempotency_key must be a string of 1 to 256 characters")
		rejected(function() resend.sendEmail({from = "a@acme.com", idempotency_key = string.rep("k", 257)}) end, "idempotency_key must be")
		rejected(function() resend.sendEmail({from = "a@acme.com", idempotency_key = 7}) end, "idempotency_key must be")

		-- A batch body is the JSON array itself.
		payload = '{"data":[{"id":"b1"},{"id":"b2"}]}'
		local batch = resend.sendBatchEmails({idempotency_key = "batch/1", emails = {
			{from = "hello@acme.com", to = "a@example.com", subject = "One", text = "1"},
			{from = "hello@acme.com", to = {"b@example.com"}, subject = "Two", text = "2"},
		}})
		req = last()
		assert(req.url == API .. "/emails/batch" and req.headers["Idempotency-Key"][1] == "batch/1")
		assert(string.match(req.body, "^%[") and json.decode(req.body)[2].subject == "Two" and batch.data[2].id == "b2")
		rejected(function() resend.sendBatchEmails({emails = {}}) end, "emails must be a nonempty array")
		rejected(function() resend.sendBatchEmails({}) end, "emails must be a nonempty array")
		rejected(function() resend.sendBatchEmails({emails = {{}}, extra = true}) end, "sendBatchEmails has no option extra")

		-- Actions without a body send neither a body nor a Content-Type.
		payload = '{"object":"email","id":"e1"}'
		resend.cancelEmail({email_id = "e1"})
		assert(last().method == "POST" and last().url == API .. "/emails/e1/cancel" and last().body == nil and last().headers["Content-Type"] == nil)
		resend.verifyDomain({domain_id = "d1"})
		assert(last().url == API .. "/domains/d1/verify" and last().body == nil)
		resend.addContactToSegment({contact_id = "ana@example.com", segment_id = "s1"})
		assert(last().method == "POST" and last().url == API .. "/contacts/ana%40example.com/segments/s1" and last().body == nil)

		resend.updateEmail({email_id = "e1", scheduled_at = "2026-10-20T09:00:00Z"})
		assert(last().method == "PATCH" and last().body == '{"scheduled_at":"2026-10-20T09:00:00Z"}', last().body)
		resend.updateContactTopics({contact_id = "c1", topics = {{id = "t1", subscription = "opt_out"}}})
		assert(last().method == "PATCH" and last().url == API .. "/contacts/c1/topics" and json.decode(last().body).topics[1].subscription == "opt_out")
		resend.createContact({email = "ana@example.com", segments = json.decode("[]")})
		assert(string.find(last().body, '"segments":[]', 1, true), last().body)

		payload = '{"object":"contact","contact":"c1","deleted":true}'
		assert(resend.deleteContact({contact_id = "c1"}).deleted == true)
		assert(last().method == "DELETE" and last().url == API .. "/contacts/c1" and last().body == nil)
		payload = ""
		assert(next(resend.removeSuppression({suppression = "bounce@example.com"})) == nil, "an empty write response is an empty object")

		-- Inbox replies and drafts send from the inbox; labels are replaced with PUT.
		payload = '{"object":"email","id":"e2","thread_id":"t1"}'
		resend.replyToThreadEmail({inbox_id = "support@acme.com", thread_id = "t1", email_id = "e1", text = "Refunded.", reply_all = true,
			idempotency_key = "reply/e1"})
		req = last()
		assert(req.method == "POST" and req.url == API .. "/inboxes/support%40acme.com/threads/t1/emails/e1/reply", req.url)
		assert(req.headers["Idempotency-Key"][1] == "reply/e1" and req.headers.Authorization == nil)
		body = json.decode(req.body)
		assert(body.text == "Refunded." and body.reply_all == true and body.idempotency_key == nil and body.inbox_id == nil and body.email_id == nil)
		resend.updateThread({inbox_id = "i1", thread_id = "t1", read = true})
		assert(last().method == "PATCH" and last().url == API .. "/inboxes/i1/threads/t1" and last().body == '{"read":true}', last().body)
		payload = '{"object":"list","data":[]}'
		resend.setThreadLabels({inbox_id = "i1", thread_id = "t1", labels = json.decode("[]")})
		assert(last().method == "PUT" and last().url == API .. "/inboxes/i1/threads/t1/labels" and last().body == '{"labels":[]}', last().body)
		assert(last().headers["Content-Type"][1] == "application/json")
		resend.removeThreadLabel({inbox_id = "i1", thread_id = "t1", label_id = "l1"})
		assert(last().method == "DELETE" and last().url == API .. "/inboxes/i1/threads/t1/labels/l1" and last().body == nil)
		payload = '{"object":"email","id":"e3"}'
		resend.sendDraft({inbox_id = "i1", draft_id = "d1", idempotency_key = "draft/d1"})
		assert(last().url == API .. "/inboxes/i1/drafts/d1/send" and last().headers["Idempotency-Key"][1] == "draft/d1")
		assert(last().body == "{}", last().body)
		rejected(function() resend.forwardThreadEmail({inbox_id = "i1", thread_id = "t1", email_id = "e1", to = "a@example.com", idempotency_key = ""}) end,
			"idempotency_key must be")

		payload = '{"object":"webhook","id":"w1","signing_secret":"whsec_fixture"}'
		assert(resend.getWebhook({webhook_id = "w1"}).signing_secret == "whsec_fixture" and last().method == "GET")
		payload = '{"object":"log","id":"l1","request_body":{},"response_body":{}}'
		resend.getLog({log_id = "l1"})
		assert(last().url == API .. "/logs/l1")

		-- Contact imports stream a CSV session file with JSON-encoded form fields.
		local csv = "email,first_name\nana@example.com,Ana\n"
		local input = fs.open("imports/contacts.csv", "w")
		input:write(csv)
		await(input:close())
		payload = '{"object":"contact_import","id":"i1"}'
		local imported = resend.createContactImport({path = "imports/contacts.csv", column_map = {email = "email", first_name = "first_name"},
			on_conflict = "upsert", segments = {{id = "s1"}}})
		req = last()
		assert(imported.id == "i1" and req.method == "POST" and req.url == API .. "/contacts/imports")
		local contentType = req.headers["Content-Type"][1]
		local boundary = string.match(contentType, "^multipart/form%-data; boundary=(.+)$")
		assert(boundary, contentType)
		local function part(header, value)
			assert(string.find(req.body, header .. "\r\n", 1, true), "missing part " .. header)
			assert(string.find(req.body, value, 1, true), "missing value " .. value)
		end
		part('Content-Disposition: form-data; name="file"; filename="contacts.csv"', csv)
		part('Content-Disposition: form-data; name="on_conflict"', "\r\n\r\nupsert\r\n")
		part('Content-Disposition: form-data; name="segments"', '[{"id":"s1"}]')
		assert(string.find(req.body, '"first_name":"first_name"', 1, true) and not string.find(req.body, 'name="path"', 1, true))
		-- Plain form values are sent as given, not URL-encoded.
		resend.createContactImport({path = "imports/contacts.csv", column_map = '{"email":"Email Address"}', on_conflict = "skip"})
		assert(string.find(last().body, '\r\n\r\n{"email":"Email Address"}\r\n', 1, true), last().body)
		rejected(function() resend.createContactImport({path = "imports/contacts.csv", on_conflict = json.decode("null")}) end, "on_conflict must be a string, number, boolean, object or array")
		rejected(function() resend.createContactImport({column_map = {email = "email"}}) end, "path is required")
		rejected(function() resend.createContactImport({path = "imports/missing.csv"}) end, "path imports/missing.csv is not a session file")
	end,
}
