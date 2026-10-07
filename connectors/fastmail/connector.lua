local state: {session: any, accountId: string?} = {}
-- Fastmail's JMAP transport uses the shared Houston HTTP/error/file plumbing.
local CORE = "urn:ietf:params:jmap:core"
local MAIL = "urn:ietf:params:jmap:mail"
local SUBMISSION = "urn:ietf:params:jmap:submission"
local MASKED = "https://www.fastmail.com/dev/maskedemail"
local REQUIRED: {[string]: string} = { ["Identity/get"] = SUBMISSION, ["EmailSubmission/set"] = SUBMISSION, ["MaskedEmail/get"] = MASKED }

local function encode(value: any)
	return (string.gsub(tostring(value), "[^A-Za-z0-9%-_%.~]", function(c: any)
		return string.format("%%%02X", string.byte(c))
	end))
end

local function fail(operation: any, message: any): never
	error(json.encode({ connector = "fastmail", operation = operation, layer = "upstream", message = message, retryable = false }))
end

local function snippet(body: any)
	if type(body) ~= "string" or body == "" then return "" end
	body = string.gsub(body, "%s+", " ")
	if #body > 300 then body = string.sub(body, 1, 300) end
	return body
end

local function upstream(operation: any, response: any)
	local status = response and response.status
	houston.fail({
		operation = operation, layer = "upstream", upstream_status = status,
		retryable = status == 429 or status == 502 or status == 503 or status == 504,
		message = "upstream HTTP " .. tostring(status) .. " " .. snippet(response and response.body),
	})
end

local function request(method: any, url: any, operation: any, body: any)
	local response = http.request({
		method = method,
		url = url,
		body = body,
		headers = { ["Content-Type"] = "application/json" },
	})
	if not response or type(response.status) ~= "number" or response.status < 200 or response.status >= 300 then
		upstream(operation, response)
	end
	local ok, decoded = pcall(json.decode, response.body)
	if not ok then
		houston.fail({
			operation = operation, layer = "upstream", upstream_status = response.status, retryable = false,
			message = "upstream returned invalid JSON: " .. snippet(response.body),
		})
	end
	return decoded
end

local function allowed_jmap(url: any)
	if type(url) ~= "string" then return false end
	local host, path = string.match(url, "^https://([A-Za-z0-9%.%-]+)(/[^%?#]*)$")
	if host ~= "api.fastmail.com" and host ~= "jmap.fastmail.com" then return false end
	return path == "/jmap/api" or path == "/jmap/api/"
end

local function session(): any
	if not state.session then
		local s = request("GET", "https://api.fastmail.com/jmap/session", "getProfile")
		local account = s and type(s.primaryAccounts) == "table" and (s.primaryAccounts :: {[string]: string})[MAIL]
		if not account or not s.apiUrl or type(s.accounts) ~= "table" or not (s.accounts :: {[string]: any})[account] then
			fail("getProfile", "Fastmail session has no primary mail account; check the token's Email scope")
		end
		assert(type(account) == "string", "Fastmail primary account ID must be a string")
		state.session = s
		state.accountId = account
	end
	return state.session
end

