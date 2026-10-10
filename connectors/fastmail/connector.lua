-- Named options are the preferred interface; positional forms remain compatible.
type Id = string | {id: string}
type IdList = {string} | {{id: string}} | {Id}
type Ids = Id | IdList
type BodyOptions = {maxBodyValueBytes: number?}
type MessageOptions = BodyOptions & {id: string}
type MessagesOptions = BodyOptions & {ids: IdList}
type SearchOptions = {
	from: (string | {string})?, to: (string | {string})?, subject: (string | {string})?, text: (string | {string})?,
	alias: (string | {string})?, aliases: {string}?, folder: (string | {string})?, folders: {string}?,
	after: string?, before: string?, includeSpamTrash: boolean?, maxResults: number?, pageToken: string?,
}
type Address = {email: string, name: string?}
type Upload = string | {path: string, filename: string?, mimeType: string?}
type SendOptions = {
	to: {Address}, text: string, subject: string?, identityId: string?, from: string?,
	cc: {Address}?, bcc: {Address}?, replyTo: {Address}?, attachments: {Upload}?,
}
type ReplyOptions = {
	id: string?, messageId: string?, text: string, all: boolean?, subject: string?, identityId: string?, from: string?,
	cc: {Address}?, bcc: {Address}?, replyTo: {Address}?, attachments: {Upload}?,
}
type Attachment = {id: string, filename: string?, mimeType: string?, size: number?, inline: boolean, contentId: string?}
type Download = {path: string, url: string, size: number?}
type DownloadItem = string | {id: string, path: string?}
type DownloadOptions = {messageId: string, attachmentId: string?, id: string?, path: string?}
type DownloadsOptions = {messageId: string, items: {DownloadItem}}
type MoveOptions = {ids: Ids?, id: string?, folder: string}
type FolderOptions = {name: string, parent: Id?, parentId: string?}
type Message = {
	id: string, threadId: string, from: string, to: string, cc: string, bcc: string, replyTo: string,
	subject: string?, date: string?, messageId: string?, body: string, bodyTruncated: boolean?,
	attachments: {Attachment}, received: {string}, headers: {{name: string, value: string}}?,
	mailboxIds: {[string]: boolean}?, keywords: {[string]: boolean}?, preview: string?,
}
type Folder = {id: string, name: string, role: string?, parentId: string?, totalEmails: number?, unreadEmails: number?}
type Identity = {id: string, email: string, name: string?}
type Alias = {
	email: string, canSend: boolean, masked: boolean, identityId: string?, name: string?,
	maskedId: string?, state: string?, description: string?, forDomain: string?,
}
type MoveResult = {ids: {string}, folderId: string}
type SendResult = {id: string, submissionId: string}

-- Fastmail's JMAP transport uses the shared Houston HTTP/error/file plumbing.
local SESSION_URL = "https://api.fastmail.com/jmap/session"
local BATCH_SIZE = 50
local DEFAULT_BODY_BYTES = 65536
local DEFAULT_PAGE_SIZE = 100
local MAX_PAGE_SIZE = 500
local ERROR_SNIPPET_BYTES = 300
local CORE = "urn:ietf:params:jmap:core"
local MAIL = "urn:ietf:params:jmap:mail"
local SUBMISSION = "urn:ietf:params:jmap:submission"
local MASKED = "https://www.fastmail.com/dev/maskedemail"
local REQUIRED: {[string]: string} = { ["Identity/get"] = SUBMISSION, ["EmailSubmission/set"] = SUBMISSION, ["MaskedEmail/get"] = MASKED }
local SET_ERROR_FIELDS = { "notCreated", "notUpdated", "notDestroyed" }
local SEARCH_FIELDS = { "from", "to", "subject", "text" }
local ADDRESS_FIELDS = { "from", "to", "cc", "bcc", "replyTo" }
local MESSAGE_PROPERTIES = { "id", "threadId", "mailboxIds", "keywords", "from", "to", "cc", "bcc", "replyTo", "subject", "sentAt", "receivedAt", "messageId", "headers", "preview", "textBody", "htmlBody", "attachments", "bodyValues" }
local FOLDER_PROPERTIES = { "id", "name", "role", "parentId", "totalEmails", "unreadEmails" }

