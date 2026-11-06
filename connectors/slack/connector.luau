-- Slack Web API for one connected user in one workspace, with a Slack user token.
-- Arguments and results keep Slack's native field names. Credentials are injected only by Houston's proxy.
type Options = {[string]: any}

local API = "https://slack.com/api/"
local LIMIT = 15

local function allow(names: {string}): {[string]: boolean}
	local set = {}
	for _, name in names do set[name] = true end
	return table.freeze(set)
end

local PAGE = allow({"cursor", "limit"})
local CHANNELS = allow({"cursor", "limit", "types", "exclude_archived"})
local HISTORY = allow({"cursor", "limit", "oldest", "latest", "inclusive", "include_all_metadata"})
local SEARCH = allow({"count", "page", "sort", "sort_dir", "highlight"})
local MENTIONS = allow({"count", "page", "sort", "sort_dir", "highlight", "query"})
local USERS = allow({"cursor", "limit", "include_locale"})
local MESSAGE = {"blocks", "attachments", "unfurl_links", "unfurl_media", "reply_broadcast", "mrkdwn", "parse", "link_names", "metadata", "client_msg_id"}
local REPLY = allow(MESSAGE)
local POST = allow({"thread_ts", table.unpack(MESSAGE)})
local UPDATE = allow({"blocks", "attachments", "parse", "link_names", "metadata", "file_ids", "reply_broadcast"})
local UPLOAD = allow({"filename", "title", "alt_text", "channel", "thread_ts", "text"})
-- Slack timestamps and cursors are opaque strings; a number would lose trailing zeros.
local STRINGS = allow({"cursor", "oldest", "latest", "thread_ts"})

-- Slack reports most failures as HTTP 200 with {ok = false, error = code}. Authentication
-- codes carry 401 and missing permissions 403, so Houston can ask for reconnection.
local AUTH_ERRORS = allow({"not_authed", "invalid_auth", "account_inactive", "token_revoked", "token_expired"})
local RETRYABLE = allow({"ratelimited", "internal_error", "fatal_error", "service_unavailable", "request_timeout"})

local function text(value: any, field: string): string
	assert(type(value) == "string" and value ~= "", "slack: " .. field .. " must be a nonempty string")
	return value
end

local function optional(value: any, field: string): string?
	if value == nil then return nil end
	return text(value, field)
end

local function options(value: any, allowed: {[string]: boolean}): Options
	local copy: Options = {}
	if value == nil then return copy end
	assert(type(value) == "table", "slack: options must be a table")
	for key, item in value do
		assert(allowed[key], "slack: unknown option " .. tostring(key))
		copy[key] = if STRINGS[key] then text(item, key) else item
	end
	return copy
end

local function form(params: Options): string
	local parts: {string} = {}
	for key, value in params do
		assert(type(value) == "string" or type(value) == "number" or type(value) == "boolean",
			"slack: " .. key .. " must be a string, number or boolean")
		table.insert(parts, url.encode(key) .. "=" .. url.encode(value))
	end
	table.sort(parts)
	return table.concat(parts, "&")
end

local function fail(operation: string, status: number, body: any, headers: HttpHeaders, write: boolean?): never
	local code = if type(body) == "table" and type(body.error) == "string" then string.sub(body.error, 1, 100) else nil
	local message = "slack: " .. (code or ("HTTP " .. status))
	if type(body) == "table" and type(body.needed) == "string" then
		message ..= " (needs " .. string.sub(body.needed, 1, 200) .. ")"
	end
	if code and AUTH_ERRORS[code] then
		status = 401
		message ..= "; reconnect Slack"
	elseif code == "missing_scope" then
		status = 403
		message ..= "; reconnect Slack with the access this call needs"
	end
	local wait = headers["retry-after"]
	if wait and wait[1] then message ..= "; retry after " .. string.sub(wait[1], 1, 10) .. "s" end
	-- A failed write may still have taken effect, unless Slack rate-limited it.
	local limited = status == 429 or code == "ratelimited"
	local transient = status >= 500 or (code ~= nil and RETRYABLE[code] == true)
	return houston.fail({operation = operation, layer = "upstream", upstream_status = status,
		retryable = limited or (transient and not write), message = message})
end

local function check(operation: string, response: HttpResponse, write: boolean?)
	if response.statusCode >= 200 and response.statusCode < 300 then return end
	local ok, body = pcall(json.decode, await(response.body:readPrefix(4096)))
	fail(operation, response.statusCode, if ok then body else nil, response.headers, write)
