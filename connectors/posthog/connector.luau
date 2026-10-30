-- PostHog Cloud REST and query API, read-only with a personal API key. Arguments and results keep PostHog's native field names.
type Options = {[string]: any}
type List = {path: string, query: {[string]: string | {string}}, fields: {string}, fixed: string?, about: string}

local API = "https://" .. config.region
-- Houston ends a call after 30 s and the sandbox has no clock, so each call splits 27 s across its requests:
-- {headers, body} milliseconds. PostHog runs a query for at most 10 s, after up to 30 s in a queue when the project
-- already runs 3. PostHog honors limit up to the 1,000-row cap, so a list's second page is rare and gets less.
local QUERY_TIME = table.freeze({20000, 7000})
local PAGE_TIMES = table.freeze({table.freeze({15000, 5000}), table.freeze({5000, 2000})})
local MAX_BYTES = 4 * 1024 * 1024
local DEFAULT_LIMIT, MAX_LIMIT, MAX_ROWS, MAX_HOGQL = 100, 1000, 1000, 32 * 1024
local NULL = json.decode("null")
local BOOLEAN = table.freeze({"true", "false"})
local REFRESH = table.freeze({"force_cache", "blocking"})
local INSIGHT_KINDS = table.freeze({"TRENDS", "FUNNELS", "RETENTION", "PATHS", "STICKINESS", "LIFECYCLE", "SQL", "JSON", "BI", "JOURNEYS"})
local FLAG_TYPES = table.freeze({"boolean", "multivariant", "experiment", "remote_config"})
local USER_FIELDS = table.freeze({"id", "first_name", "last_name", "email"})
local INSIGHT_FIELDS = table.freeze({"id", "short_id", "name", "derived_name", "description", "query", "result", "columns", "types", "hasMore", "timezone",
	"last_refresh", "is_cached", "query_status", "saved", "favorited", "tags", "created_at", "created_by", "last_modified_at"})
-- PostHog decrypts remote config payloads for personal API keys; they often hold secrets, so they never leave Houston.
local REDACTED = "(encrypted)"

-- List rows keep these fields: lists drop project tokens, autocapture DOM elements and the dashboards, permissions
-- and usage details that make PostHog's rows large.
local lists: {[string]: List} = {
	listOrganizations = {path = "/api/organizations/", query = {},
		fields = {"id", "name", "slug", "created_at", "membership_level", "member_count"},
		about = "Organizations the key can read: `{id, name, slug, created_at, membership_level, member_count}`. Needs organization:read and a key not limited to projects."},
	listProjects = {path = "/api/organizations/{organization}/projects/", query = {search = "text"},
		fields = {"id", "uuid", "organization", "project_id", "name", "timezone", "is_demo", "ingested_event", "tags"},
		about = "Projects of one organization (opts.organization: an organization id, default \"@current\", the one last opened in PostHog): `{id, name, organization, timezone, is_demo, ingested_event, tags, ...}`. search matches names. Needs project:read and a key not limited to projects."},
	listEvents = {path = "/api/projects/{project}/events/",
		query = {event = "text", after = "text", before = "text", distinct_id = "text", person_id = "text", properties = "filters", include_person = BOOLEAN},
		fields = {"id", "distinct_id", "event", "timestamp", "properties", "person"},
		about = "Events, newest first: `{id, distinct_id, event, timestamp, properties, person?}`. Without after, only the last 24 hours. after and before take ISO 8601 times; event is an event name such as `$pageview`; person_id is a person uuid; include_person = true adds `person = {distinct_ids, properties, is_identified}`. Needs query:read. Prefer query for counts and aggregates."},
	listPersons = {path = "/api/projects/{project}/persons/", query = {search = "text", distinct_id = "text", email = "text", properties = "filters"},
		fields = {"id", "uuid", "name", "distinct_ids", "properties", "created_at", "last_seen_at"},
		about = "Persons, newest first: `{id, uuid, name, distinct_ids, properties, created_at, last_seen_at}`. search matches email, name, person id or distinct id; email and distinct_id match exactly. Needs person:read."},
	listInsights = {path = "/api/projects/{project}/insights/", fixed = "basic=true",
		query = {search = "text", saved = BOOLEAN, insight = INSIGHT_KINDS},
		fields = {"id", "short_id", "name", "derived_name", "description", "query", "saved", "favorited", "tags", "created_at", "created_by", "last_modified_at", "last_refresh", "last_viewed_at"},
		about = "Insights without their results: `{id, short_id, name, derived_name, description, query, saved, favorited, tags, created_at, created_by, last_modified_at, last_refresh, last_viewed_at}`. search matches names, descriptions and tags; saved = true keeps saved insights; insight: " .. table.concat(INSIGHT_KINDS, ", ") .. ". Needs insight:read."},
	listFeatureFlags = {path = "/api/projects/{project}/feature_flags/", query = {search = "text", key = "text", active = {"true", "false", "STALE"}, type = FLAG_TYPES},
		fields = {"id", "key", "name", "active", "archived", "status", "filters", "ensure_experience_continuity", "evaluation_runtime", "is_remote_configuration",
			"has_encrypted_payloads", "tags", "experiment_set", "version", "created_at", "created_by", "updated_at", "last_called_at"},
		about = "Feature flags, archived ones excluded: `{id, key, name (its description), active, status, filters = {groups, multivariate, payloads}, evaluation_runtime, tags, created_by, last_called_at, ...}`. filters.groups are the release conditions with rollout_percentage. Encrypted payloads read \"" .. REDACTED .. "\". search matches keys and names; key matches exactly; active: true, false or \"STALE\"; type: " .. table.concat(FLAG_TYPES, ", ") .. ". Needs feature_flag:read."},
}

