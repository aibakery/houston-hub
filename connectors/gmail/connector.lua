-- Gmail API v1 for the connected mailbox. Arguments and results keep Google's native
-- field names; reads add decoded bodies and writes build MIME so callers never handle base64.
type Options = {[string]: any}
type Endpoint = {method: string, path: string, read: boolean, query: {string}?, body: boolean?, defaults: Options?, list: string?, help: string}
local API = "https://gmail.googleapis.com/gmail/v1/users/me"
local UPLOAD = "https://gmail.googleapis.com/upload/gmail/v1/users/me"
local base64 = require("lib/base64.lua")

-- Request layer shared verbatim by the Google connectors (tools/validate checks they match).
local function text(value: any, field: string): string
	assert(type(value) == "string" and value ~= "", field .. " must be a nonempty string")
	return value
end

local function options(value: any): Options
	if value == nil then return {} end
	assert(type(value) == "table", "opts must be an object")
	for key in value do assert(type(key) == "string", "opts must have named fields") end
	return table.clone(value)
end

-- Moves the named fields from args into a query string; arrays repeat the key.
local function query(args: Options, names: {string}): string
	local parts: {string} = {}
	for _, name in names do
		local value = args[name]
		args[name] = nil
		for _, item in (if type(value) == "table" then value else {value}) do
			assert(type(item) == "string" or type(item) == "number" or type(item) == "boolean", name .. " must be a string, number, boolean or an array of them")
			table.insert(parts, url.encode(name) .. "=" .. url.encode(item))
		end
	end
	return if #parts > 0 then "?" .. table.concat(parts, "&") else ""
end

local function fail(operation: string, response: HttpResponse): never
	local ok, decoded = pcall(json.decode, await(response.body:readPrefix(4096)))
	local problem = if ok and type(decoded) == "table" and type(decoded.error) == "table" then decoded.error else {}
	local reason = type(problem.errors) == "table" and type(problem.errors[1]) == "table" and problem.errors[1].reason
	local message = "Google HTTP " .. tostring(response.statusCode)
	if type(problem.status) == "string" then message ..= " (" .. problem.status .. ")" end
	if type(problem.message) == "string" then message ..= ": " .. string.sub(problem.message, 1, 600) end
	if type(reason) == "string" then message ..= " [" .. reason .. "]" end
	local retry = response.headers["retry-after"]
	if retry and retry[1] then message ..= "; Retry-After: " .. retry[1] end
	local limited = type(reason) == "string" and string.find(string.lower(reason), "ratelimitexceeded", 1, true) ~= nil
	return houston.fail({operation = operation, layer = "upstream", upstream_status = response.statusCode,
		retryable = response.statusCode == 429 or response.statusCode >= 500 or limited, message = message})
end

local function decode(operation: string, response: HttpResponse): any
	if response.statusCode < 200 or response.statusCode >= 300 then fail(operation, response) end
	local raw = await(response.body:readAll())
	if raw == "" then return {success = true} end
	local ok, value = pcall(json.decode, raw)
	if not ok or type(value) ~= "table" or not string.match(raw, "^%s*{") then
		houston.fail({operation = operation, layer = "upstream", upstream_status = response.statusCode,
			retryable = false, message = "Google returned an invalid JSON object"})
	end
	return value
end

local function call(operation: string, method: string, href: string, body: any?): any
	return decode(operation, await(http.request({method = method, url = href,
		headers = if body ~= nil then {["Content-Type"] = {"application/json"}} else nil,
		body = if body ~= nil then json.encode(body) else nil})))
end

-- Moves {placeholders} and declared query fields from args into the URL; remaining fields form the JSON body.
local function target(name: string, endpoint: Endpoint, args: Options): string
	local defaults: Options = endpoint.defaults or {}
	for key, value in defaults do
		if args[key] == nil then args[key] = value end
	end
	local path = string.gsub(endpoint.path, "{(%w+)}", function(field: string)
		local value = url.segment(text(args[field], field), field)
		args[field] = nil
		return value
	end)
	path ..= query(args, endpoint.query or {})
	if not endpoint.body then assert(next(args) == nil, name .. " received an unknown option") end
	return API .. path