end

-- Reads use GET query strings and writes JSON bodies. files.getUploadURLExternal takes a form
-- body; it only reserves an upload URL, so like reads its transient failures stay retryable.
local function call(operation: string, method: string, params: Options, encoding: ("json" | "form")?): Options
	local request: HttpRequest = {method = "GET", url = API .. method}
	if encoding == "json" then
		request.method, request.body = "POST", json.encode(params)
		request.headers = {["Content-Type"] = {"application/json; charset=utf-8"}}
	elseif encoding == "form" then
		request.method, request.body = "POST", form(params)
		request.headers = {["Content-Type"] = {"application/x-www-form-urlencoded"}}
	else
		local query = form(params)
		if query ~= "" then request.url ..= "?" .. query end
	end
	local response = await(http.request(request))
	check(operation, response, encoding == "json")
	local ok, body = pcall(json.decode, await(response.body:readAll()))
	if not ok or type(body) ~= "table" or type(body.ok) ~= "boolean" then
		return houston.fail({operation = operation, layer = "upstream", upstream_status = response.statusCode,
			retryable = false, message = "slack: invalid JSON response"})
	end
	if body.ok ~= true then fail(operation, response.statusCode, body, response.headers, encoding == "json") end
	local metadata = body.response_metadata
	if type(metadata) == "table" and type(metadata.next_cursor) == "string" and metadata.next_cursor ~= "" then
		body.nextCursor = metadata.next_cursor
	end
	return body
end

local function field(operation: string, body: Options, name: string): any
	local value = body[name]
	if value == nil then
		return houston.fail({operation = operation, layer = "upstream", retryable = false,
			message = "slack: response has no " .. name})
	end
	return value
end

local function getProfile(): Options
	return call("getProfile", "auth.test", {})
end

local function listChannels(opts: Options?): Options
	local params = options(opts, CHANNELS)
	params.types = params.types or "public_channel,private_channel,im,mpim"
	if params.exclude_archived == nil then params.exclude_archived = true end
	return call("listChannels", "users.conversations", params)
end

local function getChannel(channel: string): Options
	return field("getChannel", call("getChannel", "conversations.info", {channel = text(channel, "channel ID")}), "channel")
end

local function listMessages(channel: string, opts: Options?): Options
	local params = options(opts, HISTORY)
	params.channel = text(channel, "channel ID")
	params.limit = params.limit or LIMIT
	return call("listMessages", "conversations.history", params)
end

local function getThread(channel: string, ts: string, opts: Options?): Options
	local params = options(opts, HISTORY)
	params.channel, params.ts = text(channel, "channel ID"), text(ts, "thread timestamp")
	params.limit = params.limit or LIMIT
	return call("getThread", "conversations.replies", params)
end

local function search(operation: string, query: string, params: Options): Options
	params.query = text(query, "search query")
	params.sort = params.sort or "timestamp"
	params.sort_dir = params.sort_dir or "desc"
	local messages = call(operation, "search.messages", params).messages
	if type(messages) ~= "table" then
		return houston.fail({operation = operation, layer = "upstream", retryable = false, message = "slack: response has no messages"})
	end
	local paging = messages.paging
	if type(paging) == "table" and type(paging.page) == "number" and type(paging.pages) == "number" and paging.page < paging.pages then
		messages.nextPage = paging.page + 1
	end
	return messages
end

local function searchMessages(query: string, opts: Options?): Options
	return search("searchMessages", query, options(opts, SEARCH))
end

local function listMentions(opts: Options?): Options
	local params = options(opts, MENTIONS)
	local narrow = if params.query == "" then nil else optional(params.query, "query")
	params.query = nil
	local query = "<@" .. text(call("listMentions", "auth.test", {}).user_id, "authenticated user ID") .. ">"
	return search("listMentions", if narrow then query .. " " .. narrow else query, params)
end

local function listMembers(channel: string, opts: Options?): Options
	local params = options(opts, PAGE)
	params.channel = text(channel, "channel ID")
	return call("listMembers", "conversations.members", params)
end

local function getUser(user: string): Options
	return field("getUser", call("getUser", "users.info", {user = text(user, "user ID")}), "user")
end