local function finite(value: any): boolean
	return type(value) == "number" and value == value and math.abs(value) < 2 ^ 53
end

local function options(value: any, operation: string): Options
	assert(value == nil or type(value) == "table", operation .. " options must be a table")
	return table.clone((value or {}) :: Options)
end

local function noneLeft(args: Options, operation: string)
	local unknown = next(args)
	assert(unknown == nil, operation .. " received an unknown option " .. string.sub(tostring(unknown), 1, 64))
end

local function choice(value: any, field: string, values: {string}): string
	if type(value) == "boolean" then value = tostring(value) end
	assert(type(value) == "string" and table.find(values, value), field .. " must be one of " .. table.concat(values, ", "))
	return value
end

-- A positive integer id given as a number or a string of digits, or nil.
local function numeric(value: any): string?
	local id = if finite(value) and value % 1 == 0 then string.format("%d", value) elseif type(value) == "string" then value else ""
	return if #id <= 15 and string.match(id, "^[1-9]%d*$") then id else nil
end

-- A project is its numeric id, or "@current" for the project last opened in PostHog.
local function projectId(value: any): string
	local id = if value == "@current" then "@current" else numeric(value)
	assert(id, "project must be a PostHog project id, such as 12345, or \"@current\"")
	return id
end

local function organizationId(value: any): string
	assert(value == "@current" or (type(value) == "string" and string.match(string.lower(value), "^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$")),
		"organization must be a PostHog organization uuid or \"@current\"")
	return value
end