end

local function invoke(name: string, endpoint: Endpoint, input: any): any
	local args = options(input)
	local result = call(name, endpoint.method, target(name, endpoint, args), if endpoint.body then args else nil)
	if endpoint.list and result[endpoint.list] == nil then result[endpoint.list] = json.decode("[]") end
	return result
end

local exports: {[string]: any} = {}
local help: {[string]: string} = {}

-- Exposes an operation when it only reads or the connection allows writes.
local function export(name: string, isRead: boolean, fn: (any) -> any, doc: string)
	if isRead or config.access == "read-write" then
		exports[name], help[name] = fn, doc
	end
end

local function exportEndpoints(endpoints: {[string]: Endpoint})
	for name, endpoint in endpoints do
		export(name, endpoint.read, function(args: Options?): any return invoke(name, endpoint, args) end, endpoint.help)
	end
end

-- help() introduces the API, then documents exactly the configured operations.
local function helpWith(overview: {string}): () -> string
	return function(): string
		local names: {string} = {}
		for name in help do table.insert(names, name) end
		table.sort(names)
		local lines = table.clone(overview)
		for _, name in names do table.insert(lines, help[name]) end
		return table.concat(lines, "\n")
	end
end
-- End of the shared request layer.

local SEARCH = {"q", "labelIds", "maxResults", "pageToken", "includeSpamTrash"}
local endpoints: {[string]: Endpoint} = {
	getProfile = {method = "GET", path = "/profile", read = true,
		help = "getProfile() -> {emailAddress, messagesTotal, threadsTotal, historyId}."},
	listLabels = {method = "GET", path = "/labels", read = true, list = "labels",
		help = "listLabels() -> {labels={{id, name, type}}}. System labels include INBOX, SENT, DRAFT, SPAM, TRASH, UNREAD, STARRED and IMPORTANT."},
	getLabel = {method = "GET", path = "/labels/{id}", read = true,
		help = "getLabel({id}) -> label with message and thread counts."},
	listMessages = {method = "GET", path = "/messages", read = true, list = "messages", query = SEARCH,
		help = "listMessages({q?, labelIds?, maxResults?, pageToken?, includeSpamTrash?}) -> {messages={{id, threadId}}, nextPageToken?, resultSizeEstimate}. IDs only: read them with getMessages. q uses Gmail search syntax, e.g. 'from:ana@example.com after:2026/10/01 has:attachment'. maxResults ≤500 (default 100). resultSizeEstimate is not a count."},
	listThreads = {method = "GET", path = "/threads", read = true, list = "threads", query = SEARCH,
		help = "listThreads({q?, labelIds?, maxResults?, pageToken?, includeSpamTrash?}) -> {threads={{id, snippet, historyId}}, nextPageToken?}. Read a conversation with getThread."},
	listDrafts = {method = "GET", path = "/drafts", read = true, list = "drafts", query = {"q", "maxResults", "pageToken", "includeSpamTrash"},
		help = "listDrafts({q?, maxResults?, pageToken?}) -> {drafts={{id, message={id, threadId}}}, nextPageToken?}."},
	listHistory = {method = "GET", path = "/history", read = true, list = "history", query = {"startHistoryId", "labelId", "historyTypes", "maxResults", "pageToken"},
		help = "listHistory({startHistoryId, historyTypes?, labelId?, maxResults?, pageToken?}) -> {history, historyId, nextPageToken?}. Changes since a historyId from getProfile or a message; 404 means it expired: resync with listMessages."},
	listSendAs = {method = "GET", path = "/settings/sendAs", read = true, list = "sendAs",
		help = "listSendAs() -> {sendAs={{sendAsEmail, displayName, isDefault, ...}}}. Addresses usable as from."},
	modifyMessage = {method = "POST", path = "/messages/{id}/modify", read = false, body = true,
		help = "modifyMessage({id, addLabelIds?, removeLabelIds?}) -> message. E.g. removeLabelIds={'UNREAD'} marks read; removeLabelIds={'INBOX'} archives."},
	batchModifyMessages = {method = "POST", path = "/messages/batchModify", read = false, body = true,
		help = "batchModifyMessages({ids, addLabelIds?, removeLabelIds?}) -> {success=true}. Up to 1000 IDs."},
	trashMessage = {method = "POST", path = "/messages/{id}/trash", read = false,
		help = "trashMessage({id}) -> message. Moves to Trash; Gmail deletes it after 30 days."},
	untrashMessage = {method = "POST", path = "/messages/{id}/untrash", read = false,
		help = "untrashMessage({id}) -> message."},
	modifyThread = {method = "POST", path = "/threads/{id}/modify", read = false, body = true,
		help = "modifyThread({id, addLabelIds?, removeLabelIds?}) -> thread. Applies to every message in the conversation."},
	trashThread = {method = "POST", path = "/threads/{id}/trash", read = false,
		help = "trashThread({id}) -> thread."},
	untrashThread = {method = "POST", path = "/threads/{id}/untrash", read = false,
		help = "untrashThread({id}) -> thread."},
	createLabel = {method = "POST", path = "/labels", read = false, body = true,
		help = "createLabel({name, labelListVisibility?, messageListVisibility?, color?}) -> label. Nest with 'Parent/Child' names."},
	updateLabel = {method = "PATCH", path = "/labels/{id}", read = false, body = true,
		help = "updateLabel({id, name?, labelListVisibility?, messageListVisibility?, color?}) -> label."},
	deleteLabel = {method = "DELETE", path = "/labels/{id}", read = false,
		help = "deleteLabel({id}) -> {success=true}. Removes the label from its messages; the messages remain."},
	sendDraft = {method = "POST", path = "/drafts/send", read = false, body = true,
		help = "sendDraft({id}) -> sent message {id, threadId, labelIds}."},
	deleteDraft = {method = "DELETE", path = "/drafts/{id}", read = false,
		help = "deleteDraft({id}) -> {success=true}. Permanently deletes the draft."},
}