local function listUsers(opts: Options?): Options
	local params = options(opts, USERS)
	params.limit = params.limit or 200
	return call("listUsers", "users.list", params)
end

local function getPermalink(channel: string, ts: string): string
	return field("getPermalink", call("getPermalink", "chat.getPermalink",
		{channel = text(channel, "channel ID"), message_ts = text(ts, "message timestamp")}), "permalink")
end

local function getFile(id: string): Options
	return field("getFile", call("getFile", "files.info", {file = text(id, "file ID")}), "file")
end

local function downloadFile(id: string, path: string): Options
	text(path, "session path")
	local file = getFile(id)
	if file.is_external == true then
		return houston.fail({operation = "downloadFile", layer = "upstream", retryable = false,
			message = "slack: this file is stored outside Slack; open its url_private link instead"})
	end
	local source = text(file.url_private_download or file.url_private, "file download URL")
	local response = await(http.request({method = "GET", url = source}))
	-- Slack redirects an unauthorized file request to its sign-in page, or serves that page.
	local status, kind = response.statusCode, response.headers["content-type"]
	local html = type(file.mimetype) == "string" and string.find(file.mimetype, "html", 1, true) ~= nil
	local page = status >= 200 and status < 300 and kind ~= nil and kind[1] ~= nil
		and string.find(kind[1], "text/html", 1, true) ~= nil and not html
	if page or (status >= 300 and status < 400) then
		response.body:close()
		return houston.fail({operation = "downloadFile", layer = "upstream", upstream_status = 401,
			retryable = false, message = "slack: file download returned a sign-in page; reconnect Slack"})
	end
	check("downloadFile", response)
	local output = fs.open(path, "w")
	output:write(response.body)
	await(output:close())
	return {path = path, url = await(fs.signedGetUrl(path)), bytes = await(fs.stat(path)).size}
end

local function post(operation: string, channel: string, message: string, params: Options): Options
	params.channel, params.text = text(channel, "channel ID"), text(message, "message text")
	return call(operation, "chat.postMessage", params, "json")
end

local function postMessage(channel: string, message: string, opts: Options?): Options
	return post("postMessage", channel, message, options(opts, POST))
end

local function reply(channel: string, ts: string, message: string, opts: Options?): Options
	local params = options(opts, REPLY)
	params.thread_ts = text(ts, "thread timestamp")
	return post("reply", channel, message, params)
end

local function updateMessage(channel: string, ts: string, message: string, opts: Options?): Options
	local params = options(opts, UPDATE)
	params.channel, params.ts, params.text = text(channel, "channel ID"), text(ts, "message timestamp"), text(message, "message text")
	return call("updateMessage", "chat.update", params, "json")
end

local function deleteMessage(channel: string, ts: string): Options
	return call("deleteMessage", "chat.delete", {channel = text(channel, "channel ID"), ts = text(ts, "message timestamp")}, "json")
end

local function openConversation(users: string | {string}): Options
	local list = users
	if type(list) == "table" then
		for index, user in list do text(user, "user ID " .. tostring(index)) end
		list = table.concat(list, ",")
	end
	return field("openConversation", call("openConversation", "conversations.open", {users = text(list, "user IDs")}, "json"), "channel")
end

local function reaction(operation: string, method: string, channel: string, ts: string, name: string): Options
	return call(operation, method, {channel = text(channel, "channel ID"), timestamp = text(ts, "message timestamp"),
		name = text(name, "emoji name")}, "json")
end

local function uploadFile(path: string, opts: Options?): Options
	local params = options(opts, UPLOAD)
	local name = text(params.filename or string.match(text(path, "session path"), "([^/]+)$"), "filename")
	local complete = {
		files = {{id = "", title = optional(params.title, "title") or name}},
		channel_id = optional(params.channel, "channel"), thread_ts = optional(params.thread_ts, "thread_ts"),
		initial_comment = optional(params.text, "text"),
	}
	local altText = optional(params.alt_text, "alt_text")
	assert(complete.channel_id or (complete.thread_ts == nil and complete.initial_comment == nil),
		"slack: thread_ts and text need channel; omit all three to keep the file private")
	local stat = await(fs.stat(path))
	assert(stat.isFile and stat.size > 0, "slack: upload path must be a nonempty session file")
	local upload = call("uploadFile", "files.getUploadURLExternal", {filename = name, length = stat.size, alt_txt = altText}, "form")
	complete.files[1].id = text(upload.file_id, "uploaded file ID")
	local response = await(http.request({method = "POST", url = text(upload.upload_url, "upload URL"),
		headers = {["Content-Type"] = {"application/octet-stream"}}, body = fs.open(path, "r")}))
	-- Slack discards an upload that is never completed, so this step is safe to retry.
	check("uploadFile", response)
	response.body:close()
	return call("uploadFile", "files.completeUploadExternal", complete, "json")
