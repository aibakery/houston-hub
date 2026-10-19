-- Meta Graph API v26.0 for one Facebook Page and its linked Instagram account. Arguments and
-- results keep Meta's native field names.
type Options = {[string]: any}
type Endpoint = {method: string, path: string, host: string?, query: {string}?, required: {string}?, paging: {string}?,
	body: {string}?, fields: string?, upload: boolean?, write: boolean?, about: string}

-- Graph versions work for two years after their successor ships; v26.0 has no sunset date yet.
local VERSION = "v26.0"
local API = "https://graph.facebook.com/" .. VERSION
local VIDEO_API = "https://graph-video.facebook.com/" .. VERSION
local LINK = "^" .. (string.gsub(API, "%p", "%%%0")) .. "(/[^?#]*)%?([^#]*)$"
local ID = "^[%w_][%w_.:$=+-]*$"
local CURSORS = {"limit", "after", "before"}
local NONE: {string} = table.freeze({})
local NULL = json.decode("null")

local POST_FIELDS = "id,message,story,created_time,permalink_url,status_type,full_picture,is_published,from,comments.summary(true).limit(0),reactions.summary(true).limit(0)"
local VIDEO_FIELDS = "id,title,description,created_time,length,permalink_url,published"
local IG_MEDIA_FIELDS = "id,caption,media_type,media_product_type,media_url,thumbnail_url,permalink,timestamp,like_count,comments_count"
local IG_COMMENT_FIELDS = "id,text,timestamp,username,like_count,hidden"
local HASHTAG_MEDIA_FIELDS = "id,caption,media_type,permalink,timestamp,like_count,comments_count"