local function queryValue(value: any, field: string, kind: string | {string}): string
	if type(kind) == "table" then return choice(value, field, kind) end
	if kind == "filters" then
		assert(type(value) == "table" and #value > 0 and next(value, #value) == nil, field .. " must be a nonempty array of PostHog property filters")
		return url.encode(json.encode(value))
	end
	local text = if finite(value) then tostring(value) else value
	assert(type(text) == "string" and string.find(text, "%S") and #text <= 1000, field .. " must be a nonempty string of at most 1000 bytes")
	return url.encode(text)
end

local function errorCode(err: any): any
	return if type(err) == "table" then err.code else nil
end

local function fail(operation: string, status: number?, retryable: boolean, message: string): never
	return houston.fail({operation = operation, layer = "upstream", upstream_status = status, retryable = retryable, message = message})
end

-- PostHog errors are {type, code, detail, attr}.
local function failure(operation: string, response: HttpResponse, bodyTime: number): never
	local status = response.statusCode
	local message = "PostHog HTTP " .. tostring(status)
	if status >= 300 and status < 400 then
		response.body:close()
		message ..= ": unexpected redirect"
	else
		local read, prefix = pcall(function(): any return await(response.body:readPrefix(32 * 1024), bodyTime) end)
		if not read and errorCode(prefix) == "cancelled" then error(prefix, 0) end
		local ok, body = pcall(json.decode, if read then prefix else "")
		if ok and type(body) == "table" then
			if type(body.code) == "string" then message ..= " " .. string.sub(body.code, 1, 64) end
			if type(body.attr) == "string" then message ..= " (" .. string.sub(body.attr, 1, 64) .. ")" end
			if type(body.detail) == "string" then message ..= ": " .. string.sub(string.gsub(body.detail, "%s+", " "), 1, 500) end
		end
	end
	if status == 401 then
		message ..= " (check the personal API key and the connection's cloud region; keys can expire or be revoked)"
	elseif status == 403 then
		message ..= " (the key may lack this function's read scope, or access to this organization or project)"
	end
	local retry = response.headers["retry-after"]
	if status == 429 and retry and retry[1] then
		local value = string.sub(retry[1], 1, 32)
		message ..= "; retry after " .. value .. (if string.match(value, "^%d+$") then "s" else "")
	end
	return fail(operation, status, status == 429 or status >= 500, message)
end

-- Returns a successful response's body, read within budget bytes and times = {headers, body} milliseconds.
local function fetch(operation: string, request: HttpRequest, times: {number}, budget: number, tooMuch: string): string
	local headersTime, bodyTime = times[1], times[2]
	request.timeoutMs = headersTime
	local sent, response = pcall(function(): any return await(http.request(request)) end)
	if not sent then
		if errorCode(response) ~= "timeout" then error(response, 0) end
		fail(operation, nil, true, "PostHog did not answer within " .. tostring(headersTime // 1000) .. " s; retry")
	end
	if response.statusCode < 200 or response.statusCode >= 300 then failure(operation, response, bodyTime) end
	local read, raw = pcall(function(): any return await(response.body:readAll(budget), bodyTime) end)
	if not read then
		local code = errorCode(raw)
		if code == "limit_exceeded" then
			fail(operation, response.statusCode, false, "PostHog returned more than " .. tostring(MAX_BYTES // 1048576) .. " MiB, more than one call can hold; " .. tooMuch)
		elseif code == "timeout" then
			fail(operation, response.statusCode, true, "PostHog did not finish sending its answer within " .. tostring(bodyTime // 1000) .. " s; retry")
		elseif code == "cancelled" then
			error(raw, 0)
		end
		local detail = if type(raw) == "table" and type(raw.message) == "string" then raw.message else tostring(raw)
		fail(operation, response.statusCode, true, "PostHog response failed: " .. string.sub(detail, 1, 300))
	end
	return raw
end

local function object(operation: string, raw: string): any
	local ok, value = false, nil
	if string.match(raw, "^%s*{") then ok, value = pcall(json.decode, raw) end
	if not ok or type(value) ~= "table" then fail(operation, 200, false, "PostHog returned an unexpected response") end
	return value
end

local function pick(value: any, fields: {string}): any
	if type(value) ~= "table" then return value end
	local kept: Options = {}
	for _, field in fields do kept[field] = value[field] end
	return kept
end

local function row(value: any, fields: {string}): any
	local kept = pick(value, fields)
	if type(kept) ~= "table" then return kept end
	if kept.created_by ~= nil then kept.created_by = pick(kept.created_by, USER_FIELDS) end
	local filters = kept.filters
	if kept.has_encrypted_payloads == true and type(filters) == "table" and type(filters.payloads) == "table" then
		for key in filters.payloads do filters.payloads[key] = REDACTED end
	end
	return kept
end

-- The query of a next link to path, keeping only the list's own options and offset and restoring its fixed one; nil
-- when it is not such a link. PostHog's links repeat the request's options with offset, or before for events.
local function cursor(link: any, spec: List, path: string): {string}?
	local linked, query
	if type(link) == "string" and #link <= 8192 then linked, query = string.match(link, "^[^?#%s]-(/api/[^?#%s]*)%?([^#%s]+)$") end
	if linked ~= path or query == nil then return nil end
	local parts: {string} = {}
	for part in string.gmatch(query, "[^&]+") do
		local name = string.match(part, "^([%w_]+)=")
		if name == "offset" then
			if not string.match(part, "^offset=%d+$") then return nil end
			table.insert(parts, part)
		elseif name and spec.query[name] then
			table.insert(parts, part)
		elseif name ~= "limit" and not (spec.fixed and part == spec.fixed) then
			return nil
		end
	end
	if spec.fixed then table.insert(parts, spec.fixed :: string) end
	return parts
end

-- One page of size rows: PostHog's object with a results array, and the bytes it took.
local function page(name: string, path: string, query: {string}, size: number, times: {number}, budget: number): (any, number)
	local parts = table.clone(query)
	table.insert(parts, "limit=" .. tostring(size))
	local raw = fetch(name, {method = "GET", url = API .. path .. "?" .. table.concat(parts, "&"), headers = {Accept = {"application/json"}}},
		times, budget, "pass a lower limit")
	local value = object(name, raw)
	if type(value.results) ~= "table" then fail(name, 200, false, "PostHog returned an unexpected response") end
	return value, #raw
end

local function list(name: string, spec: List, project: any, input: any): any
	local args = options(input, name)
	local path = spec.path
	if string.find(path, "{project}", 1, true) then
		path = string.gsub(path, "{project}", projectId(project))
	elseif string.find(path, "{organization}", 1, true) then
		path = string.gsub(path, "{organization}", organizationId(if args.organization == nil then "@current" else args.organization))
		args.organization = nil
	end
	local limit = DEFAULT_LIMIT
	if args.limit ~= nil then
		limit = args.limit
		assert(finite(limit) and limit % 1 == 0 and limit >= 1 and limit <= MAX_LIMIT, "limit must be an integer from 1 to " .. tostring(MAX_LIMIT))
	end
	args.limit = nil
	local query: {string} = {}
	if args.next ~= nil then
		local parts = cursor(args.next, spec, path)
		assert(parts, "next must be the next link of an earlier " .. name .. " page of the same project or organization")
		args.next = nil
		assert(next(args) == nil, name .. " takes only limit with next, which keeps the other options")
		query = parts
	else
		for field, kind in spec.query do
			if args[field] ~= nil then table.insert(query, field .. "=" .. queryValue(args[field], field, kind)) end
			args[field] = nil
		end
		noneLeft(args, name)
		if spec.fixed then table.insert(query, spec.fixed :: string) end
		table.sort(query)
	end
	local results: {any} = json.decode("[]")
	local count, link = nil, NULL
	local function add(value: any)
		for _, item in value.results do table.insert(results, row(item, spec.fields)) end
		if count == nil and finite(value.count) then count = value.count end
		link = if type(value.next) == "string" then value.next else NULL
	end
	local first, used = page(name, path, query, limit, PAGE_TIMES[1], MAX_BYTES)
	add(first)
	-- A short first page continues once with the time and bytes left. When that fails, the first page comes back
	-- with its next link, so a retry does not repeat it.
	local parts = if link ~= NULL and #results < limit and used < MAX_BYTES then cursor(link, spec, path) else nil
	if parts then
		local ok, more = pcall(page, name, path, parts, limit - #results, PAGE_TIMES[2], MAX_BYTES - used)
		if ok then
			add(more)
		elseif errorCode(more) == "cancelled" then
			error(more, 0)
		end
	end
	return {results = results, next = link, count = count}
end

local function getInsight(project: any, id: any, input: any): any
	local args = options(input, "getInsight")
	local insight = numeric(id) or (if type(id) == "string" and string.match(id, "^%w%w%w%w%w%w%w%w$") then id else nil)
	assert(insight, "id must be an insight's numeric id or 8-character short_id")
	local query = ""
	if args.refresh ~= nil then query = "?refresh=" .. choice(args.refresh, "refresh", REFRESH) end
	args.refresh = nil
	noneLeft(args, "getInsight")
	return row(object("getInsight", fetch("getInsight", {method = "GET", url = API .. "/api/projects/" .. projectId(project) .. "/insights/" .. insight .. "/" .. query,
		headers = {Accept = {"application/json"}}}, QUERY_TIME, MAX_BYTES, "the insight's results are too large; run a narrower query instead")), INSIGHT_FIELDS)
end

local function runQuery(project: any, hogql: any, input: any): any
	local args = options(input, "query")
	local path = "/api/projects/" .. projectId(project) .. "/query/"
	assert(type(hogql) == "string" and string.find(hogql, "%S") and #hogql <= MAX_HOGQL, "hogql must be a nonempty HogQL query of at most " .. tostring(MAX_HOGQL // 1024) .. " KiB")
	local values = args.values
	if values ~= nil then
		assert(type(values) == "table", "values must be an object of placeholder values")
		for key in values do assert(type(key) == "string", "values must be an object of placeholder values") end
	end
	local label = args.name
	assert(label == nil or (type(label) == "string" and (utf8.len(label) or 129) <= 128), "name must be a string of at most 128 characters")
	args.values, args.name = nil, nil
	noneLeft(args, "query")
	local body = json.encode({query = {kind = "HogQLQuery", query = hogql, values = values}, refresh = "blocking", name = label or "houston"})
	local value = object("query", fetch("query", {method = "POST", url = API .. path,
		headers = {Accept = {"application/json"}, ["Content-Type"] = {"application/json"}}, body = body},
		QUERY_TIME, MAX_BYTES, "add a lower LIMIT or select fewer columns"))
	local rows = value.results
	if type(rows) ~= "table" then
		if type(value.query_status) == "table" then fail("query", 200, true, "PostHog is still running the query; retry") end
		fail("query", 200, false, "PostHog returned an unexpected response")
	end
	local truncated = #rows > MAX_ROWS
	if truncated then
		local kept: {any} = json.decode("[]")
		for index = 1, MAX_ROWS do kept[index] = rows[index] end
		rows = kept
	end
	return {columns = value.columns, types = value.types, results = rows, hasMore = value.hasMore, truncated = truncated}
end

local functions: {[string]: any} = {getInsight = getInsight, query = runQuery}
for name, spec in lists do
	if string.find(spec.path, "{project}", 1, true) then
		functions[name] = function(project: any, opts: Options?): any return list(name, spec, project, opts) end
	else
		functions[name] = function(opts: Options?): any return list(name, spec, nil, opts) end
	end
end

function functions.help(): string
	local sections = {"PostHog (" .. string.sub(API, 9) .. "): read-only access to the organizations, projects, events, persons, insights and feature flags this personal API key can read, and HogQL queries. Credentials stay on Houston. Calls return completed values; do not wrap them in await(). Results keep PostHog's field names. Invalid input and unknown options fail before any request.",
		"project is a numeric project id (from listProjects, or the number after /project/ in PostHog's address) or \"@current\", the project last opened in PostHog.",
		"Lists take opts.limit (default " .. tostring(DEFAULT_LIMIT) .. ", at most " .. tostring(MAX_LIMIT) .. " rows) and return `{results, next, count?}`; a call follows PostHog's pages until it has limit rows, making at most " .. tostring(#PAGE_TIMES) .. " requests; when the second fails, the first page comes back with its next link. While next is not null, pass `{next = page.next, limit?}` to continue (for listProjects, with the same organization): next keeps the other options, and a link from another list, project or organization is refused. Rows are compact; created_by is `{id, first_name, last_name, email}`.",
		"Errors carry the HTTP status, PostHog's code and detail. HTTP 403 usually means the key lacks the function's read scope, or is limited to other projects; keys limited to projects cannot list organizations or projects. HTTP 429 and 5xx are retryable. PostHog allows a personal API key 240 analytics requests a minute and 1,200 an hour (events, persons, insights), and queries draw on the project's hourly read budget (HTTP 429 api_queries_budget_exceeded): make few calls with filters rather than many. Each call reads at most " .. tostring(MAX_BYTES // 1048576) .. " MiB in all and gives PostHog " .. tostring((QUERY_TIME[1] + QUERY_TIME[2]) // 1000) .. " s in all; a call that runs out of time fails as retryable."}
	local names: {string} = {}
	for name in lists do table.insert(names, name) end
	table.sort(names)
	for _, name in names do
		local spec = lists[name]
		local signature = if string.find(spec.path, "{project}", 1, true) then "(project, opts?)" else "(opts?)"
		local fields: {string} = {}
		for field in spec.query do table.insert(fields, field) end
		if name == "listProjects" then table.insert(fields, "organization") end
		table.sort(fields)
		table.insert(fields, "limit")
		table.insert(fields, "next")
		table.insert(sections, "## " .. name .. signature .. "\n\nGET " .. spec.path .. ". " .. spec.about .. " opts: " .. table.concat(fields, ", ") .. ".")
	end
	table.insert(sections, "## getInsight(project, id, opts?)\n\nGET /api/projects/{project}/insights/{id}/. One insight by numeric id or 8-character short_id (the code in its PostHog address): `{id, short_id, name, derived_name, description, query, result, columns, types, hasMore, timezone, last_refresh, is_cached, query_status, saved, favorited, tags, created_at, created_by, last_modified_at}`; result holds the calculated data. opts.refresh: \"force_cache\" (default, never calculates; result is null when nothing is cached) or \"blocking\" (calculates unless fresh results exist, drawing on the read budget). Needs insight:read.")
	table.insert(sections, "## query(project, hogql, opts?)\n\nPOST /api/projects/{project}/query/ with kind HogQLQuery: one HogQL (PostHog SQL) SELECT, run synchronously. Returns `{columns, types, results, hasMore, truncated}`: results is an array of rows, each an array in columns order. PostHog returns 100 rows unless the query has its own LIMIT; this connector keeps at most " .. tostring(MAX_ROWS) .. " rows (truncated = true when it cut more). opts.values maps `{placeholder}` names in the query to values, for example `query(p, \"select count() from events where event = {name}\", {values = {name = \"$pageview\"}})`; opts.name labels the query in PostHog's query_log (default \"houston\"). Tables include events (event, timestamp, distinct_id, properties.$browser, person.properties.email), persons, sessions and groups. Always filter on timestamp and aggregate in SQL; this is for analysis, not exports, and OFFSET is refused for API keys: page on timestamp instead. Queries run for at most 10 s. Needs query:read.")
	table.insert(sections, [[## Example

Here posthog is the configured PostHog connection.

```lua
local projects = posthog.listProjects()
if not projects.results[1] then return "no projects" end
local project = projects.results[1].id
local daily = posthog.query(project, "select toDate(timestamp) as day, count() as pageviews from events where event = '$pageview' and timestamp > now() - interval 7 day group by day order by day")
-- daily.columns == {"day", "pageviews"}; daily.results[1] == {"2026-10-24", 1234}
local flags = posthog.listFeatureFlags(project, {active = true, limit = 50})
local events = posthog.listEvents(project, {event = "$pageview", after = "2026-10-29T00:00:00Z", limit = 200})
if type(events.next) == "string" then
	local more = posthog.listEvents(project, {next = events.next, limit = 200})
end
```

Reference: https://posthog.com/docs/api and https://posthog.com/docs/sql]])
	return table.concat(sections, "\n\n")
end

return functions