end

local exports: {[string]: any} = {
	getProfile = getProfile, listChannels = listChannels, getChannel = getChannel,
	listMessages = listMessages, getThread = getThread, searchMessages = searchMessages,
	listMentions = listMentions, listMembers = listMembers, getUser = getUser, listUsers = listUsers,
	getPermalink = getPermalink, getFile = getFile, downloadFile = downloadFile,
}
if config.access == "read-write" then
	exports.postMessage = postMessage
	exports.reply = reply
	exports.updateMessage = updateMessage
	exports.deleteMessage = deleteMessage
	exports.openConversation = openConversation
	exports.addReaction = function(channel: string, ts: string, name: string): Options
		return reaction("addReaction", "reactions.add", channel, ts, name)
	end
	exports.removeReaction = function(channel: string, ts: string, name: string): Options
		return reaction("removeReaction", "reactions.remove", channel, ts, name)
	end
	exports.uploadFile = uploadFile
end

local helpSchemas = require("lib/help.luau")
local str, flag = {type = "string"}, {type = "boolean"}
local nonempty = {type = "string", minLength = 1}
local stamp = {type = "string", minLength = 1, description = "Opaque Slack message timestamp, preserving all digits; never a number."}
local function record(properties: Options): any return {type = "object", properties = properties, additionalProperties = true} end
local function list(item: any): any return {type = "array", items = item} end
local channelSchema = record({id = str, name = str, is_channel = flag, is_group = flag, is_im = flag, is_mpim = flag, is_archived = flag,
	topic = record({value = str}), purpose = record({value = str})})
local userSchema = record({id = str, name = str, real_name = str, deleted = flag, is_bot = flag,
	profile = record({display_name = str, real_name = str, email = str, title = str})})
local fileSchema = record({id = str, name = str, title = str, mimetype = str, size = {type = "integer"}, is_external = flag,
	url_private = str, url_private_download = str, permalink = str})
local messageSchema = record({ts = stamp, thread_ts = stamp, text = str, user = str, subtype = str, files = list(fileSchema),
	blocks = list(record({type = str})), reply_count = {type = "integer"}})
local function page(field: string, item: any): any
	return record({[field] = list(item), ok = {const = true}, has_more = flag, nextCursor = str,
		response_metadata = record({next_cursor = str, warnings = list(str)})})
end
local historySchema = page("messages", messageSchema)
local searchSchema = record({matches = list(messageSchema), total = {type = "integer"}, nextPage = {type = "integer"},
	paging = record({count = {type = "integer"}, total = {type = "integer"}, page = {type = "integer"}, pages = {type = "integer"}})})
local postedSchema = record({ok = {const = true}, channel = str, ts = stamp, text = str, message = messageSchema})
local uploadOptions = helpSchemas.options(UPLOAD)
uploadOptions.dependentRequired = {thread_ts = {"channel"}, text = {"channel"}}
local function document(description: string, args: {string}, properties: Options, required: {string}, example: Options, output: any, write: boolean): any
	local schema: any = {type = "object", properties = properties, required = if #required > 0 then required else nil,
		additionalProperties = false, examples = {example}}
	if properties.opts and (properties.opts.properties.blocks or properties.opts.properties.attachments) then
		schema["$defs"] = helpSchemas.definitions
	end
	return {description = description, args = args, inputSchema = schema, outputSchema = output,
		annotations = {readOnlyHint = not write, destructiveHint = write, idempotentHint = not write}}
