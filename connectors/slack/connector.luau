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

-- Reads use GET query strings, writes JSON bodies, and files.getUploadURLExternal a form body.
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
	check(operation, response, encoding ~= nil)
	local ok, body = pcall(json.decode, await(response.body:readAll()))
	if not ok or type(body) ~= "table" or type(body.ok) ~= "boolean" then
		return houston.fail({operation = operation, layer = "upstream", upstream_status = response.statusCode,
			retryable = false, message = "slack: invalid JSON response"})
	end
	if body.ok ~= true then fail(operation, response.statusCode, body, response.headers, encoding ~= nil) end
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
	local narrow = optional(params.query, "query")
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
	local source = text(file.url_private_download or file.url_private, "file download URL")
	local output = fs.open(path, "w")
	local response = await(http.request({method = "GET", url = source}))
	-- Slack answers an unauthorized file request with its HTML sign-in page.
	local kind = response.headers["content-type"]
	local signIn = kind ~= nil and kind[1] ~= nil and string.find(kind[1], "text/html", 1, true) ~= nil and file.mimetype ~= "text/html"
	if signIn or response.statusCode < 200 or response.statusCode >= 300 then
		await(output:close())
		check("downloadFile", response)
		response.body:close()
		return houston.fail({operation = "downloadFile", layer = "upstream", upstream_status = 401,
			retryable = false, message = "slack: file download returned a sign-in page; reconnect Slack"})
	end
	output:write(response.body)
	await(output:close())
	return {path = path, url = await(fs.signedGetUrl(path)), bytes = await(fs.stat(path)).size}
end

local function postMessage(channel: string, message: string, opts: Options?): Options
	local params = options(opts, POST)
	params.channel, params.text = text(channel, "channel ID"), text(message, "message text")
	return call("postMessage", "chat.postMessage", params, "json")
end

local function reply(channel: string, ts: string, message: string, opts: Options?): Options
	local params = options(opts, REPLY)
	params.channel, params.thread_ts, params.text = text(channel, "channel ID"), text(ts, "thread timestamp"), text(message, "message text")
	return call("reply", "chat.postMessage", params, "json")
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
	check("uploadFile", response, true)
	response.body:close()
	-- Slack discards the upload unless it is completed.
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

local operationHelp: {[string]: string} = {
	getProfile = [[getProfile() -> {user_id, user, team_id, team, url}
The connected Slack user and workspace.]],
	listChannels = [[listChannels(opts?) -> {channels, nextCursor?}
Your channels and DMs (users.conversations). opts: types (comma-separated public_channel,private_channel,im,mpim; default all), exclude_archived (default true), limit, cursor.]],
	getChannel = [[getChannel(channel) -> channel
Channel details (conversations.info).]],
	listMessages = [[listMessages(channel, opts?) -> {messages, has_more, nextCursor?}
Newest first (conversations.history). opts: limit (default 15), cursor, oldest, latest, inclusive, include_all_metadata. Message files arrays carry file IDs for getFile and downloadFile.]],
	getThread = [[getThread(channel, ts, opts?) -> {messages, has_more, nextCursor?}
The parent message and its replies (conversations.replies). Same opts as listMessages.]],
	searchMessages = [[searchMessages(query, opts?) -> {matches, total, paging, nextPage?}
Slack search syntax, such as "in:#general from:@ana after:2026-01-01". opts: count, page, sort ("timestamp" default or "score"), sort_dir ("desc" default), highlight. Pass page = result.nextPage for the next page.]],
	listMentions = [[listMentions(opts?) -> {matches, total, paging, nextPage?}
Search results mentioning you, including thread replies. Same opts as searchMessages, plus query to narrow it, such as "in:#general".]],
	listMembers = [[listMembers(channel, opts?) -> {members, nextCursor?}
User IDs in a channel. opts: limit, cursor.]],
	getUser = [[getUser(user) -> user
A user's profile (users.info).]],
	listUsers = [[listUsers(opts?) -> {members, nextCursor?}
Workspace users. opts: limit (default 200), cursor, include_locale.]],
	getPermalink = [[getPermalink(channel, ts) -> string
A message's Slack URL.]],
	getFile = [[getFile(id) -> file
File metadata (files.info): name, mimetype, size, url_private...]],
	downloadFile = [[downloadFile(id, path) -> {path, url, bytes}
Streams a Slack file into a session path; url is a Houston signed download URL. Never inline file contents.]],
	postMessage = [[postMessage(channel, text, opts?) -> {channel, ts, message}
Posts as you; channel is a channel or DM ID. opts: thread_ts, blocks, attachments, unfurl_links, unfurl_media, reply_broadcast, mrkdwn, parse, link_names, metadata, client_msg_id. Never retry automatically: after an error the message may already be posted, so check with listMessages first.]],
	reply = [[reply(channel, ts, text, opts?) -> {channel, ts, message}
Replies in the thread of message ts. Same opts as postMessage, without thread_ts.]],
	updateMessage = [[updateMessage(channel, ts, text, opts?) -> {channel, ts, text}
Edits one of your messages. opts: blocks, attachments, parse, link_names, metadata, file_ids, reply_broadcast.]],
	deleteMessage = [[deleteMessage(channel, ts) -> {channel, ts}
Deletes one of your messages.]],
	openConversation = [[openConversation(users) -> channel
Opens a DM (one user ID) or group DM (a comma-separated string or array of IDs); pass channel.id to postMessage.]],
	addReaction = [[addReaction(channel, ts, name) -> {ok}
Adds an emoji reaction; name has no colons, such as "thumbsup".]],
	removeReaction = [[removeReaction(channel, ts, name) -> {ok}
Removes your emoji reaction.]],
	uploadFile = [[uploadFile(path, opts?) -> {files}
Streams a session file to Slack. opts: filename (default the path's last segment), title, alt_text, channel (share there; omit to keep the file private), thread_ts, text (a comment posted with the file).]],
}

exports.help = function(): string
	local names: {string} = {}
	for name in exports do
		if name ~= "help" then table.insert(names, name) end
	end
	table.sort(names)
	local sections = {[[Slack: one connected user in one workspace. Credentials stay on Houston. Calls return completed values; do not wrap them in await(). Pass channel IDs, user IDs and message timestamps (ts) as strings, never numbers. Unknown options are rejected. Writes act as the connected user and need Read and write access.
Each call returns one page. Pass cursor = result.nextCursor (or page = result.nextPage for searches) for the next one. Slack limits conversations.history and conversations.replies to 1 request per minute and 15 messages for apps outside the Slack Marketplace, so listMessages and getThread can fail with ratelimited: wait as the error says, and prefer searchMessages to scan many channels. Slack errors name the Slack error code, such as not_in_channel or missing_scope.]]}
	for _, name in names do
		local section = operationHelp[name]
		assert(section, "missing help for configured function " .. name)
		table.insert(sections, "## " .. section)
	end
	return table.concat(sections, "\n\n")
end

return exports
