-- One connected Slack user in one workspace. Houston owns the credentials.
local BASE = "https://slack.com/api/"

local function required(value, label)
	if type(value) ~= "string" or value == "" then
		error("slack: " .. label .. " must be a non-empty string")
	end
	return value
end

local function options(opts)
	if opts == nil then return {} end
	if type(opts) ~= "table" then error("slack: options must be a table") end
	return table.clone(opts)
end

local function request(ctx, method, params, write)
	params = params or {}
	local url = BASE .. method
	local body, headers
	if write then
		body = json.encode(params)
		headers = { ["Content-Type"] = "application/json; charset=utf-8" }
	else
		local query = connector_http.query_string(params)
		if query ~= "" then url ..= "?" .. query end
	end
	local result = connector_http.send({
		connector = "slack", connector_id = ctx.id, operation = method,
		method = if write then "POST" else "GET", path = method,
		url = url, body = body, headers = headers, affected_cursor = params.cursor,
	})
	-- Slack reports most failures as HTTP 200 with ok=false.
	if type(result) ~= "table" or result.ok ~= true then
		local code = if type(result) == "table" then result.error else "invalid_response"
		connector_http.fail({
			connector = "slack", operation = method, layer = "upstream",
			message = "slack: " .. tostring(code),
			retryable = code == "ratelimited", recovery = if code == "ratelimited" then "retry later" else "do not retry",
		})
	end
	if result.response_metadata then
		local cursor = result.response_metadata.next_cursor
		if cursor and cursor ~= "" then result.nextCursor = cursor end
	end
	return result
end

local function channel_params(channel, opts)
	local params = options(opts)
	params.channel = required(channel, "channel ID")
	return params
end

local functions = {}
local writes = {}

function functions.getProfile(ctx)
	return request(ctx, "auth.test")
end

function functions.listChannels(ctx, opts)
	local params = options(opts)
	-- users.conversations without user uses the authenticated user, and includes DMs.
	params.user = nil
	params.types = params.types or "public_channel,private_channel,im,mpim"
	params.exclude_archived = if params.exclude_archived == nil then true else params.exclude_archived
	return request(ctx, "users.conversations", params)
end

function functions.getChannel(ctx, channel)
	return request(ctx, "conversations.info", channel_params(channel)).channel
end

function functions.listMessages(ctx, channel, opts)
	local params = channel_params(channel, opts)
	params.limit = params.limit or 15
	return request(ctx, "conversations.history", params)
end

function functions.getThread(ctx, channel, ts, opts)
	local params = channel_params(channel, opts)
	params.ts = required(ts, "thread timestamp")
	params.limit = params.limit or 15
	return request(ctx, "conversations.replies", params)
end

function functions.searchMessages(ctx, query, opts)
	local params = options(opts)
	params.query = required(query, "search query")
	params.sort = params.sort or "timestamp"
	params.sort_dir = params.sort_dir or "desc"
	local result = request(ctx, "search.messages", params).messages
	if type(result) ~= "table" then error("slack: missing search results") end
	local paging = result.paging
	if paging and paging.page < paging.pages then result.nextPage = paging.page + 1 end
	return result
end

function functions.listMentions(ctx, opts)
	local params = options(opts)
	local user = functions.getProfile(ctx).user_id
	local query = "<@" .. required(user, "authenticated user ID") .. ">"
	if params.query and params.query ~= "" then query ..= " " .. params.query end
	params.query = nil
	return functions.searchMessages(ctx, query, params)
end

function functions.listMembers(ctx, channel, opts)
	return request(ctx, "conversations.members", channel_params(channel, opts))
end

function functions.getUser(ctx, user)
	return request(ctx, "users.info", { user = required(user, "user ID") }).user
end

function functions.listUsers(ctx, opts)
	return request(ctx, "users.list", options(opts))
end

function functions.getPermalink(ctx, channel, ts)
	return request(ctx, "chat.getPermalink", { channel = required(channel, "channel ID"), message_ts = required(ts, "message timestamp") }).permalink
end

function functions.getFile(ctx, id)
	return request(ctx, "files.info", { file = required(id, "file ID") }).file
end

function functions.downloadFile(ctx, id, path)
	local file = functions.getFile(ctx, id)
	required(path, "session path")
	local saved = connector_http.send({
		connector = "slack", connector_id = ctx.id, operation = "downloadFile",
		method = "GET", path = path, dest = path,
		url = required(file.url_private_download or file.url_private, "file download URL"),
	})
	return { path = path, url = fs.signedGetUrl(path), bytes = saved.bytes }
end

function writes.postMessage(ctx, channel, text, opts)
	local params = channel_params(channel, opts)
	params.text = required(text, "message text")
	-- The user token determines authorship. Do not accept an alternate identity.
	params.username, params.icon_url, params.icon_emoji = nil, nil, nil
	return request(ctx, "chat.postMessage", params, true)
end

function writes.reply(ctx, channel, ts, text, opts)
	local params = options(opts)
	params.thread_ts = required(ts, "thread timestamp")
	return writes.postMessage(ctx, channel, text, params)
end

function writes.updateMessage(ctx, channel, ts, text, opts)
	local params = channel_params(channel, opts)
	params.ts, params.text = required(ts, "message timestamp"), required(text, "message text")
	return request(ctx, "chat.update", params, true)
end

function writes.deleteMessage(ctx, channel, ts)
	return request(ctx, "chat.delete", { channel = required(channel, "channel ID"), ts = required(ts, "message timestamp") }, true)
end

function writes.openConversation(ctx, users)
	if type(users) == "table" then users = table.concat(users, ",") end
	return request(ctx, "conversations.open", { users = required(users, "user IDs") }, true).channel
end

