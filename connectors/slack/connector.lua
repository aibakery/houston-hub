local function encode(value: any)
    return (string.gsub(tostring(value), "[^A-Za-z0-9%-_%.~]", function(c: any)
        return string.format("%%%02X", string.byte(c))
    end))
end

local function query_string(params: any)
    local parts = {}
    local function add(key: any, value: any)
        if value == nil then return end
        if type(value) == "table" then for _, item in value do add(key, item) end
        else parts[#parts + 1] = encode(key) .. "=" .. encode(value) end
    end
    for key, value in params or {} do add(key, value) end
    table.sort(parts)
    return table.concat(parts, "&")
end

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
		local query = query_string(params)
		if query ~= "" then url ..= "?" .. query end
	end
	local response = http.request({
		method = if write then "POST" else "GET",
		url = url,
		body = body,
		headers = headers,
	})
	if response.status < 200 or response.status >= 300 then
		houston.fail({operation = method, layer = "upstream", upstream_status = response.status,
			retryable = response.status == 429 or response.status == 502 or response.status == 503 or response.status == 504,
			message = "upstream HTTP request failed"})
	end
	local result = nil
	if response.body ~= nil and response.body ~= "" then
		local ok, body = pcall(json.decode, response.body)
		assert(ok, "upstream returned invalid JSON")
		result = body
	end
	-- Slack reports most failures as HTTP 200 with ok=false.
	if type(result) ~= "table" or result.ok ~= true then
		local code = if type(result) == "table" then result.error else "invalid_response"
		houston.fail({
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
	local response = http.request({
		method = "GET",
		dest = path,
		url = required(file.url_private_download or file.url_private, "file download URL"),
	})
	if response.status < 200 or response.status >= 300 then
		houston.fail({operation = "downloadFile", layer = "upstream", upstream_status = response.status,
			retryable = response.status == 429 or response.status == 502 or response.status == 503 or response.status == 504,
			message = "upstream HTTP request failed"})
	end
	return { path = path, url = fs.signedGetUrl(path), bytes = response.bytes }
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
	local response = http.request({
		method = "POST",
		src = path,
		url = required(upload.upload_url, "upload URL"),
		headers = { ["Content-Type"] = "application/octet-stream" },
	})
	if response.status < 200 or response.status >= 300 then
		houston.fail({operation = "uploadFile", layer = "upstream", upstream_status = response.status,
			retryable = response.status == 429 or response.status == 502 or response.status == 503 or response.status == 504,
			message = "upstream HTTP request failed"})
	end
	return request("files.completeUploadExternal", {
		files = { { id = upload.file_id, title = params.title or name } },
		channel_id = params.channel, thread_ts = params.thread_ts, initial_comment = params.text,
	}, true)
end

if config.access == "read-write" then
    for name, fn in (writes :: {[string]: any}) do (functions :: {[string]: any})[name] = fn end
end

local operationHelp: {[string]: string} = {
	addReaction = [==[- addReaction/removeReaction(channel, ts, name): emoji name without colons.]==],
	deleteMessage = [==[- updateMessage(channel, ts, text, opts?), deleteMessage(channel, ts): your messages.]==],
	downloadFile = [==[- downloadFile(id, path): stream a file into a session path; returns
  {path, url, bytes} with a Houston signed GET URL. Never inline attachment bytes.]==],
	getChannel = [==[- getChannel(channel): channel details.]==],
	getFile = [==[- getFile(id): attachment metadata. Message files arrays contain these IDs.]==],
	getPermalink = [==[- getUser(user): profile. getPermalink(channel, ts): message link.]==],
	getProfile = [==[- getProfile(): authenticated user_id, team_id, team, and user.]==],
	getThread = [==[- getThread(channel, ts, opts?): parent and replies, has_more, nextCursor; same
  options as listMessages. One page per call, default 15. Loop with cursor =
  result.nextCursor in the same run until absent. History can also use latest
  set to the last message ts if has_more is true without a cursor.]==],
	getUser = [==[- getUser(user): profile. getPermalink(channel, ts): message link.]==],
	listChannels = [==[- listChannels(opts?): your channels and DMs via users.conversations. Options:
  types (comma-separated public_channel,private_channel,im,mpim), exclude_archived,
  limit, cursor. Returns channels and nextCursor.]==],
	listMembers = [==[- listMembers(channel, opts?), listUsers(opts?): cursor pagination.]==],
	listMentions = [==[- listMentions(opts?): search results for mentions of your authenticated Slack
  user, including replies. Same search options plus query to narrow the search.]==],
	listMessages = [==[- listMessages(channel, opts?): messages, has_more, nextCursor. Options: limit,
  cursor, oldest, latest, inclusive. Default limit 15.]==],
	listUsers = [==[- listMembers(channel, opts?), listUsers(opts?): cursor pagination.]==],
	openConversation = [==[- openConversation(users): user ID, comma-separated IDs, or an array of IDs;
  returns a DM/group channel to pass to postMessage.]==],
	postMessage = [==[- postMessage(channel, text, opts?): send as yourself. Options include thread_ts,
  blocks, attachments (Slack message attachment objects), unfurl_links,
  unfurl_media, reply_broadcast, and client_msg_id. Returns ts and message.]==],
	removeReaction = [==[- addReaction/removeReaction(channel, ts, name): emoji name without colons.]==],
	reply = [==[- reply(channel, ts, text, opts?): send into a thread.]==],
	searchMessages = [==[- searchMessages(query, opts?): matches, total, paging, nextPage. Slack search
  syntax: in:general, from:me, after:2026-01-01. Options: count, page, sort,
  sort_dir. Loop with page = result.nextPage until absent.]==],
	updateMessage = [==[- updateMessage(channel, ts, text, opts?), deleteMessage(channel, ts): your messages.]==],
	uploadFile = [==[- uploadFile(path, opts?): stream a session file with Slack's external upload
  flow. Options: filename, title, alt_text, channel, thread_ts, text (initial
  comment). Set channel to share the file; omit to keep it private in Slack.
  Use fs.signedPutUrl to receive large files first. Returns files metadata.]==],
}

function functions.help(): string
	local names: {string} = {}
	for name in (functions :: {[string]: any}) do
		if name ~= "help" then names[#names + 1] = name end
	end
	table.sort(names)
	local sections = {"slack: configured connection help. Credentials stay on Houston. Use only the functions listed below. Provider scopes are enforced by real calls; help makes no network requests."}
	for _, name in names do
		local text = operationHelp[name]
		assert(text, "missing help for configured function " .. name)
		sections[#sections + 1] = text
	end
	return table.concat(sections, "\n\n")
end

return functions
