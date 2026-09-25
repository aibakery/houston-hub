-- Fastmail's JMAP transport uses the shared Houston HTTP/error/file plumbing.
local CORE = "urn:ietf:params:jmap:core"
local MAIL = "urn:ietf:params:jmap:mail"
local SUBMISSION = "urn:ietf:params:jmap:submission"
local encode = connector_http.encode

local function fail(operation, message)
	connector_http.fail({ connector = "fastmail", operation = operation, layer = "upstream", message = message, retryable = false })
end

local function request(ctx, method, url, operation, body, dest)
	return connector_http.send({
		connector = "fastmail", connector_id = ctx.id, operation = operation,
		method = method, url = url, path = url, body = body, dest = dest,
		headers = { ["Content-Type"] = "application/json" },
	})
end

local function session(ctx)
	if not ctx.session then
		local s = request(ctx, "GET", "https://api.fastmail.com/jmap/session", "getProfile")
		local account = s and s.primaryAccounts and s.primaryAccounts[MAIL]
		if not account or not s.apiUrl or not s.accounts or not s.accounts[account] then
			fail("getProfile", "Fastmail session has no primary mail account; check the token's Email scope")
		end
		ctx.session = s
		ctx.accountId = account
	end
	return ctx.session
end

local function call(ctx, name, args)
	local s = session(ctx)
	args = table.clone(args or {})
	args.accountId = ctx.accountId
	local using = { CORE, MAIL }
	if name == "Identity/get" or name == "EmailSubmission/set" then
		if not s.capabilities or not s.capabilities[SUBMISSION] then
			fail(name, "Fastmail token needs Email submission scope")
		end
		using[#using + 1] = SUBMISSION
	end
	local response = request(ctx, "POST", s.apiUrl, name, json.encode({
		using = using, methodCalls = { { name, args, "0" } },
	}))
	local result = response and response.methodResponses and response.methodResponses[1]
	if not result or result[3] ~= "0" then fail(name, "Invalid JMAP response") end
	if result[1] == "error" then
		fail(name, tostring(result[2].type) .. ": " .. tostring(result[2].description or "JMAP request failed"))
	end
	if result[1] ~= name or type(result[2]) ~= "table" then fail(name, "Unexpected JMAP method response") end
	for _, invocation in response.methodResponses do
		local data = invocation[2]
		if invocation[1] == "error" then fail(name, tostring(data.type)) end
		for _, field in { "notCreated", "notUpdated", "notDestroyed" } do
			for id, problem in (type(data[field]) == "table" and data[field] or {}) do
				fail(name, tostring(id) .. ": " .. tostring(problem.type) .. ": " .. tostring(problem.description or "JMAP operation failed"))
			end
		end
		if type(data.notFound) == "table" and #data.notFound > 0 then fail(name, "Not found: " .. table.concat(data.notFound, ", ")) end
	end
	local data = result[2]
	return data
end

local function id_of(value)
	if type(value) == "table" then value = value.id end
	if type(value) ~= "string" or value == "" then error("fastmail requires a nonempty id") end
	return value
end

local functions = {}

function functions.getProfile(ctx)
	local s = session(ctx)
	return { emailAddress = s.username, accountId = ctx.accountId, name = s.accounts[ctx.accountId].name }
end

function functions.listFolders(ctx)
	local data = call(ctx, "Mailbox/get", { properties = { "id", "name", "role", "parentId", "totalEmails", "unreadEmails" } })
	return { folders = data.list or {} }
end

local function folder_id(folders, value)
	value = id_of(value)
	for _, folder in folders do
		if folder.id == value then return value end
	end
	for _, folder in folders do
		if folder.role == string.lower(value) then return folder.id end
	end
	error("fastmail: unknown folder " .. value .. "; use listFolders() ids or a role such as INBOX")
end

local function date(value)
	if type(value) ~= "string" then error("fastmail dates must be YYYY-MM-DD or UTC timestamps") end
	if string.match(value, "^%d%d%d%d%-%d%d%-%d%d$") then return value .. "T00:00:00Z" end
	return value
end

local function query(ctx, opts, threads)
	opts = opts or {}
	local limit = opts.maxResults or 100
	local position = tonumber(opts.pageToken or "0")
	if type(limit) ~= "number" or limit < 1 or limit > 500 or limit % 1 ~= 0 then error("fastmail.maxResults must be 1–500") end
	if not position or position < 0 or position % 1 ~= 0 then error("fastmail.pageToken must be a nonnegative integer") end
	local filters = {}
	local function add(key, value)
		if value == nil then return end
		if type(value) == "table" then
			for _, item in value do add(key, item) end
		else
			filters[#filters + 1] = { [key] = value }
		end
	end
	for _, key in { "from", "to", "subject", "text" } do add(key, opts[key]) end
	if opts.after then add("after", date(opts.after)) end
	if opts.before then add("before", date(opts.before)) end
	local folders = functions.listFolders(ctx).folders
	local function add_folder(value)
		if type(value) == "table" then
			for _, item in value do add_folder(item) end
		elseif value ~= nil then
			add("inMailbox", folder_id(folders, value))
		end
	end
	add_folder(opts.folder)
	add_folder(opts.folders)
	if not opts.includeSpamTrash and not opts.folder and not opts.folders then
		for _, folder in folders do
			if folder.role == "junk" or folder.role == "trash" then
				filters[#filters + 1] = { operator = "NOT", conditions = { { inMailbox = folder.id } } }
			end
		end
	end
	local filter = nil
	if #filters > 0 then filter = { operator = "AND", conditions = filters } end
	local data = call(ctx, "Email/query", {
		filter = filter, sort = { { property = "receivedAt", isAscending = false } },
		position = position, limit = limit, collapseThreads = threads, calculateTotal = true,
	})
	local nextPage = nil
	local nextPosition = (data.position or position) + #(data.ids or {})
	if #(data.ids or {}) > 0 and ((type(data.total) == "number" and nextPosition < data.total) or (data.total == nil and #data.ids == limit)) then nextPage = tostring(nextPosition) end
	return data.ids or {}, nextPage
end

function functions.listMessages(ctx, opts)
	local ids, nextPage = query(ctx, opts, false)
	local rows = {}
	for _, id in ids do rows[#rows + 1] = { id = id } end
	return { messages = rows, nextPageToken = nextPage }
end

local PROPERTIES = { "id", "threadId", "mailboxIds", "keywords", "from", "to", "cc", "bcc", "replyTo", "subject", "sentAt", "receivedAt", "messageId", "headers", "preview", "textBody", "htmlBody", "attachments", "bodyValues" }

local function addresses(values)
	local out = {}
	for _, value in values or {} do
		if value.name and value.name ~= "" then
			out[#out + 1] = value.name .. " <" .. value.email .. ">"
		else
			out[#out + 1] = value.email
		end
	end
	return table.concat(out, ", ")
end

-- JSON null is a truthy sentinel in the sandbox. Remove optional null fields
-- before normalizing envelopes and MIME parts; retain it in JMAP set responses.
local function remove_nulls(value)
	for key, item in value do
		if type(item) == "userdata" then value[key] = nil
		elseif type(item) == "table" then remove_nulls(item) end
	end
end

local function decorate(msg)
	remove_nulls(msg)
	for _, key in { "from", "to", "cc", "bcc", "replyTo" } do msg[key] = addresses(msg[key]) end
	msg.date = msg.sentAt or msg.receivedAt
	msg.messageId = msg.messageId and msg.messageId[1]
	msg.received = {}
	for _, header in msg.headers or {} do
		if string.lower(header.name) == "received" then msg.received[#msg.received + 1] = header.value end
	end
	local function body(parts)
		local out = {}
		for _, part in parts or {} do
			local value = msg.bodyValues and msg.bodyValues[part.partId]
			if value then
				out[#out + 1] = value.value
				if value.isTruncated then msg.bodyTruncated = true end
			end
		end
		return table.concat(out, "\n")
	end
	msg.body = body(msg.textBody)
	if msg.body == "" then msg.body = body(msg.htmlBody) end
	if msg.body == "" then msg.body = msg.preview or "" end
	local attachments = {}
	for _, part in msg.attachments or {} do
		attachments[#attachments + 1] = {
			id = part.blobId, filename = part.name, mimeType = part.type, size = part.size,
			inline = part.disposition == "inline" or (part.disposition ~= "attachment" and part.cid ~= nil), contentId = part.cid,
		}
	end
	msg.attachments = attachments
	msg.bodyValues, msg.textBody, msg.htmlBody = nil, nil, nil
	return msg
end

function functions.getMessages(ctx, ids, opts)
	if type(ids) == "table" and ids.ids then opts, ids = ids, ids.ids end
	if type(ids) ~= "table" or #ids < 1 or #ids > 50 then error("fastmail.getMessages requires 1–50 ids") end
	opts = opts or {}
	local maxBytes = opts.maxBodyValueBytes or 65536
	if type(maxBytes) ~= "number" or maxBytes < 0 or maxBytes % 1 ~= 0 then
		error("fastmail.maxBodyValueBytes must be a nonnegative integer")
	end
	local requested = {}
	for _, id in ids do requested[#requested + 1] = id_of(id) end
	local data = call(ctx, "Email/get", {
		ids = requested, properties = PROPERTIES, fetchTextBodyValues = true, fetchHTMLBodyValues = true,
		maxBodyValueBytes = maxBytes,
	})
	local byId, out = {}, {}
	for _, msg in data.list or {} do byId[msg.id] = decorate(msg) end
	for _, id in requested do
		if not byId[id] then fail("getMessages", "Missing message " .. id) end
		out[#out + 1] = byId[id]
	end
	return out
end

function functions.getMessage(ctx, id, opts)
	if type(id) == "table" then opts = opts or id end
	return functions.getMessages(ctx, { id_of(id) }, opts)[1]
end

function functions.listThreads(ctx, opts)
	local ids, nextPage = query(ctx, opts, true)
	local threads = {}
	if #ids > 0 then
		local data = call(ctx, "Email/get", { ids = ids, properties = { "id", "threadId" } })
		local byId = {}
		for _, msg in data.list or {} do byId[msg.id] = msg.threadId end
		for _, id in ids do
			if not byId[id] then fail("listThreads", "Missing message " .. id) end
			threads[#threads + 1] = { id = byId[id] }
		end
	end
	return { threads = threads, nextPageToken = nextPage }
end

function functions.getThread(ctx, id, opts)
	if type(id) == "table" then opts = opts or id end
	id = id_of(id)
	local data = call(ctx, "Thread/get", { ids = { id } })
	local thread = data.list and data.list[1]
	if not thread then fail("getThread", "Missing thread " .. id) end
	local messages, batch = {}, {}
	for i, emailId in thread.emailIds do
		batch[#batch + 1] = emailId
		if #batch == 50 or i == #thread.emailIds then
			for _, msg in functions.getMessages(ctx, batch, opts) do messages[#messages + 1] = msg end
			batch = {}
		end
	end
	return { id = id, messages = messages }
end

function functions.listAttachments(ctx, id)
	if type(id) == "table" and id.attachments then return id.attachments end
	return functions.getMessage(ctx, id).attachments
end

function functions.getAttachments(ctx, messageId, items)
	if type(messageId) == "table" and items == nil then items, messageId = messageId, messageId.messageId end
	messageId = id_of(messageId)
	if type(items) ~= "table" then error("fastmail.getAttachments requires attachment items") end
	if #items == 0 then return {} end
	local s = session(ctx)
	if type(s.downloadUrl) ~= "string" then fail("getAttachments", "Missing download URL") end
	local byId = {}
	for _, item in functions.listAttachments(ctx, messageId) do byId[item.id] = item end
	local jobs, paths = {}, {}
	for _, item in items do
		local id = id_of(item)
		local attachment = byId[id]
		if not attachment then error("fastmail: attachment does not belong to this message") end
		local path = type(item) == "table" and item.path or nil
		path = path or ("attachments/" .. encode(messageId) .. "/" .. encode(id))
		if paths[path] then error("fastmail: attachment paths must be distinct") end
		paths[path] = true
		local values = { accountId = ctx.accountId, blobId = id, name = attachment.filename or "attachment", type = attachment.mimeType or "application/octet-stream" }
		local url = string.gsub(s.downloadUrl, "{(%w+)}", function(key) return encode(values[key] or "") end)
		jobs[#jobs + 1] = { path = path, size = attachment.size, url = url }
	end
	local handles = {}
	for _, job in jobs do
		handles[#handles + 1] = connector_http.sendAsync({ connector = "fastmail", connector_id = ctx.id,
			operation = "getAttachment", method = "GET", url = job.url, path = job.url, dest = job.path })
	end
	local results = connector_http.wait(handles)
	if results.status then results = { results } end
	local out = {}
	for i, job in jobs do
		local res = results[i]
		if not res or res.status < 200 or res.status >= 300 then fail("getAttachment", "Download failed") end
		out[#out + 1] = { path = job.path, url = fs.signedGetUrl(job.path), size = job.size }
	end
	return out
end

function functions.getAttachment(ctx, messageId, attachmentId, path)
	if type(messageId) == "table" and attachmentId == nil then
		path, attachmentId, messageId = messageId.path, messageId.attachmentId or messageId.id, messageId.messageId
	elseif type(attachmentId) == "table" then
		path, attachmentId = attachmentId.path or path, attachmentId.id
	end
	return functions.getAttachments(ctx, messageId, { { id = id_of(attachmentId), path = path } })[1]
end

local writes = {}

function writes.trashMessage(ctx, id)
	id = id_of(id)
	local folders = functions.listFolders(ctx).folders
	local trash = folder_id(folders, "trash")
	local data = call(ctx, "Email/set", { update = { [id] = { mailboxIds = { [trash] = true } } } })
	if not data.updated or data.updated[id] == nil then fail("trashMessage", "Missing update confirmation") end
	return { id = id }
end

-- A structured message avoids adding a second MIME/base64 implementation.
function writes.sendMessage(ctx, body)
	if type(body) ~= "table" or type(body.to) ~= "table" or #body.to == 0 then error("fastmail.sendMessage requires to = { { email = ... } }") end
	if type(body.text) ~= "string" then error("fastmail.sendMessage requires text") end
	local identities = call(ctx, "Identity/get").list or {}
	local identity = nil
	for _, item in identities do
		if (body.identityId and item.id == body.identityId) or (not body.identityId and item.email == session(ctx).username) then identity = item; break end
	end
	if not identity and not body.identityId and #identities == 1 then identity = identities[1] end
	if not identity then error("fastmail: specify a valid identityId from listIdentities()") end
	local folders = functions.listFolders(ctx).folders
	local drafts, sent = folder_id(folders, "drafts"), folder_id(folders, "sent")
	local created = call(ctx, "Email/set", { create = { draft = {
		mailboxIds = { [drafts] = true }, keywords = { ["$draft"] = true },
		from = { { email = identity.email, name = identity.name } }, to = body.to, cc = body.cc, bcc = body.bcc,
		replyTo = body.replyTo, subject = body.subject or "", textBody = { { partId = "text", type = "text/plain" } },
		bodyValues = { text = { value = body.text } },
	} } })
	local draft = created.created and created.created.draft
	if not draft or not draft.id then fail("sendMessage", "Missing draft creation confirmation") end
	-- No automatic retries: a failed/ambiguous submission may leave this draft.
	local submitted = call(ctx, "EmailSubmission/set", {
		create = { send = { identityId = identity.id, emailId = draft.id } },
		onSuccessUpdateEmail = { ["#send"] = { mailboxIds = { [sent] = true }, keywords = { ["$seen"] = true } } },
	})
	if not submitted.created or not submitted.created.send then fail("sendMessage", "Missing submission confirmation; draft " .. draft.id) end
	return { id = draft.id, submissionId = submitted.created.send.id }
end

function functions.listIdentities(ctx)
	return { identities = call(ctx, "Identity/get").list or {} }
end

return {
	name = "fastmail", description = "Read a Fastmail mailbox, threads, and attachments; optionally send and trash mail.",
	signatures = {
		getProfile = "getProfile()", listFolders = "listFolders()", listMessages = "listMessages(opts?)",
		getMessage = "getMessage(id, opts?)", getMessages = "getMessages(ids, opts?)",
		listThreads = "listThreads(opts?)", getThread = "getThread(id, opts?)",
		listAttachments = "listAttachments(id)", getAttachment = "getAttachment(messageId, attachmentId, path?)",
		getAttachments = "getAttachments(messageId, items)", listIdentities = "listIdentities()",
		sendMessage = "sendMessage(body)", trashMessage = "trashMessage(id)",
	},
	help = [[
# Fastmail
Use an instance from houston.connectors(). API tokens stay on the server.
getProfile() returns emailAddress, accountId, name. listFolders() returns folders
with id/name/role; use an id or a role such as INBOX as a folder filter.

listMessages(opts?) returns messages ({id}[]) and nextPageToken. listThreads(opts?)
returns threads ({id}[]) with the same pagination. Loop until nextPageToken is nil;
a final page may be empty. Newest first. Filters: from, to, subject, text; after and
before (YYYY-MM-DD or UTC timestamp); folder/folders. Arrays combine with AND.
maxResults defaults to 100 (1–500); pageToken is opaque to callers. Spam/trash are
excluded unless a folder is explicit or includeSpamTrash=true. No Gmail q syntax.

getMessage(id, opts?) and getMessages(ids, opts?) return envelope strings (from, to,
cc, bcc, replyTo, subject, date, messageId), body, headers, received, and attachments.
Ids may be strings or {id}; getMessages accepts 1–50 ids or {ids={...}} and preserves
order. Body parts default to 64 KiB; bodyTruncated flags this. Set
opts.maxBodyValueBytes to change the cap (0 disables it). If a response exceeds
the proxy limit, request fewer messages or smaller bodies.
getThread(id, opts?) returns all messages in conversation order, fetching in batches.

listAttachments(id) returns metadata: id, filename, mimeType, size, inline, contentId.
getAttachment(messageId, attachmentId, path?) returns {path,url,size}; the URL is a
signed Houston download. getAttachments(messageId, items) downloads in parallel;
items is {{id,path?},...}. Bytes are stored in session files, never returned inline.

Writes appear only with read-write access. trashMessage(id) moves mail to Trash.
listIdentities() needs the token's Email submission scope and returns identities.
sendMessage({to={{email="recipient@example.com"}},subject="Hello",text="Hi"}) sends
plain text using your primary identity; optional identityId selects another identity.
cc, bcc, replyTo use the same address arrays. Sent mail is moved from Drafts to Sent.
The token needs Email and Email submission scopes without Read-only access.
If sending fails, inspect Drafts/Sent before retrying: delivery may have succeeded.

Example: return {run=function() return c.listMessages({folder="INBOX",maxResults=5}) end}
]],
	functions = functions, writes = writes,
}