-- Edges and parameters of Meta's reference and Business SDK v26.0.2, checked on 2026-10-19.
-- Page functions act on /me, the Page the token belongs to. Path {fields} are IDs; listed query
-- fields are taken from the options, and the other options form the body of writes. paging lists
-- the cursor options; any paging list, even an empty one, also accepts next. body limits the
-- writes to one object (a post, comment or media) to its own fields, so they cannot change the Page.
local endpoints: {[string]: Endpoint} = {
	getPage = {method = "GET", path = "/me",
		fields = "id,name,username,link,category,about,description,website,phone,emails,followers_count,fan_count,verification_status",
		about = "The connected Page. With Instagram permissions, fields='id,name,instagram_business_account{id,username}' adds the linked account, whose id is the ig_user of Instagram functions."},
	getObject = {method = "GET", path = "/{id}",
		about = "Any object the Page can see: a post, comment, photo, video, conversation, message, Instagram account, media, comment or container. Without fields Meta returns only a few defaults."},

	listFeed = {method = "GET", path = "/me/feed", query = {"since", "until", "include_hidden", "show_expired"}, paging = CURSORS, fields = POST_FIELDS,
		about = "Posts on the Page by the Page and by others, newest first, without reels. limit is at most 100; Meta returns about 600 ranked posts per year."},
	listPublishedPosts = {method = "GET", path = "/me/published_posts", query = {"since", "until", "include_hidden"}, paging = CURSORS, fields = POST_FIELDS,
		about = "Posts the Page published."},
	listScheduledPosts = {method = "GET", path = "/me/scheduled_posts", query = {"since", "until"}, paging = CURSORS, fields = "id,message,created_time,scheduled_publish_time,permalink_url",
		about = "Posts waiting for their scheduled_publish_time."},
	listTaggedPosts = {method = "GET", path = "/me/tagged", query = {"since", "until"}, paging = CURSORS, fields = "id,message,created_time,permalink_url,from",
		about = "Posts by others that tag the Page."},
	listPhotos = {method = "GET", path = "/me/photos", query = {"type"}, paging = CURSORS, fields = "id,name,created_time,link,picture,alt_text",
		about = "type='uploaded' lists the Page's own photos, type='tagged' photos it is tagged in; the default lists its profile pictures."},
	listVideos = {method = "GET", path = "/me/videos", paging = CURSORS, fields = VIDEO_FIELDS, about = "The Page's videos."},
	listReels = {method = "GET", path = "/me/video_reels", query = {"since", "until"}, paging = CURSORS, fields = VIDEO_FIELDS, about = "The Page's reels."},
	listRatings = {method = "GET", path = "/me/ratings", paging = CURSORS, fields = "created_time,recommendation_type,review_text,has_review,reviewer",
		about = "Recommendations and reviews of the Page; recommendation_type is positive or negative."},
	listComments = {method = "GET", path = "/{object}/comments", query = {"filter", "order", "summary", "since"}, paging = CURSORS,
		fields = "id,message,created_time,from,like_count,comment_count,is_hidden,can_hide,can_remove,permalink_url",
		about = "Comments on a Facebook post, photo, video or comment (replies). filter: toplevel (default) or stream for all; order: chronological or reverse_chronological; summary=true adds summary.total_count."},
	listReactions = {method = "GET", path = "/{object}/reactions", query = {"type", "summary"}, paging = CURSORS,
		about = "Reactions to a post or comment. type: LIKE, LOVE, WOW, HAHA, SORRY, ANGRY or CARE; summary='total_count' adds summary.total_count. Meta names only the Page among reacting profiles."},
	getInsights = {method = "GET", path = "/{object}/insights",
		query = {"metric", "period", "since", "until", "date_preset", "breakdown", "metric_type", "timeframe"}, required = {"metric"}, paging = NONE,
		about = "Metrics of the Page ('me'), a post, the Instagram account or Instagram media; see Insights above. metric and breakdown take an array or a comma-separated string."},
	listConversations = {method = "GET", path = "/me/conversations", query = {"platform", "user_id", "folder"}, paging = CURSORS,
		fields = "id,updated_time,participants",
		about = "Inbox threads, latest first. platform: messenger or instagram; user_id finds the thread with one person (PSID or IGSID). Messenger threads also have snippet, unread_count, message_count, can_reply and link."},
	listMessages = {method = "GET", path = "/{conversation}/messages", paging = CURSORS, fields = "id,created_time,from,to,message,attachments",
		about = "Messages of a conversation, newest first. Only the 20 most recent have details."},

	getInstagramAccount = {method = "GET", path = "/{ig_user}",
		fields = "id,username,name,biography,website,followers_count,follows_count,media_count,profile_picture_url",
		about = "The linked Instagram professional account. fields='business_discovery.username(name){followers_count,media_count,media{caption,like_count}}' reads another business or creator account."},
	listInstagramMedia = {method = "GET", path = "/{ig_user}/media", query = {"since", "until"}, paging = CURSORS, fields = IG_MEDIA_FIELDS,
		about = "Posts and reels, newest first, at most the latest 10,000. media_product_type is FEED, REELS or AD."},
	listInstagramStories = {method = "GET", path = "/{ig_user}/stories", paging = CURSORS, fields = IG_MEDIA_FIELDS, about = "Stories of the last 24 hours."},
	listInstagramTags = {method = "GET", path = "/{ig_user}/tags", paging = CURSORS, fields = "id,caption,media_type,media_url,permalink,timestamp,username",
		about = "Media by others that tag the account."},
	listInstagramChildren = {method = "GET", path = "/{media}/children", fields = "id,media_type,media_url,thumbnail_url,timestamp",
		about = "The images and videos of a carousel."},
	listInstagramComments = {method = "GET", path = "/{media}/comments", paging = CURSORS, fields = IG_COMMENT_FIELDS .. ",replies{" .. IG_COMMENT_FIELDS .. "}",
		about = "Top-level comments on Instagram media, newest first, with their replies. limit is at most 50."},
	listInstagramReplies = {method = "GET", path = "/{comment}/replies", paging = CURSORS, fields = IG_COMMENT_FIELDS, about = "Replies to an Instagram comment."},
	getInstagramPublishingLimit = {method = "GET", path = "/{ig_user}/content_publishing_limit", query = {"since"}, fields = "config,quota_usage", write = true,
		about = "Posts published through the API in the last 24 hours (quota_usage) and the quota (config.quota_total). Needs instagram_content_publish, so read-write only."},
	searchInstagramHashtag = {method = "GET", path = "/ig_hashtag_search", query = {"user_id", "q"}, required = {"user_id", "q"},
		about = "The ID of a hashtag (q without #); user_id is your ig_user. At most 30 different hashtags per 7 days; needs Meta's Instagram Public Content Access feature."},
	listHashtagTopMedia = {method = "GET", path = "/{hashtag}/top_media", query = {"user_id"}, required = {"user_id"}, paging = {"limit", "after"},
		fields = HASHTAG_MEDIA_FIELDS, about = "Most popular public media with a hashtag. limit is at most 50."},
	listHashtagRecentMedia = {method = "GET", path = "/{hashtag}/recent_media", query = {"user_id"}, required = {"user_id"}, paging = {"limit", "after"},
		fields = HASHTAG_MEDIA_FIELDS, about = "Public media with a hashtag from the last 24 hours. limit is at most 50."},

	createPost = {method = "POST", path = "/me/feed",
		about = "Body {message?, link?, published?, scheduled_publish_time?, attached_media?, place?}. Posts as the Page; returns {id}. Pass message or link."},
	updatePost = {method = "POST", path = "/{post}", body = {"message", "is_hidden", "is_published", "scheduled_publish_time", "is_pinned", "timeline_visibility"},
		about = "Body {message?, is_hidden?, is_published?, scheduled_publish_time?, is_pinned?, timeline_visibility?}. Only posts made through the token's Meta app can change."},
	uploadPhoto = {method = "POST", path = "/me/photos", upload = true,
		about = "Body {url | path, caption?, published?, temporary?, scheduled_publish_time?, no_story?, alt_text_custom?}. JPEG, PNG, GIF, BMP or TIFF up to 10 MB; returns {id, post_id}."},
	uploadVideo = {method = "POST", path = "/me/videos", host = VIDEO_API, upload = true,
		about = "Body {file_url | path, title?, description?, published?, scheduled_publish_time?, no_story?}. Returns {id}; Meta processes the video afterwards."},
	createComment = {method = "POST", path = "/{object}/comments",
		about = "Body {message?, attachment_url?, attachment_id?, attachment_share_url?}. Comments as the Page on a Facebook post, photo, video or comment, or on Instagram media (message only); returns {id}."},
	updateComment = {method = "POST", path = "/{comment}", body = {"message", "is_hidden", "hide", "attachment_url", "attachment_id"},
		about = "Body {is_hidden} or {message} for a Facebook comment, {hide} for an Instagram comment."},
	createInstagramReply = {method = "POST", path = "/{comment}/replies", required = {"message"},
		about = "Body {message}. Replies as the account to a top-level Instagram comment; returns {id}."},
	updateInstagramMedia = {method = "POST", path = "/{media}", required = {"comment_enabled"}, body = {"comment_enabled"},
		about = "Body {comment_enabled}. Turns comments on Instagram media on or off."},
	deleteObject = {method = "DELETE", path = "/{id}",
		about = "Deletes a Facebook post, photo, video or comment, or Instagram media or comment. Instagram media need the instagram_manage_contents permission; carousels are deleted whole."},
	sendMessage = {method = "POST", path = "/me/messages", required = {"recipient"},
		about = "Body {recipient, messaging_type?, message? | sender_action?, tag?, notification_type?, reply_to?}. Sends as the Page on Messenger or Instagram, or privately replies to a Facebook comment; see Inbox above. Returns {recipient_id, message_id}."},
	sendInstagramPrivateReply = {method = "POST", path = "/{ig_user}/messages", required = {"recipient", "message"},
		about = "Body {recipient={comment_id}, message={text}}. Sends the commenter the one private message allowed per Instagram comment, within 7 days of it; at most 750 per hour."},
	createInstagramContainer = {method = "POST", path = "/{ig_user}/media",
		about = "Body {image_url? (JPEG), video_url?, media_type? (REELS, STORIES, CAROUSEL or VIDEO for carousel items), caption?, children?, is_carousel_item?, alt_text?, cover_url?, share_to_feed?, location_id?, user_tags?, collaborators?}. Returns {id}; see Publishing to Instagram above."},
	publishInstagramMedia = {method = "POST", path = "/{ig_user}/media_publish", required = {"creation_id"},
		about = "Body {creation_id}. Publishes a FINISHED container; returns the media {id}."},
}

