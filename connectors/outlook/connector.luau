-- Microsoft Graph v1.0 for the connected account's Outlook mailbox. Arguments and results keep
-- Graph's native field names; attachments move through session files, never base64.
local base64 = require("lib/base64.luau")

-- Request layer shared verbatim by the Microsoft Graph connectors (tools/validate checks they match).
type Options = {[string]: any}
type Endpoint = {method: string, path: string, read: boolean, query: {string}?, body: boolean?, defaults: Options?, list: boolean?, help: string}
local GRAPH = "https://graph.microsoft.com/v1.0"
local API = GRAPH .. "/me"
-- Preauthenticated OneDrive download links, under either annotation, work without credentials,
-- so results never carry them.
local SIGNED = {"@microsoft.graph.downloadUrl", "@content.downloadUrl"}

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

local function done(name: string, args: Options)
	local unknown = next(args)
	assert(unknown == nil, name .. " received an unknown option " .. tostring(unknown))
end

-- Moves the named fields from args into a query string. A $name is an OData option taken from
-- the field without $ (select, top, ...); arrays join with commas, as OData lists do.
local function query(args: Options, names: {string}): string
	local parts: {string} = {}
	for _, name in names do
		local field = if string.sub(name, 1, 1) == "$" then string.sub(name, 2) else name
		local value = args[field]
		args[field] = nil
		if value ~= nil then
			local items: {string} = {}
			for key, item in (if type(value) == "table" then value else {value}) do
				assert(type(key) == "number" and (type(item) == "string" or type(item) == "number" or type(item) == "boolean"), field .. " must be a string, number, boolean or an array of them")
				table.insert(items, url.encode(item))
			end
			assert(#items > 0, field .. " must not be an empty array")
			table.insert(parts, (if field == name then url.encode(name) else name) .. "=" .. table.concat(items, ","))
		end
	end
	return if #parts > 0 then "?" .. table.concat(parts, "&") else ""
end

-- Graph errors are {error = {code, message}}; throttling answers 429 or 503 with Retry-After.
-- Quota (507) and other server refusals are not transient.
local function fail(operation: string, response: HttpResponse): never
	local ok, decoded = pcall(json.decode, await(response.body:readPrefix(4096)))
	local problem = if ok and type(decoded) == "table" and type(decoded.error) == "table" then decoded.error else {}
	local status = response.statusCode
	local message = "Microsoft Graph HTTP " .. tostring(status)
	if type(problem.code) == "string" then message ..= " (" .. problem.code .. ")" end
	if type(problem.message) == "string" then message ..= ": " .. string.sub(problem.message, 1, 600) end
	local retry = response.headers["retry-after"]
	if retry and retry[1] then message ..= "; Retry-After: " .. retry[1] end
	return houston.fail({operation = operation, layer = "upstream", upstream_status = status, message = message,
		retryable = status == 429 or status == 500 or status == 502 or status == 503 or status == 504 or status == 509})
end

local function decode(operation: string, response: HttpResponse): any
	if response.statusCode < 200 or response.statusCode >= 300 then fail(operation, response) end
	local raw = await(response.body:readAll())
	if string.match(raw, "^%s*$") then return {success = true} end
	local ok, value = pcall(json.decode, raw)
	if not ok or type(value) ~= "table" or not string.match(raw, "^%s*{") then
		houston.fail({operation = operation, layer = "upstream", upstream_status = response.statusCode,
			retryable = false, message = "Microsoft Graph returned an invalid JSON object"})
	end
	for _, key in SIGNED do
		value[key] = nil
		for _, item in (if type(value.value) == "table" then value.value else {}) :: {any} do
			if type(item) == "table" then item[key] = nil end
		end
	end
	return value
end

local function call(operation: string, method: string, href: string, body: any?, headers: HttpHeaders?): any
	local sent: HttpHeaders = if headers then table.clone(headers) else {}
	if body ~= nil then sent["Content-Type"] = {"application/json"} end
	return decode(operation, await(http.request({method = method, url = href, headers = sent,
		body = if body ~= nil then json.encode(body) elseif method == "POST" then "" else nil})))
end

-- Streams fetch()'s response to a session file; the path changes only when the whole body arrived.
local function save(operation: string, path: string, fetch: () -> HttpResponse): Options
	local output = fs.open(path, "w")
	local ok, err = pcall(function()
		local response = fetch()
		if response.statusCode ~= 200 then fail(operation, response) end
		output:write(response.body)
		await(output:close())
	end)
	if not ok then
		output:cancel()
		pcall(function() await(output:close()) end)
		error(err, 0)
	end
	return {path = path, url = await(fs.signedGetUrl(path)), size = await(fs.stat(path)).size}
end

-- Follows an @odata.nextLink of the list whose path ends with the pattern ending. It may carry only
-- paging options: an $expand, or another route such as thumbnails, could return attachment bytes
-- or signed links. Graph may name entities by OData key, as in mailFolders('inbox'), which the
-- routes accept in their path form, mailFolders/inbox.
local PAGING = {select = true, top = true, skip = true, skiptoken = true, orderby = true, filter = true, search = true, count = true}
local function pageLink(link: string, ending: string): string
	local raw, search = string.match(link, "^([^?#]*)(%??[^#]*)$")
	assert(raw and search and string.sub(raw, 1, #GRAPH + 1) == GRAPH .. "/", "nextLink must be an @odata.nextLink from Microsoft Graph")
	local path = string.gsub((string.gsub(raw, "%%27", "'")), "/(%w+)%('([^'/]+)'%)", "/%1/%2")
	assert(string.find(path, ending), "nextLink must come from the same list")
	for pair in string.gmatch(string.sub(search, 2), "[^&]+") do
		local name = string.lower((string.gsub(string.match(pair, "^[^=]*") or "", "%%(%x%x)", function(hex: string): string
			return string.char(tonumber(hex, 16) or 0)
		end)))
		assert(PAGING[(string.gsub(name, "^%$", ""))], "nextLink may carry only paging options")
	end
	return path .. search
end

-- A list's nextLink, the previous page's @odata.nextLink, replaces every other option.
local function nextLink(name: string, args: Options, ending: string): string?
	if args.nextLink == nil then return nil end
	local link = text(args.nextLink, "nextLink")
	args.nextLink = nil
	assert(next(args) == nil, name .. " takes nextLink alone, from a previous page of the same list")
	return pageLink(link, ending)
end

-- Moves {placeholders} and declared query fields from args into the URL; remaining fields form the
-- JSON body.
local function target(name: string, endpoint: Endpoint, args: Options): string
	local link = if endpoint.list then nextLink(name, args, "/" .. (string.match(endpoint.path, "[^/]+$") or "") .. "$") else nil
	if link then return link end
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
	if not endpoint.body then done(name, args) end
	return API .. path
end

local function invoke(name: string, endpoint: Endpoint, input: any): any
	local args = options(input)
	local href = target(name, endpoint, args)
	local result = call(name, endpoint.method, href, if endpoint.body then args else nil)
	if endpoint.list and result.value == nil then result.value = json.decode("[]") end
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

-- Read and draft (custom) connections change only drafts, and the proxy refuses every send.
local DRAFTS = config.access == "custom"
local LIST = "id,subject,from,toRecipients,ccRecipients,receivedDateTime,sentDateTime,isRead,isDraft,hasAttachments,importance,flag,categories,conversationId,parentFolderId,bodyPreview,webLink"
-- Graph takes attachments "under 3 MB" in one request of at most 4 MB once base64-encoded.
local MAX_REQUEST = 4000000
local MAX_ATTACHMENTS = 3000000

local endpoints: {[string]: Endpoint} = {
	getProfile = {method = "GET", path = "", read = true, defaults = {select = "id,displayName,mail,userPrincipalName"}, query = {"$select"},
		help = "getProfile({select?}) -> {id, displayName, mail, userPrincipalName}. The connected account."},
	getMailFolder = {method = "GET", path = "/mailFolders/{id}", read = true, query = {"$select"},
		help = "getMailFolder({id, select?}) -> {id, displayName, parentFolderId, childFolderCount, unreadItemCount, totalItemCount}. id is a folder ID or a well-known name: inbox, drafts, sentitems, deleteditems, archive, junkemail."},
	listAttachments = {method = "GET", path = "/messages/{messageId}/attachments", read = true, list = true,
		defaults = {select = "id,name,contentType,size,isInline,lastModifiedDateTime"}, query = {"$select"},
		help = "listAttachments({messageId}) -> {value={{id, name, contentType, size, isInline}}}. Metadata only: save one with getAttachment."},
	sendDraft = {method = "POST", path = "/messages/{id}/send", read = false,
		help = "sendDraft({id}) -> {success=true}. Sends a draft; the sent copy gets a new ID in Sent Items."},
	moveMessage = {method = "POST", path = "/messages/{id}/move", read = false, body = true,
		help = "moveMessage({id, destinationId}) -> the moved message, with a new id. destinationId is a folder ID or well-known name; 'deleteditems' trashes and 'archive' archives."},
}

-- Replies and forwards take a message whose attachments are session files, like createDraft.
local replies: {[string]: Endpoint} = {
	reply = {method = "POST", path = "/messages/{id}/reply", read = false, body = true,
		help = "reply({id, comment?, message?}) -> {success=true}. Sends a reply to the sender: comment is the text above the quoted original, message sets other fields such as attachments."},
	replyAll = {method = "POST", path = "/messages/{id}/replyAll", read = false, body = true,
		help = "replyAll({id, comment?, message?}) -> {success=true}. As reply, to every recipient."},
	forward = {method = "POST", path = "/messages/{id}/forward", read = false, body = true,
		help = "forward({id, toRecipients, comment?, message?}) -> {success=true}. Sends the message on to toRecipients."},
}
local drafting: {[string]: Endpoint} = {
	createReply = {method = "POST", path = "/messages/{id}/createReply", read = false, body = true,
		help = "createReply({id, comment?, message?}) -> draft message. A reply draft in the conversation, addressed to the sender; edit it with updateMessage."},
	createReplyAll = {method = "POST", path = "/messages/{id}/createReplyAll", read = false, body = true,
		help = "createReplyAll({id, comment?, message?}) -> draft message. As createReply, addressed to every recipient."},
	createForward = {method = "POST", path = "/messages/{id}/createForward", read = false, body = true,
		help = "createForward({id, toRecipients?, comment?, message?}) -> draft message. A forward draft with the original's attachments."},
}

-- Prefer selects the body format; Graph defaults to HTML.
local function bodyFormat(args: Options): HttpHeaders
	local format = if args.bodyFormat == nil then "text" else args.bodyFormat
	args.bodyFormat = nil
	assert(format == "text" or format == "html", "bodyFormat must be text or html")
	return {Prefer = {"outlook.body-content-type=\"" .. format .. "\""}}
end

local function messagePath(id: any, field: string): string
	return API .. "/messages/" .. url.segment(text(id, field), field)
end

-- Read and draft connections change a message only while it is a draft, and never set extended
-- MAPI properties, which could make a draft look sent or received.
local function draftOnly(name: string, id: any)
	if not DRAFTS then return end
	local message = call(name, "GET", messagePath(id, "id") .. "?$select=isDraft")
	assert(message.isDraft == true, name .. " changes only drafts on a Read and draft connection")
end

local function plain(fields: Options)
	assert(not DRAFTS or (fields.singleValueExtendedProperties == nil and fields.multiValueExtendedProperties == nil),
		"Read and draft connections cannot set extended properties")
end

-- Session files become fileAttachments, under 3 MB in total.
local function fileAttachments(items: any): {Options}
	assert(type(items) == "table" and items[1] ~= nil, "attachments must be an array of paths or {path, name?, contentType?}")
	local list: {Options} = json.decode("[]")
	local total = 0
	for _, entry in items do
		local spec = if type(entry) == "string" then {path = entry} else entry
		assert(type(spec) == "table", "attachments must be paths or {path, name?, contentType?}")
		local path = text(spec.path, "attachment path")
		total += await(fs.stat(path)).size
		assert(total < MAX_ATTACHMENTS, "attachments must stay under 3 MB in total; share larger files from OneDrive")
		local file = fs.open(path, "r")
		local data = await(file:readAll())
		await(file:close())
		table.insert(list, {["@odata.type"] = "#microsoft.graph.fileAttachment", name = text(spec.name or string.match(path, "[^/]+$"), "attachment name"),
			contentType = if spec.contentType == nil then nil else text(spec.contentType, "attachment contentType"), contentBytes = base64.encode(data)})
	end
	return list
end

-- A message resource with its attachments read from session files. Graph refuses requests over
-- 4 MB, which base64-encoded attachments and the rest of the message must fit in.
local function compose(value: any, field: string): Options
	local message = options(value)
	assert(next(message) ~= nil, field .. " must be a nonempty message object")
	plain(message)
	if message.attachments ~= nil then
		message.attachments = fileAttachments(message.attachments)
		assert(#json.encode(message) <= MAX_REQUEST, "the message and its attachments must stay under 4 MB; share larger files from OneDrive")
	end
	return message
end

-- Caps body.content and uniqueBody.content at maxBodyBytes without splitting a UTF-8 sequence, and
-- reports it in bodyTruncated.
local function limitBody(message: any, limit: number)
	if type(message) ~= "table" then return end
	for _, field in {"body", "uniqueBody"} do
		local body = message[field]
		if type(body) == "table" and type(body.content) == "string" then
			local content = body.content
			message.bodyTruncated = message.bodyTruncated == true or (limit > 0 and #content > limit)
			if limit > 0 and #content > limit then
				local start = limit
				while start > 1 and start > limit - 3 and string.byte(content, start) // 64 == 2 do start -= 1 end
				local lead = string.byte(content, start)
				local size = if lead >= 240 then 4 elseif lead >= 224 then 3 elseif lead >= 192 then 2 else 1
				body.content = string.sub(content, 1, if start + size - 1 > limit then start - 1 else limit)
			end
		end
	end
end

local function bodyLimit(args: Options): number
	local limit = if args.maxBodyBytes == nil then 65536 else args.maxBodyBytes
	args.maxBodyBytes = nil
	assert(type(limit) == "number" and limit >= 0 and limit % 1 == 0, "maxBodyBytes must be a nonnegative integer")
	return limit
end

exportEndpoints(endpoints)
for group, isRead in {[replies] = false, [drafting] = DRAFTS} do
	for name, endpoint in group do
		export(name, isRead, function(input: any): any
			local args = options(input)
			if args.message ~= nil then args.message = compose(args.message, "message") end
			return invoke(name, endpoint, args)
		end, endpoint.help)
	end
end

local READ = "bodyFormat='text' (default) or 'html' sets body.contentType; maxBodyBytes caps body.content (default 65536, 0 for no cap) and sets bodyTruncated."

export("listMessages", true, function(input: any): Options
	local args = options(input)
	local headers = bodyFormat(args)
	local limit = bodyLimit(args)
	local link = nextLink("listMessages", args, "/messages$")
	local href = API .. "/messages"
	if not link then
		if args.folderId ~= nil then href = API .. "/mailFolders/" .. url.segment(text(args.folderId, "folderId"), "folderId") .. "/messages" end
		args.folderId = nil
		if args.select == nil then args.select = LIST end
		-- $search takes a quoted string; \ and " inside it are escaped.
		if args.search ~= nil then args.search = "\"" .. (string.gsub(text(args.search, "search"), "[\\\"]", "\\%0")) .. "\"" end
		href ..= query(args, {"$select", "$filter", "$search", "$orderby", "$top", "$skip"})
		done("listMessages", args)
	end
	local page = call("listMessages", "GET", link or href, nil, headers)
	if page.value == nil then page.value = json.decode("[]") end
	for _, message in page.value do limitBody(message, limit) end
	return page
end, "listMessages({folderId?, search?, filter?, orderby?, select?, top?, skip?, bodyFormat?, maxBodyBytes?, nextLink?}) -> {value={message}, @odata.nextLink?}. Every folder without folderId (a folder ID or well-known name such as 'inbox'). search is KQL, e.g. 'from:ana budget' or 'subject:invoice hasAttachments:true', returns at most 1000 messages and cannot combine with filter, orderby or skip; filter is OData, e.g. \"receivedDateTime ge 2026-10-01T00:00:00Z and isRead eq false\"; orderby e.g. 'receivedDateTime desc', whose fields must also lead filter when both are set (Graph answers InefficientFilter otherwise). top ≤1000 (default 10). Default fields: " .. LIST .. "; add body to select for full bodies. " .. READ)

export("getMessage", true, function(input: any): Options
	local args = options(input)
	local headers = bodyFormat(args)
	local limit = bodyLimit(args)
	local href = messagePath(args.id, "id")
	args.id = nil
	href ..= query(args, {"$select"})
	done("getMessage", args)
	local message = call("getMessage", "GET", href, nil, headers)
	limitBody(message, limit)
	return message
end, "getMessage({id, select?, bodyFormat?, maxBodyBytes?}) -> message {id, subject, from, toRecipients, ccRecipients, bccRecipients, replyTo, receivedDateTime, body={contentType, content}, bodyTruncated, uniqueBody?, isRead, isDraft, hasAttachments, conversationId, internetMessageId, webLink, ...}. Every field unless select narrows them. " .. READ .. " A conversation is listMessages({filter=\"conversationId eq '<id>'\"}).")

export("getAttachment", true, function(input: any): Options
	local args = options(input)
	local href = messagePath(args.messageId, "messageId") .. "/attachments/" .. url.segment(text(args.attachmentId, "attachmentId"), "attachmentId") .. "/$value"
	local path = text(args.path, "path")
	args.messageId, args.attachmentId, args.path = nil, nil, nil
	done("getAttachment", args)
	return save("getAttachment", path, function(): HttpResponse return await(http.request({method = "GET", url = href})) end)
end, "getAttachment({messageId, attachmentId, path}) -> {path, url, size}. Saves an attachment's bytes to a session path (an attached message saves as MIME); url is a signed Houston download link. Never inline attachment bytes.")

-- Fixed-signature folder list shared with other mail connectors.
export("listMailFolders", true, function(...: any): {{id: string, name: string}}
	assert(select("#", ...) == 0, "listMailFolders takes no arguments")
	local FIELDS = "?$top=100&$select=id,displayName,childFolderCount"
	local folders: {{id: string, name: string}} = json.decode("[]")
	local seen: {[string]: boolean} = {}
	local pending: {{href: string, prefix: string}} = {{href = API .. "/mailFolders" .. FIELDS, prefix = ""}}
	while #pending > 0 do
		local job = table.remove(pending) :: {href: string, prefix: string}
		local page = call("listMailFolders", "GET", job.href)
		local items: {any} = if type(page.value) == "table" then page.value else {}
		for _, folder in items do
			if type(folder) ~= "table" or type(folder.id) ~= "string" or folder.id == "" or type(folder.displayName) ~= "string" then
				houston.fail({operation = "listMailFolders", layer = "upstream", retryable = false, message = "Microsoft Graph returned invalid folder metadata"})
			end
			-- $skip paging can repeat a folder when the mailbox changes between pages.
			if not seen[folder.id] then
				seen[folder.id] = true
				local name = job.prefix .. folder.displayName
				table.insert(folders, {id = folder.id, name = name})
				if type(folder.childFolderCount) == "number" and folder.childFolderCount > 0 then
					table.insert(pending, {href = API .. "/mailFolders/" .. url.segment(folder.id, "folder ID") .. "/childFolders" .. FIELDS, prefix = name .. "/"})
				end
			end
		end
		local link = page["@odata.nextLink"]
		if type(link) == "string" then table.insert(pending, {href = pageLink(link, "/%l+Folders$"), prefix = job.prefix}) end
	end
	table.sort(folders, function(a: any, b: any) return a.id < b.id end)
	return folders
end, "listMailFolders() -> {{id, name}} sorted by ID. No arguments; every visible folder of the mailbox, nested names joined with '/' such as 'Inbox/Projects'.")

local MESSAGE = "A message uses Graph's fields: subject, body={contentType='Text'|'HTML', content}, toRecipients/ccRecipients/bccRecipients/replyTo={{emailAddress={address, name?}}}, importance?, attachments?={'path' or {path, name?, contentType?}} read from session files, under 3 MB in total (share larger files from OneDrive)."

export("createDraft", DRAFTS, function(input: any): Options
	return call("createDraft", "POST", API .. "/messages", compose(input, "createDraft options"))
end, "createDraft({subject?, body?, toRecipients?, ccRecipients?, bccRecipients?, attachments?, ...}) -> draft message. Saves to Drafts without sending" .. (if DRAFTS then "; the person reviews and sends it from Outlook. " else ". ") .. MESSAGE)

export("updateMessage", DRAFTS, function(input: any): Options
	local args = options(input)
	local id = text(args.id, "id")
	args.id = nil
	assert(next(args) ~= nil and args.attachments == nil, "updateMessage requires fields to change; add attachments with addAttachment")
	plain(args)
	draftOnly("updateMessage", id)
	return call("updateMessage", "PATCH", messagePath(id, "id"), args)
end, if DRAFTS then "updateMessage({id, subject?, body?, toRecipients?, ...}) -> message. Changes a draft's fields."
	else "updateMessage({id, isRead?, categories?, flag?={flagStatus='flagged'|'complete'|'notFlagged'}, importance?, ...draft fields}) -> message. Marks read or unread, categorizes or flags; drafts also take subject, body and recipients.")

export("deleteMessage", DRAFTS, function(input: any): Options
	local args = options(input)
	local id = text(args.id, "id")
	args.id = nil
	done("deleteMessage", args)
	draftOnly("deleteMessage", id)
	return call("deleteMessage", "DELETE", messagePath(id, "id"))
end, "deleteMessage({id}) -> {success=true}. Moves " .. (if DRAFTS then "a draft" else "the message") .. " to Deleted Items.")

export("addAttachment", DRAFTS, function(input: any): Options
	local args = options(input)
	local id = text(args.messageId, "messageId")
	local spec = {path = args.path, name = args.name, contentType = args.contentType}
	args.messageId, args.path, args.name, args.contentType = nil, nil, nil, nil
	done("addAttachment", args)
	assert(await(fs.stat(text(spec.path, "path"))).size < MAX_ATTACHMENTS, "attachments must stay under 3 MB; share larger files from OneDrive")
	draftOnly("addAttachment", id)
	local attachment = fileAttachments({spec})[1]
	return call("addAttachment", "POST", messagePath(id, "messageId") .. "/attachments", attachment)
end, "addAttachment({messageId, path, name?, contentType?}) -> attachment {id, name, size}. Attaches a session file under 3 MB to a draft.")

export("sendMail", false, function(input: any): Options
	local args = options(input)
	local body = {message = compose(args.message, "message"), saveToSentItems = args.saveToSentItems}
	args.message, args.saveToSentItems = nil, nil
	done("sendMail", args)
	return call("sendMail", "POST", API .. "/sendMail", body)
end, "sendMail({message, saveToSentItems?=true}) -> {success=true}. Sends immediately. " .. MESSAGE .. " A timeout may still have sent the mail: check Sent Items before retrying.")

export("createMailFolder", false, function(input: any): Options
	local args = options(input)
	local href = API .. "/mailFolders" .. (if args.parentId == nil then "" else "/" .. url.segment(text(args.parentId, "parentId"), "parentId") .. "/childFolders")
	args.parentId = nil
	text(args.displayName, "displayName")
	return call("createMailFolder", "POST", href, args)
end, "createMailFolder({displayName, parentId?}) -> mailFolder. A top-level folder, or a child of parentId.")

local overview = {
	"Microsoft Graph v1.0 for the connected Outlook mailbox. Operations take one named options object with Graph's camelCase fields and return Graph's JSON unchanged; sends and deletes return {success=true}. Connector calls return completed values: use them directly, without await.",
	"Messages carry decoded bodies; attachments save to session files, and composing reads attachments from session paths: never base64-encode anything yourself.",
	"Lists return one page: while ['@odata.nextLink'] is present, pass it back as nextLink (alone, with bodyFormat or maxBodyBytes if used) for the next page.",
	"No hidden paging; Houston itself retries only a short 429 wait. Errors report the HTTP status and Graph's error code and message, e.g. 'Microsoft Graph HTTP 404 (ErrorItemNotFound)'; 429, 503 and other transient server errors are retryable after Retry-After. A failed or timed-out write may already have succeeded; check before repeating.",
	"Example: local page = outlook.listMessages({folderId='inbox', filter='isRead eq false', top=20}); local full = outlook.getMessage({id=page.value[1].id}).",
}
if DRAFTS then
	table.insert(overview, 2, "Read and draft connection: Houston refuses every send, and changes apply only to drafts. Save drafts for the person to review and send from Outlook.")
end
exports.help = helpWith(overview)
return exports
