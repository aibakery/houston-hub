-- Gmail connector: one mailbox through Houston's HTTP proxy.
-- Host primitives used: http.send (with this instance's connector id) and json.
-- Public functions are the mail contract later providers reuse; only the
-- HTTP paths and filter compilation below are Gmail-specific.

local BASE = "https://gmail.googleapis.com/gmail/v1/users/me"
local BATCH_URL = "https://gmail.googleapis.com/batch/gmail/v1"
local MAX_BATCH = 50
local BATCH_BOUNDARY = "batch_houston"
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local function encode(s)
	s = tostring(s)
	return (string.gsub(s, "[^A-Za-z0-9%-_%.~]", function(c)
		return string.format("%%%02X", string.byte(c))
	end))
end

local function scalar(value)
	if type(value) == "boolean" then
		if value then
			return "true"
		end
		return "false"
	end
	return tostring(value)
end

local function add_query(parts, key, value)
	if value == nil then
		return
	end
	if type(value) == "table" then
		for _, item in value do
			add_query(parts, key, item)
		end
		return
	end
	parts[#parts + 1] = encode(key) .. "=" .. encode(scalar(value))
end

local function query_string(params)
	if type(params) ~= "table" then
		return ""
	end
	local parts = {}
	for key, value in params do
		add_query(parts, key, value)
	end
	if #parts == 0 then
		return ""
	end
	local s = parts[1]
	for i = 2, #parts do
		s = s .. "&" .. parts[i]
	end
	return s
end

local function require_ctx(ctx)
	if type(ctx) ~= "table" or type(ctx.id) ~= "string" or ctx.id == "" then
		error("gmail connector id is required")
	end
end

local function request(ctx, method, path, params, operation, cursor, body)
	require_ctx(ctx)
	local url = BASE .. path
	local qs = query_string(params)
	if qs ~= "" then
		url = url .. "?" .. qs
	end
	if cursor == nil and type(params) == "table" then
		cursor = params.pageToken
	end
	local headers, payload = nil, nil
	if body ~= nil then
		headers = { ["Content-Type"] = "application/json" }
		payload = json.encode(body)
	end
	return connector_http.send({
		connector = "gmail",
		operation = operation,
		method = method,
		path = path,
		url = url,
		headers = headers,
		body = payload,
		connector_id = ctx.id,
		affected_cursor = cursor,
	})
end

local function gmail_date(value)
	local s = tostring(value)
	local y, m, d = string.match(s, "^(%d%d%d%d)%D(%d%d)%D(%d%d)")
	if y then
		return y .. "/" .. m .. "/" .. d
	end
	return s
end

local function quote_term(value)
	local s = tostring(value)
	if string.find(s, '[%s"()]') == nil then
		return s
	end
	s = string.gsub(s, "\\", "\\\\")
	s = string.gsub(s, '"', '\\"')
	return '"' .. s .. '"'
end

local function add_term(terms, prefix, value)
	if value == nil then
		return
	end
	if type(value) == "table" then
		for _, item in value do
			add_term(terms, prefix, item)
		end
		return
	end
	local s = tostring(value)
	if s == "" then
		return
	end
	if prefix == "" then
		terms[#terms + 1] = s
	else
		terms[#terms + 1] = prefix .. quote_term(s)
	end
end

local function compile_query(opts)
	local terms = {}
	add_term(terms, "from:", opts.from)
	add_term(terms, "to:", opts.to)
	add_term(terms, "subject:", opts.subject)
	if opts.after ~= nil and tostring(opts.after) ~= "" then
		terms[#terms + 1] = "after:" .. gmail_date(opts.after)
	end
	if opts.before ~= nil and tostring(opts.before) ~= "" then
		terms[#terms + 1] = "before:" .. gmail_date(opts.before)
	end
	add_term(terms, "", opts.text)
	add_term(terms, "", opts.q)
	if #terms == 0 then
		return nil
	end
	return table.concat(terms, " ")
end

local function folder_ids(opts)
	local ids = {}
	local function add(value)
		if value == nil then
			return
		end
		if type(value) == "table" then
			for _, item in value do
				add(item)
			end
			return
		end
		local s = tostring(value)
		if s ~= "" then
			ids[#ids + 1] = s
		end
	end
	add(opts.folder)
	add(opts.folders)
	add(opts.labelIds)
	if #ids == 0 then
		return nil
	end
	return ids
end

local function list_params(opts)
	opts = opts or {}
	return {
		maxResults = opts.maxResults,
		pageToken = opts.pageToken,
		q = compile_query(opts),
		labelIds = folder_ids(opts),
		includeSpamTrash = opts.includeSpamTrash,
	}
end

local function get_params(opts)
	opts = opts or {}
	return {
		format = opts.format,
		metadataHeaders = opts.metadataHeaders,
	}
end

local function message_id(value)
	if type(value) == "table" then
		return value.id
	end
	return value
end

local function collect_ids(ids)
	if type(ids) ~= "table" then
		return {}
	end
	local out = {}
	for _, item in ids do
		local id = message_id(item)
		if type(id) == "string" and id ~= "" then
			out[#out + 1] = id
		end
	end
	return out
end

local function last_json_end(part, json_start)
	local last = nil
	local k = json_start
	while true do
		local n = string.find(part, "}", k, true)
		if not n then
			break
		end
		last = n
		k = n + 1
	end
	return last
end

local function parse_batch(body)
	if type(body) ~= "string" or body == "" then
		error("gmail.getMessages: empty batch response")
	end
	local boundary = string.match(body, "%-%-([A-Za-z0-9_%-]+)")
	if not boundary then
		error("gmail.getMessages: missing multipart boundary")
	end
	local sep = "--" .. boundary
	local out = {}
	local start = 1
	while true do
		local _, j = string.find(body, sep, start, true)
		if not j then
			break
		end
		local next_i = string.find(body, sep, j + 1, true)
		if not next_i then
			break
		end
		local part = string.sub(body, j + 1, next_i - 1)
		local status = string.match(part, "HTTP/%d%.%d (%d+)")
		if status and tonumber(status) >= 400 then
			error("gmail.getMessages part failed: " .. tostring(status))
		end
		local json_start = string.find(part, "{", 1, true)
		if json_start then
			local json_end = last_json_end(part, json_start)
			if json_end then
				out[#out + 1] = json.decode(string.sub(part, json_start, json_end))
			end
		end
		start = next_i
	end
	return out
end

local function decode_base64url(data)
	if type(data) ~= "string" or data == "" then
		return ""
	end
	data = string.gsub(data, "-", "+")
	data = string.gsub(data, "_", "/")
	while #data % 4 ~= 0 do
		data = data .. "="
	end
	local out = {}
	local acc, n = 0, 0
	for i = 1, #data do
		local c = string.sub(data, i, i)
		if c ~= "=" then
			local p = string.find(B64, c, 1, true)
			if p then
				acc = acc * 64 + (p - 1)
				n += 1
				if n == 4 then
					out[#out + 1] = string.char(
						bit32.extract(acc, 16, 8),
						bit32.extract(acc, 8, 8),
						bit32.extract(acc, 0, 8)
					)
					acc, n = 0, 0
				end
			end
		end
	end
	if n == 3 then
		acc = acc * 64
		out[#out + 1] = string.char(bit32.extract(acc, 16, 8), bit32.extract(acc, 8, 8))
	elseif n == 2 then
		acc = acc * 64 * 64
		out[#out + 1] = string.char(bit32.extract(acc, 16, 8))
	end
	return table.concat(out)
end

local function header_map(headers)
	local map = {}
	if type(headers) ~= "table" then
		return map
	end
	for _, h in headers do
		if type(h) == "table" and type(h.name) == "string" then
			map[string.lower(h.name)] = h.value or ""
		end
	end
	return map
end

local function header_values(headers, name)
	local want = string.lower(name)
	local out = {}
	if type(headers) ~= "table" then
		return out
	end
	for _, h in headers do
		if type(h) == "table" and type(h.name) == "string" and string.lower(h.name) == want then
			out[#out + 1] = h.value or ""
		end
	end
	return out
end

local function content_id(raw)
	if type(raw) ~= "string" or raw == "" then
		return nil
	end
	return (string.gsub(string.gsub(raw, "^%s*<", ""), ">%s*$", ""))
end

local function collect_part(part, bodies, atts)
	if type(part) ~= "table" then
		return
	end
	if type(part.parts) == "table" then
		for _, child in part.parts do
			collect_part(child, bodies, atts)
		end
		return
	end
	local mime = string.lower(tostring(part.mimeType or ""))
	local headers = header_map(part.headers)
	local disp = string.lower(headers["content-disposition"] or "")
	local filename = part.filename
	if type(filename) ~= "string" or filename == "" then
		filename = nil
	end
	local attached = string.find(disp, "attachment", 1, true) ~= nil
	local body = part.body or {}
	if (mime == "text/plain" or mime == "text/html") and not attached and not filename then
		local data = decode_base64url(body.data)
		if mime == "text/plain" then
			if bodies.text == nil and data ~= "" then
				bodies.text = data
			end
		elseif bodies.html == nil and data ~= "" then
			bodies.html = data
		end
		return
	end
	local cid = content_id(headers["content-id"])
	local has_id = type(body.attachmentId) == "string" and body.attachmentId ~= ""
	if
		not filename
		and not has_id
		and cid == nil
		and not attached
		and string.find(disp, "inline", 1, true) == nil
	then
		return
	end
	local inline = false
	if attached then
		inline = false
	elseif string.find(disp, "inline", 1, true) ~= nil or cid ~= nil then
		inline = true
	end
	atts[#atts + 1] = {
		id = body.attachmentId,
		filename = filename,
		mimeType = part.mimeType,
		size = body.size,
		inline = inline,
		contentId = cid,
		data = body.data,
	}
end

local function decorate_message(msg)
	if type(msg) ~= "table" then
		return msg
	end
	local payload = msg.payload
	local headers = {}
	if type(payload) == "table" and type(payload.headers) == "table" then
		headers = payload.headers
	end
	local map = header_map(headers)
	msg.from = map.from
	msg.to = map.to
	msg.cc = map.cc
	msg.bcc = map.bcc
	msg.replyTo = map["reply-to"]
	msg.subject = map.subject
	msg.date = map.date
	msg.messageId = map["message-id"]
	msg.headers = headers
	msg.received = header_values(headers, "Received")
	local bodies = {}
	local atts = {}
	if type(payload) == "table" then
		collect_part(payload, bodies, atts)
	end
	local body = bodies.text
	if body == nil or body == "" then
		body = bodies.html
	end
	if body == nil or body == "" then
		body = msg.snippet
	end
	msg.body = body or ""
	msg.attachments = atts
	return msg
end

local function decorate_thread(thread)
	if type(thread) == "table" and type(thread.messages) == "table" then
		for _, m in thread.messages do
			decorate_message(m)
		end
	end
	return thread
end

local functions = {}

function functions.getProfile(ctx)
	return request(ctx, "GET", "/profile", nil, "getProfile")
end

function functions.listFolders(ctx)
	local raw = request(ctx, "GET", "/labels", nil, "listFolders")
	if type(raw) ~= "table" then
		return { folders = {} }
	end
	local folders = {}
	if type(raw.labels) == "table" then
		for _, lab in raw.labels do
			if type(lab) == "table" then
				folders[#folders + 1] = {
					id = lab.id,
					name = lab.name,
					type = lab.type,
				}
			end
		end
	end
	raw.folders = folders
	return raw
end

function functions.listMessages(ctx, opts)
	return request(ctx, "GET", "/messages", list_params(opts), "listMessages")
end

function functions.getMessage(ctx, id, opts)
	if type(id) == "table" then
		opts = id
		id = id.id
	end
	if type(id) ~= "string" or id == "" then
		error("gmail.getMessage requires a message id")
	end
	return decorate_message(request(ctx, "GET", "/messages/" .. encode(id), get_params(opts), "getMessage", id))
end

function functions.listThreads(ctx, opts)
	return request(ctx, "GET", "/threads", list_params(opts), "listThreads")
end

function functions.getThread(ctx, id, opts)
	if type(id) == "table" then
		opts = id
		id = id.id
	end
	if type(id) ~= "string" or id == "" then
		error("gmail.getThread requires a thread id")
	end
	return decorate_thread(request(ctx, "GET", "/threads/" .. encode(id), get_params(opts), "getThread", id))
end

function functions.getMessages(ctx, ids, opts)
	if type(ids) == "table" and ids[1] == nil and type(ids.ids) == "table" then
		opts = ids
		ids = ids.ids
	end
	local collected = collect_ids(ids)
	if #collected == 0 then
		error("gmail.getMessages requires a list of message ids")
	end
	if #collected > MAX_BATCH then
		error("gmail.getMessages accepts at most 50 ids")
	end
	require_ctx(ctx)
	local qs = query_string(get_params(opts))
	local parts = {}
	for i, id in collected do
		local path = "/gmail/v1/users/me/messages/" .. encode(id)
		if qs ~= "" then
			path = path .. "?" .. qs
		end
		parts[#parts + 1] = "--"
			.. BATCH_BOUNDARY
			.. "\r\nContent-Type: application/http\r\nContent-ID: <item"
			.. tostring(i - 1)
			.. ">\r\n\r\nGET "
			.. path
			.. "\r\n"
	end
	parts[#parts + 1] = "--" .. BATCH_BOUNDARY .. "--\r\n"
	local body = table.concat(parts, "")
	local raw = connector_http.send({
		connector = "gmail",
		operation = "getMessages",
		method = "POST",
		path = "/batch/gmail/v1",
		url = BATCH_URL,
		headers = { ["Content-Type"] = "multipart/mixed; boundary=" .. BATCH_BOUNDARY },
		body = body,
		connector_id = ctx.id,
		raw = true,
	})
	local out = parse_batch(raw)
	for _, msg in out do
		decorate_message(msg)
	end
	return out
end

function functions.listAttachments(ctx, id)
	if type(id) == "table" then
		if type(id.attachments) == "table" then
			return id.attachments
		end
		id = id.id
	end
	if type(id) ~= "string" or id == "" then
		error("gmail.listAttachments requires a message id")
	end
	local msg = functions.getMessage(ctx, id)
	if type(msg) ~= "table" or type(msg.attachments) ~= "table" then
		return {}
	end
	return msg.attachments
end

local function attachment_path(attachmentId, path)
	if type(path) == "string" and path ~= "" then
		return path
	end
	local safe = string.gsub(tostring(attachmentId or "file"), "[^%w%-_]", "")
	if #safe > 24 then
		safe = string.sub(safe, 1, 24)
	end
	if safe == "" then
		safe = "file"
	end
	return "attachments/" .. safe
end

local function start_attachment(ctx, messageId, attachmentId, path)
	require_ctx(ctx)
	return connector_http.sendAsync({
		connector = "gmail",
		operation = "getAttachment",
		method = "GET",
		path = "/messages/" .. encode(messageId) .. "/attachments/" .. encode(attachmentId),
		url = BASE .. "/messages/" .. encode(messageId) .. "/attachments/" .. encode(attachmentId),
		dest = path,
		connector_id = ctx.id,
		affected_cursor = attachmentId,
	})
end

local function finish_attachment(path)
	local parsed = json.decode(fs.read(path))
	if type(parsed) ~= "table" then
		error("gmail.getAttachment: invalid attachment payload")
	end
	local data = decode_base64url(parsed.data)
	fs.write(path, data)
	local signed = nil
	if type(fs) == "table" and type(fs.signedGetUrl) == "function" then
		signed = fs.signedGetUrl(path)
	end
	return {
		path = path,
		url = signed,
		size = parsed.size or #data,
	}
end

function functions.getAttachments(ctx, messageId, items)
	if type(messageId) == "table" and items == nil then
		items = messageId
		messageId = messageId.messageId or messageId.id
	end
	if type(messageId) ~= "string" or messageId == "" then
		error("gmail.getAttachments requires a message id")
	end
	if type(items) ~= "table" then
		error("gmail.getAttachments requires a list of attachments")
	end
	local jobs = {}
	for _, item in ipairs(items) do
		local attachmentId = item
		local path = nil
		if type(item) == "table" then
			attachmentId = item.id or item.attachmentId
			path = item.path
		end
		if type(attachmentId) ~= "string" or attachmentId == "" then
			error("gmail.getAttachments requires an attachment id")
		end
		path = attachment_path(attachmentId, path)
		jobs[#jobs + 1] = { handle = start_attachment(ctx, messageId, attachmentId, path), path = path }
	end
	if #jobs == 0 then
		return {}
	end
	local handles = {}
	for i, job in ipairs(jobs) do
		handles[i] = job.handle
	end
	local results = connector_http.wait(handles)
	if type(results) ~= "table" or results.status ~= nil then
		results = { results }
	end
	local out = {}
	for i, job in ipairs(jobs) do
		local res = results[i]
		if type(res) ~= "table" or (res.status ~= nil and (res.status < 200 or res.status >= 300)) then
			connector_http.fail({
				layer = "upstream",
				upstream_status = res and res.status,
				connector = "gmail",
				operation = "getAttachment",
				path = job.path,
				message = "download failed",
			})
		end
		out[i] = finish_attachment(job.path)
	end
	return out
end

function functions.getAttachment(ctx, messageId, attachmentId, path)
	if type(messageId) == "table" and attachmentId == nil then
		path = messageId.path
		attachmentId = messageId.attachmentId or messageId.id
		messageId = messageId.messageId
	elseif type(attachmentId) == "table" then
		path = attachmentId.path or path
		attachmentId = attachmentId.id or attachmentId.attachmentId
	end
	if type(messageId) ~= "string" or messageId == "" then
		error("gmail.getAttachment requires a message id")
	end
	if type(attachmentId) ~= "string" or attachmentId == "" then
		error("gmail.getAttachment requires an attachment id")
	end
	return functions.getAttachments(ctx, messageId, { { id = attachmentId, path = path } })[1]
end

local writes = {}

function writes.sendMessage(ctx, body)
	if type(body) ~= "table" then
		error("gmail.sendMessage requires a message body")
	end
	return request(ctx, "POST", "/messages/send", nil, "sendMessage", nil, body)
end

function writes.trashMessage(ctx, id)
	if type(id) == "table" then
		id = id.id
	end
	if type(id) ~= "string" or id == "" then
		error("gmail.trashMessage requires a message id")
	end
	return request(ctx, "POST", "/messages/" .. encode(id) .. "/trash", nil, "trashMessage", id)
end

return {
	name = "gmail",
	description = "Read a connected Gmail mailbox.",
	signatures = {
		getProfile = "getProfile()",
		listFolders = "listFolders()",
		listMessages = "listMessages(opts?)",
		getMessage = "getMessage(id, opts?)",
		listThreads = "listThreads(opts?)",
		getThread = "getThread(id, opts?)",
		getMessages = "getMessages(ids, opts?)",
		listAttachments = "listAttachments(id)",
		getAttachment = "getAttachment(messageId, attachmentId, path?)",
		getAttachments = "getAttachments(messageId, items)",
		sendMessage = "sendMessage(body)",
		trashMessage = "trashMessage(id)",
	},
	help = [[
# Gmail

Read mail for one connected mailbox. Credentials stay on the Houston
server. This is the mail contract: later mailbox providers implement the
same functions. Use the instance from `houston.connectors()` — do not
call provider URLs yourself.

List-connector signatures are enough to call. Return compact rows;
`truncate` defaults true. Loop pagination in one `run`.

## getProfile()

Mailbox identity (`emailAddress`, plus provider extras).

## listFolders()

Folders in this mailbox (Gmail labels). Returns `folders`
(`{ id, name, type }[]`). Use `id` as `folder` when listing messages.

## listMessages(opts?)

Search and list message ids. Returns **ids only** (`id`, `threadId`) —
not subjects or bodies. Optional filters on `opts`:

- `from`, `to`, `subject` (string, or array of strings)
- `after`, `before` (YYYY-MM-DD)
- `folder` or `folders` (id from `listFolders`, or array)
- `text` (free-text)
- `maxResults` (number, default 100, max 500)
- `pageToken` (string)
- `includeSpamTrash` (boolean)

This list+filters path is search. Returns `messages` (`{ id, threadId }[]`),
`nextPageToken`, and `resultSizeEstimate`. `resultSizeEstimate` is capped
(often ~201) and is **not a count**. Use `#messages` plus `nextPageToken`.
`messages` is omitted when there are no results.

## getMessage(id, opts?)

One message. `id` may be a string or a table with `id`. Returns envelope
fields so callers do not parse headers or MIME:

- `from`, `to`, `cc`, `bcc`, `replyTo`, `subject`, `date`, `messageId`
- `body` (plain text when present)
- `attachments` (metadata rows; use `getAttachment` to download)
- `headers` (raw header list, including `Received`)
- `received` (Received header values, for originating IP when present)

`getMessage("abc")` and `getMessage({ id = "abc" })` are the same call.

## listAttachments(id)

Attachment rows for one message: `id`, `filename`, `mimeType`, `size`,
`inline`, `contentId`. Same rows as `getMessage(id).attachments`. `id`
may be a message id, `{ id }`, or an already-fetched message.

## getAttachment(messageId, attachmentId, path?)

Downloads one listed attachment onto a session path (streams past the
proxy buffer) and returns `{ path, url, size }` where `url` is a Houston
signed GET URL. `attachmentId` is `id` from `listAttachments` /
`getMessage.attachments`. Optional `path` defaults under `attachments/`.
`getAttachment({ messageId, id, path })` is the same call. Do not inline
bytes or base64; give the caller the signed URL.

## getAttachments(messageId, items)

Downloads several attachments in parallel. `items` is `{ { id, path? }, ... }`.
Returns an array of `{ path, url, size }` in the same order. Uses `http.sendAsync`
handles and `http.wait`.

## listThreads(opts?)

Conversation list. Same optional filters as `listMessages`. Returns
`threads` (`{ id, snippet, historyId }[]`), `nextPageToken`, and
`resultSizeEstimate` (capped; not a count). Prefer this plus `getThread`
for conversation state. Loop pagination in one `run`.

## getThread(id, opts?)

The thread and **all messages** in that conversation. Each message has
the same envelope, body, and attachments fields as `getMessage`.

## getMessages(ids, opts?)

Batch get, at most 50 ids. `ids` is an array of message ids (strings or
`{ id }`), or a table with `ids`. Returns an array of messages (same
shape as `getMessage`). One Houston call. Otherwise loop `getMessage`
in the same `run`.

Write functions are bound only when this instance is read-write.

## sendMessage(body)

Send a message. `body` is typically `{ raw = "<base64url RFC 2822>" }`.

## trashMessage(id)

Move a message to trash. `id` may be a string or a table with `id`.

## Example

	return {
		run = function()
			return c.listMessages({ maxResults = 5, folder = "INBOX" })
		end,
	}
]],
	functions = functions,
	writes = writes,
}