-- Write bodies never send these: method replaces the HTTP verb, batch runs other requests,
-- callback and suppress_http_code turn errors into HTTP 200, fields reads the written object
-- back (a Page's own access_token included), next belongs to paging, and the rest carry or
-- reveal credentials.
local RESERVED = table.freeze({method = true, batch = true, callback = true, suppress_http_code = true, include_headers = true,
	attached_files = true, fields = true, next = true, access_token = true, appsecret_proof = true, appsecret_time = true, input_token = true, ids = true})
-- Temporary errors (1, 2) and rate limits: app, user, Pages, custom and Business Use Case
-- (80000-80014) throttling.
local RETRYABLE = table.freeze({[1] = true, [2] = true, [4] = true, [17] = true, [32] = true, [341] = true, [613] = true})

local function options(input: Options?): Options
	if input == nil then return {} end
	assert(type(input) == "table", "opts must be an object")
	for key in input do assert(type(key) == "string", "opts must have named fields") end
	return table.clone(input)
end

local function text(value: any, field: string): string
	assert(type(value) == "string" and value ~= "" and not string.find(value, "%c"), field .. " must be a nonempty string without control characters")
	return value
end

-- IDs exceed 2^53, so only strings keep them exact. Meta's IDs (123_456, t_1, m_1, mid.$c1,
-- aWdG...=) use these characters only.
local function segment(value: any, field: string): string
	assert(type(value) == "string", field .. " must be an ID string, such as '123_456'")
	assert(string.match(value, ID), field .. " must be one Meta ID, such as '123_456' or 't_123'")
	return url.segment(value, field)