type Session = {
	accountId: string, apiUrl: string, username: string, name: string,
	capabilities: {[string]: any}, maskedAccountId: string?, downloadUrl: string?, uploadUrl: string?,
}
-- Execution-local discovery cache: keep only fields used by this connector.
local cachedSession: Session? = nil

type RequestOptions = {method: string, url: string, operation: string, body: string?}
type IdentityOptions = {identityId: string?, from: string?}
type UploadOptions = {path: string, mimeType: string, operation: string}
type SubmitOptions = {operation: string, identity: Identity, fields: any}

local function encode(value: string): string
	return (string.gsub(tostring(value), "[^A-Za-z0-9%-_%.~]", function(c: any)
		return string.format("%%%02X", string.byte(c))
	end))
end

local function fail(operation: string, message: string): never
	error(json.encode({ connector = "fastmail", operation = operation, layer = "upstream", message = message, retryable = false }))
end

local function snippet(body: any)
	if type(body) ~= "string" or body == "" then return "" end
	-- Bound the copy before normalizing a potentially large error response.
	return (string.gsub(string.sub(body, 1, ERROR_SNIPPET_BYTES), "%s+", " "))
end

local function upstream(operation: string, response: HttpResponse)
	local status = response.statusCode
	local chunk = await(response.body:read(ERROR_SNIPPET_BYTES))
	response.body:close()
	houston.fail({
		operation = operation, layer = "upstream", upstream_status = status,
		retryable = status == 429 or status == 502 or status == 503 or status == 504,
		message = "upstream HTTP " .. tostring(status) .. " " .. snippet(if chunk.done then "" else chunk.data),
	})
end

local function request(options: RequestOptions): any
	local response = await(http.request({
		method = options.method,
		url = options.url,
		body = options.body,
		headers = { ["Content-Type"] = { "application/json" } },
	}))
	if response.statusCode < 200 or response.statusCode >= 300 then
		upstream(options.operation, response)
	end
	local body = await(response.body:readAll())
	local ok, decoded = pcall(json.decode, body)
	if not ok then
		houston.fail({
			operation = options.operation, layer = "upstream", upstream_status = response.statusCode, retryable = false,
			message = "upstream returned invalid JSON: " .. snippet(body),
		})
	end
	return decoded
end

local function session(): Session
	if cachedSession then return cachedSession end
	local s = request({method = "GET", url = SESSION_URL, operation = "getProfile"})
	local account = type(s) == "table" and type(s.primaryAccounts) == "table" and (s.primaryAccounts :: {[string]: string})[MAIL]
	if type(account) ~= "string" or account == "" or type(s.apiUrl) ~= "string" or type(s.accounts) ~= "table" or type((s.accounts :: {[string]: any})[account]) ~= "table" then
		return fail("getProfile", "Fastmail session has no primary mail account; check the token's Email scope")
	end
	local maskedAccount = s.primaryAccounts[MASKED]
	local primaryAccount = (s.accounts :: {[string]: any})[account]
	local discovered: Session = {
		accountId = account, apiUrl = s.apiUrl, username = s.username, name = primaryAccount.name,
		capabilities = if type(s.capabilities) == "table" then (s.capabilities :: {[string]: any}) else {},
		maskedAccountId = if type(maskedAccount) == "string" and maskedAccount ~= "" then maskedAccount else nil,
		downloadUrl = s.downloadUrl, uploadUrl = s.uploadUrl,
	}
	cachedSession = discovered
	return discovered
end

