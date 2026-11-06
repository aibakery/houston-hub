-- Public X API v2 browsing. Credentials are injected only by Houston's proxy.
-- Each call performs one request; preserve X's envelopes, errors and cursors.
type Options = {[string]: any}
type Endpoint = {path: string, kind: string, page: string?, minimum: number?, maximum: number?, help: string, example: Options}
local POST_FIELDS = "created_at,conversation_id,public_metrics,entities,note_post"
local USER_FIELDS = "username,name,description,public_metrics,verified"
local endpoints: {[string]: Endpoint} = {
	searchRecentTweets = {path = "/tweets/search/recent", kind = "search", page = "next_token", minimum = 10, maximum = 100,
		example = {query = "from:XDevelopers -is:retweet", max_results = 10},
		help = "Search the last seven days. Required query uses X search syntax (e.g. from:XDevelopers -is:retweet). Optional sort_order: recency or relevancy."},
	searchAllTweets = {path = "/tweets/search/all", kind = "search", page = "next_token", minimum = 10, maximum = 500,
		example = {query = "Houston", max_results = 500, sort_order = "recency", start_time = "2020-01-01T00:00:00Z", since_id = "123"},
		help = "Search the full archive. Required query uses X search syntax. Optional sort_order: recency or relevancy. Requires archive access on your X developer account."},
	getTweet = {path = "/tweets/{id}", kind = "tweet", example = {id = "123"}, help = "Look up one tweet. Required id is a decimal string, never a number or URL."},
	getTweets = {path = "/tweets", kind = "batch", example = {ids = {"123", "456"}}, help = "Look up 1–100 tweets. Required ids is an array of decimal strings. Inspect errors for missing or inaccessible tweets; results need not match input order."},
	getUser = {path = "/users/{id}", kind = "user", example = {id = "789"}, help = "Look up a public profile. Required id is a decimal string."},
	getUserByUsername = {path = "/users/by/username/{username}", kind = "user", example = {username = "XDevelopers"}, help = "Look up a public profile. Required username excludes @. Use data.id for timeline calls."},
	listUserTweets = {path = "/users/{id}/tweets", kind = "timeline", page = "pagination_token", minimum = 5, maximum = 100,
		example = {id = "789", exclude = {"replies", "retweets"}, max_results = 5},
		help = "Read a user's tweets. Required id is the user ID string. Optional exclude: replies, retweets (array or comma-separated string)."},
	listUserMentions = {path = "/users/{id}/mentions", kind = "timeline", page = "pagination_token", minimum = 5, maximum = 100,
		example = {id = "789", pagination_token = "timeline+/=", until_id = "999"},
		help = "Read public tweets mentioning a user. Required id is the user ID string."},
}
local NULL = json.decode("null")

local function text(value: any, field: string): string
	assert(type(value) == "string" and value ~= "", field .. " must be a nonempty string")
	return value
end

local function id(value: any, field: string): string
	local result = text(value, field)
	assert(string.match(result, "^%d+$"), field .. " must be a decimal ID string")
	return result
end

