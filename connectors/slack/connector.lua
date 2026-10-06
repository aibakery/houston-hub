local connector_http = require("lib/http.lua")
-- One connected Slack user in one workspace. Houston owns the credentials.
local BASE = "https://slack.com/api/"

local function required(value: any,label: any)
	if type(value) ~= "string" or value == "" then
		error("slack: " .. label .. " must be a non-empty string")
	end
	return value
end

local function options(opts: any): {[string]: any}
	if opts == nil then return {} end
	if type(opts) ~= "table" then error("slack: options must be a table") end
	return table.clone(opts)
end

local function request(method: any,params: any,write: any)
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
		connector = "slack", operation = method,
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

local function channel_params(channel: any,opts: any)
	local params = options(opts)
	params.channel = required(channel, "channel ID")
	return params
end

local functions = {}
local writes = {}

function functions.getProfile()
	return request("auth.test")
end

function functions.listChannels(opts: any)
	local params = options(opts)
	-- users.conversations without user uses the authenticated user, and includes DMs.
	params.user = nil
	params.types = params.types or "public_channel,private_channel,im,mpim"
	params.exclude_archived = if params.exclude_archived == nil then true else params.exclude_archived
	return request("users.conversations", params)
end

function functions.getChannel(channel: any)
	return request("conversations.info", channel_params(channel)).channel
end

function functions.listMessages(channel: any,opts: any)
	local params = channel_params(channel, opts)
	params.limit = params.limit or 15
	return request("conversations.history", params)
end

function functions.getThread(channel: any,ts: any,opts: any)
	local params = channel_params(channel, opts)
	params.ts = required(ts, "thread timestamp")
	params.limit = params.limit or 15
	return request("conversations.replies", params)
end

function functions.searchMessages(query: any,opts: any)
	local params = options(opts)
	params.query = required(query, "search query")
	params.sort = params.sort or "timestamp"
	params.sort_dir = params.sort_dir or "desc"
	local result = request("search.messages", params).messages
	if type(result) ~= "table" then error("slack: missing search results") end
	local paging = result.paging
	if paging and paging.page < paging.pages then result.nextPage = paging.page + 1 end
	return result
end

function functions.listMentions(opts: any)
	local params = options(opts)
	local user = functions.getProfile().user_id
	local query = "<@" .. required(user, "authenticated user ID") .. ">"
	if params.query and params.query ~= "" then query ..= " " .. params.query end
	params.query = nil
	return functions.searchMessages(query, params)
end

function functions.listMembers(channel: any,opts: any)
	return request("conversations.members", channel_params(channel, opts))
end

function functions.getUser(user: any)
	return request("users.info", { user = required(user, "user ID") }).user
end

function functions.listUsers(opts: any)
	return request("users.list", options(opts))
end

function functions.getPermalink(channel: any,ts: any)
	return request("chat.getPermalink", { channel = required(channel, "channel ID"), message_ts = required(ts, "message timestamp") }).permalink
end

function functions.getFile(id: any)
	return request("files.info", { file = required(id, "file ID") }).file
end

function functions.downloadFile(id: any,path: any)
	local file = functions.getFile(id)
	required(path, "session path")
	local saved = connector_http.send({
		connector = "slack", operation = "downloadFile",
		method = "GET", path = path, dest = path,
		url = required(file.url_private_download or file.url_private, "file download URL"),
	})
	return { path = path, url = fs.signedGetUrl(path), bytes = saved.bytes }
end

function writes.postMessage(channel: any,text: any,opts: any)
	local params = channel_params(channel, opts)
	params.text = required(text, "message text")
	-- The user token determines authorship. Do not accept an alternate identity.
	params.username, params.icon_url, params.icon_emoji = nil, nil, nil
	return request("chat.postMessage", params, true)
end

function writes.reply(channel: any,ts: any,text: any,opts: any)
	local params = options(opts)
	params.thread_ts = required(ts, "thread timestamp")
	return writes.postMessage(channel, text, params)
end

function writes.updateMessage(channel: any,ts: any,text: any,opts: any)
	local params = channel_params(channel, opts)
	params.ts, params.text = required(ts, "message timestamp"), required(text, "message text")
	return request("chat.update", params, true)
end

function writes.deleteMessage(channel: any,ts: any)
	return request("chat.delete", { channel = required(channel, "channel ID"), ts = required(ts, "message timestamp") }, true)
end

function writes.openConversation(users: any)
	if type(users) == "table" then users = table.concat(users, ",") end
	return request("conversations.open", { users = required(users, "user IDs") }, true).channel
end

function writes.addReaction(channel: any,ts: any,name: any)
	return request("reactions.add", { channel = required(channel, "channel ID"), timestamp = required(ts, "message timestamp"), name = required(name, "emoji name") }, true)
end

function writes.removeReaction(channel: any,ts: any,name: any)
	return request("reactions.remove", { channel = required(channel, "channel ID"), timestamp = required(ts, "message timestamp"), name = required(name, "emoji name") }, true)
end

function writes.uploadFile(path: any,opts: any)
	required(path, "session path")
	local params = options(opts)
	local stat = fs.stat(path)
	if not stat.isFile then error("slack: upload path must be a file") end
	local name = params.filename or string.match(path, "([^/]+)$")
	local upload = request("files.getUploadURLExternal", { filename = required(name, "filename"), length = stat.size, alt_txt = params.alt_text })
	connector_http.send({
		connector = "slack", operation = "uploadFile",
		method = "POST", path = path, src = path, raw = true,
		url = required(upload.upload_url, "upload URL"), headers = { ["Content-Type"] = "application/octet-stream" },
	})
	return request("files.completeUploadExternal", {
		files = { { id = upload.file_id, title = params.title or name } },
		channel_id = params.channel, thread_ts = params.thread_ts, initial_comment = params.text,
	}, true)
end

if config.access == "read-write" then
    for name, fn in (writes :: {[string]: any}) do (functions :: {[string]: any})[name] = fn end
end

return functions
