-- Splits a MIME entity into its header block and body.
local function entity(mime)
	local head, body = string.match(mime, "^(.-)\r\n\r\n(.*)$")
	return head, body
end
-- Returns the parts of a multipart body with the given boundary.
local function parts(body, boundary)
	local out = {}
	local delimiter = "--" .. boundary
	local rest = string.sub(body, string.find(body, delimiter, 1, true) + #delimiter + 2)
	while true do
		local stop = string.find(rest, "\r\n" .. delimiter, 1, true)
		table.insert(out, string.sub(rest, 1, stop - 1))
		rest = string.sub(rest, stop + 2 + #delimiter)
		if string.sub(rest, 1, 2) == "--" then return out end
		rest = string.sub(rest, 3)
	end
end
-- Returns the JSON metadata and the MIME message of a Gmail multipart upload.
local function uploaded(req)
	assert(req.headers["Content-Type"][1] == 'multipart/related; boundary="=_houston_upload"')
	local sections = parts(req.body, "=_houston_upload")
	assert(#sections == 2 and select(1, entity(sections[1])) == "Content-Type: application/json; charset=UTF-8" and select(1, entity(sections[2])) == "Content-Type: message/rfc822")
	return json.decode(select(2, entity(sections[1]))), select(2, entity(sections[2]))
end
return {
	scenario = {publisher = {client_id = "fixture-client", client_secret = "fixture-private-secret"}, config = {}, auth_method = "oauth", auth_config = {}},
	config = {access = "read-write"},
	configure = function()
		requests, responses = {}, {}
		fs = fixture.files()
		http = {request = function(req)
			table.insert(requests, req)
			assert(#responses > 0, "unexpected request: " .. req.url)
			local response = table.remove(responses, 1)
			return fixture.operation({statusCode = response.status or 200, headers = {}, body = fixture.reader(response.body or "")})
		end}
	end,
	run = function(c)
		local base64 = require("lib/base64.luau")
		local API = "https://gmail.googleapis.com/gmail/v1/users/me"
		local UPLOAD = "https://gmail.googleapis.com/upload/gmail/v1/users/me"
		local binary = string.char(0, 255, 13, 10) .. string.rep("x", 100)
		local file = fs.open("files/report.bin", "w")
		file:write(binary)
		await(file:close())

		responses = {{body = '{"id":"s1","threadId":"t1","labelIds":["SENT"]}'}}
		local sent = c.sendMessage({to = {"Ana <ana@example.com>", "bo@example.com"}, subject = "Résumé", text = "Hi Ana", html = "<p>Hi Ana</p>", bcc = "boss@example.com",
			attachments = {"files/report.bin", {path = "files/report.bin", filename = "naïve.bin", mimeType = "application/x-test"}}})
		assert(sent.id == "s1")
		local req = requests[#requests]
		assert(req.method == "POST" and req.url == UPLOAD .. "/messages/send?uploadType=multipart", req.url)
		local metadata, mime = uploaded(req)
		assert(json.encode(metadata) == "{}", "a new message has no thread")
		local head, content = entity(mime)
		assert(string.find(head, "To: Ana <ana@example.com>, bo@example.com\r\n", 1, true) and string.find(head, "Bcc: boss@example.com\r\n", 1, true))
		assert(string.find(head, "Subject: =?UTF-8?B?" .. base64.encode("Résumé") .. "?=", 1, true) and string.find(head, "MIME-Version: 1.0", 1, true))
		assert(string.find(head, 'Content-Type: multipart/mixed; boundary="=_houston_mixed"', 1, true) and not string.find(head, "In-Reply-To", 1, true))
		local mixed = parts(content, "=_houston_mixed")
		assert(#mixed == 3)
		local altHead, altBody = entity(mixed[1])
		assert(string.find(altHead, "multipart/alternative", 1, true))
		local alternative = parts(altBody, "=_houston_alternative")
		local textHead, textBody = entity(alternative[1])
		assert(string.find(textHead, "text/plain; charset=UTF-8", 1, true) and base64.decode(textBody) == "Hi Ana")
		assert(base64.decode(select(2, entity(alternative[2]))) == "<p>Hi Ana</p>")
		local fileHead, fileBody = entity(mixed[2])
		assert(string.find(fileHead, 'Content-Disposition: attachment; filename="report.bin"', 1, true) and string.find(fileHead, "application/octet-stream", 1, true))
		assert(base64.decode(fileBody) == binary)
		for encodedLine in string.gmatch(fileBody, "[^\r\n]+") do assert(#encodedLine <= 76, "base64 lines must wrap at 76") end
		local namedHead = entity(mixed[3])
		assert(string.find(namedHead, "filename*=UTF-8''na%C3%AFve.bin", 1, true) and string.find(namedHead, "application/x-test", 1, true))

		local original = {id = "o1", threadId = "t9", payload = {headers = {
			{name = "From", value = "Ana <ana@example.com>"}, {name = "To", value = "me@example.com, Bo <bo@example.com>"}, {name = "Cc", value = "cy@example.com, ana@example.com"},
			{name = "Subject", value = "Plans"}, {name = "Message-ID", value = "<o1@example.com>"}, {name = "References", value = "<o0@example.com>"},
		}}}
		responses = {{body = json.encode(original)}, {body = '{"emailAddress":"Me@example.com"}'}, {body = '{"id":"d1","message":{"id":"m","threadId":"t9"}}'}}
		local draft = c.createDraft({inReplyTo = "o1", replyAll = true, text = "Sounds good", attachments = {}})
		assert(draft.id == "d1")
		assert(string.find(requests[#requests - 2].url, API .. "/messages/o1?format=metadata&metadataHeaders=From&metadataHeaders=Reply-To", 1, true), requests[#requests - 2].url)
		assert(requests[#requests - 1].url == API .. "/profile" and requests[#requests].url == UPLOAD .. "/drafts?uploadType=multipart")
		metadata, mime = uploaded(requests[#requests])
		assert(metadata.message.threadId == "t9")
		head, content = entity(mime)
		assert(string.find(head, "To: Ana <ana@example.com>\r\n", 1, true) and string.find(head, "Cc: bo@example.com, cy@example.com\r\n", 1, true), head)
		assert(string.find(head, "Subject: Re: Plans\r\n", 1, true) and string.find(head, "In-Reply-To: <o1@example.com>\r\n", 1, true))
		assert(string.find(head, "References: <o0@example.com> <o1@example.com>\r\n", 1, true) and string.find(head, "Content-Type: text/plain; charset=UTF-8", 1, true))
		assert(base64.decode(content) == "Sounds good")

		original.payload.headers[4] = {name = "Subject", value = "RE: Plans"}
		responses = {{body = json.encode(original)}, {body = '{"id":"d1"}'}}
		c.updateDraft({id = "d1", inReplyTo = "o1", html = "<p>Updated</p>"})
		assert(requests[#requests].method == "PUT" and requests[#requests].url == UPLOAD .. "/drafts/d1?uploadType=multipart")
		head = entity(select(2, uploaded(requests[#requests])))
		assert(string.find(head, "Subject: RE: Plans\r\n", 1, true) and not string.find(head, "Cc:", 1, true) and string.find(head, "text/html", 1, true))

		responses = {{body = '{"id":"s2"}'}}
		c.sendDraft({id = "d1"})
		assert(requests[#requests].url == API .. "/drafts/send" and json.decode(requests[#requests].body).id == "d1")

		local count = #requests
		for _, args in {
			{subject = "No recipient", text = "x"}, {to = "a@example.com"}, {to = "a@example.com", text = "x", unknown = true},
			{to = "a@example.com", subject = "Injected\r\nBcc: evil@example.com", text = "x"}, {to = {}, text = "x"},
			{to = "a@example.com", text = "x", inReplyTo = ".."}, {to = "a@example.com", text = "x", inReplyTo = "o/1"},
			{to = "a@example.com", text = "x", attachments = {"files/missing.bin"}}, {to = "a@example.com", text = "x", attachments = "files/report.bin"},
		} do assert(not pcall(c.sendMessage, args)) end
		for _, id in {"..", "d/1", "d%2F1"} do assert(not pcall(c.updateDraft, {id = id, to = "a@example.com", text = "x"})) end
		assert(#requests == count and #responses == 0, "invalid messages reached Google")
	end,
}
