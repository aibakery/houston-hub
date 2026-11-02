-- Discord REST API v10 as Houston's bot, bound to the one server (guild) this connection added it to.
-- Arguments and results keep Discord's native field names. Credentials are injected only by Houston's proxy.
type Options = {[string]: any}
type Check = (any, string) -> any

local API = "https://discord.com/api/v10/"
-- Discord requires this User-Agent format for bots.
local AGENT = "DiscordBot (https://ok-houston.com, 1.0)"
local LIMIT = 25
local MAX_BODY = 4 * 1024 * 1024
local MAX_ID = "18446744073709551615"
-- Captured by Houston from the install's token exchange. The proxy pins every guild route to
-- it; channel routes carry no guild, so inGuild below checks each channel against it first.
local GUILD: string? = if auth.facts then auth.facts.guild_id else nil

local function snowflake(value: any, field: string): string
	assert(type(value) == "string" and #value <= 20 and string.match(value, "^[1-9]%d*$") ~= nil
		and (#value < 20 or value <= MAX_ID), "discord: " .. field .. " must be a Discord ID string of digits")
	return value
end

local function text(value: any, field: string, max: number): string
	assert(type(value) == "string" and value ~= "", "discord: " .. field .. " must be a nonempty string")
	local length = utf8.len(value)
	assert(length ~= nil and length <= max, "discord: " .. field .. " must be valid UTF-8 of at most " .. max .. " characters")
	return value
end

local function integer(min: number, max: number): Check
	return function(value: any, field: string): any
		assert(type(value) == "number" and value == math.floor(value) and value >= min and value <= max,
			"discord: " .. field .. " must be an integer from " .. min .. " to " .. max)
		return value
	end
end

local function boolean(value: any, field: string): any
	assert(type(value) == "boolean", "discord: " .. field .. " must be a boolean")
	return value
end

local function oneOf(values: {any}): Check
	return function(value: any, field: string): any
		assert(table.find(values, value) ~= nil, "discord: " .. field .. " must be one of " .. table.concat(values, ", "))
		return value
	end
end

-- A dense array of 1 to max items; a single string counts as a one-item array.
local function array(max: number, each: Check): Check
	return function(value: any, field: string): any
		if type(value) == "string" then value = {value} end
		assert(type(value) == "table", "discord: " .. field .. " must be an array")
		local count = 0
		for _ in value do count += 1 end
		assert(count >= 1 and count <= max and #value == count, "discord: " .. field .. " must be an array of 1 to " .. max .. " items")
		local out = table.create(count)
		for index = 1, count do out[index] = each(value[index], field) end
		return out
	end
end

local function object(value: any, field: string): any
	assert(type(value) == "table", "discord: " .. field .. " must be a table")
	return value
end

-- Messages notify nobody unless the caller names the users or roles to mention.
local function mentions(value: any, field: string): any
	assert(type(value) == "table", "discord: " .. field .. " must be a table")
	local out: Options = {parse = json.decode("[]")}
	for key, item in value do
		if key == "users" or key == "roles" then
			out[key] = array(100, snowflake)(item, field .. "." .. key)
		elseif key == "replied_user" then
			out[key] = boolean(item, field .. ".replied_user")
		else
			error("discord: unknown " .. field .. " field " .. tostring(key) .. "; use users, roles or replied_user")
		end
	end
	return out
end

local function flags(allowed: number): Check
	return function(value: any, field: string): any
		integer(0, allowed)(value, field)
		assert(bit32.band(value, bit32.bnot(allowed)) == 0, "discord: " .. field .. " only accepts the documented flags")
		return value
	end
end

local function nonce(value: any, field: string): any
	assert(type(value) == "string" and #value <= 25 and string.match(value, "^[%w_%-]+$") ~= nil,
		"discord: " .. field .. " must be at most 25 letters, digits, - or _")
	return value
end

local function timestamp(value: any, field: string): any
	assert(type(value) == "string" and #value <= 40 and string.match(value, "^%d%d%d%d%-%d%d%-%d%dT[%d:%.]+[%dZ:+%-]*$") ~= nil,
		"discord: " .. field .. " must be an ISO 8601 timestamp such as 2026-01-31T12:00:00Z")
	return value
end

local function options(value: any, allowed: {[string]: Check}): Options
	local copy: Options = {}
	if value == nil then return copy end
	assert(type(value) == "table", "discord: options must be a table")
	for key, item in value do
		local check = allowed[key]
		assert(check ~= nil, "discord: unknown option " .. tostring(key))
		copy[key] = check(item, key)
	end
	return copy
end

local SERVER = table.freeze({with_counts = boolean})
local MESSAGES = table.freeze({before = snowflake, after = snowflake, around = snowflake, limit = integer(1, 100)})
local ARCHIVED = table.freeze({before = timestamp, limit = integer(2, 100)})
local MEMBERS = table.freeze({limit = integer(1, 1000)})
local HAS = {"image", "sound", "video", "file", "sticker", "embed", "link", "poll", "snapshot"}
for index = 1, #HAS do table.insert(HAS, "-" .. HAS[index]) end
local SEARCH = table.freeze({
	channel_id = array(500, snowflake), author_id = array(100, snowflake), mentions = array(100, snowflake),
	author_type = array(6, oneOf({"user", "bot", "webhook", "-user", "-bot", "-webhook"})), has = array(18, oneOf(HAS)),
	min_id = snowflake, max_id = snowflake, pinned = boolean, include_nsfw = boolean,
	sort_by = oneOf({"timestamp", "relevance"}), sort_order = oneOf({"desc", "asc"}),
	limit = integer(1, 25), offset = integer(0, 9975),
})
-- SUPPRESS_EMBEDS (4) and SUPPRESS_NOTIFICATIONS (4096); edits only accept SUPPRESS_EMBEDS.
local POST = table.freeze({embeds = array(10, object), allowed_mentions = mentions, flags = flags(4100), nonce = nonce, enforce_nonce = boolean})
local EDIT = table.freeze({embeds = array(10, object), allowed_mentions = mentions, flags = flags(4)})
local THREAD = table.freeze({message = snowflake, auto_archive_duration = oneOf({60, 1440, 4320, 10080}), rate_limit_per_user = integer(0, 21600)})

local function query(params: Options): string
	local parts: {string} = {}
	for key, value in params do
		for _, item in (if type(value) == "table" then value else {value}) :: {any} do
			table.insert(parts, url.encode(key) .. "=" .. url.encode(item))
		end
	end
	table.sort(parts)
	return if #parts == 0 then "" else "?" .. table.concat(parts, "&")
end

local function firstError(errors: any, path: string, depth: number): string?
	if type(errors) ~= "table" or depth > 8 then return nil end
	local list = errors._errors
	if type(list) == "table" and type(list[1]) == "table" and type(list[1].message) == "string" then
		return (if path == "" then "" else path .. ": ") .. string.sub(list[1].message, 1, 200)
	end
	for key, child in errors do
		local found = firstError(child, if path == "" then tostring(key) else path .. "." .. tostring(key), depth + 1)
		if found then return found end
	end
	return nil
end

local function retryAfter(headers: HttpHeaders, body: any): string?
	local wait = headers["retry-after"]
	if wait and wait[1] then return string.sub(wait[1], 1, 10) end
	if type(body) == "table" and type(body.retry_after) == "number" and body.retry_after > 0 and body.retry_after < 1e6 then
		return tostring(math.ceil(body.retry_after))
	end
	return nil
end

-- Discord bans clients that repeat 401, 403 and 429 responses, so none of them is retried here.
local function fail(operation: string, response: HttpResponse, write: boolean, guildRoute: boolean): never
	local status = response.statusCode
	local ok, body = pcall(json.decode, await(response.body:readPrefix(4096)))
	if not ok or type(body) ~= "table" then body = nil end
	local code = if body and type(body.code) == "number" then body.code else nil
	local message: string
	if status == 401 then
		message = "discord: Discord rejected Houston's bot credentials. This is a Houston configuration problem, not a problem with your connection; reconnecting does not fix it"
	elseif guildRoute and ((status == 403 and code == 50001) or (status == 404 and code == 10004)) then
		message = "discord: Houston was removed from this Discord server; open the connection settings and add it again"
	elseif status == 403 and code == 50013 then
		message = "discord: Houston's bot lacks a Discord permission for this action (code 50013); a server admin can grant it in the channel or role settings"
	else
		message = "discord: " .. (if body and type(body.message) == "string" then string.sub(body.message, 1, 200) else "HTTP " .. status)
		if code and code ~= 0 then message ..= " (code " .. code .. ")" end
		local detail = if body then firstError(body.errors, "", 0) else nil
		if detail then message ..= ": " .. detail end
	end
	local wait = if status == 429 then retryAfter(response.headers, body) else nil
	if wait then message ..= "; retry after " .. wait .. "s" end
	-- A rejected (429) write had no effect; after a 5xx a write may still have been applied.
	return houston.fail({operation = operation, layer = "upstream", upstream_status = status,
		retryable = status == 429 or (status >= 500 and not write), message = message})
end

local function send(method: string, path: string, params: Options?, body: any?): HttpResponse
	local headers: HttpHeaders = {["User-Agent"] = {AGENT}}
	local request: HttpRequest = {method = method, url = API .. path .. query(params or {}), headers = headers}
	if body ~= nil then
		headers["Content-Type"] = {"application/json"}
		request.body = json.encode(body)
	end
	return await(http.request(request))
end

local function decode(operation: string, method: string, path: string, response: HttpResponse): any
	local status = response.statusCode
	if status < 200 or status >= 300 then fail(operation, response, method ~= "GET", string.sub(path, 1, 7) == "guilds/") end
	if status == 204 then
		response.body:close()
		return true
	end
	local ok, body = pcall(json.decode, await(response.body:readAll(MAX_BODY)))
	if not ok or type(body) ~= "table" then
		return houston.fail({operation = operation, layer = "upstream", upstream_status = status, retryable = false,
			message = "discord: invalid JSON response"})
	end
	-- Search answers 202 with code 110000 while Discord is still indexing the server.
	if status == 202 then
		local wait = retryAfter(response.headers, body)
		return houston.fail({operation = operation, layer = "upstream", upstream_status = status, retryable = true,
			message = "discord: Discord is still indexing this server for search; retry after " .. (if wait then wait .. "s" else "a few seconds")})
	end
	return body
end

local function call(operation: string, method: string, path: string, params: Options?, body: any?): any
	return decode(operation, method, path, send(method, path, params, body))
end

local function guild(operation: string, path: string): string
	if GUILD == nil then
		return houston.fail({operation = operation, layer = "upstream", retryable = false,
			message = "discord: this connection is not bound to a Discord server; open the connection settings and add Houston to a server again"})
	end
	return "guilds/" .. GUILD .. path
end

-- The isolation guard for channel, thread and message routes: Discord serves any channel the bot
-- can see, in any server. Every outcome other than a channel of the bound server raises the same
-- error, so a foreign or DM channel is never returned or distinguished from a missing one.
local function inGuild(operation: string, channel: string): Options
	snowflake(channel, "channel ID")
	guild(operation, "")
	local path = "channels/" .. channel
	local response = send("GET", path)
	if response.statusCode == 403 or response.statusCode == 404 then
		response.body:close()
	else
		local found = decode(operation, "GET", path, response)
		if type(found) == "table" and found.guild_id == GUILD then return found end
	end
	return houston.fail({operation = operation, layer = "upstream", upstream_status = 404, retryable = false,
		message = "discord: channel " .. channel .. " is not in this server, or Houston's bot cannot view it"})
end

local function channelPath(operation: string, channel: string, rest: string): string
	inGuild(operation, channel)
	return "channels/" .. channel .. rest
end

local function messagePath(operation: string, channel: string, message: string, rest: string): string
	snowflake(channel, "channel ID")
	snowflake(message, "message ID")
	return channelPath(operation, channel, "/messages/" .. message .. rest)
end

local function emoji(value: any): string
	assert(type(value) == "string" and value ~= "" and #value <= 200, "discord: emoji must be a nonempty string")
	local name, id = string.match(value, "^<a?:([%w_]+):(%d+)>$")
	if name == nil then name, id = string.match(value, "^([%w_]+):(%d+)$") end
	if name ~= nil and id ~= nil then return url.encode(name .. ":" .. snowflake(id, "custom emoji ID")) end
	assert(utf8.len(value) ~= nil and string.find(value, "[%c%s/\\%%:<>]") == nil and string.find(value, "[\128-\255]") ~= nil,
		"discord: emoji must be a Unicode emoji such as \"👍\" or a custom emoji as \"name:id\"")
	return url.encode(value)
end

local function getServer(opts: Options?): Options
	local params = options(opts, SERVER)
	return call("getServer", "GET", guild("getServer", ""), params)
end

local function listChannels(): Options
	return call("listChannels", "GET", guild("listChannels", "/channels"))
end

local function getChannel(channel: string): Options
	return inGuild("getChannel", channel)
end

local function listMessages(channel: string, opts: Options?): Options
	local params = options(opts, MESSAGES)
	snowflake(channel, "channel ID")
	local anchors = (if params.before then 1 else 0) + (if params.after then 1 else 0) + (if params.around then 1 else 0)
	assert(anchors <= 1, "discord: pass only one of before, after and around")
	params.limit = params.limit or LIMIT
	return call("listMessages", "GET", channelPath("listMessages", channel, "/messages"), params)
end

local function getMessage(channel: string, message: string): Options
	return call("getMessage", "GET", messagePath("getMessage", channel, message, ""))
end

local function listThreads(): Options
	return call("listThreads", "GET", guild("listThreads", "/threads/active"))
end

local function listArchivedThreads(channel: string, opts: Options?): Options
	local params = options(opts, ARCHIVED)
	snowflake(channel, "channel ID")
	params.limit = params.limit or LIMIT
	return call("listArchivedThreads", "GET", channelPath("listArchivedThreads", channel, "/threads/archived/public"), params)
end

local function searchMessages(content: string?, opts: Options?): Options
	local params = options(opts, SEARCH)
	if content ~= nil and content ~= "" then params.content = text(content, "query", 1024) end
	return call("searchMessages", "GET", guild("searchMessages", "/messages/search"), params)
end

local function searchMembers(prefix: string, opts: Options?): Options
	local params = options(opts, MEMBERS)
	params.query = text(prefix, "query", 100)
	params.limit = params.limit or LIMIT
	return call("searchMembers", "GET", guild("searchMembers", "/members/search"), params)
end

local function getMember(user: string): Options
	return call("getMember", "GET", guild("getMember", "/members/" .. snowflake(user, "user ID")))
end

local function listRoles(): Options
	return call("listRoles", "GET", guild("listRoles", "/roles"))
end

local function messageBody(content: string, opts: Options?, allowed: {[string]: Check}): Options
	local body = options(opts, allowed)
	body.content = text(content, "content", 2000)
	body.allowed_mentions = body.allowed_mentions or {parse = json.decode("[]")}
	return body
end

local function postMessage(channel: string, content: string, opts: Options?): Options
	local body = messageBody(content, opts, POST)
	return call("postMessage", "POST", channelPath("postMessage", snowflake(channel, "channel ID"), "/messages"), nil, body)
end

local function reply(channel: string, message: string, content: string, opts: Options?): Options
	local body = messageBody(content, opts, POST)
	body.message_reference = {message_id = snowflake(message, "message ID")}
	return call("reply", "POST", channelPath("reply", snowflake(channel, "channel ID"), "/messages"), nil, body)
end

local function editMessage(channel: string, message: string, content: string, opts: Options?): Options
	local body = messageBody(content, opts, EDIT)
	return call("editMessage", "PATCH", messagePath("editMessage", channel, message, ""), nil, body)
end

local function deleteMessage(channel: string, message: string): boolean
	return call("deleteMessage", "DELETE", messagePath("deleteMessage", channel, message, ""))
end

local function reaction(operation: string, method: string, channel: string, message: string, value: string): boolean
	local encoded = emoji(value)
	return call(operation, method, messagePath(operation, channel, message, "/reactions/" .. encoded .. "/@me"))
end

local function createThread(channel: string, name: string, opts: Options?): Options
	local body = options(opts, THREAD)
	body.name = text(name, "name", 100)
	snowflake(channel, "channel ID")
	local start = body.message
	body.message = nil
	local parent = inGuild("createThread", channel)
	if start then
		return call("createThread", "POST", "channels/" .. channel .. "/messages/" .. start .. "/threads", nil, body)
	end
	assert(parent.type == 0 or parent.type == 5, "discord: threads without a starting message need a text or announcement channel")
	body.type = if parent.type == 5 then 10 else 11
	return call("createThread", "POST", "channels/" .. channel .. "/threads", nil, body)
end

local exports: {[string]: any} = {
	getServer = getServer, listChannels = listChannels, getChannel = getChannel, listMessages = listMessages,
	getMessage = getMessage, listThreads = listThreads, listArchivedThreads = listArchivedThreads,
	searchMessages = searchMessages, searchMembers = searchMembers, getMember = getMember, listRoles = listRoles,
}
if config.access == "read-write" then
	exports.postMessage = postMessage
	exports.reply = reply
	exports.editMessage = editMessage
	exports.deleteMessage = deleteMessage
	exports.addReaction = function(channel: string, message: string, value: string): boolean
		return reaction("addReaction", "PUT", channel, message, value)
	end
	exports.removeReaction = function(channel: string, message: string, value: string): boolean
		return reaction("removeReaction", "DELETE", channel, message, value)
	end
	exports.createThread = createThread
end

local operationHelp: {[string]: string} = {
	getServer = [[getServer(opts?) -> guild
The connected server: id, name, description, owner_id, roles, emojis, features... opts: with_counts (true adds approximate_member_count and approximate_presence_count).]],
	listChannels = [[listChannels() -> {channel}
The server's channels and categories (not threads): id, type (0 text, 2 voice, 4 category, 5 announcement, 15 forum), name, parent_id, position, topic. Channels Houston's bot cannot view may be missing.]],
	getChannel = [[getChannel(channel) -> channel
One channel or thread of this server.]],
	listMessages = [[listMessages(channel, opts?) -> {message}
Newest first. opts: limit (1-100, default 25) and at most one of before, after or around (message IDs). For older messages pass before = the last message's id. Returns [] when the bot lacks Read Message History in that channel.]],
	getMessage = [[getMessage(channel, message) -> message
One message: id, channel_id, author, content, timestamp, edited_timestamp, attachments, embeds, mentions, reactions, message_reference, referenced_message, thread...]],
	listThreads = [[listThreads() -> {threads, members}
Active threads in the whole server, newest first; members lists the threads the bot has joined.]],
	listArchivedThreads = [[listArchivedThreads(channel, opts?) -> {threads, members, has_more}
Public archived threads of a text or announcement channel, most recently archived first. opts: limit (2-100, default 25), before (ISO 8601 timestamp; pass the last thread's thread_metadata.archive_timestamp for the next page).]],
	searchMessages = [[searchMessages(query, opts?) -> {total_results, messages, threads?, members?}
Searches the whole server; query is the text to match, or "" to search by filters only. Each item of messages is a one-element array holding the matching message. opts (Discord's names): channel_id, author_id, mentions (ID or array of IDs), author_type ("user", "bot", "webhook", "-bot"...), has ("link", "file", "image", "embed", "-link"...), min_id, max_id, pinned, include_nsfw, sort_by ("timestamp" default or "relevance"), sort_order ("desc" default or "asc"), limit (1-25, default 25), offset (0-9975). Discord can return fewer than limit even when more match, so get the next page with offset = offset + limit; total_results is approximate. While Discord indexes a server for the first time this fails as retryable with the wait.]],
	searchMembers = [[searchMembers(query, opts?) -> {member}
Members whose username or nickname starts with query (1-100 characters). opts: limit (1-1000, default 25). Each member: user {id, username, global_name, bot?}, nick, roles (role IDs), joined_at.]],
	getMember = [[getMember(user) -> member
One member of this server by user ID.]],
	listRoles = [[listRoles() -> {role}
The server's roles: id, name, color, position, permissions, mentionable. The @everyone role's id is the server id.]],
	postMessage = [[postMessage(channel, content, opts?) -> message
Posts as Houston's bot in a channel or thread; content is 1-2000 characters of Discord markdown. Mention people as <@userId> and roles as <@&roleId>; mentions notify nobody unless opts.allowed_mentions names them: {users = {userId}, roles = {roleId}, replied_user = true}. opts: embeds (up to 10 embed objects), allowed_mentions, flags (4 suppresses link previews, 4096 sends silently), nonce plus enforce_nonce = true (Discord then ignores a repeat with the same nonce for a few minutes). After an error the message may already be posted: check listMessages, or resend with the same nonce and enforce_nonce, rather than retrying blindly.]],
	reply = [[reply(channel, message, content, opts?) -> message
Replies to a message in the same channel. Same opts as postMessage; the replied-to author is notified only with allowed_mentions.replied_user = true.]],
	editMessage = [[editMessage(channel, message, content, opts?) -> message
Replaces the content of a message Houston's bot posted. opts: embeds, allowed_mentions, flags (4 suppresses link previews).]],
	deleteMessage = [[deleteMessage(channel, message) -> true
Deletes a message Houston's bot posted; other people's messages cannot be deleted.]],
	addReaction = [[addReaction(channel, message, emoji) -> true
Reacts as Houston's bot. emoji is the Unicode character, such as "👍", or a server emoji as "name:id"; Slack-style names such as "thumbsup" are rejected.]],
	removeReaction = [[removeReaction(channel, message, emoji) -> true
Removes Houston's bot's reaction. Same emoji format as addReaction.]],
	createThread = [[createThread(channel, name, opts?) -> channel
Starts a public thread named name (1-100 characters) and returns it; post into it with postMessage(thread.id, ...). opts: message (start the thread from this message; one thread per message), auto_archive_duration (60, 1440, 4320 or 10080 minutes), rate_limit_per_user (0-21600 seconds). Without message the channel must be a text or announcement channel; forum posts are not supported.]],
}

exports.help = function(): string
	local names: {string} = {}
	for name in exports do
		if name ~= "help" then table.insert(names, name) end
	end
	table.sort(names)
	local sections = {[[Discord: Houston's bot in one Discord server, the one this connection added it to. Credentials stay on Houston. Calls return completed values; do not wrap them in await(). Pass every ID (server, channel, thread, message, user, role) as a string, never a number. Results keep Discord's field names. Unknown options are rejected.
Scope: guild routes always address the connected server, and channel, thread and message calls first check that the channel belongs to it; any other channel, including DMs, fails with "is not in this server". Threads are channels: pass a thread's id wherever a channel is expected. The bot sees only channels its role can view. Without Discord's Message Content access, messages from other people can have empty content, embeds and attachments (the bot's own messages and messages mentioning it stay complete).
Each call returns one page and never paginates on its own. Discord rate-limits the bot across every Houston server, so prefer searchMessages over scanning channels page by page, keep limits small, and do not loop over many channels. Rate-limited calls fail as retryable with the wait; permission errors (403) never succeed on retry. Writes act as Houston's bot, need Read and write access and never retry automatically.]]}
	for _, name in names do
		local section = operationHelp[name]
		assert(section, "missing help for configured function " .. name)
		table.insert(sections, "## " .. section)
	end
	return table.concat(sections, "\n\n")
end

return exports