end
local operationHelp: Options = {
	getProfile = document([[The connected Slack user and workspace.]],
		{}, {}, {}, {}, record({user_id=str,user=str,team_id=str,team=str,url=str}), false),
	listChannels = document([[Your channels and DMs (users.conversations). opts: types (comma-separated public_channel,private_channel,im,mpim; default all), exclude_archived (default true), limit, cursor.]],
		{"opts"}, {opts=helpSchemas.options(CHANNELS)}, {}, {}, page("channels",channelSchema), false),
	getChannel = document([[Channel details (conversations.info).]],
		{"channel"}, {channel=nonempty}, {"channel"}, {channel="C1"}, channelSchema, false),
	listMessages = document([[Newest first (conversations.history). opts: limit (default 15), cursor, oldest, latest, inclusive, include_all_metadata. Message files arrays carry file IDs for getFile and downloadFile.]],
		{"channel","opts"}, {channel=nonempty,opts=helpSchemas.options(HISTORY,LIMIT)}, {"channel"}, {channel="C1",opts={oldest="1780000000.000000"}}, historySchema, false),
	getThread = document([[The parent message and its replies (conversations.replies). Same opts as listMessages.]],
		{"channel","ts","opts"}, {channel=nonempty,ts=stamp,opts=helpSchemas.options(HISTORY,LIMIT)}, {"channel","ts"}, {channel="C1",ts="1790000000.000001",opts={cursor="next+one",limit=5}}, historySchema, false),
	searchMessages = document([[Slack search syntax, such as "in:#general from:@ana after:2026-01-01". opts: count, page, sort ("timestamp" default or "score"), sort_dir ("desc" default), highlight. Pass page = result.nextPage for the next page.]],
		{"query","opts"}, {query=nonempty,opts=helpSchemas.options(SEARCH)}, {"query"}, {query="in:#general hello",opts={count=1}}, searchSchema, false),
	listMentions = document([[Search results mentioning you, including thread replies. Same opts as searchMessages, plus query to narrow it, such as "in:#general".]],
		{"opts"}, {opts=helpSchemas.options(MENTIONS)}, {}, {opts={query="in:#general",page=1}}, searchSchema, false),
	listMembers = document([[User IDs in a channel. opts: limit, cursor.]],
		{"channel","opts"}, {channel=nonempty,opts=helpSchemas.options(PAGE)}, {"channel"}, {channel="C1",opts={limit=2}}, page("members",str), false),
	getUser = document([[A user's profile (users.info).]],
		{"user"}, {user=nonempty}, {"user"}, {user="U1"}, userSchema, false),
	listUsers = document([[Workspace users. opts: limit (default 200), cursor, include_locale.]],
		{"opts"}, {opts=helpSchemas.options(USERS,200)}, {}, {}, page("members",userSchema), false),
	getPermalink = document([[A message's Slack URL.]],
		{"channel","ts"}, {channel=nonempty,ts=stamp}, {"channel","ts"}, {channel="C1",ts="1.2"}, nil, false),
	getFile = document([[File metadata (files.info): name, mimetype, size, url_private...]],
		{"id"}, {id=nonempty}, {"id"}, {id="F1"}, fileSchema, false),
	downloadFile = document([[Streams a Slack file into a session path; url is a Houston signed download URL. Never inline file contents. A download that fails while streaming leaves path as it was. External files (is_external) are not stored in Slack and cannot be downloaded.]],
		{"id","path"}, {id=nonempty,path=nonempty}, {"id","path"}, {id="F1",path="report.pdf"}, record({path=str,url=str,bytes={type="integer",minimum=0}}), true),
	postMessage = document([[Posts as you; channel is a channel or DM ID. opts: thread_ts, blocks, attachments, unfurl_links, unfurl_media, reply_broadcast, mrkdwn, parse, link_names, metadata, client_msg_id. Never retry automatically: after an error the message may already be posted, so check with listMessages first.]],
		{"channel","text","opts"}, {channel=nonempty,text=nonempty,opts=helpSchemas.options(POST)}, {"channel","text"}, {channel="C1",text="Hi"}, postedSchema, true),
	reply = document([[Replies in the thread of message ts. Same opts as postMessage, without thread_ts.]],
		{"channel","ts","text","opts"}, {channel=nonempty,ts=stamp,text=nonempty,opts=helpSchemas.options(REPLY)}, {"channel","ts","text"}, {channel="C1",ts="1.000001",text="Hello",opts={blocks={{type="section",text={type="mrkdwn",text="*Hi*"}}},unfurl_links=false}}, postedSchema, true),
	updateMessage = document([[Edits one of your messages. opts: blocks, attachments, parse, link_names, metadata, file_ids, reply_broadcast.]],
		{"channel","ts","text","opts"}, {channel=nonempty,ts=stamp,text=nonempty,opts=helpSchemas.options(UPDATE)}, {"channel","ts","text"}, {channel="C1",ts="1.000003",text="Edited"}, postedSchema, true),
	deleteMessage = document([[Deletes one of your messages.]],
		{"channel","ts"}, {channel=nonempty,ts=stamp}, {"channel","ts"}, {channel="C1",ts="1.000003"}, postedSchema, true),
	openConversation = document([[Opens a DM (one user ID) or group DM (a comma-separated string or array of IDs); pass channel.id to postMessage.]],
		{"users"}, {users={anyOf={nonempty :: any,{type="array",minItems=1,maxItems=8,items=nonempty}}}}, {"users"}, {users={"U1","U2"}}, channelSchema, true),
	addReaction = document([[Adds an emoji reaction; name has no colons, such as "thumbsup".]],
		{"channel","ts","name"}, {channel=nonempty,ts=stamp,name=nonempty}, {"channel","ts","name"}, {channel="C1",ts="1.000003",name="thumbsup"}, record({ok={const=true}}), true),
	removeReaction = document([[Removes your emoji reaction.]],
		{"channel","ts","name"}, {channel=nonempty,ts=stamp,name=nonempty}, {"channel","ts","name"}, {channel="C1",ts="1.000003",name="thumbsup"}, record({ok={const=true}}), true),
	uploadFile = document([[Streams a session file to Slack. opts: filename (default the path's last segment), title, alt_text, channel (share there; omit to keep the file private), thread_ts, text (a comment posted with the file).]],
		{"path","opts"}, {path=nonempty,opts=uploadOptions}, {"path"}, {path="reports/q3.txt",opts={channel="C1",thread_ts="1.000001",text="Q3 numbers",title="Q3",alt_text="Report"}}, page("files",fileSchema), true),
}

table.insert(operationHelp.postMessage.inputSchema.examples, {channel = "C1", text = "Review the release notes", opts = {
	blocks = {{type = "rich_text", elements = {{type = "rich_text_section", elements = {{type = "text", text = "Release notes", style = {bold = true}} :: any,
		{type = "link", url = "https://example.com/releases", text = "Read notes"}}}}} :: any,
		{type = "actions", elements = {{type = "button", action_id = "review_release", text = {type = "plain_text", text = "Review"}, url = "https://example.com/releases"}}}},
	metadata = {event_type = "release_notes", event_payload = {release = "example"}},
}})
local docs: Options = {}
for name in exports do
	assert(operationHelp[name], "missing help for configured function " .. name)
	docs[name] = operationHelp[name]
end
exports.help = {text = "Slack: one connected user in one workspace. Calls return completed values; use them directly without await. Pass channel IDs, user IDs and message timestamps as strings. Unknown options are rejected. Writes act as the connected user and require Read and write access. Configured access: " .. config.access .. ".", functions = docs,
	sections = {
		paging = "Each call returns one page. Pass cursor=result.nextCursor, or page=result.nextPage for search, retaining other filters. Stop when the continuation field is absent. Slack timestamps are opaque strings: preserve every digit, including trailing zeros.",
		limits = "Slack limits conversations.history and conversations.replies to 1 request per minute and 15 messages for apps outside the Slack Marketplace. Wait as a ratelimited error says; prefer searchMessages to scanning many channels. Methods have separate provider limits. Keep message text under 4000 characters when practical; Slack truncates very long text. A message allows at most 50 blocks and 100 attachments, with limits on each block's fields.",
		formatting = "Slack uses mrkdwn: <@U123> mentions a user, <#C123> links a channel, and <https://example.com|label> labels a link. Message text is required by this connector, including with blocks; use it for an accessible fallback. Block Kit fields use native Slack objects. Help describes nested text, options, elements, rich text and common block discriminators; provider extensions pass through. See https://docs.slack.dev/reference/block-kit/ for each block's surface and field rules.",
		files = "Download to a session path and return the signed Houston URL; never inline file bytes. Failed downloads leave the existing session file untouched. Upload a nonempty session file with uploadFile; omitting channel keeps it private. thread_ts and text need channel. Transfers must finish within the invocation and session file limits.",
		errors = "Errors preserve Slack codes, such as not_in_channel or missing_scope, and Retry-After when supplied. Authentication or missing scopes require reconnecting with the necessary access. Writes never retry automatically; after a timeout or error, inspect the message or file before repeating a change because Slack may already have applied it.",
	}}
return exports
