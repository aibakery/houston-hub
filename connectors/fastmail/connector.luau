-- Named options are the preferred interface; positional forms remain compatible.
type Id = string | {id: string}
type IdList = {string} | {{id: string}} | {Id}
type Ids = Id | IdList
type BodyOptions = {maxBodyValueBytes: number?, bodyFormat: string?}
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
	to: {Address}?, cc: {Address}?, bcc: {Address}?, replyTo: {Address}?, attachments: {Upload}?,
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
type DraftResult = {id: string, threadId: string?}
-- createDraft and updateDraft options: every field is optional, but createDraft needs text and updateDraft needs id.
type DraftOptions = {
	id: string?, text: string?, subject: string?, identityId: string?, from: string?,
	to: {Address}?, cc: {Address}?, bcc: {Address}?, replyTo: {Address}?, attachments: {Upload}?,
}
type SendDraftOptions = {id: string, identityId: string?}

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
local RECIPIENT_FIELDS = { "to", "cc", "bcc", "replyTo" }
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
-- A sender without an id comes from a draft-only token and cannot submit.
type Sender = {id: string?, email: string, name: string?}
type Fields = {
	to: {Address}?, cc: {Address}?, bcc: {Address}?, replyTo: {Address}?, subject: string, text: string?,
	attachments: {Upload}?, inReplyTo: {string}?, references: {string}?,
}
type Composed = {sender: Sender, fields: Fields}
type EmailFields = {
	mailboxIds: {[string]: boolean}, keywords: {[string]: boolean}, from: {Address}?,
	to: {Address}?, cc: {Address}?, bcc: {Address}?, replyTo: {Address}?, subject: string?, text: string?, html: string?,
	inReplyTo: {string}?, references: {string}?, attachments: any,
}

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
	local body = await(response.body:readPrefix(ERROR_SNIPPET_BYTES))
	houston.fail({
		operation = operation, layer = "upstream", upstream_status = status,
		retryable = status == 429 or status == 502 or status == 503 or status == 504,
		message = "upstream HTTP " .. tostring(status) .. " " .. snippet(body),
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

local function as_list(value: any): {any}
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
local operationHelp: {[string]: string} = {}

operationHelp.getProfile = [==[getProfile() -> {emailAddress, accountId, name, capabilities, canSend}. Reads the connected account profile; does not infer unknown token scopes during discovery.]==]
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

operationHelp.listFolders = [==[listFolders() -> {folders={{id,name,role,parentId,totalEmails,unreadEmails}}}. Folder filters accept opaque IDs or roles such as INBOX.]==]
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

operationHelp.listMessages = [==[listMessages(opts?) -> {messages={{id}},nextPageToken?}. Newest first; loop using nextPageToken until nil, including a possibly empty last page. opts: from,to,subject,text,after,before (date or UTC timestamp),folder/folders,alias/aliases,includeSpamTrash,maxResults (1–500, default 100),pageToken. Alias searches From/To/Cc/Bcc. Array filters combine with AND; spam/trash excluded unless explicitly selected. No Gmail q syntax.]==]
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

-- Match Unicode White_Space, as the native IMAP reader does; preserve the original text.
local function hasContent(value: string): boolean
	for _, point in utf8.codes(value) do
		if not ((point >= 9 and point <= 13) or point == 32 or point == 0x85 or point == 0xA0 or point == 0x1680
			or (point >= 0x2000 and point <= 0x200A) or point == 0x2028 or point == 0x2029 or point == 0x202F or point == 0x205F or point == 0x3000) then
			return true
		end
	end
	return false
end

-- Joins the fetched values of body parts of one MIME type (nil: any); found is false when none matched.
local function join_parts(msg: any, parts: any, mimeType: string?): (string, boolean, boolean)
	local out = {}
	local truncated = false
	for _, part in parts or {} do
		local value = msg.bodyValues and msg.bodyValues[part.partId]
		if value and (mimeType == nil or part.type == nil or part.type == mimeType) then
			out[#out + 1] = value.value
			if value.isTruncated then truncated = true end
		end
	end
	return table.concat(out, "\n"), truncated, #out > 0
end

local function decorate(msg: any, bodyFormat: string): Message
	remove_nulls(msg)
	for _, key in ADDRESS_FIELDS do msg[key] = addresses(msg[key]) end
	msg.date = msg.sentAt or msg.receivedAt
	msg.messageId = msg.messageId and msg.messageId[1]
	msg.received = json.decode("[]")
	for _, header in msg.headers or {} do
		if string.lower(header.name) == "received" then msg.received[#msg.received + 1] = header.value end
	end
	if bodyFormat == "html" then msg.body, msg.bodyTruncated = join_parts(msg, msg.htmlBody, "text/html")
	else msg.body, msg.bodyTruncated = join_parts(msg, msg.textBody, if bodyFormat == "text" then "text/plain" else nil) end
	if bodyFormat == "auto" then
		if not msg.bodyTruncated and not hasContent(msg.body) then msg.body, msg.bodyTruncated = join_parts(msg, msg.htmlBody, nil) end
		if not msg.bodyTruncated and not hasContent(msg.body) then msg.body = msg.preview or "" end
	end
	msg.attachments = attachment_metadata(msg.attachments)
	msg.bodyValues, msg.textBody, msg.htmlBody = nil, nil, nil
	return msg
end

local function body_format(opts: BodyOptions): string
	local value = if opts.bodyFormat == nil then "auto" else opts.bodyFormat
	assert(value == "auto" or value == "text" or value == "html", "bodyFormat must be auto, text or html")
	return value
end

operationHelp.getMessages = [==[getMessages({ids={...},maxBodyValueBytes:number?,bodyFormat:string?}) -> messages in requested order. Requires 1–50 IDs, each a string or {id}. Positional getMessages(ids,opts?) remains supported. Same fields and body options as getMessage; request fewer messages when responses are too large.]==]
function functions.getMessages(input: IdList | MessagesOptions, options: BodyOptions?): {Message}
	local ids: any = input
	local opts: BodyOptions = options or {}
	if type(ids) == "table" and ids.ids then opts, ids = ids, ids.ids end
	if type(ids) ~= "table" or #ids < 1 or #ids > BATCH_SIZE then error("fastmail.getMessages requires 1–50 ids") end
	local bodyFormat = body_format(opts)
	local maxBytes = opts.maxBodyValueBytes or DEFAULT_BODY_BYTES
	if type(maxBytes) ~= "number" or maxBytes < 0 or maxBytes % 1 ~= 0 then
		error("fastmail.maxBodyValueBytes must be a nonnegative integer")
	end
	local requested = {}
	for _, id in ids do requested[#requested + 1] = id_of(id) end
	local data = call("Email/get", {
		ids = requested, properties = MESSAGE_PROPERTIES, fetchTextBodyValues = bodyFormat ~= "html", fetchHTMLBodyValues = bodyFormat ~= "text",
		-- Fastmail rejects explicit zero; omitting the argument leaves bodies unlimited.
		maxBodyValueBytes = if maxBytes > 0 then maxBytes else nil,
	})
	local byId, out = {}, {}
	for _, msg in data.list or {} do byId[msg.id] = decorate(msg, bodyFormat) end
	for _, id in requested do
		if not byId[id] then fail("getMessages", "Missing message " .. id) end
		out[#out + 1] = byId[id]
	end
	return out
end

local function body_options(value: any, options: BodyOptions?): BodyOptions
	return options or (if type(value) == "table" then value else {})
end

operationHelp.getMessage = [==[getMessage({id:string,maxBodyValueBytes:number?,bodyFormat:string?}) -> message envelope,body,headers,received,attachments. Positional getMessage(id,opts?) remains supported; IDs accept strings or {id}. Envelope includes from,to,cc,bcc,replyTo,subject,date,messageId. bodyFormat: auto (default) chooses the nonblank JMAP text-preferred rendering, then HTML-preferred rendering, then preview (renderings may mix MIME types); text or html selects only that MIME type, preserving whitespace and returning an empty string if missing. Whitespace is ignored only when deciding emptiness. Body parts default 64 KiB; bodyTruncated flags truncation of the selected body. A truncated whitespace prefix is not considered empty. maxBodyValueBytes changes the per-part cap (0 disables it). Request smaller bodies when a proxy response is too large.]==]
function functions.getMessage(id: Id | MessageOptions, opts: BodyOptions?): Message
	local options = body_options(id, opts)
	return functions.getMessages({ id_of(id) }, options)[1]
end

operationHelp.listThreads = [==[listThreads(opts?) -> {threads={{id}},nextPageToken?}. Uses the same filters and opaque pagination as listMessages; loop until nextPageToken is nil, even if a page is empty.]==]
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

operationHelp.getThread = [==[getThread({id:string,maxBodyValueBytes:number?,bodyFormat:string?}) -> {id,messages} in conversation order, fetching in batches. Positional getThread(id,opts?) remains supported. Same message-body options as getMessage.]==]
function functions.getThread(input: Id | MessageOptions, opts: BodyOptions?): {id: string, messages: {Message}}
	local options = body_options(input, opts)
	body_format(options)
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

operationHelp.listAttachments = [==[listAttachments(messageId) -> attachment metadata {id,filename,mimeType,size,inline,contentId}[]. Attachment bytes are never returned inline.]==]
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

operationHelp.getAttachments = [==[getAttachments({messageId:string,items={{id:string,path:string?},...}}) -> ordered {path,url,size}[]. Items also accept ID strings; destination paths must be distinct. Positional getAttachments(messageId,items) remains supported. Streams to session files; never returns inline attachment bytes.]==]
function functions.getAttachments(input: Id | DownloadsOptions, requested: {DownloadItem}?): {Download}
	local messageId: any = input
	local items: any = requested
	if type(messageId) == "table" and items == nil then items, messageId = messageId.items or messageId, messageId.messageId end
	messageId = id_of(messageId)
	if type(items) ~= "table" then error("fastmail.getAttachments requires attachment items") end
	if #items == 0 then return json.decode("[]") end
	local folder = "attachments/" .. url.segment(messageId, "messageId") .. "/"
	local ids, blobs = {}, {}
	for index, item in items do
		ids[index] = id_of(item)
		blobs[index] = url.segment(ids[index], "blobId")
	end
	local s = session()
	local template = s.downloadUrl
	if type(template) ~= "string" then return fail("getAttachments", "Missing download URL") end
	local account = url.segment(s.accountId, "accountId")
	local byId = {}
	for _, item in functions.listAttachments(messageId) do byId[item.id] = item end
	local jobs, paths = {}, {}
	for index, item in items do
		local id = ids[index]
		local attachment = byId[id]
		if not attachment then error("fastmail: attachment does not belong to this message") end
		local path = type(item) == "table" and item.path or nil
		local blob = blobs[index]
		path = path or (folder .. blob)
		if paths[path] then error("fastmail: attachment paths must be distinct") end
		paths[path] = true
		-- Placeholders are filled by name, wherever the server puts them. IDs must be safe path
		-- segments; the name only labels the download, so one url.segment refuses becomes a
		-- plain label. Fastmail puts {type}, which contains a slash, in the query.
		local ok, name = pcall(url.segment, attachment.filename or "attachment")
		local values = { accountId = account, blobId = blob, name = if ok then name else "attachment",
			type = url.encode(if type(attachment.mimeType) == "string" then attachment.mimeType else "application/octet-stream") }
		local link = string.gsub(template, "{(%w+)}", function(key: any) return values[key] or "" end)
		jobs[#jobs + 1] = { path = path, size = attachment.size, url = link }
	end
	local out = {}
	for _, job in jobs do
		local res = await(http.request({ method = "GET", url = job.url }))
		if res.statusCode < 200 or res.statusCode >= 300 then upstream("getAttachment", res) end
		local output = fs.open(job.path, "w")
		output:write(res.body)
		await(output:close())
		out[#out + 1] = { path = job.path, url = await(fs.signedGetUrl(job.path)), size = job.size }
	end
	return out
end

operationHelp.getAttachment = [==[getAttachment({messageId:string,attachmentId:string,path:string?}) -> {path,url,size}. id is also accepted in place of attachmentId. Positional getAttachment(messageId,attachmentId,path?) remains supported. Streams to private session files; url is a signed Houston download. Default path: attachments/<encoded-message-id>/<encoded-attachment-id>. Links expire; files remain scoped to caller and execution workspace.]==]
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

operationHelp.listAliases = [==[listAliases() -> {aliases,notes}. Each alias has email,canSend,masked. Sending identities add identityId,name; masked addresses add maskedId,state,description,forDomain. Combines addresses shared by both lists. Missing Email submission or Masked Email scope is explained in notes; fails if neither scope is available.]==]
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

operationHelp.listIdentities = [==[listIdentities() -> {identities}, raw JMAP sending identities. Requires the provider Email submission scope, which may be unknown before the first real call.]==]
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
	local account = url.segment(s.accountId, "accountId")
	local endpoint = string.gsub(template, "{accountId}", function() return account end)
	local stat = await(fs.stat(path))
	if not stat.isFile then error("fastmail: attachment path must be a file") end
	local response = await(http.request({
		method = "POST", url = endpoint, body = fs.open(path, "r"), headers = { ["Content-Type"] = { mime } },
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

local function nonempty(list: any): any
	if type(list) == "table" and next(list) == nil then return nil end
	return list
end

-- Builds a JMAP Email from structured fields; Fastmail generates the MIME message.
local function email_object(email: EmailFields): any
	local out: {[string]: any} = {
		mailboxIds = email.mailboxIds, keywords = email.keywords, from = email.from,
		to = nonempty(email.to), cc = nonempty(email.cc), bcc = nonempty(email.bcc), replyTo = nonempty(email.replyTo),
		subject = email.subject or "", inReplyTo = email.inReplyTo, references = email.references,
		attachments = email.attachments, bodyValues = {},
	}
	if email.text ~= nil or email.html == nil then
		out.textBody = { { partId = "text", type = "text/plain" } }
		out.bodyValues.text = { value = email.text or "" }
	end
	if email.html ~= nil then
		out.htmlBody = { { partId = "html", type = "text/html" } }
		out.bodyValues.html = { value = email.html }
	end
	return out
end

local function create_email(operation: string, email: EmailFields): DraftResult
	local created = call("Email/set", { create = { draft = email_object(email) } }, operation)
	local made = created.created and created.created.draft
	if type(made) ~= "table" or type(made.id) ~= "string" or made.id == "" then fail(operation, "Missing draft creation confirmation") end
	return { id = made.id, threadId = if type(made.threadId) == "string" then made.threadId else nil }
end

-- Saves a composed message in Drafts; only sending it needs Email submission.
local function save_draft(operation: string, message: Composed, folders: any?): DraftResult
	local drafts = folder_id(folders or functions.listFolders().folders, "drafts")
	local sender, fields = message.sender, message.fields
	return create_email(operation, {
		mailboxIds = { [drafts] = true }, keywords = { ["$draft"] = true, ["$seen"] = true },
		from = { { email = sender.email, name = sender.name } }, to = fields.to, cc = fields.cc, bcc = fields.bcc,
		replyTo = fields.replyTo, subject = fields.subject, text = fields.text,
		inReplyTo = fields.inReplyTo, references = fields.references, attachments = attachment_parts(fields.attachments, operation),
	})
end

-- No automatic retries: a failed/ambiguous submission leaves the draft in place.
local function send_email(operation: string, identity: Sender, emailId: string, sent: string): SendResult
	assert(identity.id, "sending identity has no id")
	local submitted = call("EmailSubmission/set", {
		create = { send = { identityId = identity.id, emailId = emailId } },
		-- Patch keywords so a draft's flags and labels survive sending.
		onSuccessUpdateEmail = { ["#send"] = {
			mailboxIds = { [sent] = true }, ["keywords/$draft"] = json.decode("null"), ["keywords/$seen"] = true,
		} },
	}, operation)
	local submission = submitted.created and submitted.created.send
	if type(submission) ~= "table" or type(submission.id) ~= "string" or submission.id == "" then fail(operation, "Missing submission confirmation; draft " .. emailId) end
	return { id = emailId, submissionId = submission.id }
end

local function submit(operation: string, message: Composed): SendResult
	local folders = functions.listFolders().folders
	local sent = folder_id(folders, "sent")
	return send_email(operation, message.sender, save_draft(operation, message, folders).id, sent)
end

-- Identity/get needs Email submission. Drafts skip it on tokens without that scope.
local function identities_for(operation: string, draft: boolean): {Identity}?
	if draft and not has_cap(session(), SUBMISSION) then return nil end
	local identities = as_list(call("Identity/get", nil, operation).list)
	for _, item in identities do
		if type(item) == "table" then remove_nulls(item) end
	end
	return identities
end

-- Without identities, a draft is from `from` as given, or from the account address.
local function sender_of(identities: {Identity}?, body: any): Sender
	if identities then return require_identity(identities, body) end
	if body.identityId ~= nil then error("fastmail: identityId needs the Email submission scope; pass from instead") end
	if body.from ~= nil and (type(body.from) ~= "string" or body.from == "") then error("fastmail from must be an email address") end
	return { email = body.from or session().username }
end

local function check_addresses(body: any, operation: string)
	for _, key in RECIPIENT_FIELDS do
		if body[key] ~= nil and type(body[key]) ~= "table" then
			error("fastmail." .. operation .. " " .. key .. " must be an array of { email = ... }")
		end
	end
end

-- Drafts may have no recipients yet; sending requires at least one.
local function compose(operation: string, body: any, draft: boolean): Composed
	if type(body) ~= "table" then error("fastmail." .. operation .. " requires options") end
	if not draft and (type(body.to) ~= "table" or #body.to == 0) then error("fastmail." .. operation .. " requires to = { { email = ... } }") end
	check_addresses(body, operation)
	if type(body.text) ~= "string" then error("fastmail." .. operation .. " requires text") end
	return { sender = sender_of(identities_for(operation, draft), body), fields = {
		to = body.to, cc = body.cc, bcc = body.bcc, replyTo = body.replyTo,
		subject = body.subject or "", text = body.text, attachments = body.attachments,
	} }
end

local function address_objects(values: any): {Address}
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

local function message_ids(value: any): {string}
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

local function reply_subject(subject: any): string
	if type(subject) ~= "string" then subject = "" end
	if string.match(subject, "^[Rr][Ee]:") then return subject end
	if subject == "" then return "Re:" end
	return "Re: " .. subject
end

-- Shared by replyMessage and createReplyDraft so both thread and address replies alike.
local function compose_reply(operation: string, input: Id | ReplyOptions, options: ReplyOptions?, draft: boolean): Composed
	local id: any = input
	local body: any = options
	if type(id) == "table" and body == nil then
		body = id
		id = id.id or id.messageId
	end
	id = id_of(id)
	if type(body) ~= "table" or type(body.text) ~= "string" then error("fastmail." .. operation .. " requires text") end
	check_addresses(body, operation)
	local to = address_objects(body.to)
	if body.to ~= nil and (#to == 0 or #to ~= #body.to) then error("fastmail." .. operation .. " to must be a nonempty array of { email = ... }") end
	local data = call("Email/get", {
		ids = { id },
		properties = { "id", "messageId", "inReplyTo", "references", "from", "to", "cc", "replyTo", "subject" },
	}, operation)
	local msg = data.list and data.list[1]
	if type(msg) ~= "table" then fail(operation, "Missing message " .. id) end
	remove_nulls(msg)
	if body.to == nil then
		local source = msg.replyTo
		if type(source) ~= "table" or #source == 0 then source = msg.from end
		to = address_objects(source)
		if #to == 0 then error("fastmail." .. operation .. ": the message has no reply address") end
	end
	local identities = identities_for(operation, draft)
	local identity: Sender? = nil
	if identities == nil or body.identityId ~= nil or body.from ~= nil then
		identity = sender_of(identities, body)
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
	assert(identity, "reply identity was not resolved")
	local cc = body.cc
	if body.all and cc == nil then
		local skip: {[string]: boolean} = {}
		for _, item in (identities or { identity }) :: {Sender} do
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
	return { sender = identity, fields = {
		to = to, cc = cc, bcc = body.bcc, replyTo = body.replyTo, subject = subject, text = body.text,
		attachments = body.attachments, inReplyTo = inReplyTo, references = references,
	} }
end

-- Loads a message and refuses anything without the $draft keyword.
local function draft_of(operation: string, id: string, properties: {string}, bodies: boolean?): any
	local data = call("Email/get", {
		ids = { id }, properties = properties, fetchTextBodyValues = bodies, fetchHTMLBodyValues = bodies,
	}, operation)
	local msg = data.list and data.list[1]
	if type(msg) ~= "table" or msg.id ~= id then fail(operation, "Missing message " .. id) end
	remove_nulls(msg)
	if type(msg.keywords) ~= "table" or msg.keywords["$draft"] ~= true then
		error("fastmail." .. operation .. ": message " .. id .. " is not a draft")
	end
	return msg
end

local function part_text(msg: any, parts: any, mimeType: string): string?
	local text, _, found = join_parts(msg, parts, mimeType)
	return if found then text else nil
end

local function update_ids(ids: {string}, patch: {[string]: any}, operation: string): {string}
	local updated: {string} = json.decode("[]") :: {string}
	for batch in each_chunk(ids) do
		local update = {}
		for _, id in batch do update[id] = patch end
		local data = call("Email/set", { update = update }, operation)
		for _, id in batch do
			if type(data.updated) ~= "table" or data.updated[id] == nil then
				fail(operation, "Missing update confirmation for " .. id)
			end
			updated[#updated + 1] = id
		end
	end
	return updated
end

local function move_to(ids: {string}, dest: string, operation: string): MoveResult
	return { ids = update_ids(ids, { mailboxIds = { [dest] = true } }, operation), folderId = dest }
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

if config.access == "read-write" then

	operationHelp.markRead = [==[markRead(ids) -> {ids}. Marks messages read by setting $seen, preserving other keywords and mailboxes. Accepts one ID or a list of strings/{id} rows. Requires a writable Email token and read-write connection access; Email submission scope is unnecessary. Batches of 50 may partially complete; inspect keywords after a failure before retrying.]==]
	function functions.markRead(ids: Ids)
		return { ids = update_ids(id_list(ids, "markRead"), { ["keywords/$seen"] = true }, "markRead") }
	end

	operationHelp.markUnread = [==[markUnread(ids) -> {ids}. Marks messages unread by removing $seen, preserving other keywords and mailboxes. Accepts one ID or a list of strings/{id} rows. Requires a writable Email token and read-write connection access; Email submission scope is unnecessary. Batches of 50 may partially complete; inspect keywords after a failure before retrying.]==]
	function functions.markUnread(ids: Ids)
		return { ids = update_ids(id_list(ids, "markUnread"), { ["keywords/$seen"] = json.decode("null") }, "markUnread") }
	end

	operationHelp.trashMessage = [==[trashMessage(id) -> {id}. Moves a single message to Trash; does not permanently destroy. ID accepts a string or {id}.]==]
	function functions.trashMessage(id: Id)
		local moved = move_to({ id_of(id) }, folder_id(functions.listFolders().folders, "trash"), "trashMessage")
		return { id = moved.ids[1] }
	end

	operationHelp.deleteMessage = [==[deleteMessage(ids) -> {ids,folderId}. Moves to Trash; does not permanently destroy. Accepts one ID or list of strings/{id}; batches may partially complete.]==]
	function functions.deleteMessage(ids: Ids)
		return move_to(id_list(ids, "deleteMessage"), folder_id(functions.listFolders().folders, "trash"), "deleteMessage")
	end

	operationHelp.deleteMessages = [==[deleteMessages(ids) -> {ids,folderId}. Moves to Trash; does not permanently destroy. Accepts one ID or list of strings/{id}; batches of 50 may partially complete. No automatic replay.]==]
	function functions.deleteMessages(ids: Ids)
		return functions.deleteMessage(ids)
	end

	operationHelp.destroyMessage = [==[destroyMessage(ids) -> {ids}. Permanently destroys messages. Accepts one ID or list of strings/{id}; batches may partially complete. This differs from moving messages to Trash.]==]
	function functions.destroyMessage(ids: Ids)
		return destroy_ids(ids, "destroyMessage")
	end

	operationHelp.destroyMessages = [==[destroyMessages(ids) -> {ids}. Permanently destroys messages in batches of 50. Accepts one ID or list of strings/{id}. Partial completion is possible; never automatically replay.]==]
	function functions.destroyMessages(ids: Ids)
		return functions.destroyMessage(ids)
	end

	operationHelp.archiveMessages = [==[archiveMessages(ids) -> {ids,folderId}. Moves to Archive; fails if Archive is absent. Accepts one ID or a list, strings or {id}; batches of 50 may partially complete. No automatic replay.]==]
	function functions.archiveMessages(ids: Ids): MoveResult
		local archive = nil
		for _, folder in functions.listFolders().folders do
			if folder.role == "archive" then archive = folder.id; break end
		end
		if type(archive) ~= "string" or archive == "" then return fail("archiveMessages", "Fastmail has no Archive mailbox") end
		return move_to(id_list(ids, "archiveMessages"), archive, "archiveMessages")
	end

	operationHelp.archiveMessage = [==[archiveMessage(ids) -> {ids,folderId}. Moves to Archive; fails if Archive is absent. Accepts strings or {id} rows, individually or in a list. Alias of archiveMessages; batches may partially complete.]==]
	function functions.archiveMessage(ids: Ids)
		return functions.archiveMessages(ids)
	end

	operationHelp.moveMessages = [==[moveMessages({ids={...},folder:string}) -> {ids,folderId}. ids accepts one ID or a list; IDs may be strings or {id}. id is also accepted instead of ids for a single message. folder accepts ID or role. Positional moveMessages(ids,folder) remains supported. Replaces mailboxes with one destination, in batches of 50. Partial completion is possible; never automatically replay.]==]
	function functions.moveMessages(input: Ids | MoveOptions, folder: string?)
		local ids: any = input
		if type(ids) == "table" and folder == nil and type(ids.folder) == "string" then
			folder = ids.folder
			ids = ids.ids or ids.id
		end
		if type(folder) ~= "string" or folder == "" then error("fastmail.moveMessages requires a folder id or role") end
		return move_to(id_list(ids, "moveMessages"), folder_id(functions.listFolders().folders, folder), "moveMessages")
	end

	operationHelp.moveMessage = [==[moveMessage({id:string,folder:string}) -> {ids,folderId}. Replaces message mailboxes with one destination. folder accepts ID or role. Positional moveMessage(id,folder) remains supported; id accepts a string or {id}.]==]
	function functions.moveMessage(id: Ids | MoveOptions, folder: string?)
		return functions.moveMessages(id, folder)
	end

	operationHelp.createFolder = [==[createFolder({name:string,parentId:string?}) -> {id,name}. parentId is a folder ID or role; parent is also accepted. Omit both for a top-level folder. Positional createFolder(name,parent?) remains supported.]==]
	function functions.createFolder(input: string | FolderOptions, parent: Id?)
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
	operationHelp.sendMessage = [==[sendMessage({to={{email=...}},text=...,subject?,identityId?,from?,cc?,bcc?,replyTo?,attachments?}) -> {id,submissionId}. text and nonempty to required; subject defaults empty. Address arrays use {email,name?}. identityId takes precedence over from. Without either, selects identity matching account username or sole identity; ambiguous sender fails. attachments={{path,filename?,mimeType?}} uploads private session files, never inline base64; MIME defaults application/octet-stream, filename defaults path basename. Moves from Drafts to Sent. Email submission scope required. On timeout inspect Drafts and Sent before retrying: delivery may have succeeded.]==]
	function functions.sendMessage(body: SendOptions): SendResult
		return submit("sendMessage", compose("sendMessage", body, false))
	end

	operationHelp.replyMessage = [==[replyMessage({id:string,text:string,all:boolean?,subject:string?,identityId:string?,from:string?,to?,cc?,bcc?,replyTo?,attachments?}) -> {id,submissionId}. messageId is also accepted instead of id. Positional replyMessage(id,options) remains supported. Replies to Reply-To, otherwise From; to={{email,name?}} replaces that recipient list. Always preserves thread message IDs/references. all defaults false. Default sender is receiving identity (To then Cc), then primary identity. all=true adds original To/Cc excluding your identities and the To recipients; cc explicitly replaces that list. Subject derives a Re: prefix unless supplied. Attachments use private session paths as in sendMessage. Email submission scope required. Never automatically replay a partial send.]==]
	function functions.replyMessage(input: Id | ReplyOptions, options: ReplyOptions?): SendResult
		return submit("replyMessage", compose_reply("replyMessage", input, options, false))
	end

	operationHelp.sendDraft = [==[sendDraft({id,identityId?}) -> {id,submissionId}. Sends an existing draft, such as one from createDraft or createReplyDraft, and moves it to Sent, keeping its other keywords. Uses the sending identity matching the draft's From unless identityId is given. Positional sendDraft(id) is supported. Refuses messages that are not drafts. Email submission scope required. On timeout inspect Drafts and Sent before retrying: delivery may have succeeded.]==]
	function functions.sendDraft(input: Id | SendDraftOptions): SendResult
		local id = id_of(input)
		local opts: any = input
		local identityId = if type(opts) == "table" then opts.identityId else nil
		local identities = identities_for("sendDraft", false) :: {Identity}
		local draft = draft_of("sendDraft", id, { "id", "keywords", "from" })
		local from = nil
		if identityId == nil then
			local addresses = address_objects(draft.from)
			if #addresses > 0 then from = addresses[1].email end
		end
		local identity = require_identity(identities, { identityId = identityId, from = from })
		return send_email("sendDraft", identity, id, folder_id(functions.listFolders().folders, "sent"))
	end

end

-- Read and draft (custom) connections add only draft operations to the reads; the person sends from Fastmail.
if config.access == "read-write" or config.access == "custom" then

	local DRAFT_SCOPE = "Needs only the Email scope: without Email submission, identityId is refused and from (default: the account address) is not checked against sending identities."
	local REVIEW = if config.access == "read-write"
		then "The person can review and send it in Fastmail, or send it later with sendDraft."
		else "Read and draft connection: this connector never sends; the person reviews and sends drafts in Fastmail."

	operationHelp.createDraft = [==[createDraft({to?,text,subject?,identityId?,from?,cc?,bcc?,replyTo?,attachments?}) -> {id,threadId}. Saves a draft in Drafts without sending. Options as for sending: address arrays use {email,name?}, but to may be empty; attachments={{path,filename?,mimeType?}} uploads session files. ]==] .. DRAFT_SCOPE .. " " .. REVIEW .. [==[ List drafts with listMessages({folder="drafts"}) and read them with getMessage.]==]
	function functions.createDraft(body: DraftOptions): DraftResult
		return save_draft("createDraft", compose("createDraft", body, true))
	end

	operationHelp.createReplyDraft = [==[createReplyDraft({id,text,all?,subject?,identityId?,from?,to?,cc?,bcc?,replyTo?,attachments?}) -> {id,threadId}. Saves a reply in Drafts without sending, so it opens in the original thread. Replies to Reply-To, otherwise From; to replaces that list. all=true adds the original To/Cc except your addresses; cc replaces that list. Subject gets a Re: prefix unless supplied. Keeps In-Reply-To/References. ]==] .. DRAFT_SCOPE .. " " .. REVIEW
	function functions.createReplyDraft(input: Id | ReplyOptions, options: ReplyOptions?): DraftResult
		return save_draft("createReplyDraft", compose_reply("createReplyDraft", input, options, true))
	end

	local DRAFT_PROPERTIES = { "id", "keywords", "mailboxIds", "from", "to", "cc", "bcc", "replyTo", "subject", "inReplyTo", "references", "attachments" }

	operationHelp.updateDraft = [==[updateDraft({id,to?,cc?,bcc?,replyTo?,subject?,text?,identityId?,from?,attachments?}) -> {id,threadId}. Changes only the given fields of a draft and keeps the rest, including its thread headers. text replaces the body with plain text and drops its inline images; attachments replaces the regular attachments ({} removes them); an empty address list such as cc={} clears that field. Refuses messages that are not drafts. JMAP messages are immutable, so this saves a new draft and destroys the old one: use the returned id. If removing the old version fails, the error names the new draft; delete the old one instead of retrying. ]==] .. DRAFT_SCOPE
	function functions.updateDraft(input: DraftOptions): DraftResult
		if type(input) ~= "table" then error("fastmail.updateDraft requires {id, ...}") end
		local id = id_of(input.id)
		check_addresses(input, "updateDraft")
		for _, key in { "subject", "text" } do
			if input[key] ~= nil and type(input[key]) ~= "string" then error("fastmail.updateDraft " .. key .. " must be a string") end
		end
		local keepBody = input.text == nil
		local properties = table.clone(DRAFT_PROPERTIES)
		if keepBody then table.move({ "textBody", "htmlBody", "bodyValues" }, 1, 3, #properties + 1, properties) end
		local old = draft_of("updateDraft", id, properties, keepBody)
		local from = old.from
		if input.identityId ~= nil or input.from ~= nil then
			local sender = sender_of(identities_for("updateDraft", true), input)
			from = { { email = sender.email, name = sender.name } }
		end
		local text, html = input.text, nil
		if keepBody then text, html = part_text(old, old.textBody, "text/plain"), part_text(old, old.htmlBody, "text/html") end
		-- Parts with a Content-ID belong to the HTML body; attachments replaces only the others.
		local attachments = attachment_parts(input.attachments, "updateDraft") or {}
		for _, part in old.attachments or {} do
			if (part.cid ~= nil and html ~= nil) or (part.cid == nil and input.attachments == nil) then
				attachments[#attachments + 1] = {
					blobId = part.blobId, name = part.name, type = part.type, charset = part.charset, disposition = part.disposition, cid = part.cid,
				}
			end
		end
		local function pick(key: string): any
			if input[key] ~= nil then return input[key] end
			return old[key]
		end
		local made = create_email("updateDraft", {
			mailboxIds = old.mailboxIds, keywords = old.keywords, from = from,
			to = pick("to"), cc = pick("cc"), bcc = pick("bcc"), replyTo = pick("replyTo"), subject = pick("subject"),
			text = text, html = html, inReplyTo = old.inReplyTo, references = old.references, attachments = nonempty(attachments),
		})
		-- Separate from the create, so a failed create never loses the old draft.
		local ok, problem = pcall(destroy_ids, id, "updateDraft")
		if not ok then fail("updateDraft", "Saved new draft " .. made.id .. " but could not remove old draft " .. id .. ": " .. tostring(problem)) end
		return made
	end

	operationHelp.deleteDraft = [==[deleteDraft(id) -> {id}. Permanently destroys a draft; {id} is also accepted. Refuses messages that are not drafts.]==]
	function functions.deleteDraft(input: Id): {id: string}
		local id = id_of(input)
		draft_of("deleteDraft", id, { "id", "keywords" })
		return { id = destroy_ids(id, "deleteDraft").ids[1] }
	end

end

operationHelp.listMailFolders = [==[listMailFolders() -> {id:string,name:string}[]. No arguments. Includes every available folder, sorted by nonempty unique ID; names may repeat. Empty mailboxes return an empty array; provider failures raise errors.]==]
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

return functions