function writes.addReaction(ctx, channel, ts, name)
	return request(ctx, "reactions.add", { channel = required(channel, "channel ID"), timestamp = required(ts, "message timestamp"), name = required(name, "emoji name") }, true)
end

function writes.removeReaction(ctx, channel, ts, name)
	return request(ctx, "reactions.remove", { channel = required(channel, "channel ID"), timestamp = required(ts, "message timestamp"), name = required(name, "emoji name") }, true)
end

function writes.uploadFile(ctx, path, opts)
	required(path, "session path")
	local params = options(opts)
	local stat = fs.stat(path)
	if not stat.isFile then error("slack: upload path must be a file") end
	local name = params.filename or string.match(path, "([^/]+)$")
	local upload = request(ctx, "files.getUploadURLExternal", { filename = required(name, "filename"), length = stat.size, alt_txt = params.alt_text })
	connector_http.send({
		connector = "slack", connector_id = ctx.id, operation = "uploadFile",
		method = "POST", path = path, src = path, raw = true,
		url = required(upload.upload_url, "upload URL"), headers = { ["Content-Type"] = "application/octet-stream" },
	})
	return request(ctx, "files.completeUploadExternal", {
		files = { { id = upload.file_id, title = params.title or name } },
		channel_id = params.channel, thread_ts = params.thread_ts, initial_comment = params.text,
	}, true)
end

return {
	name = "slack",
	description = "Your Slack account in one workspace: channels, threads, mentions, messages, and files.",
	functions = functions,
	writes = writes,
	signatures = {
		getProfile = "getProfile()", listChannels = "listChannels(opts?)", getChannel = "getChannel(channel)",
		listMessages = "listMessages(channel, opts?)", getThread = "getThread(channel, ts, opts?)",
		searchMessages = "searchMessages(query, opts?)", listMentions = "listMentions(opts?)",
		listMembers = "listMembers(channel, opts?)", getUser = "getUser(user)", listUsers = "listUsers(opts?)",
		getPermalink = "getPermalink(channel, ts)", getFile = "getFile(id)", downloadFile = "downloadFile(id, path)",
		postMessage = "postMessage(channel, text, opts?)", reply = "reply(channel, ts, text, opts?)",
		updateMessage = "updateMessage(channel, ts, text, opts?)", deleteMessage = "deleteMessage(channel, ts)",
		openConversation = "openConversation(users)", addReaction = "addReaction(channel, ts, name)", removeReaction = "removeReaction(channel, ts, name)",
		uploadFile = "uploadFile(path, opts?)",
	},
	help = [=[# Slack

Each instance is one user account in one authorized Slack workspace. Personal
connections are private to their owner. Shared connections are available to the
organization admins and granted members. Add a separate connection for each Slack
workspace. Tokens stay on Houston; posts are authored by the connected Slack user.
Use dot calls, channel IDs, user IDs, and timestamps as strings (never numbers).

Read functions:
- getProfile(): authenticated user_id, team_id, team, and user.
- listChannels(opts?): your channels and DMs via users.conversations. Options:
  types (comma-separated public_channel,private_channel,im,mpim), exclude_archived,
  limit, cursor. Returns channels and nextCursor.
- getChannel(channel): channel details.
- listMessages(channel, opts?): messages, has_more, nextCursor. Options: limit,
  cursor, oldest, latest, inclusive. Default limit 15.
- getThread(channel, ts, opts?): parent and replies, has_more, nextCursor; same
  options as listMessages. One page per call, default 15. Loop with cursor =
  result.nextCursor in the same run until absent. History can also use latest
  set to the last message ts if has_more is true without a cursor.
- searchMessages(query, opts?): matches, total, paging, nextPage. Slack search
  syntax: in:general, from:me, after:2026-01-01. Options: count, page, sort,
  sort_dir. Loop with page = result.nextPage until absent.
- listMentions(opts?): search results for mentions of your authenticated Slack
  user, including replies. Same search options plus query to narrow the search.
- listMembers(channel, opts?), listUsers(opts?): cursor pagination.
- getUser(user): profile. getPermalink(channel, ts): message link.
- getFile(id): attachment metadata. Message files arrays contain these IDs.
- downloadFile(id, path): stream a file into a session path; returns
  {path, url, bytes} with a Houston signed GET URL. Never inline attachment bytes.

Write functions (only present on read-write connections):
- postMessage(channel, text, opts?): send as yourself. Options include thread_ts,
  blocks, attachments (Slack message attachment objects), unfurl_links,
  unfurl_media, reply_broadcast, and client_msg_id. Returns ts and message.
- reply(channel, ts, text, opts?): send into a thread.
- updateMessage(channel, ts, text, opts?), deleteMessage(channel, ts): your messages.
- openConversation(users): user ID, comma-separated IDs, or an array of IDs;
  returns a DM/group channel to pass to postMessage.
- addReaction/removeReaction(channel, ts, name): emoji name without colons.
- uploadFile(path, opts?): stream a session file with Slack's external upload
  flow. Options: filename, title, alt_text, channel, thread_ts, text (initial
  comment). Set channel to share the file; omit to keep it private in Slack.
  Use fs.signedPutUrl to receive large files first. Returns files metadata.

Slack enforces the granted scopes and your workspace's permissions. Errors such
as missing_scope or not_in_channel propagate; HTTP 200 with ok=false is a failure.
Rate limits vary by app distribution, especially history/replies. A 429 means
retry later; no automatic retries or duplicate posts. A timeout during posting
can be ambiguous: check the channel before sending again. Search follows Slack's
own indexing and filters; it is not an unread-notifications API.

Example:
return { run = function()
    local slack
    for _, c in houston.connectors() do
        if c.type == "slack" then slack = c; break end
    end
    assert(slack, "Connect Slack first")
    return slack.listMentions({ count = 10 })
end }
]=],
}