local function call(name: string, arguments: {[string]: any}?, operationName: string?): any
	local operation = operationName or name
	local s = session()
	local args = table.clone(arguments or {})
	if args.accountId == nil then args.accountId = s.accountId end
	local using = { CORE, MAIL }
	local cap = REQUIRED[name]
	if cap then
		local label = if cap == SUBMISSION then "Email submission" else "Masked Email"
		if type(s.capabilities) ~= "table" or s.capabilities[cap] == nil then
			fail(operation, "Fastmail token needs " .. label .. " scope")
		end
		using[#using + 1] = cap
	end
	local methodCall: {any} = { name, args, "0" }
	local response = request({method = "POST", url = s.apiUrl, operation = operation, body = json.encode({
		using = using, methodCalls = { methodCall },
	})})
	local result = type(response) == "table" and type(response.methodResponses) == "table" and (response.methodResponses :: {any})[1]
	if type(result) ~= "table" or result[3] ~= "0" or type(result[2]) ~= "table" then fail(operation, "Invalid JMAP response") end
	if result[1] == "error" then
		fail(operation, tostring(result[2].type) .. ": " .. tostring(result[2].description or "JMAP request failed"))
	end
	if result[1] ~= name or type(result[2]) ~= "table" then fail(operation, "Unexpected JMAP method response") end
	for _, invocation in response.methodResponses do
		if type(invocation) ~= "table" or type(invocation[2]) ~= "table" then fail(operation, "Invalid JMAP response") end
		local data = invocation[2]
		if invocation[1] == "error" then fail(operation, tostring(data.type)) end
		for _, field in SET_ERROR_FIELDS do
			if type(data[field]) == "table" then
				for id, problem in data[field] do
					if type(problem) ~= "table" then fail(operation, "Invalid JMAP set error") end
					fail(operation, tostring(id) .. ": " .. tostring(problem.type) .. ": " .. tostring(problem.description or "JMAP operation failed"))
				end
			end
		end
		if type(data.notFound) == "table" and #data.notFound > 0 then fail(operation, "Not found: " .. table.concat(data.notFound, ", ")) end
	end
	return result[2]
end

local function id_of(value: any): string
	if type(value) == "table" then value = value.id end
	if type(value) ~= "string" or value == "" then error("fastmail requires a nonempty id") end
	return value
end

local function id_list(value: any, operation: string): {string}
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

local function each_chunk(ids: {string}): () -> {string}?
	local position = 1
	return function(): {string}?
		if position > #ids then return nil end
		local last = math.min(position + BATCH_SIZE - 1, #ids)
		local batch = table.move(ids, position, last, 1, {})
		position = last + 1
		return batch
	end
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
		emailAddress = s.username, accountId = s.accountId, name = s.name,
		capabilities = caps, canSend = type(s.capabilities) == "table" and s.capabilities[SUBMISSION] ~= nil,
	}
end

function functions.listFolders(): {folders: {Folder}}
	local data = call("Mailbox/get", { properties = FOLDER_PROPERTIES })
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

local function query(options: SearchOptions?, threads: boolean): ({string}, string?)
	local opts: SearchOptions = options or {}
	local limit = opts.maxResults or DEFAULT_PAGE_SIZE
	local position = tonumber(opts.pageToken or "0")
	if type(limit) ~= "number" or limit < 1 or limit > MAX_PAGE_SIZE or limit % 1 ~= 0 then error("fastmail.maxResults must be 1–500") end
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
	for _, key in SEARCH_FIELDS do add(key, (opts :: any)[key]) end
	local function add_alias(value: any)
		if type(value) == "table" then
			for _, item in value do add_alias(item) end
			return
		end
		if value == nil then return end
		if type(value) ~= "string" or value == "" then error("fastmail.alias must be an email address") end
		local conditions: {{[string]: string}} = { { to = value }, { cc = value }, { bcc = value }, { from = value } }
		filters[#filters + 1] = { operator = "OR", conditions = conditions }
	end
	add_alias(opts.alias)
	add_alias(opts.aliases)
	if opts.after then add("after", date(opts.after)) end
	if opts.before then add("before", date(opts.before)) end
	local needsFolders = opts.folder ~= nil or opts.folders ~= nil or not opts.includeSpamTrash
	local folders = if needsFolders then functions.listFolders().folders else {}
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

function functions.listMessages(opts: SearchOptions?)
	local ids, nextPage = query(opts, false)
	local rows: {{id: string}} = json.decode("[]")
	for _, id in ids do rows[#rows + 1] = { id = id } end
	return { messages = rows, nextPageToken = nextPage }
end

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

local function attachment_metadata(parts: any): {Attachment}
	local attachments: {Attachment} = json.decode("[]")
	for _, part in parts or {} do
		attachments[#attachments + 1] = {
			id = part.blobId, filename = part.name, mimeType = part.type, size = part.size,
			inline = part.disposition == "inline" or (part.disposition ~= "attachment" and part.cid ~= nil), contentId = part.cid,
		}
	end
	return attachments
end

local function decorate(msg: any): Message
	remove_nulls(msg)
	for _, key in ADDRESS_FIELDS do msg[key] = addresses(msg[key]) end
	msg.date = msg.sentAt or msg.receivedAt
	msg.messageId = msg.messageId and msg.messageId[1]
	msg.received = json.decode("[]")
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
	msg.attachments = attachment_metadata(msg.attachments)
	msg.bodyValues, msg.textBody, msg.htmlBody = nil, nil, nil
	return msg
end

function functions.getMessages(input: IdList | MessagesOptions, options: BodyOptions?): {Message}
	local ids: any = input
	local opts: BodyOptions = options or {}
	if type(ids) == "table" and ids.ids then opts, ids = ids, ids.ids end
	if type(ids) ~= "table" or #ids < 1 or #ids > BATCH_SIZE then error("fastmail.getMessages requires 1–50 ids") end
	local maxBytes = opts.maxBodyValueBytes or DEFAULT_BODY_BYTES
	if type(maxBytes) ~= "number" or maxBytes < 0 or maxBytes % 1 ~= 0 then
		error("fastmail.maxBodyValueBytes must be a nonnegative integer")
	end
	local requested = {}
	for _, id in ids do requested[#requested + 1] = id_of(id) end
	local data = call("Email/get", {
		ids = requested, properties = MESSAGE_PROPERTIES, fetchTextBodyValues = true, fetchHTMLBodyValues = true,
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

local function body_options(value: any, options: BodyOptions?): BodyOptions
	return options or (if type(value) == "table" then value else {})
end

function functions.getMessage(id: Id | MessageOptions, opts: BodyOptions?): Message
	local options = body_options(id, opts)
	return functions.getMessages({ id_of(id) }, options)[1]
end

function functions.listThreads(opts: SearchOptions?)
	local ids, nextPage = query(opts, true)
	local threads: {{id: string}} = json.decode("[]")
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

function functions.getThread(input: Id | MessageOptions, opts: BodyOptions?): {id: string, messages: {Message}}
	local options = body_options(input, opts)
	local id = id_of(input)
	local data = call("Thread/get", { ids = { id } })
	local thread = data.list and data.list[1]
	if not thread then fail("getThread", "Missing thread " .. id) end
	local messages: {Message} = json.decode("[]")
	for batch in each_chunk(thread.emailIds) do
		for _, msg in functions.getMessages(batch, options) do messages[#messages + 1] = msg end
	end
	return { id = id, messages = messages }
end

function functions.listAttachments(input: Id | Message): {Attachment}
	local id: any = input
	if type(id) == "table" and id.attachments then return id.attachments :: {Attachment} end
	local requested = id_of(id)
	local data = call("Email/get", {ids = {requested}, properties = {"id", "attachments"}}, "listAttachments")
	local msg = data.list and data.list[1]
	if type(msg) ~= "table" or msg.id ~= requested then fail("listAttachments", "Missing message " .. requested) end
	remove_nulls(msg)
	return attachment_metadata(msg.attachments)
end

function functions.getAttachments(input: Id | DownloadsOptions, requested: {DownloadItem}?): {Download}
	local messageId: any = input
	local items: any = requested
	if type(messageId) == "table" and items == nil then items, messageId = messageId.items or messageId, messageId.messageId end
	messageId = id_of(messageId)
	if type(items) ~= "table" then error("fastmail.getAttachments requires attachment items") end
	if #items == 0 then return json.decode("[]") end
	local s = session()
	local template = s.downloadUrl
	if type(template) ~= "string" then return fail("getAttachments", "Missing download URL") end
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
		local values = { accountId = s.accountId, blobId = id, name = attachment.filename or "attachment", type = attachment.mimeType or "application/octet-stream" }
		local url = string.gsub(template, "{(%w+)}", function(key: any) return encode(values[key] or "") end)
		jobs[#jobs + 1] = { path = path, size = attachment.size, url = url }
	end
	local out = {}
	for _, job in jobs do
		local res = await(http.request({ method = "GET", url = job.url }))
		if res.statusCode < 200 or res.statusCode >= 300 then
			res.body:close()
			fail("getAttachment", "Download failed")
		end
		local output = fs.open(job.path, "w")
		output:write(res.body)
		await(output:close())
		out[#out + 1] = { path = job.path, url = await(fs.signedGetUrl(job.path)), size = job.size }
	end
	return out
end

function functions.getAttachment(input: Id | DownloadOptions, attachment: DownloadItem?, destination: string?): Download
	local messageId: any = input
	local attachmentId: any = attachment
	local path = destination
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

function functions.listAliases(): {aliases: {Alias}, notes: {string}}
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
		local account = s.maskedAccountId or s.accountId
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

function functions.listIdentities(): {identities: {Identity}}
	return { identities = as_list(call("Identity/get", nil, "listIdentities").list) }
end

local function lower_email(value: any): string?
	if type(value) ~= "string" or value == "" then return nil end
	return string.lower(value)
end

local function pick_identity(identities: {Identity}, options: IdentityOptions): Identity?
	local identityId, fromEmail = options.identityId, options.from
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

local function require_identity(identities: {Identity}, options: IdentityOptions): Identity
	local identityId, fromEmail = options.identityId, options.from
	local identity = pick_identity(identities, options)
	if identity then return identity end
	if type(fromEmail) == "string" then
		error("fastmail: no sending identity for " .. fromEmail .. "; list aliases with listAliases()")
	end
	if type(identityId) == "string" then
		error("fastmail: no sending identity for " .. identityId .. "; list aliases with listAliases()")
	end
	error("fastmail: specify a valid identityId from listIdentities()")
end

local function upload_blob(options: UploadOptions): any
	local path, mime, operation = options.path, options.mimeType, options.operation
	local s = session()
	local template = s.uploadUrl
	if type(template) ~= "string" or string.find(template, "{accountId}", 1, true) == nil then
		return fail(operation, "Fastmail session has no upload URL")
	end
	local url = string.gsub(template, "{accountId}", encode(s.accountId))
	local stat = await(fs.stat(path))
	if not stat.isFile then error("fastmail: attachment path must be a file") end
	local response = await(http.request({
		method = "POST", url = url, body = fs.open(path, "r"), headers = { ["Content-Type"] = { mime } },
	}))
	if response.statusCode < 200 or response.statusCode >= 300 then
		upstream(operation, response)
	end
	local body = await(response.body:readAll())
	local ok, decoded = pcall(json.decode, body)
	if not ok or type(decoded) ~= "table" or type(decoded.blobId) ~= "string" or decoded.blobId == "" then
		fail(operation, "Fastmail upload did not return a blobId: " .. snippet(body))
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
		local blob = upload_blob({path = path, mimeType = mime, operation = operation})
		local partType = if type(blob.type) == "string" and blob.type ~= "" then blob.type else mime
		out[#out + 1] = { blobId = blob.blobId, name = filename, type = partType, disposition = "attachment" }
	end
	if #out == 0 then return nil end
	return out
end

local function submit(options: SubmitOptions): SendResult
	local operation, identity, fields = options.operation, options.identity, options.fields
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
	if type(made) ~= "table" or type(made.id) ~= "string" or made.id == "" then fail(operation, "Missing draft creation confirmation") end
	-- No automatic retries: a failed/ambiguous submission may leave this draft.
	local submitted = call("EmailSubmission/set", {
		create = { send = { identityId = identity.id, emailId = made.id } },
		onSuccessUpdateEmail = { ["#send"] = { mailboxIds = { [sent] = true }, keywords = { ["$seen"] = true } } },
	}, operation)
	local submission = submitted.created and submitted.created.send
	if type(submission) ~= "table" or type(submission.id) ~= "string" or submission.id == "" then fail(operation, "Missing submission confirmation; draft " .. made.id) end
	return { id = made.id, submissionId = submission.id }
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

local function move_to(ids: {string}, dest: string, operation: string): MoveResult
	local moved: {string} = json.decode("[]") :: {string}
	for batch in each_chunk(ids) do
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
	for batch in each_chunk(list) do
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

function writes.trashMessage(id: Id)
	local moved = move_to({ id_of(id) }, folder_id(functions.listFolders().folders, "trash"), "trashMessage")
	return { id = moved.ids[1] }
end

function writes.deleteMessage(ids: Ids)
	return move_to(id_list(ids, "deleteMessage"), folder_id(functions.listFolders().folders, "trash"), "deleteMessage")
end

function writes.deleteMessages(ids: Ids)
	return writes.deleteMessage(ids)
end

function writes.destroyMessage(ids: Ids)
	return destroy_ids(ids, "destroyMessage")
end

function writes.destroyMessages(ids: Ids)
	return writes.destroyMessage(ids)
end

function writes.archiveMessages(ids: Ids): MoveResult
	local archive = nil
	for _, folder in functions.listFolders().folders do
		if folder.role == "archive" then archive = folder.id; break end
	end
	if type(archive) ~= "string" or archive == "" then return fail("archiveMessages", "Fastmail has no Archive mailbox") end
	return move_to(id_list(ids, "archiveMessages"), archive, "archiveMessages")
end

function writes.archiveMessage(ids: Ids)
	return writes.archiveMessages(ids)
end

function writes.moveMessages(input: Ids | MoveOptions, folder: string?)
	local ids: any = input
	if type(ids) == "table" and folder == nil and type(ids.folder) == "string" then
		folder = ids.folder
		ids = ids.ids or ids.id
	end
	if type(folder) ~= "string" or folder == "" then error("fastmail.moveMessages requires a folder id or role") end
	return move_to(id_list(ids, "moveMessages"), folder_id(functions.listFolders().folders, folder), "moveMessages")
end

function writes.moveMessage(id: Ids | MoveOptions, folder: string?)
	return writes.moveMessages(id, folder)
end

function writes.createFolder(input: string | FolderOptions, parent: Id?)
	local name: any = input
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
function writes.sendMessage(body: SendOptions): SendResult
	if type(body) ~= "table" or type(body.to) ~= "table" or #body.to == 0 then error("fastmail.sendMessage requires to = { { email = ... } }") end
	if type(body.text) ~= "string" then error("fastmail.sendMessage requires text") end
	local identities = as_list(call("Identity/get", nil, "sendMessage").list)
	local identity = require_identity(identities, body)
	return submit({operation = "sendMessage", identity = identity, fields = {
		to = body.to, cc = body.cc, bcc = body.bcc, replyTo = body.replyTo,
		subject = body.subject or "", text = body.text, attachments = body.attachments,
	}})
end

function writes.replyMessage(input: Id | ReplyOptions, options: ReplyOptions?): SendResult
	local id: any = input
	local body: any = options
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
		identity = require_identity(identities, body)
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
		if not identity then identity = require_identity(identities, {}) end
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
	assert(identity, "reply identity was not resolved")
	return submit({operation = "replyMessage", identity = identity, fields = {
		to = to, cc = cc, bcc = body.bcc, replyTo = body.replyTo, subject = subject, text = body.text,
		attachments = body.attachments, inReplyTo = inReplyTo, references = references,
	}})
end

function functions.listMailFolders(...: any): {{id: string, name: string}}
    if select("#", ...) ~= 0 then error("listMailFolders takes no arguments") end
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

local operationHelp: {[string]: string} = {
	archiveMessage = [==[archiveMessage(ids) -> {ids,folderId}. Moves to Archive; fails if Archive is absent. Accepts strings or {id} rows, individually or in a list. Alias of archiveMessages; batches may partially complete.]==],
	archiveMessages = [==[archiveMessages(ids) -> {ids,folderId}. Moves to Archive; fails if Archive is absent. Accepts one ID or a list, strings or {id}; batches of 50 may partially complete. No automatic replay.]==],
	createFolder = [==[createFolder({name:string,parentId:string?}) -> {id,name}. parentId is a folder ID or role; parent is also accepted. Omit both for a top-level folder. Positional createFolder(name,parent?) remains supported.]==],
	deleteMessage = [==[deleteMessage(ids) -> {ids,folderId}. Moves to Trash; does not permanently destroy. Accepts one ID or list of strings/{id}; batches may partially complete.]==],
	deleteMessages = [==[deleteMessages(ids) -> {ids,folderId}. Moves to Trash; does not permanently destroy. Accepts one ID or list of strings/{id}; batches of 50 may partially complete. No automatic replay.]==],
	destroyMessage = [==[destroyMessage(ids) -> {ids}. Permanently destroys messages. Accepts one ID or list of strings/{id}; batches may partially complete. This differs from moving messages to Trash.]==],
	destroyMessages = [==[destroyMessages(ids) -> {ids}. Permanently destroys messages in batches of 50. Accepts one ID or list of strings/{id}. Partial completion is possible; never automatically replay.]==],
	getAttachment = [==[getAttachment({messageId:string,attachmentId:string,path:string?}) -> {path,url,size}. id is also accepted in place of attachmentId. Positional getAttachment(messageId,attachmentId,path?) remains supported. Streams to private session files; url is a signed Houston download. Default path: attachments/<encoded-message-id>/<encoded-attachment-id>. Links expire; files remain scoped to caller and execution workspace.]==],
	getAttachments = [==[getAttachments({messageId:string,items={{id:string,path:string?},...}}) -> ordered {path,url,size}[]. Items also accept ID strings; destination paths must be distinct. Positional getAttachments(messageId,items) remains supported. Streams to session files; never returns inline attachment bytes.]==],
	getMessage = [==[getMessage({id:string,maxBodyValueBytes:number?}) -> message envelope,body,headers,received,attachments. Positional getMessage(id,opts?) remains supported; IDs accept strings or {id}. Envelope includes from,to,cc,bcc,replyTo,subject,date,messageId. Body parts default 64 KiB; bodyTruncated flags truncation. maxBodyValueBytes changes the cap (0 disables it). Request smaller bodies when a proxy response is too large.]==],
	getMessages = [==[getMessages({ids={...},maxBodyValueBytes:number?}) -> messages in requested order. Requires 1–50 IDs, each a string or {id}. Positional getMessages(ids,opts?) remains supported. Same fields and maxBodyValueBytes option as getMessage; request fewer messages when responses are too large.]==],
	getProfile = [==[getProfile() -> {emailAddress, accountId, name, capabilities, canSend}. Reads the connected account profile; does not infer unknown token scopes during discovery.]==],
	getThread = [==[getThread({id:string,maxBodyValueBytes:number?}) -> {id,messages} in conversation order, fetching in batches. Positional getThread(id,opts?) remains supported. Same message-body options as getMessage.]==],
	listAliases = [==[listAliases() -> {aliases,notes}. Each alias has email,canSend,masked. Sending identities add identityId,name; masked addresses add maskedId,state,description,forDomain. Combines addresses shared by both lists. Missing Email submission or Masked Email scope is explained in notes; fails if neither scope is available.]==],
	listAttachments = [==[listAttachments(messageId) -> attachment metadata {id,filename,mimeType,size,inline,contentId}[]. Attachment bytes are never returned inline.]==],
	listFolders = [==[listFolders() -> {folders={{id,name,role,parentId,totalEmails,unreadEmails}}}. Folder filters accept opaque IDs or roles such as INBOX.]==],
	listIdentities = [==[listIdentities() -> {identities}, raw JMAP sending identities. Requires the provider Email submission scope, which may be unknown before the first real call.]==],
	listMailFolders = [==[listMailFolders() -> {id:string,name:string}[]. No arguments. Includes every available folder, sorted by nonempty unique ID; names may repeat. Empty mailboxes return an empty array; provider failures raise errors.]==],
	listMessages = [==[listMessages(opts?) -> {messages={{id}},nextPageToken?}. Newest first; loop using nextPageToken until nil, including a possibly empty last page. opts: from,to,subject,text,after,before (date or UTC timestamp),folder/folders,alias/aliases,includeSpamTrash,maxResults (1–500, default 100),pageToken. Alias searches From/To/Cc/Bcc. Array filters combine with AND; spam/trash excluded unless explicitly selected. No Gmail q syntax.]==],
	listThreads = [==[listThreads(opts?) -> {threads={{id}},nextPageToken?}. Uses the same filters and opaque pagination as listMessages; loop until nextPageToken is nil, even if a page is empty.]==],
	moveMessage = [==[moveMessage({id:string,folder:string}) -> {ids,folderId}. Replaces message mailboxes with one destination. folder accepts ID or role. Positional moveMessage(id,folder) remains supported; id accepts a string or {id}.]==],
	moveMessages = [==[moveMessages({ids={...},folder:string}) -> {ids,folderId}. ids accepts one ID or a list; IDs may be strings or {id}. id is also accepted instead of ids for a single message. folder accepts ID or role. Positional moveMessages(ids,folder) remains supported. Replaces mailboxes with one destination, in batches of 50. Partial completion is possible; never automatically replay.]==],
	replyMessage = [==[replyMessage({id:string,text:string,all:boolean?,subject:string?,identityId:string?,from:string?,cc?,bcc?,replyTo?,attachments?}) -> {id,submissionId}. messageId is also accepted instead of id. Positional replyMessage(id,options) remains supported. Replies to Reply-To, otherwise From; preserves thread message IDs/references. all defaults false. Default sender is receiving identity (To then Cc), then primary identity. all=true adds original To/Cc excluding your identities and reply recipient; cc explicitly replaces that list. Subject derives a Re: prefix unless supplied. Attachments use private session paths as in sendMessage. Email submission scope required. Never automatically replay a partial send.]==],
	sendMessage = [==[sendMessage({to={{email=...}},text=...,subject?,identityId?,from?,cc?,bcc?,replyTo?,attachments?}) -> {id,submissionId}. text and nonempty to required; subject defaults empty. Address arrays use {email,name?}. identityId takes precedence over from. Without either, selects identity matching account username or sole identity; ambiguous sender fails. attachments={{path,filename?,mimeType?}} uploads private session files, never inline base64; MIME defaults application/octet-stream, filename defaults path basename. Moves from Drafts to Sent. Email submission scope required. On timeout inspect Drafts and Sent before retrying: delivery may have succeeded.]==],
	trashMessage = [==[trashMessage(id) -> {id}. Moves a single message to Trash; does not permanently destroy. ID accepts a string or {id}.]==],
}

function functions.help(): string
	local names: {string} = {}
	for name in (functions :: {[string]: any}) do
		if name ~= "help" then names[#names + 1] = name end
	end
	table.sort(names)
	local sections = {"fastmail: configured connection help. Operations are synchronous: they return completed results or raise errors; no wait call is needed. Credentials stay on Houston. Use only the functions listed below. Provider scopes are enforced by real calls; help makes no network requests."}
	for _, name in names do
		local text = operationHelp[name]
		assert(text, "missing help for configured function " .. name)
		sections[#sections + 1] = text
	end
	return table.concat(sections, "\n\n")
end

if config.access == "read-write" then
	for name, fn in (writes :: {[string]: any}) do (functions :: {[string]: any})[name] = fn end
end

return functions