local function call(name: any, args: any, operation: any)
	operation = operation or name
	local s = session()
	if not allowed_jmap(s.apiUrl) then
		fail(operation, "Fastmail session API URL is not an allowlisted JMAP endpoint")
	end
	args = table.clone(args or {})
	if args.accountId == nil then args.accountId = state.accountId end
	local using = { CORE, MAIL }
	local cap = REQUIRED[name]
	if cap then
		local label = if cap == SUBMISSION then "Email submission" else "Masked Email"
		if type(s.capabilities) ~= "table" or s.capabilities[cap] == nil then
			fail(operation, "Fastmail token needs " .. label .. " scope")
		end
		using[#using + 1] = cap
	end
	local response = request("POST", s.apiUrl, operation, json.encode({
		using = using, methodCalls = { { name, args, "0" } },
	}))
	local result = response and type(response.methodResponses) == "table" and (response.methodResponses :: {any})[1]
	if not result or result[3] ~= "0" then fail(operation, "Invalid JMAP response") end
	if result[1] == "error" then
		fail(operation, tostring(result[2].type) .. ": " .. tostring(result[2].description or "JMAP request failed"))
	end
	if result[1] ~= name or type(result[2]) ~= "table" then fail(operation, "Unexpected JMAP method response") end
	for _, invocation in response.methodResponses do
		local data = invocation[2]
		if invocation[1] == "error" then fail(operation, tostring(data.type)) end
		for _, field in { "notCreated", "notUpdated", "notDestroyed" } do
			for id, problem in (type(data[field]) == "table" and data[field] or {}) do
				fail(operation, tostring(id) .. ": " .. tostring(problem.type) .. ": " .. tostring(problem.description or "JMAP operation failed"))
			end
		end
		if type(data.notFound) == "table" and #data.notFound > 0 then fail(operation, "Not found: " .. table.concat(data.notFound, ", ")) end
	end
	return result[2]
end

local function id_of(value: any)
	if type(value) == "table" then value = value.id end
	if type(value) ~= "string" or value == "" then error("fastmail requires a nonempty id") end
	return value
end

local function id_list(value: any, operation: any)
	if type(value) == "string" or (type(value) == "table" and type(value.id) == "string" and value[1] == nil) then
		value = { value }
	end
	if type(value) ~= "table" or #value < 1 then error("fastmail." .. operation .. " requires an id or a list of ids") end
	local out = {}
	for _, item in value do out[#out + 1] = id_of(item) end
	return out
end

local function as_list(value: any)
	if type(value) ~= "table" then return json.decode("[]") end
	return value
end

local function each_chunk(ids: any, size: number)
	local groups = {}
	local batch = {}
	for _, id in ids do
		batch[#batch + 1] = id
		if #batch == size then
			groups[#groups + 1] = batch
			batch = {}
		end
	end
	if #batch > 0 then groups[#groups + 1] = batch end
	return groups
end

local functions = {}

function functions.getProfile()
	local s = session()
	local caps: {string} = json.decode("[]") :: {string}
	if type(s.capabilities) == "table" then
		for name in (s.capabilities :: {[string]: any}) do
			if type(name) == "string" then caps[#caps + 1] = name end
		end
	end
	table.sort(caps)
	return {
		emailAddress = s.username, accountId = state.accountId, name = s.accounts[state.accountId].name,
		capabilities = caps, canSend = type(s.capabilities) == "table" and s.capabilities[SUBMISSION] ~= nil,
	}
end

function functions.listFolders()
	local data = call("Mailbox/get", { properties = { "id", "name", "role", "parentId", "totalEmails", "unreadEmails" } })
	return { folders = as_list(data.list) }
end

local function folder_id(folders: any, value: any)
	value = id_of(value)
	for _, folder in (folders :: {any}) do
		if folder.id == value then return value end
	end
	for _, folder in (folders :: {any}) do
		if folder.role == string.lower(value) then return folder.id end
	end
	error("fastmail: unknown folder " .. value .. "; use listFolders() ids or a role such as INBOX")
end

local function date(value: any)
	if type(value) ~= "string" then error("fastmail dates must be YYYY-MM-DD or UTC timestamps") end
	if string.match(value, "^%d%d%d%d%-%d%d%-%d%d$") then return value .. "T00:00:00Z" end
	return value
end

local function query(opts: any, threads: any)
	opts = opts or {}
	local limit = opts.maxResults or 100
	local position = tonumber(opts.pageToken or "0")
	if type(limit) ~= "number" or limit < 1 or limit > 500 or limit % 1 ~= 0 then error("fastmail.maxResults must be 1–500") end
	if not position or position < 0 or position % 1 ~= 0 then error("fastmail.pageToken must be a nonnegative integer") end
	local filters = {}
	local function add(key: any, value: any)
		if value == nil then return end
		if type(value) == "table" then
			for _, item in value do add(key, item) end
		else
			filters[#filters + 1] = { [key] = value }
		end
	end
	for _, key in { "from", "to", "subject", "text" } do add(key, opts[key]) end
	local function add_alias(value: any)
		if type(value) == "table" then
			for _, item in value do add_alias(item) end
			return
		end
		if value == nil then return end
		if type(value) ~= "string" or value == "" then error("fastmail.alias must be an email address") end
		filters[#filters + 1] = { operator = "OR", conditions = { { to = value }, { cc = value }, { bcc = value }, { from = value } } }
	end
	add_alias(opts.alias)
	add_alias(opts.aliases)
	if opts.after then add("after", date(opts.after)) end
	if opts.before then add("before", date(opts.before)) end
	local folders = functions.listFolders().folders
	local function add_folder(value: any)
		if type(value) == "table" then
			for _, item in value do add_folder(item) end
		elseif value ~= nil then
			add("inMailbox", folder_id(folders, value))
		end
	end
	add_folder(opts.folder)
	add_folder(opts.folders)
	if not opts.includeSpamTrash and not opts.folder and not opts.folders then
		for _, folder in (folders :: {any}) do
			if folder.role == "junk" or folder.role == "trash" then
				filters[#filters + 1] = { operator = "NOT", conditions = { { inMailbox = folder.id } } }
			end
		end
	end
	local filter = nil
	if #filters > 0 then filter = { operator = "AND", conditions = filters } end
	local data = call("Email/query", {
		filter = filter, sort = { { property = "receivedAt", isAscending = false } },
		position = position, limit = limit, collapseThreads = threads, calculateTotal = true,
	})
	local nextPage = nil
	local nextPosition = (data.position or position) + #(data.ids or {})
	if #(data.ids or {}) > 0 and ((type(data.total) == "number" and nextPosition < data.total) or (data.total == nil and #data.ids == limit)) then nextPage = tostring(nextPosition) end
	return data.ids or {}, nextPage
end

function functions.listMessages(opts: any)
	local ids, nextPage = query(opts, false)
	local rows = {}
	for _, id in ids do rows[#rows + 1] = { id = id } end
	return { messages = rows, nextPageToken = nextPage }
end

local PROPERTIES = { "id", "threadId", "mailboxIds", "keywords", "from", "to", "cc", "bcc", "replyTo", "subject", "sentAt", "receivedAt", "messageId", "headers", "preview", "textBody", "htmlBody", "attachments", "bodyValues" }

local function addresses(values: any)
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
local function remove_nulls(value: any)
	for key, item in value do
		if type(item) == "userdata" then value[key] = nil
		elseif type(item) == "table" then remove_nulls(item) end
	end
end

local function decorate(msg: any)
	remove_nulls(msg)
	for _, key in { "from", "to", "cc", "bcc", "replyTo" } do msg[key] = addresses(msg[key]) end
	msg.date = msg.sentAt or msg.receivedAt
	msg.messageId = msg.messageId and msg.messageId[1]
	msg.received = {}
	for _, header in msg.headers or {} do
		if string.lower(header.name) == "received" then msg.received[#msg.received + 1] = header.value end
	end
	local function body(parts: any)
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

function functions.getMessages(ids: any, opts: any)
	if type(ids) == "table" and ids.ids then opts, ids = ids, ids.ids end
	if type(ids) ~= "table" or #ids < 1 or #ids > 50 then error("fastmail.getMessages requires 1–50 ids") end
	opts = opts or {}
	local maxBytes = opts.maxBodyValueBytes or 65536
	if type(maxBytes) ~= "number" or maxBytes < 0 or maxBytes % 1 ~= 0 then
		error("fastmail.maxBodyValueBytes must be a nonnegative integer")
	end
	local requested = {}
	for _, id in ids do requested[#requested + 1] = id_of(id) end
	local data = call("Email/get", {
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

function functions.getMessage(id: any, opts: any)
	if type(id) == "table" then opts = opts or id end
	return functions.getMessages({ id_of(id) }, opts)[1]
end

function functions.listThreads(opts: any)
	local ids, nextPage = query(opts, true)
	local threads = {}
	if #ids > 0 then
		local data = call("Email/get", { ids = ids, properties = { "id", "threadId" } })
		local byId = {}
		for _, msg in data.list or {} do byId[msg.id] = msg.threadId end
		for _, id in ids do
			if not byId[id] then fail("listThreads", "Missing message " .. id) end
			threads[#threads + 1] = { id = byId[id] }
		end
	end
	return { threads = threads, nextPageToken = nextPage }
end

function functions.getThread(id: any, opts: any)
	if type(id) == "table" then opts = opts or id end
	id = id_of(id)
	local data = call("Thread/get", { ids = { id } })
	local thread = data.list and data.list[1]
	if not thread then fail("getThread", "Missing thread " .. id) end
	local messages, batch = {}, {}
	for i, emailId in thread.emailIds do
		batch[#batch + 1] = emailId
		if #batch == 50 or i == #thread.emailIds then
			for _, msg in functions.getMessages(batch, opts) do messages[#messages + 1] = msg end
			batch = {}
		end
	end
	return { id = id, messages = messages }
end

function functions.listAttachments(id: any)
	if type(id) == "table" and id.attachments then return id.attachments end
	return functions.getMessage(id).attachments
end

function functions.getAttachments(messageId: any, items: any): {any}
	if type(messageId) == "table" and items == nil then items, messageId = messageId, messageId.messageId end
	messageId = id_of(messageId)
	if type(items) ~= "table" then error("fastmail.getAttachments requires attachment items") end
	if #items == 0 then return {} end
	local s = session()
	if type(s.downloadUrl) ~= "string" then fail("getAttachments", "Missing download URL") end
	local byId = {}
	for _, item in functions.listAttachments(messageId) do byId[item.id] = item end
	local jobs, paths = {}, {}
	for _, item in items do
		local id = id_of(item)
		local attachment = byId[id]
		if not attachment then error("fastmail: attachment does not belong to this message") end
		local path = type(item) == "table" and item.path or nil
		path = path or ("attachments/" .. encode(messageId) .. "/" .. encode(id))
		if paths[path] then error("fastmail: attachment paths must be distinct") end
		paths[path] = true
		local values = { accountId = state.accountId, blobId = id, name = attachment.filename or "attachment", type = attachment.mimeType or "application/octet-stream" }
		local url = string.gsub(s.downloadUrl, "{(%w+)}", function(key: any) return encode(values[key] or "") end)
		jobs[#jobs + 1] = { path = path, size = attachment.size, url = url }
	end
	local out = {}
	for _, job in jobs do
		local res = http.request({ method = "GET", url = job.url, dest = job.path })
		if not res or type(res.status) ~= "number" or res.status < 200 or res.status >= 300 then fail("getAttachment", "Download failed") end
		out[#out + 1] = { path = job.path, url = fs.signedGetUrl(job.path), size = job.size }
	end
	return out
end

function functions.getAttachment(messageId: any, attachmentId: any, path: any)
	if type(messageId) == "table" and attachmentId == nil then
		path, attachmentId, messageId = messageId.path, messageId.attachmentId or messageId.id, messageId.messageId
	elseif type(attachmentId) == "table" then
		path, attachmentId = attachmentId.path or path, attachmentId.id
	end
	return functions.getAttachments(messageId, { { id = id_of(attachmentId), path = path } })[1]
end

local function has_cap(s: any, cap: string)
	return type(s.capabilities) == "table" and s.capabilities[cap] ~= nil
end

function functions.listAliases()
	local s = session()
	if not has_cap(s, SUBMISSION) and not has_cap(s, MASKED) then
		fail("listAliases", "Fastmail token needs Email submission and/or Masked Email scope")
	end
	local byEmail: {[string]: any} = {}
	local order: {any} = json.decode("[]") :: {any}
	local function row(email: string)
		local key = string.lower(email)
		local existing = byEmail[key]
		if existing then return existing end
		local created = { email = email, canSend = false, masked = false }
		byEmail[key] = created
		order[#order + 1] = created
		return created
	end
	local notes: {string} = json.decode("[]") :: {string}
	if has_cap(s, SUBMISSION) then
		for _, item in as_list(call("Identity/get", nil, "listAliases").list) do
			if type(item) == "table" then remove_nulls(item) end
			if type(item.email) == "string" and item.email ~= "" then
				local alias = row(item.email)
				alias.canSend = true
				alias.identityId = item.id
				alias.name = item.name
			end
		end
	else
		notes[#notes + 1] = "Email submission scope is off, so sending identities were not listed"
	end
	if has_cap(s, MASKED) then
		local account = state.accountId
		if type(s.primaryAccounts) == "table" and type(s.primaryAccounts[MASKED]) == "string" and s.primaryAccounts[MASKED] ~= "" then
			account = s.primaryAccounts[MASKED]
		end
		for _, item in as_list(call("MaskedEmail/get", { accountId = account }, "listAliases").list) do
			if type(item) == "table" then remove_nulls(item) end
			if type(item.email) == "string" and item.email ~= "" then
				local alias = row(item.email)
				alias.masked = true
				alias.maskedId = item.id
				alias.state = item.state
				alias.description = item.description
				alias.forDomain = item.forDomain
				if alias.name == nil and type(item.description) == "string" and item.description ~= "" then alias.name = item.description end
			end
		end
	else
		notes[#notes + 1] = "Masked Email scope is off, so masked addresses were not listed"
	end
	return { aliases = order, notes = notes }
end

function functions.listIdentities()
	return { identities = as_list(call("Identity/get", nil, "listIdentities").list) }
end

local function lower_email(value: any): string?
	if type(value) ~= "string" or value == "" then return nil end
	return string.lower(value)
end

local function pick_identity(identities: any, identityId: any, fromEmail: any)
	if identityId ~= nil and type(identityId) ~= "string" then error("fastmail identityId must be a string") end
	if fromEmail ~= nil and type(fromEmail) ~= "string" then error("fastmail from must be an email address") end
	if identityId then
		for _, item in identities do
			if item.id == identityId then return item end
		end
		return nil
	end
	if fromEmail then
		local want = lower_email(fromEmail)
		for _, item in identities do
			if lower_email(item.email) == want then return item end
		end
		return nil
	end
	local username = lower_email(session().username)
	for _, item in identities do
		if lower_email(item.email) == username then return item end
	end
	if #identities == 1 then return identities[1] end
	return nil
end

local function require_identity(identities: any, identityId: any, fromEmail: any)
	local identity = pick_identity(identities, identityId, fromEmail)
	if identity then return identity end
	if type(fromEmail) == "string" then
		error("fastmail: no sending identity for " .. fromEmail .. "; list aliases with listAliases()")
	end
	if type(identityId) == "string" then
		error("fastmail: no sending identity for " .. identityId .. "; list aliases with listAliases()")
	end
	error("fastmail: specify a valid identityId from listIdentities()")
end

local function upload_blob(path: any, mime: any, operation: any)
	local s = session()
	local template = s.uploadUrl
	if type(template) ~= "string" or string.find(template, "{accountId}", 1, true) == nil then
		fail(operation, "Fastmail session has no upload URL")
	end
	if type(state.accountId) ~= "string" then fail(operation, "Fastmail session has no mail account") end
	local url = string.gsub(template, "{accountId}", encode(state.accountId))
	local host = string.match(url, "^https://([A-Za-z0-9%.%-]+)/")
	if host ~= "api.fastmail.com" and host ~= "jmap.fastmail.com" then
		fail(operation, "Fastmail upload URL is not on an allowlisted host")
	end
	local stat = fs.stat(path)
	if not stat.isFile then error("fastmail: attachment path must be a file") end
	local response = http.request({
		method = "POST", url = url, src = path, headers = { ["Content-Type"] = mime },
	})
	if not response or type(response.status) ~= "number" or response.status < 200 or response.status >= 300 then
		upstream(operation, response)
	end
	local ok, decoded = pcall(json.decode, response.body)
	if not ok or type(decoded) ~= "table" or type(decoded.blobId) ~= "string" or decoded.blobId == "" then
		fail(operation, "Fastmail upload did not return a blobId: " .. snippet(response and response.body))
	end
	return decoded
end

local function attachment_parts(items: any, operation: any): any
	if items == nil then return nil end
	if type(items) ~= "table" then error("fastmail attachments must be a list of {path}") end
	local out = {}
	for _, item in items do
		local path = item
		local filename, mime = nil, nil
		if type(item) == "table" then
			path = item.path
			filename = item.filename
			mime = item.mimeType
		end
		if type(path) ~= "string" or path == "" then error("fastmail attachment requires a session file path") end
		if filename ~= nil and type(filename) ~= "string" then error("fastmail attachment filename must be a string") end
		if mime ~= nil and (type(mime) ~= "string" or mime == "") then error("fastmail attachment mimeType must be a string") end
		if filename == nil or filename == "" then filename = string.match(path, "([^/]+)$") or "attachment" end
		mime = mime or "application/octet-stream"
		local blob = upload_blob(path, mime, operation)
		local partType = if type(blob.type) == "string" and blob.type ~= "" then blob.type else mime
		out[#out + 1] = { blobId = blob.blobId, name = filename, type = partType, disposition = "attachment" }
	end
	if #out == 0 then return nil end
	return out
end

local function submit(operation: any, identity: any, fields: any)
	local folders = functions.listFolders().folders
	local drafts, sent = folder_id(folders, "drafts"), folder_id(folders, "sent")
	local parts = attachment_parts(fields.attachments, operation)
	local draft = {
		mailboxIds = { [drafts] = true }, keywords = { ["$draft"] = true },
		from = { { email = identity.email, name = identity.name } }, to = fields.to, cc = fields.cc, bcc = fields.bcc,
		replyTo = fields.replyTo, subject = fields.subject or "", textBody = { { partId = "text", type = "text/plain" } },
		bodyValues = { text = { value = fields.text } },
		inReplyTo = fields.inReplyTo, references = fields.references, attachments = parts,
	}
	local created = call("Email/set", { create = { draft = draft } }, operation)
	local made = created.created and created.created.draft
	if not made or not made.id then fail(operation, "Missing draft creation confirmation") end
	-- No automatic retries: a failed/ambiguous submission may leave this draft.
	local submitted = call("EmailSubmission/set", {
		create = { send = { identityId = identity.id, emailId = made.id } },
		onSuccessUpdateEmail = { ["#send"] = { mailboxIds = { [sent] = true }, keywords = { ["$seen"] = true } } },
	}, operation)
	if not submitted.created or not submitted.created.send then fail(operation, "Missing submission confirmation; draft " .. made.id) end
	return { id = made.id, submissionId = submitted.created.send.id }
end

local function address_objects(values: any)
	local out = {}
	if type(values) ~= "table" then return out end
	for _, value in values do
		if type(value) == "table" and type(value.email) == "string" and value.email ~= "" then
			local addr = { email = value.email }
			if type(value.name) == "string" and value.name ~= "" then addr.name = value.name end
			out[#out + 1] = addr
		end
	end
	return out
end

local function message_ids(value: any)
	local out: {string} = json.decode("[]") :: {string}
	if type(value) == "table" then
		for _, item in value do
			if type(item) == "string" and item ~= "" then out[#out + 1] = item end
		end
	elseif type(value) == "string" then
		for token in string.gmatch(value, "%S+") do out[#out + 1] = token end
	end
	return out
end

local function reply_subject(subject: any)
	if type(subject) ~= "string" then subject = "" end
	if string.match(subject, "^[Rr][Ee]:") then return subject end
	if subject == "" then return "Re:" end
	return "Re: " .. subject
end

local function move_to(ids: any, folder: any, operation: any)
	local dest = folder_id(functions.listFolders().folders, folder)
	local moved: {string} = json.decode("[]") :: {string}
	for _, batch in each_chunk(ids, 50) do
		local update = {}
		for _, id in batch do update[id] = { mailboxIds = { [dest] = true } } end
		local data = call("Email/set", { update = update }, operation)
		for _, id in batch do
			if type(data.updated) ~= "table" or data.updated[id] == nil then
				fail(operation, "Missing update confirmation for " .. id)
			end
			moved[#moved + 1] = id
		end
	end
	return { ids = moved, folderId = dest }
end

local function destroy_ids(ids: any, operation: any)
	local list = id_list(ids, operation)
	local gone: {string} = json.decode("[]") :: {string}
	for _, batch in each_chunk(list, 50) do
		local data = call("Email/set", { destroy = batch }, operation)
		local found: {[string]: boolean} = {}
		if type(data.destroyed) == "table" then
			for _, id in data.destroyed do found[id] = true end
		end
		for _, id in batch do
			if not found[id] then fail(operation, "Missing destroy confirmation for " .. id) end
			gone[#gone + 1] = id
		end
	end
	return { ids = gone }
end

local writes = {}

function writes.trashMessage(id: any)
	local moved = move_to({ id_of(id) }, "trash", "trashMessage")
	return { id = moved.ids[1] }
end

function writes.deleteMessage(ids: any)
	return move_to(id_list(ids, "deleteMessage"), "trash", "deleteMessage")
end

function writes.deleteMessages(ids: any)
	return writes.deleteMessage(ids)
end

function writes.destroyMessage(ids: any)
	return destroy_ids(ids, "destroyMessage")
end

function writes.destroyMessages(ids: any)
	return writes.destroyMessage(ids)
end

function writes.archiveMessages(ids: any)
	local archive = nil
	for _, folder in functions.listFolders().folders do
		if folder.role == "archive" then archive = folder.id; break end
	end
	if type(archive) ~= "string" or archive == "" then fail("archiveMessages", "Fastmail has no Archive mailbox") end
	return move_to(id_list(ids, "archiveMessages"), archive, "archiveMessages")
end

function writes.archiveMessage(ids: any)
	return writes.archiveMessages(ids)
end

function writes.moveMessages(ids: any, folder: any)
	if type(ids) == "table" and folder == nil and type(ids.folder) == "string" then
		folder = ids.folder
		ids = ids.ids or ids.id
	end
	if type(folder) ~= "string" or folder == "" then error("fastmail.moveMessages requires a folder id or role") end
	return move_to(id_list(ids, "moveMessages"), folder, "moveMessages")
end

function writes.moveMessage(id: any, folder: any)
	return writes.moveMessages(id, folder)
end

function writes.createFolder(name: any, parent: any)
	if type(name) == "table" and parent == nil then
		parent = name.parent or name.parentId
		name = name.name
	end
	if type(name) ~= "string" or name == "" then error("fastmail.createFolder requires a name") end
	local spec: {[string]: any} = { name = name }
	if parent ~= nil then spec.parentId = folder_id(functions.listFolders().folders, parent) end
	local data = call("Mailbox/set", { create = { folder = spec } }, "createFolder")
	local made = data.created and data.created.folder
	if type(made) ~= "table" or type(made.id) ~= "string" or made.id == "" then
		fail("createFolder", "Missing folder creation confirmation")
	end
	local createdName = if type(made.name) == "string" and made.name ~= "" then made.name else name
	return { id = made.id, name = createdName }
end

-- A structured message avoids adding a second MIME/base64 implementation.
function writes.sendMessage(body: any)
	if type(body) ~= "table" or type(body.to) ~= "table" or #body.to == 0 then error("fastmail.sendMessage requires to = { { email = ... } }") end
	if type(body.text) ~= "string" then error("fastmail.sendMessage requires text") end
	local identities = as_list(call("Identity/get", nil, "sendMessage").list)
	local identity = require_identity(identities, body.identityId, body.from)
	return submit("sendMessage", identity, {
		to = body.to, cc = body.cc, bcc = body.bcc, replyTo = body.replyTo,
		subject = body.subject or "", text = body.text, attachments = body.attachments,
	})
end

function writes.replyMessage(id: any, body: any)
	if type(id) == "table" and body == nil then
		body = id
		id = id.id or id.messageId
	end
	id = id_of(id)
	if type(body) ~= "table" or type(body.text) ~= "string" then error("fastmail.replyMessage requires text") end
	local data = call("Email/get", {
		ids = { id },
		properties = { "id", "messageId", "inReplyTo", "references", "from", "to", "cc", "replyTo", "subject" },
	}, "replyMessage")
	local msg = data.list and data.list[1]
	if type(msg) ~= "table" then fail("replyMessage", "Missing message " .. id) end
	remove_nulls(msg)
	local source = msg.replyTo
	if type(source) ~= "table" or #source == 0 then source = msg.from end
	local to = address_objects(source)
	if #to == 0 then error("fastmail.replyMessage: the message has no reply address") end
	local identities = as_list(call("Identity/get", nil, "replyMessage").list)
	for _, item in identities do
		if type(item) == "table" then remove_nulls(item) end
	end
	local identity = nil
	if body.identityId ~= nil or body.from ~= nil then
		identity = require_identity(identities, body.identityId, body.from)
	else
		local byEmail: {[string]: any} = {}
		for _, item in identities do
			local key = lower_email(item.email)
			if key ~= nil and byEmail[key] == nil then byEmail[key] = item end
		end
		for _, list in { msg.to, msg.cc } do
			for _, addr in address_objects(list) do
				local key = lower_email(addr.email)
				if key ~= nil then
					local hit = byEmail[key]
					if hit then identity = hit; break end
				end
			end
			if identity then break end
		end
		if not identity then identity = require_identity(identities, nil, nil) end
	end
	local cc = body.cc
	if body.all and cc == nil then
		local skip: {[string]: boolean} = {}
		for _, item in identities do
			local key = lower_email(item.email)
			if key ~= nil then skip[key] = true end
		end
		for _, addr in to do
			local key = lower_email(addr.email)
			if key ~= nil then skip[key] = true end
		end
		local combined = {}
		local seen: {[string]: boolean} = {}
		for _, list in { msg.to, msg.cc } do
			for _, addr in address_objects(list) do
				local key = lower_email(addr.email)
				if key ~= nil and not skip[key] and not seen[key] then
					seen[key] = true
					combined[#combined + 1] = addr
				end
			end
		end
		if #combined > 0 then cc = combined end
	end
	local ids = message_ids(msg.messageId)
	local inReplyTo = nil
	local references = nil
	if #ids > 0 then
		inReplyTo = ids
		local refs: {string} = json.decode("[]") :: {string}
		local seen: {[string]: boolean} = {}
		local function add(values: any)
			for _, value in message_ids(values) do
				if not seen[value] then
					seen[value] = true
					refs[#refs + 1] = value
				end
			end
		end
		add(msg.references)
		add(ids)
		references = refs
	end
	local subject = body.subject
	if type(subject) ~= "string" then subject = reply_subject(msg.subject) end
	return submit("replyMessage", identity, {
		to = to, cc = cc, bcc = body.bcc, replyTo = body.replyTo, subject = subject, text = body.text,
		attachments = body.attachments, inReplyTo = inReplyTo, references = references,
	})
end

if config.access == "read-write" then
	for name, fn in (writes :: {[string]: any}) do (functions :: {[string]: any})[name] = fn end
end

function functions.listMailFolders(): {{id: string, name: string}}
	local folders = functions.listFolders().folders
	if type(folders) ~= "table" then error("mail provider returned invalid folders") end
	local out: {{id: string, name: string}} = json.decode("[]")
	local seen = {}
	for _, folder in (folders :: {any}) do
		if type(folder.id) ~= "string" or folder.id == "" or type(folder.name) ~= "string" or seen[folder.id] then
			error("mail provider returned invalid folder metadata")
		end
		seen[folder.id] = true
		out[#out + 1] = { id = folder.id, name = folder.name }
	end
	table.sort(out, function(a: any, b: any) return a.id < b.id end)
	return out
end

return functions