local function header(headers: any, name: string): string?
	for _, item in headers or {} do
		if type(item) == "table" and type(item.name) == "string" and string.lower(item.name) == name then return item.value end
	end
	return nil
end

-- Gmail returns body bytes in their original charset; non-UTF-8 text is read as Latin-1.
local function bodyText(data: string, limit: number): (string, boolean)
	local value = base64.decode(data)
	if utf8.len(value) == nil then
		value = string.gsub(value, "[\128-\255]", function(c: string) return utf8.char(string.byte(c)) end)
	end
	if limit == 0 or #value <= limit then return value, false end
	value = string.sub(value, 1, limit)
	while utf8.len(value) == nil do value = string.sub(value, 1, -2) end
	return value, true
end

local function collect(part: any, found: Options)
	if type(part.parts) == "table" then
		for _, child in part.parts do collect(child, found) end
		return
	end
	local body = part.body or {}
	local disposition = string.lower(header(part.headers, "content-disposition") or "")
	local attached = string.sub(disposition, 1, 10) == "attachment"
	local filename = if type(part.filename) == "string" and part.filename ~= "" then part.filename else nil
	if not filename and not attached and (part.mimeType == "text/plain" or part.mimeType == "text/html") then
		found[part.mimeType] = found[part.mimeType] or body.data
	elseif type(body.attachmentId) == "string" then
		local contentId = header(part.headers, "content-id")
		table.insert(found.attachments, {id = body.attachmentId, filename = filename, mimeType = part.mimeType, size = body.size,
			inline = not attached and (contentId ~= nil or string.sub(disposition, 1, 6) == "inline"),
			contentId = if contentId then string.match(contentId, "^%s*<?(.-)>?%s*$") else nil})
	end
end