end

-- A Graph field list with expansions such as comments.limit(5){message}. A Page can read its
-- own access_token field, so no field may name a token.
local function fieldList(value: any): string
	assert(type(value) == "string" and #value <= 4096 and string.match(value, "^[%w_,.(){}: -]+$"),
		"fields must be a Graph field list such as 'id,message,comments.limit(5){message}'")
	assert(not string.find(string.lower(value), "token", 1, true), "fields cannot request access tokens")
	return value
end

local function int(value: any): string?
	return if type(value) == "number" and value % 1 == 0 and math.abs(value) < 2 ^ 53 then string.format("%d", value) else nil
end

local function scalar(value: any, field: string): string
	local kind = type(value)
	assert(kind == "string" or kind == "boolean" or kind == "number", field .. " must be a string, boolean, number or array of those")
	return url.encode(int(value) or value)
end

-- Metric and breakdown lists are comma-separated, encoded like fields so paging links keep them.
local function queryValue(value: any, field: string): string
	if type(value) ~= "table" then return scalar(value, field) end
	local parts: {string} = {}
	for index, item in value do
		assert(type(index) == "number" and index == #parts + 1, field .. " must be an array, not an object")
		table.insert(parts, scalar(item, field))
	end
	assert(#parts > 0, field .. " must not be an empty array")
	return table.concat(parts, "%2C")
end

local function unescape(value: string): string
	local spaced = string.gsub(value, "%+", " ")
	return (string.gsub(spaced, "%%(%x%x)", function(hex: string): string return string.char(tonumber(hex, 16) :: number) end))
end

-- A paging.next link from an earlier result of the same function. It is replayed as is once its
-- route and parameters check out: the function's own options plus Meta's paging tokens and
-- pretty, which v26.0 ignores.
local function nextPage(name: string, endpoint: Endpoint, link: any): string
	local usage = "next must be the unchanged paging.next link of an earlier " .. name .. " result"
	assert(type(link) == "string" and #link <= 8192, usage)
	local path, query = string.match(link, LINK)
	assert(path and query, usage)
	-- Meta writes the Page's ID where the request said me.
	local parts = string.split(string.sub(path, 2), "/")
	local expected = string.split(string.sub(endpoint.path, 2), "/")
	assert(#parts == #expected, usage)
	for index, part in parts do
		local literal = expected[index]
		assert(string.match(part, ID) and (part == literal or literal == "me" or string.match(literal, "^{")), usage)
	end
	local seen: {[string]: boolean} = {}
	for pair in string.gmatch(query, "[^&]+") do
		local key, value = string.match(pair, "^([%w_]+)=([%w%%._~+,-]*)$")
		assert(key and value and not seen[key], usage)
		assert(key == "fields" or key == "pretty" or key == "__paging_token" or key == "__previous" or table.find(endpoint.query or NONE, key)
			or table.find(endpoint.paging or NONE, key), usage)
		if key == "fields" then fieldList(unescape(value)) end
		seen[key] = true
	end
	return API .. path .. "?" .. query
end

-- Meta writes the request's access token into paging links, also URL-encoded inside others.
local TOKEN_CHARS = "[%w_.-]*"
local function scrub(text: string): string
	local plain, found = string.gsub(text, "access_token=" .. TOKEN_CHARS .. "&?", "")
	if found > 0 then plain = string.gsub(plain, "[?&]$", "") end
	return (string.gsub(plain, "access_token%%3[Dd]" .. TOKEN_CHARS, ""))
end

-- Error messages also echo malformed tokens: EAA and at least 30 more token characters.
local ECHOED = "%f[%w]EAA" .. string.rep("[%w_-]", 30) .. "[%w_-]*"
local function scrubError(text: string): string
	return (string.gsub(scrub(text), ECHOED, "EAA[redacted]"))
end

-- Results never carry credentials: Meta's own Graph links lose their token and token fields,
-- such as an expanded accounts edge's access_token, are dropped. Text from people is kept.
local function redact(value: any)
	if type(value) ~= "table" then return end
	for key, child in value do
		if type(key) == "string" and string.find(string.lower(key), "token", 1, true) then
			value[key] = nil
		elseif type(child) == "string" and string.match(child, "^https://graph[%w-]*%.facebook%.com/") then
			value[key] = scrub(child)
		else
			redact(child)
		end
	end
end

-- Business Use Case limits report, per Page or account, the minutes until calls succeed again.
local function regainMinutes(response: HttpResponse): string?
	local usage = response.headers["x-business-use-case-usage"]
	if not usage or not usage[1] or #usage[1] > 16384 then return nil end
	local ok, value = pcall(json.decode, usage[1])
	if not ok or type(value) ~= "table" then return nil end
	local longest = 0
	for _, entries in value do
		if type(entries) == "table" then
			for _, entry in entries do
				local minutes = if type(entry) == "table" then entry.estimated_time_to_regain_access else nil
				if type(minutes) == "number" and minutes > longest then longest = minutes end
			end
		end
	end
	return if longest > 0 then int(math.ceil(longest)) else nil
end

-- Meta errors are {error = {message, type, code, error_subcode?, error_user_msg?, is_transient?, fbtrace_id}}.
-- raw is the body when it was already read.
local function fail(name: string, response: HttpResponse, raw: string?): never
	local status = response.statusCode
	local message = "Meta HTTP " .. tostring(status)
	local retryable = status == 429 or status >= 500
	-- A body that fails to arrive still yields the status and retry hint.
	local ok, value = pcall(function(): any return json.decode(raw or await(response.body:readPrefix(16 * 1024))) end)
	local problem = if ok and type(value) == "table" and type(value.error) == "table" then value.error else nil
	if problem then
		local code, subcode = int(problem.code), int(problem.error_subcode)
		if code then message ..= " (#" .. code .. (if subcode then "/" .. subcode else "") .. ")" end
		if type(problem.message) == "string" then message ..= ": " .. string.sub(scrubError(problem.message), 1, 600) end
		if type(problem.error_user_msg) == "string" then message ..= " " .. string.sub(scrubError(problem.error_user_msg), 1, 600) end
		-- Meta's code decides, so a 500 for an unsupported request is final.
		local number = tonumber(code)
		if number then
			retryable = status == 429 or RETRYABLE[number] == true or (number >= 80000 and number <= 80014)
		end
		if problem.is_transient == true then retryable = true end
		if number == 190 or number == 102 then message ..= "; the Page access token is invalid or expired: create a new one and update the connection" end
		if type(problem.fbtrace_id) == "string" then message ..= " (fbtrace_id " .. string.sub(problem.fbtrace_id, 1, 64) .. ")" end
	end
	local minutes = regainMinutes(response)
	if minutes then message ..= "; Meta expects calls to succeed again in about " .. minutes .. " min" end
	return houston.fail({operation = name, layer = "upstream", upstream_status = status, retryable = retryable, message = message})
end

local function decode(name: string, response: HttpResponse): any
	if response.statusCode < 200 or response.statusCode >= 300 then fail(name, response) end
	local raw = await(response.body:readAll())
	local ok, value = pcall(json.decode, raw)
	if not ok or type(value) ~= "table" or not string.match(raw, "^%s*{") then
		return houston.fail({operation = name, layer = "upstream", upstream_status = response.statusCode, retryable = false,
			message = "Meta returned an invalid JSON object"})
	end
	if type(value.error) == "table" then fail(name, response, raw) end
	-- Every token key or link names a token; most bodies have none to walk for.
	if string.find(raw, "[Tt][Oo][Kk][Ee][Nn]") then redact(value) end
	return value
end

-- Streams a session file with the other options as form fields.
local function multipart(args: Options): (any, string)
	local source = text(args.path, "path")
	args.path = nil
	local names: {string} = {}
	for key in args do table.insert(names, key) end
	table.sort(names)
	local parts: {any} = {}
	for _, key in names do
		local value = args[key]
		assert(value ~= NULL, "a file upload cannot send null as " .. key)
		local body = if type(value) == "table" then json.encode(value) elseif type(value) == "number" then int(value) or tostring(value) else tostring(value)
		table.insert(parts, {name = key, body = body})
	end
	assert(await(fs.stat(source)).isFile, "path must be a session file")
	local file = fs.open(source, "r")
	local ok, body, contentType = pcall(function()
		await(file)
		table.insert(parts, {name = "source", filename = string.match(source, "[^/]+$"), body = file})
		return http.multipart(parts)
	end)
	if not ok then
		pcall(function() await(file:close()) end)
		error(body, 0)
	end
	return body, contentType
end

local function request(name: string, endpoint: Endpoint, input: Options?): any
	local args = options(input)
	if args.next ~= nil and endpoint.paging then
		for key in args do assert(key == "next", "pass next alone, as {next = result.paging.next}") end
		return decode(name, await(http.request({method = "GET", url = nextPage(name, endpoint, args.next)})))
	end
	local path = string.gsub(endpoint.path, "{([%w_]+)}", function(field: string): string
		local value = segment(args[field], field)
		args[field] = nil
		return value
	end)
	for _, field in endpoint.required or NONE do
		assert(args[field] ~= nil and args[field] ~= NULL, field .. " is required")
	end
	local query: {string} = {}
	if endpoint.method == "GET" then
		local fields = if args.fields == nil then endpoint.fields else args.fields
		if fields ~= nil then table.insert(query, "fields=" .. url.encode(fieldList(fields))) end
		args.fields = nil
	end
	for _, group in {endpoint.query or NONE, endpoint.paging or NONE} do
		for _, field in group do
			if args[field] ~= nil then table.insert(query, field .. "=" .. queryValue(args[field], field)) end
			args[field] = nil
		end
	end
	if #query > 0 then path ..= "?" .. table.concat(query, "&") end
	local headers: HttpHeaders = {Accept = {"application/json"}}
	local body: any = nil
	if endpoint.method == "POST" then
		-- Graph's PHP-style parser may trim names, map . and spaces to _ and read name[] as arrays, so only
		-- plain snake_case names are sent.
		for key in args do
			assert(string.match(key, "^%l[%l%d_]*$") and not RESERVED[key] and (endpoint.body == nil or table.find(endpoint.body, key)),
				name .. " cannot send " .. key)
		end
		if endpoint.upload and args.path ~= nil then
			local contentType
			body, contentType = multipart(args)
			headers["Content-Type"] = {contentType}
		else
			headers["Content-Type"] = {"application/json"}
			body = json.encode(args)
		end
		args = {}
	end
	local unknown = next(args)
	assert(unknown == nil, name .. " has no option " .. tostring(unknown))
	return decode(name, await(http.request({method = endpoint.method, url = (endpoint.host or API) .. path, headers = headers, body = body})))
end

local exports: {[string]: any} = {}
for name, endpoint in endpoints do
	local write = if endpoint.write ~= nil then endpoint.write else endpoint.method ~= "GET"
	if not write or config.access == "read-write" then
		exports[name] = function(args: Options?): any return request(name, endpoint, args) end
	end
end

-- name({path fields, query fields?, next?, ...body}) built from the endpoint itself.
local function signature(endpoint: Endpoint): string
	local fields: {string} = {}
	for field in string.gmatch(endpoint.path, "{([%w_]+)}") do table.insert(fields, field) end
	if endpoint.method == "GET" then table.insert(fields, "fields?") end
	for _, group in {endpoint.query or NONE, endpoint.paging or NONE} do
		for _, field in group do
			table.insert(fields, if table.find(endpoint.required or NONE, field) then field else field .. "?")
		end
	end
	if endpoint.paging then table.insert(fields, "next?") end
	if endpoint.method == "POST" then table.insert(fields, "...body") end
	return "({" .. table.concat(fields, ", ") .. "})"
end

exports.help = function(): string
	local lines = {
		"Meta Graph API " .. VERSION .. " for one Facebook Page and the Instagram professional account linked to it. Each function takes one options object with Meta's snake_case names (? marks optional; ...body are the body fields after Body). Results are Meta's JSON unchanged, except that access tokens are removed; writes return {id} or {success=true}. Connector calls return completed values: use them directly, without await.",
		"Start with local page = meta.getPage(): page.id is the Page. For Instagram, local ig = meta.getPage({fields='id,instagram_business_account'}).instagram_business_account gives the linked account, whose ig.id is the ig_user of Instagram functions; it is nil when none is linked, and the call needs the instagram_basic permission. Page functions act on the connected Page itself. IDs are strings: posts look like '<page-id>_<post-id>', conversations 't_...', Messenger messages 'm_...'; Instagram media, comments and accounts are numeric strings, Instagram threads and messages opaque ones.",
		"fields chooses what Meta returns and accepts field expansion, such as fields='id,message,comments.limit(5){message,from}' or, to get insights with each post, fields='id,message,insights.metric(post_media_view,post_clicks)'. Functions list their default fields; getObject without fields returns only Meta's minimal defaults. Access tokens cannot be requested. Media links (full_picture, picture, media_url, attachments) are signed CDN URLs that expire within days; read the object again for fresh ones.",
		"Paging: lists return one page, {data, paging}. limit sets its size (default 25) and paging.cursors.after is the next call's after. While paging.next is present, call the same function with {next = result.paging.next} alone for the next page; stop when it is absent, as a page can be empty yet have next. Expanded edges, such as business_discovery media, are paged with their own .after(cursor) modifier instead.",
		"Insights: getInsights({object, metric, period?, since?, until?, ...}); since and until take Unix times or dates, at most 90 days apart for the Page, and paging.next or since/until move through time. Page (object='me'): page_media_view, page_total_media_view_unique, page_daily_follows_unique, page_daily_unfollows_unique, page_post_engagements, page_total_actions, page_views_total, page_video_views, with period day, week or days_28, and page_follows with period day; needs 100 or more followers. Posts: post_media_view, post_total_media_view_unique, post_clicks, post_reactions_by_type_total, post_video_views (period lifetime). Instagram account: reach, views, accounts_engaged, total_interactions, likes, comments, shares, saves, replies, follows_and_unfollows, profile_links_taps, with period='day' and metric_type='total_value' (breakdown='media_product_type' splits most), covering the last 24 hours unless since/until are given; follower_demographics and engaged_audience_demographics need period='lifetime', timeframe='this_month' and breakdown age, city, country or gender. Instagram media: views, reach, likes, comments, shares, saved, total_interactions; reels add ig_reels_avg_watch_time, stories navigation (24 hours only). impressions, plays and page_fans no longer exist.",
		"Inbox: listConversations({platform='messenger' or 'instagram'}), then listMessages({conversation=thread.id}). Meta returns conversations with your customers only once the app has Advanced Access for messaging. sendMessage({recipient={id=psid}, messaging_type='RESPONSE', message={text='Thanks!'}}) answers within 24 hours of the person's last message; after that Meta requires messaging_type='MESSAGE_TAG' with a tag it still accepts, such as 'HUMAN_AGENT' (within 7 days, once Meta approved its Human Agent feature). sendMessage({recipient={comment_id=id}, message}) sends the one private reply allowed to a Facebook comment, within 7 days; Instagram comments use sendInstagramPrivateReply. Instagram texts are at most 1,000 bytes; recipients are the IDs in participants or from.",
		"Publishing to Facebook: createPost({message='Hello'}) posts now; published=false with scheduled_publish_time (Unix time 10 minutes to 30 days ahead) schedules it. uploadPhoto and uploadVideo take a public url (file_url for videos) or path, a session file streamed to Meta. For several photos in one post, upload each with published=false (and temporary=true when the post is scheduled), then createPost({message, attached_media={{media_fbid=id1}, {media_fbid=id2}}}). Facebook reels cannot be published here.",
		"Publishing to Instagram: createInstagramContainer({ig_user, image_url=jpeg_url, caption}) (or media_type='REELS' with video_url, media_type='STORIES', or media_type='CAROUSEL' with children='id1,id2', at most 10 made with is_carousel_item=true) returns {id}; poll getObject({id=container.id, fields='status_code'}) about once a minute, for at most 5 minutes, until FINISHED (EXPIRED after 24 hours, ERROR on failure); then publishInstagramMedia({ig_user, creation_id=container.id}). Meta fetches media from public HTTPS URLs. Captions take at most 2,200 characters, 30 hashtags and 20 @ tags; an account creates at most 400 containers a day, and getInstagramPublishingLimit gives the 24-hour publishing quota.",
		"Moderation: updateComment({comment, is_hidden=true}) hides a Facebook comment and updateComment({comment, hide=true}) an Instagram one; deleteObject({id}) deletes either. Instagram comments can be deleted only on the account's own media.",
		"Read-only connections omit writes. Meta also applies the token's permissions and the system user's tasks on the Page; a missing one fails with code 10 or 200 naming it. Errors give the HTTP status, Meta's code/subcode, message and fbtrace_id; rate limits (codes 4, 17, 32, 341, 613, 80000-80014) and transient errors are retryable and may say when calls succeed again. There are no automatic retries: after a timeout or 5xx, read the Page again before repeating a write, since a post or message may already be live.",
	}
	local names: {string} = {}
	for name in exports do if name ~= "help" then table.insert(names, name) end end
	table.sort(names)
	for _, name in names do
		local endpoint = endpoints[name]
		local defaults = if endpoint.fields then " Default fields: " .. endpoint.fields .. "." else ""
		table.insert(lines, name .. signature(endpoint) .. ": " .. endpoint.about .. defaults .. " " .. endpoint.method .. " " .. endpoint.path)
	end
	return table.concat(lines, "\n")
end
return exports