local function list(value: any, field: string): {string}
	assert(type(value) == "table", field .. " must be an array")
	local count = 0
	for index, item in value do
		assert(type(index) == "number" and index >= 1 and index % 1 == 0, field .. " must be a dense array")
		text(item, field)
		count += 1
	end
	assert(count > 0 and count == #value, field .. " must be a nonempty dense array")
	return value
end

local function failure(name: string, response: HttpResponse): never
	-- Do not echo arbitrary provider bodies or credentials into errors.
	response.body:close()
	local message = "X HTTP " .. tostring(response.statusCode)
	if response.statusCode == 401 then message ..= ": check your app bearer token"
	elseif response.statusCode == 402 then message ..= ": check your X developer account credits"
	elseif response.statusCode == 403 then message ..= ": your app may lack access to this resource or endpoint" end
	local reset = response.headers["x-rate-limit-reset"]
	if response.statusCode == 429 and reset and reset[1] then message ..= "; rate limit resets at Unix time " .. string.sub(reset[1], 1, 32) end
	return houston.fail({operation = name, layer = "upstream", upstream_status = response.statusCode,
		retryable = response.statusCode == 429 or response.statusCode >= 500, message = message})
end

local function request(name: string, endpoint: Endpoint, input: Options?): any
	assert(type(input) == "table", name .. " requires an options object")
	local args = table.clone(input :: Options)
	local path = string.gsub(endpoint.path, "{(%w+)}", function(field: string)
		local value = if field == "id" then id(args[field], field) else text(args[field], field)
		if field == "username" then assert(#value <= 15 and string.match(value, "^[A-Za-z0-9_]+$"), "username must be an X handle without @") end
		args[field] = nil
		return url.segment(value, field)
	end)
	local query: {string} = {}
	local function take(field: string, default: any, csv: boolean?)
		local value = args[field]
		args[field] = nil
		if value == nil then value = default end
		if value == nil then return end
		if csv and type(value) == "table" then value = table.concat(list(value, field), ",") end
		table.insert(query, url.encode(field) .. "=" .. url.encode(text(value, field)))
	end
	if endpoint.kind == "batch" then
		local ids = list(args.ids, "ids")
		assert(#ids <= 100, "ids must contain at most 100 IDs")
		for _, value in ids do id(value, "ids") end
		take("ids", nil, true)
	end
	if endpoint.kind ~= "user" then
		take("post.fields", POST_FIELDS, true)
		take("expansions", "author_id", true)
		take("media.fields", nil, true)
		take("place.fields", nil, true)
		take("poll.fields", nil, true)
	else
		take("expansions", nil, true)
		take("post.fields", nil, true)
	end
	take("user.fields", USER_FIELDS, true)
	if endpoint.kind == "search" then
		text(args.query, "query")
		take("query", nil)
		if args.sort_order ~= nil then
			assert(args.sort_order == "recency" or args.sort_order == "relevancy", "sort_order must be recency or relevancy")
			take("sort_order", nil)
		end
	end
	if endpoint.page then
		local size = if args.max_results == nil then 10 else args.max_results
		assert(type(size) == "number" and size % 1 == 0 and size >= (endpoint.minimum :: number) and size <= (endpoint.maximum :: number), "max_results is outside this endpoint's range")
		args.max_results = nil
		table.insert(query, "max_results=" .. tostring(size))
		take(endpoint.page, nil)
		take("start_time", nil)
		take("end_time", nil)
		for _, field in {"since_id", "until_id"} do
			if args[field] ~= nil then id(args[field], field) end
			take(field, nil)
		end
	end
	if name == "listUserTweets" then take("exclude", nil, true) end
	assert(next(args) == nil, name .. " received an unknown option")
	table.sort(query)
	local response = await(http.request({method = "GET", url = "https://api.x.com/2" .. path .. "?" .. table.concat(query, "&"), headers = {Accept = {"application/json"}}}))
	if response.statusCode < 200 or response.statusCode >= 300 then failure(name, response) end
	local raw = await(response.body:readAll())
	local ok, value = pcall(json.decode, raw)
	if not ok or type(value) ~= "table" or not string.match(raw, "^%s*{") then
		houston.fail({operation = name, layer = "upstream", upstream_status = response.statusCode, retryable = false, message = "X returned an invalid JSON object"})
	end
	-- Partial batch/expansion errors are meaningful alongside successful data.
	if value.errors ~= nil and (value.data == nil or value.data == NULL) then
		houston.fail({operation = name, layer = "upstream", upstream_status = response.statusCode, retryable = false, message = "X returned errors without data"})
	end
	if value.data == NULL or (value.data == nil and (not endpoint.page or type(value.meta) ~= "table" or value.meta.result_count ~= 0)) then
		houston.fail({operation = name, layer = "upstream", upstream_status = response.statusCode, retryable = false, message = "X returned no data or empty-page metadata"})
	end
	return value
end

local functions: {[string]: any} = {}
for name, endpoint in endpoints do
	functions[name] = function(opts: Options?) return request(name, endpoint, opts) end
end
function functions.help()
	local nonempty: any = {type = "string", minLength = 1}
	local idSchema: any = {type = "string", pattern = "^[0-9]+$", description = "Decimal ID kept as a string, never a number or URL."}
	local function selector(description: string, default: string?): any
		return {anyOf = {nonempty, {type = "array", minItems = 1, items = nonempty}}, description = description .. " Comma-separated string or nonempty array of names; X validates supported names.", default = default}
	end
	local tweet = {type = "object", properties = {id = idSchema, text = {type = "string"}, author_id = idSchema, conversation_id = idSchema, created_at = {type = "string"},
		public_metrics = {type = "object", additionalProperties = {type = "integer"}}, note_post = {type = "object", properties = {text = {type = "string"}}, description = "Read text here for long-form posts."}}}
	local user = {type = "object", properties = {id = idSchema, username = {type = "string"}, name = {type = "string"}, description = {type = "string"}, verified = {type = "boolean"},
		public_metrics = {type = "object", additionalProperties = {type = "integer"}}}}
	local docs: {[string]: any} = {}
	for name, endpoint in endpoints do
		local properties: {[string]: any} = {
			["user.fields"] = selector("User fields, such as username, name, description, public_metrics and verified.", USER_FIELDS),
			["post.fields"] = selector("Post fields, such as created_at, conversation_id, public_metrics, entities and note_post.", if endpoint.kind == "user" then nil else POST_FIELDS),
			expansions = selector("Related resources to include, such as author_id or attachments.media_keys.", if endpoint.kind == "user" then nil else "author_id"),
		}
		local required: {string} = {}
		for field in string.gmatch(endpoint.path, "{(%w+)}") do
			properties[field] = if field == "id" then idSchema else {type = "string", minLength = 1, maxLength = 15, pattern = "^[A-Za-z0-9_]+$", description = "X handle without @."}
			table.insert(required, field)
		end
		if endpoint.kind ~= "user" then
			properties["media.fields"] = selector("Expanded media fields, such as url, preview_image_url and type; request the relevant expansion too.", nil)
			properties["place.fields"] = selector("Expanded place fields, such as country, full_name and geo; request the relevant expansion too.", nil)
			properties["poll.fields"] = selector("Expanded poll fields, such as options, voting_status and end_datetime; request the relevant expansion too.", nil)
		end
		if endpoint.kind == "batch" then
			properties.ids = {type = "array", minItems = 1, maxItems = 100, items = idSchema}
			table.insert(required, "ids")
		elseif endpoint.kind == "search" then
			properties.query = {type = "string", minLength = 1, description = "X search expression; for replies use conversation_id:<tweet-id>. Query limits and archive availability depend on the developer account."}
			properties.sort_order = {type = "string", enum = {"recency", "relevancy"}}
			table.insert(required, "query")
		end
		if endpoint.page then
			properties.max_results = {type = "integer", minimum = endpoint.minimum, maximum = endpoint.maximum, default = 10}
			properties[endpoint.page] = {type = "string", minLength = 1, description = "Prior meta.next_token; repeat the same query and filters. Stop when meta.next_token is absent."}
			properties.start_time = {type = "string", minLength = 1, format = "date-time", description = "RFC 3339 start time; X validates the requested search window."}
			properties.end_time = {type = "string", minLength = 1, format = "date-time", description = "RFC 3339 end time."}
			properties.since_id = idSchema
			properties.until_id = idSchema
		end
		if name == "listUserTweets" then properties.exclude = selector("Timeline entries to omit: replies, retweets.", nil) end
		local data = if endpoint.kind == "user" then user elseif endpoint.kind == "tweet" then tweet else {type = "array", items = tweet}
		docs[name] = {description = "GET /2" .. endpoint.path .. ". " .. endpoint.help .. " Returns the native {data, includes?, meta?, errors?} envelope. Related objects and partial errors remain available; inspect errors even when data is present. An empty page may omit data and report meta.result_count=0.",
			inputSchema = {type = "object", properties = properties, required = required, additionalProperties = false, examples = {endpoint.example}},
			outputSchema = {type = "object", properties = {data = data,
				includes = {type = "object", properties = {users = {type = "array", items = user}, tweets = {type = "array", items = tweet}}},
				meta = {type = "object", properties = {result_count = {type = "integer", minimum = 0}, next_token = {type = "string"}, previous_token = {type = "string"}, newest_id = idSchema, oldest_id = idSchema}},
				errors = {type = "array", items = {type = "object", properties = {title = {type = "string"}, detail = {type = "string"}, type = {type = "string"}, resource_id = {type = "string"}}}},
			}}, annotations = {readOnlyHint = true, idempotentHint = true}}
	end
	return {text = "X: public, read-only API v2 browsing with your app bearer token. Credentials stay on Houston. Each function takes one options object and makes one request, with no automatic pagination or retries. X bills your developer account; access depends on its permissions and credits. IDs must stay strings. Responses preserve data, includes, meta, errors and nulls. Inspect errors even when data is present. No private accounts, home feed, bookmarks, DMs or writes.", functions = docs, sections = {fields = "Field selectors use native X names: opts[\"post.fields\"], opts[\"user.fields\"], media.fields, place.fields, poll.fields and expansions. Pass comma-separated strings or arrays. Tweet calls include authors, dates, public metrics and note_post (long-form text) by default. Profile calls accept user.fields, post.fields and expansions.", paging = "Paged calls accept max_results (default 10), start_time/end_time (RFC3339), since_id/until_id (strings). Pass result.meta.next_token as next_token for search, or pagination_token for timelines. Stop when it is absent. Fetch only the pages you need; each request uses your provider quota. To browse replies, search query = \"conversation_id:<tweet-id>\" within the chosen search window.", workflow = [[Here x is the configured X connection. Calls return completed values; do not wrap them in await(). Read note_post.text when present for long-form posts.

```lua
local users = x.getUserByUsername({username = "XDevelopers"})
local tweets = x.listUserTweets({id = users.data.id, max_results = 10})
local matches = x.searchRecentTweets({query = "from:XDevelopers -is:retweet", max_results = 10})
-- For the next search page, pass matches.meta.next_token as next_token.
-- For timeline pages, pass tweets.meta.next_token as pagination_token.
```

References: https://docs.x.com/x-api/posts/search/introduction,
https://docs.x.com/x-api/posts/lookup/quickstart,
https://docs.x.com/x-api/posts/timelines/introduction,
https://docs.x.com/x-api/users/lookup/introduction.]]}}
end
return functions