-- Replaces Gmail's MIME payload with envelope fields, one decoded body and attachment metadata.
local function message(raw: Options, limit: number): Options
	local payload = raw.payload or {}
	local headers = payload.headers or json.decode("[]")
	local found: Options = {attachments = json.decode("[]")}
	collect(payload, found)
	local data = found["text/plain"] or found["text/html"]
	local body, truncated = raw.snippet or "", false
	if data then body, truncated = bodyText(data, limit) end
	return {
		id = raw.id, threadId = raw.threadId, labelIds = raw.labelIds or json.decode("[]"), snippet = raw.snippet,
		historyId = raw.historyId, internalDate = raw.internalDate, sizeEstimate = raw.sizeEstimate,
		from = header(headers, "from"), to = header(headers, "to"), cc = header(headers, "cc"), bcc = header(headers, "bcc"),
		replyTo = header(headers, "reply-to"), subject = header(headers, "subject"), date = header(headers, "date"),
		messageId = header(headers, "message-id"), body = body, bodyTruncated = truncated, attachments = found.attachments, headers = headers,
	}
end

-- Moves the read options from args into a query string; returns it with the body byte limit.
local function readQuery(args: Options): (string, number)
	local limit = args.maxBodyBytes or 65536
	assert(type(limit) == "number" and limit >= 0 and limit % 1 == 0, "maxBodyBytes must be a nonnegative integer")
	local format = args.format or "full"
	assert(format == "full" or format == "metadata" or format == "minimal", "format must be full, metadata or minimal")
	args.maxBodyBytes, args.format = nil, format
	return query(args, {"format", "metadataHeaders"}), limit
end

local function read(name: string, collection: string, input: any): (any, number)
	local args = options(input)
	local id = text(args.id, "id")
	args.id = nil
	local suffix, limit = readQuery(args)
	assert(next(args) == nil, name .. " received an unknown option")
	return call(name, "GET", API .. "/" .. collection .. "/" .. url.segment(id, "id") .. suffix), limit
end

local function getMessages(input: any): {Options}
	local args = options(input)
	local ids = args.ids
	assert(type(ids) == "table" and #ids >= 1 and #ids <= 100, "ids must be an array of 1 to 100 message IDs")
	local segments: {string} = {}
	for i, id in ids do
		local field = "ids[" .. tostring(i) .. "]"
		segments[i] = url.segment(text(id, field), field)
	end
	args.ids = nil
	local suffix, limit = readQuery(args)
	assert(next(args) == nil, "getMessages received an unknown option")
	local out: {Options} = json.decode("[]")
	-- Bounded concurrency stays within Gmail's per-user rate limits.
	for first = 1, #ids, 10 do
		local pending = {}
		for i = first, math.min(first + 9, #ids) do
			table.insert(pending, http.request({method = "GET", url = API .. "/messages/" .. segments[i] .. suffix}))
		end
		local responses = awaitAll(pending)
		for i = 1, responses.n do table.insert(out, message(decode("getMessages", responses[i]), limit)) end
	end
	return out
end

-- Gmail returns {"size": n, "data": "<base64url>"}; decode the data string as it streams so
-- large attachments never sit in memory.
local function getAttachment(input: any): Options
	local args = options(input)
	local messageId, attachmentId, path = text(args.messageId, "messageId"), text(args.attachmentId, "attachmentId"), text(args.path, "path")
	args.messageId, args.attachmentId, args.path = nil, nil, nil
	assert(next(args) == nil, "getAttachment received an unknown option")
	local response = await(http.request({method = "GET", url = API .. "/messages/" .. url.segment(messageId, "messageId") .. "/attachments/" .. url.segment(attachmentId, "attachmentId")}))
	if response.statusCode < 200 or response.statusCode >= 300 then fail("getAttachment", response) end
	local output = fs.open(path, "w")
	local pending, started, finished = "", false, false
	while not finished do
		local chunk = await(response.body:read(1048576))
		if chunk.done then break end
		pending ..= chunk.data
		if not started then
			local _, last = string.find(pending, '"data"%s*:%s*"')
			if last then started, pending = true, string.sub(pending, last + 1) end
		end
		if started then
			local close = string.find(pending, '"', 1, true)
			finished = close ~= nil
			local usable = if close then close - 1 else #pending - #pending % 4
			await(output:write(base64.decode(string.sub(pending, 1, usable))))
			pending = string.sub(pending, usable + 1)
		end
	end
	response.body:close()
	await(output:close())
	if not finished then
		houston.fail({operation = "getAttachment", layer = "upstream", upstream_status = response.statusCode, retryable = false, message = "Google returned no attachment data"})
	end
	return {path = path, url = await(fs.signedGetUrl(path)), size = await(fs.stat(path)).size}
end

local EMAIL = "[%w%.%_%%%+%-]+@[%w%.%-]+"

local function line(name: string, value: string?): string
	if value == nil then return "" end
	assert(not string.find(value, "[\r\n]"), name .. " must not contain line breaks")
	return name .. ": " .. value .. "\r\n"
end

local function addresses(value: any, field: string): string?
	if value == nil then return nil end
	local list = if type(value) == "string" then {value} else value
	assert(type(list) == "table" and #list > 0, field .. " must be an address or an array of addresses")
	for _, item in list do assert(type(item) == "string" and item ~= "", field .. " must contain address strings") end
	return table.concat(list, ", ")
end

-- Appends one base64-encoded MIME part.
local function part(out: {string}, contentType: string, data: string, disposition: string?)
	table.insert(out, line("Content-Type", contentType) .. line("Content-Disposition", disposition) .. "Content-Transfer-Encoding: base64\r\n\r\n")
	table.insert(out, base64.encode(data, true))
end

-- Returns the opening, separating and closing lines of a multipart body.
-- Base64 parts never contain "=_", so these fixed boundaries cannot collide with content.
local function multipart(subtype: string): (string, string, string)
	local boundary = "=_houston_" .. subtype
	return "Content-Type: multipart/" .. subtype .. "; boundary=\"" .. boundary .. "\"\r\n\r\n--" .. boundary .. "\r\n",
		"\r\n--" .. boundary .. "\r\n", "\r\n--" .. boundary .. "--\r\n"
end

local function attachment(out: {string}, item: any)
	local spec = if type(item) == "string" then {path = item} else item
	assert(type(spec) == "table", "attachments must be paths or {path, filename?, mimeType?}")
	local path = text(spec.path, "attachment path")
	local filename = text(spec.filename or string.match(path, "[^/]+$"), "attachment filename")
	local file = fs.open(path, "r")
	local data = await(file:readAll())
	await(file:close())
	local name = if string.match(filename, "^[%w%.%-_ ()]+$") then "filename=\"" .. filename .. "\"" else "filename*=UTF-8''" .. url.encode(filename)
	part(out, text(spec.mimeType or "application/octet-stream", "attachment mimeType"), data, "attachment; " .. name)
end

-- Builds the MIME message as pieces and returns them with the thread to post into. inReplyTo
-- threads a reply to that message: recipients, subject and references default from the original.
local function compose(name: string, args: Options): ({string}, string?)
	local known = {}
	for _, field in {"to", "cc", "bcc", "replyTo", "from", "subject", "text", "html", "attachments", "inReplyTo", "replyAll"} do known[field] = true end
	for key in args do assert(known[key], name .. " received an unknown option " .. key) end
	local to, cc, subject, threadId, references, inReplyTo = addresses(args.to, "to"), addresses(args.cc, "cc"), args.subject, nil, nil, nil
	if args.inReplyTo ~= nil then
		local metadata = {format = "metadata", metadataHeaders = {"From", "Reply-To", "To", "Cc", "Subject", "Message-ID", "References"}}
		local original = call(name, "GET", API .. "/messages/" .. url.segment(text(args.inReplyTo, "inReplyTo"), "inReplyTo") .. query(metadata, {"format", "metadataHeaders"}))
		local headers = original.payload and original.payload.headers
		threadId, inReplyTo = original.threadId, header(headers, "message-id")
		references = if inReplyTo then table.concat({header(headers, "references") or "", inReplyTo}, " ") else nil
		to = to or header(headers, "reply-to") or header(headers, "from")
		if subject == nil then
			local previous = header(headers, "subject") or ""
			subject = if string.match(string.lower(previous), "^re:") then previous else "Re: " .. previous
		end
		if args.replyAll == true and cc == nil then
			local seen = {[string.lower(call(name, "GET", API .. "/profile").emailAddress or "")] = true}
			for email in string.gmatch(string.lower(to or ""), EMAIL) do seen[email] = true end
			local copied: {string} = {}
			for email in string.gmatch(string.lower((header(headers, "to") or "") .. "," .. (header(headers, "cc") or "")), EMAIL) do
				if not seen[email] then seen[email], copied[#copied + 1] = true, email end
			end
			cc = if #copied > 0 then table.concat(copied, ", ") else nil
		end
	end
	assert(to, name .. " requires to (or inReplyTo)")
	assert(args.text ~= nil or args.html ~= nil, name .. " requires text or html")
	local attachments = if args.attachments == nil then {} else args.attachments
	assert(type(attachments) == "table", "attachments must be an array")
	if subject ~= nil and string.find(subject, "[\128-\255]") then subject = "=?UTF-8?B?" .. base64.encode(subject) .. "?=" end
	local out = {line("From", args.from) .. line("To", to) .. line("Cc", cc) .. line("Bcc", addresses(args.bcc, "bcc"))
		.. line("Reply-To", addresses(args.replyTo, "replyTo")) .. line("Subject", subject) .. line("In-Reply-To", inReplyTo)
		.. line("References", references) .. "MIME-Version: 1.0\r\n"}
	local open, between, close = multipart("mixed")
	if #attachments > 0 then table.insert(out, open) end
	if args.text ~= nil and args.html ~= nil then
		local first, second, last = multipart("alternative")
		table.insert(out, first)
		part(out, "text/plain; charset=UTF-8", text(args.text, "text"))
		table.insert(out, second)
		part(out, "text/html; charset=UTF-8", text(args.html, "html"))
		table.insert(out, last)
	elseif args.html ~= nil then
		part(out, "text/html; charset=UTF-8", text(args.html, "html"))
	else
		part(out, "text/plain; charset=UTF-8", text(args.text, "text"))
	end
	if #attachments > 0 then
		for _, item in attachments do
			table.insert(out, between)
			attachment(out, item)
		end
		table.insert(out, close)
	end
	return out, threadId
end

-- Uploads the message as message/rfc822 beside Gmail's JSON metadata, so attachments are
-- base64-encoded only once. Drafts nest the thread under message.
local function submit(name: string, method: string, path: string, args: Options, draft: boolean): any
	local mime, threadId = compose(name, args)
	local metadata = if draft then {message = {threadId = threadId}} else {threadId = threadId}
	local body = {"--=_houston_upload\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n" .. json.encode(metadata)
		.. "\r\n--=_houston_upload\r\nContent-Type: message/rfc822\r\n\r\n"}
	table.move(mime, 1, #mime, 2, body)
	table.insert(body, "\r\n--=_houston_upload--\r\n")
	return decode(name, await(http.request({method = method, url = UPLOAD .. path .. "?uploadType=multipart",
		headers = {["Content-Type"] = {"multipart/related; boundary=\"=_houston_upload\""}}, body = table.concat(body)})))
end

exportEndpoints(endpoints)

local READ_OPTIONS = "format: full (default), metadata (headers only) or minimal; metadataHeaders limits metadata headers; maxBodyBytes caps body (default 65536, 0 for no cap) and sets bodyTruncated."
export("getMessage", true, function(input: any): Options
	local raw, limit = read("getMessage", "messages", input)
	return message(raw, limit)
end, "getMessage({id, format?, metadataHeaders?, maxBodyBytes?}) -> {id, threadId, labelIds, snippet, internalDate, from, to, cc, bcc, replyTo, subject, date, messageId, body, bodyTruncated, attachments={{id, filename, mimeType, size, inline, contentId}}, headers}. body is the decoded plain text, else HTML, else the snippet. " .. READ_OPTIONS)
export("getMessages", true, getMessages,
	"getMessages({ids, format?, metadataHeaders?, maxBodyBytes?}) -> messages in the order of ids, each shaped like getMessage. 1 to 100 IDs; use format='metadata' to scan many messages cheaply.")
export("getThread", true, function(input: any): Options
	local thread, limit = read("getThread", "threads", input)
	local messages: {Options} = json.decode("[]")
	for _, raw in thread.messages or {} do table.insert(messages, message(raw, limit)) end
	thread.messages = messages
	return thread
end, "getThread({id, format?, metadataHeaders?, maxBodyBytes?}) -> {id, historyId, messages} with every message of the conversation, oldest first, shaped like getMessage.")
export("getDraft", true, function(input: any): Options
	local draft, limit = read("getDraft", "drafts", input)
	draft.message = message(draft.message or {}, limit)
	return draft
end, "getDraft({id, format?, maxBodyBytes?}) -> {id, message} with message shaped like getMessage.")
export("getAttachment", true, getAttachment,
	"getAttachment({messageId, attachmentId, path}) -> {path, url, size}. Saves an attachment (id from a message's attachments) to a session path; url is a signed Houston download link. Never inline attachment bytes.")
export("listMailFolders", true, function(...: any): {{id: string, name: string}}
	assert(select("#", ...) == 0, "listMailFolders takes no arguments")
	local labels = call("listMailFolders", "GET", API .. "/labels").labels or {}
	local folders: {{id: string, name: string}} = json.decode("[]")
	local seen = {}
	for _, label in labels do
		if type(label) ~= "table" or type(label.id) ~= "string" or label.id == "" or type(label.name) ~= "string" or seen[label.id] then
			houston.fail({operation = "listMailFolders", layer = "upstream", retryable = false, message = "Google returned invalid label metadata"})
		end
		seen[label.id] = true
		table.insert(folders, {id = label.id, name = label.name})
	end
	table.sort(folders, function(a: any, b: any) return a.id < b.id end)
	return folders
end, "listMailFolders() -> {{id, name}} sorted by ID. No arguments; every label of the mailbox.")

local COMPOSE = "to, cc, bcc and replyTo take an address ('Ana <ana@example.com>') or an array of them; from must be one of listSendAs. text and/or html are required. attachments={'path' or {path, filename?, mimeType?}} reads session files; the message must stay under 8 MiB (about 5 MiB of attachments), so share larger files from Drive. inReplyTo=<Gmail message id> replies in that thread: to, subject (Re:) and threading headers default from the original; replyAll=true also copies its To and Cc (except you) into cc."
export("sendMessage", false, function(input: any): any
	return submit("sendMessage", "POST", "/messages/send", options(input), false)
end, "sendMessage({to, subject?, text?, html?, cc?, bcc?, replyTo?, from?, attachments?, inReplyTo?, replyAll?}) -> {id, threadId, labelIds}. " .. COMPOSE .. " A timeout may still have sent the mail: check the SENT label before retrying.")
export("createDraft", false, function(input: any): any
	return submit("createDraft", "POST", "/drafts", options(input), true)
end, "createDraft({...same options as sendMessage}) -> {id, message={id, threadId}}. Saves without sending; send later with sendDraft.")
export("updateDraft", false, function(input: any): any
	local args = options(input)
	local id = text(args.id, "id")
	args.id = nil
	return submit("updateDraft", "PUT", "/drafts/" .. url.segment(id, "id"), args, true)
end, "updateDraft({id, ...same options as sendMessage}) -> draft. Replaces the draft's whole content.")

exports.help = helpWith({
	"Gmail API v1 for the connected mailbox. Operations take one named options object with Google's camelCase fields. Lists and label operations return Google's JSON unchanged; deletes return {success=true}.",
	"Message reads decode bodies and list attachment metadata; attachments download to session files. Sends build the MIME message from plain fields: never base64-encode anything yourself.",
	"Lists return one page: pass nextPageToken as pageToken until it is absent. List results carry IDs only; fetch details with getMessages or getThread.",
	"No hidden paging or retries. Errors report the HTTP status, Google's message and reason. A failed or timed-out write may already have succeeded; check before repeating.",
	"Example: local page = listMessages({q='is:unread in:inbox', maxResults=20}); local ids = {}; for _, m in page.messages do table.insert(ids, m.id) end; getMessages({ids=ids, format='metadata', metadataHeaders={'From','Subject'}}).",
})
return exports
