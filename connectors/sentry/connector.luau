-- Sentry REST API v0. Arguments and results keep Sentry's native camelCase field names.
type Options = {[string]: any}
type Endpoint = {method: string, path: string, query: {string}?, extra: {string}?, required: {string}?, write: boolean?, body: (boolean | string)?,
	fields: {string}?, shape: string?, doc: string, about: string}

local PROVIDER = "Sentry"
local DOCS = "https://docs.sentry.io/api/"
local PAGE = {"cursor", "per_page"}
local PERIOD = {"statsPeriod", "start", "end"}

local function with(...: {string}): {string}
	local fields: {string} = {}
	for _, group in {...} do table.move(group, 1, #group, #fields + 1, fields) end
	return fields
end

-- Operations in Sentry's public OpenAPI (github.com/getsentry/sentry-api-schema), checked on
-- 2026-10-30; the issue comment routes are Sentry's own, outside the published schema. :org is
-- the connection's organization and path {fields} are required; listed query fields are taken
-- from the options and the other fields form the JSON body. Lists answer with one page.
local endpoints: {[string]: Endpoint} = {
	listOrganizations = {method = "GET", path = "/organizations/", query = with({"owner", "query", "sortBy"}, PAGE), shape = "list",
		doc = "users/list-your-organizations/", about = "Organizations the token can reach in this region: {id, slug, name, dateCreated, status, links}."},
	getOrganization = {method = "GET", path = "/organizations/:org/", query = {"detailed"}, doc = "organizations/retrieve-an-organization/",
		about = "The connection's organization, with its projects and teams unless detailed='0'."},

	listProjects = {method = "GET", path = "/organizations/:org/projects/", query = with({"query"}, PAGE), shape = "list",
		doc = "organizations/list-an-organizations-projects/", about = "Projects: {id, slug, name, platform, dateCreated, isMember, hasAccess, teams, latestRelease}."},
	getProject = {method = "GET", path = "/projects/:org/{project_id_or_slug}/", shape = "project", doc = "projects/retrieve-a-project/",
		about = "A project by id or slug: {id, slug, name, platform, status, dateCreated, firstEvent, teams, latestRelease, features, defaultEnvironment, resolveAge, isMember, hasAccess, access, hasSessions, hasReplays, hasProfiles, hasLogs}."},
	listTeams = {method = "GET", path = "/organizations/:org/teams/", query = with({"query", "detailed"}, PAGE), shape = "list",
		doc = "teams/list-an-organizations-teams/", about = "Teams: {id, slug, name, memberCount, isMember, projects}. Assign an issue to one with assignedTo='team:<id>'."},
	listMembers = {method = "GET", path = "/organizations/:org/members/", query = with({"query"}, PAGE), shape = "list",
		doc = "organizations/list-an-organizations-members/",
		about = "Members: {id, email, name, role, user={id, username, email}}. query matches names and emails, or filters with email:, role: or user.id:. Assign an issue with assignedTo='user:<user.id>'."},

	listIssues = {method = "GET", path = "/organizations/:org/issues/",
		query = with({"query", "project", "environment", "sort", "limit", "shortIdLookup", "groupStatsPeriod", "viewId", "expand", "collapse", "cursor"}, PERIOD),
		shape = "list", doc = "events/list-an-organizations-issues/",
		about = "Issues: {id, shortId, title, culprit, level, status, substatus, priority, count, userCount, firstSeen, lastSeen, project, assignedTo, permalink, metadata}. query uses Sentry's search syntax, such as 'is:unresolved level:error release:1.2.0 assigned:me'; without it Sentry applies its default 'is:unresolved' view, and query='' lists all. project and environment take an id/slug or name, or an array. sort: date (last seen, default), new, freq, user, trends or inbox. limit is at most 100. statsPeriod such as 24h or 14d (default), or start and end in ISO 8601. shortIdLookup='1' finds a short id such as WEB-1A in query. hits gives the total match count."},
	getIssue = {method = "GET", path = "/organizations/:org/issues/{issue_id}/", query = {"environment", "expand", "collapse"},
		doc = "events/retrieve-an-issue/",
		about = "An issue by numeric id or short id such as WEB-1A, with its stats, tags (top values), activity, participants and first and last release."},
	getIssueTag = {method = "GET", path = "/organizations/:org/issues/{issue_id}/tags/{key}/", query = {"environment"},
		doc = "events/retrieve-tag-details/", about = "One tag of an issue's events, such as browser, release, environment or user, with {totalValues, topValues: [{value, count, firstSeen, lastSeen}]}."},
	listIssueEvents = {method = "GET", path = "/organizations/:org/issues/{issue_id}/events/",
		query = with({"query", "environment", "full", "sample"}, PERIOD, PAGE), shape = "events", doc = "events/list-an-issues-events/",
		about = "An issue's events, newest first: {id (the event id), eventID, groupID, title, message, dateCreated, platform, tags, user}. full=true adds entries, contexts and stack traces, at most 10 per page, trimmed as described above."},
	getIssueEvent = {method = "GET", path = "/organizations/:org/issues/{issue_id}/events/{event_id}/", query = {"environment", "collapse"},
		shape = "event", doc = "events/retrieve-an-issue-event/",
		about = "One event of an issue, trimmed as described above; event_id is a 32-character hex id, 'latest', 'oldest' or 'recommended' (the most helpful one Sentry picks). nextEventID and previousEventID walk the issue's events."},
	getEvent = {method = "GET", path = "/projects/:org/{project_id_or_slug}/events/{event_id}/", query = {"environment", "collapse"},
		shape = "event", doc = "events/retrieve-an-event-for-a-project/", about = "An event by its 32-character hex id, trimmed as described above."},
	listIssueComments = {method = "GET", path = "/organizations/:org/issues/{issue_id}/comments/", query = PAGE, shape = "list",
		doc = "events/", about = "Comments on an issue, newest first: {id, type='note', dateCreated, user, data={text}}. Sentry doesn't document this route."},

	listReleases = {method = "GET", path = "/organizations/:org/releases/",
		query = with({"query", "project", "environment", "health", "healthStat", "healthStatsPeriod", "summaryStatsPeriod", "adoptionStages", "status", "sort", "flatten"}, PAGE),
		shape = "list", doc = "releases/list-an-organizations-releases/",
		about = "Releases, newest first: {version, shortVersion, dateCreated, dateReleased, firstEvent, lastEvent, newGroups, projects, lastDeploy}. query matches part of the version. health='1' adds each project's healthData {crashFreeSessions, crashFreeUsers, sessionsCrashed, sessionsErrored, totalSessions, totalUsers, adoption, stats}; healthStatsPeriod (default 24h) and summaryStatsPeriod (default 14d) are 1h, 24h, 1d, 48h, 2d, 7d, 14d, 30d or 90d. status: open (default) or archived. sort: date (default), semver, build or adoption, or crash_free_sessions, crash_free_users, sessions or users with flatten='1' and one project."},
	getRelease = {method = "GET", path = "/organizations/:org/releases/{version}/",
		query = {"project", "health", "adoptionStages", "healthStatsPeriod", "summaryStatsPeriod", "sort", "status", "query"},
		doc = "releases/retrieve-an-organizations-release/",
		about = "A release by version, such as 'web@1.2.0', with its commits, deploys and authors; health='1' adds each project's health as in listReleases."},
	getSessions = {method = "GET", path = "/organizations/:org/sessions/",
		query = with({"field", "groupBy", "project", "environment", "interval", "query", "orderBy", "per_page", "includeTotals", "includeSeries"}, PERIOD),
		required = {"field"}, doc = "releases/retrieve-release-health-session-statistics/",
		about = "Release health time series, {start, end, intervals, groups: [{by, totals, series}]}. field (one or an array): sum(session), count_unique(user), crash_free_rate(session), crash_free_rate(user), crash_rate(session), crash_rate(user) or avg, p50 to p99 or max of session.duration. groupBy: project, release, environment or session.status. query filters, such as 'release:web@1.2.0'. interval is at least 1h."},

	updateIssue = {method = "PUT", path = "/organizations/:org/issues/{issue_id}/",
		fields = {"status", "statusDetails", "substatus", "assignedTo", "priority", "hasSeen", "isBookmarked", "isSubscribed", "inbox"}, doc = "events/update-an-issue/",
		about = "Changes an issue and returns it. Resolve with status='resolved', optionally with statusDetails={inNextRelease=true} or {inRelease='web@1.2.0'} (or 'latest'); reopen with status='unresolved'. Ignore (archive) with status='ignored' and substatus 'archived_forever', 'archived_until_escalating', or 'archived_until_condition_met' with statusDetails such as {ignoreDuration=minutes}, {ignoreCount=n, ignoreWindow=minutes} or {ignoreUserCount=n, ignoreUserWindow=minutes}. assignedTo: 'user:<id>', 'team:<id>', a username or an email, or '' to unassign. priority: low, medium or high. hasSeen, isBookmarked and isSubscribed apply to the token's user."},
	addIssueComment = {method = "POST", path = "/organizations/:org/issues/{issue_id}/comments/", required = {"text"}, fields = {"text"},
		doc = "events/", about = "Comments on an issue in Markdown, {id, type='note', data={text}}; Sentry notifies the issue's subscribers and refuses an identical comment twice. Sentry doesn't document this route."},
}

-- Request layer shared verbatim by the endpoint-table connectors
-- (tools/validate checks they match). It uses each connector's PROVIDER, DOCS and Endpoint type.
local NULL = json.decode("null")
local NONE: {string} = table.freeze({})

local function options(input: Options?): Options
	if input == nil then return {} end
	assert(type(input) == "table", "opts must be an object")
	for key in input do assert(type(key) == "string", "opts must have named fields") end
	return table.clone(input)
end

local function scalar(value: any, field: string): string
	local kind = type(value)
	assert(kind == "string" or kind == "boolean" or kind == "number", field .. " must be a string, boolean, number or array of those")
	return url.encode(value)
end

-- A query value's encoded parts: one for a scalar, one per item of a nonempty array. Each
-- connector joins them as its provider expects, comma-separated or with the key repeated.
local function queryParts(value: any, field: string): {string}
	if type(value) ~= "table" then return {scalar(value, field)} end
	local parts: {string} = {}
	for index, item in value do
		assert(type(index) == "number" and index == #parts + 1, field .. " must be an array, not an object")
		table.insert(parts, scalar(item, field))
	end
	assert(#parts > 0, field .. " must not be an empty array")
	return parts
end

-- Only GET reads unless write says otherwise.
local function writes(endpoint: Endpoint): boolean
	if endpoint.write ~= nil then return endpoint.write end
	return endpoint.method ~= "GET"
end

-- POST, PATCH and PUT send the remaining options as the JSON body unless body is false
-- (no body) or names the one option to send.
local function hasBody(endpoint: Endpoint): boolean
	return endpoint.body ~= false and (endpoint.method == "POST" or endpoint.method == "PATCH" or endpoint.method == "PUT")
end

local function fail(name: string, response: HttpResponse, message: string): never
	return houston.fail({operation = name, layer = "upstream", upstream_status = response.statusCode,
		retryable = response.statusCode == 429 or response.statusCode >= 500, message = message})
end

-- A successful response's JSON object, or nil when a write answers without a body. With arrays,
-- a top-level JSON array is accepted too, and the second result tells which one came back.
local function object(name: string, endpoint: Endpoint, response: HttpResponse, arrays: boolean?): (any, boolean)
	local raw = await(response.body:readAll())
	if endpoint.method ~= "GET" and writes(endpoint) and string.match(raw, "^%s*$") then return nil, false end
	local ok, value = pcall(json.decode, raw)
	local list = arrays == true and string.match(raw, "^%s*%[") ~= nil
	if not ok or type(value) ~= "table" or not (list or string.match(raw, "^%s*{")) then
		fail(name, response, PROVIDER .. " returned an invalid JSON object")
	end
	return value, list
end

-- name({path fields, query fields?, extra fields?, required body fields, ...body}) built from the
-- endpoint itself.
-- Extra fields are options the connector's own request consumes, such as a request header.
local function signature(endpoint: Endpoint): string
	local fields: {string} = {}
	for field in string.gmatch(endpoint.path, "{([%w_]+)}") do table.insert(fields, field) end
	for _, group in {endpoint.query or NONE, endpoint.extra or NONE} do
		for _, field in group do
			table.insert(fields, if table.find(endpoint.required or NONE, field) then field else field .. "?")
		end
	end
	if type(endpoint.body) == "string" then
		table.insert(fields, endpoint.body)
	elseif hasBody(endpoint) then
		for _, field in endpoint.required or NONE do
			if not table.find(fields, field) then table.insert(fields, field) end
		end
		table.insert(fields, "...body")
	end
	return "({" .. table.concat(fields, ", ") .. "})"
end

-- A function for each endpoint the connection's access allows, and help listing them after intro.
local function operations(endpoints: {[string]: Endpoint}, request: (string, Endpoint, Options?) -> any, intro: {string}): {[string]: any}
	local exports: {[string]: any} = {}
	for name, endpoint in endpoints do
		if not writes(endpoint) or config.access == "read-write" then
			exports[name] = function(args: Options?): any return request(name, endpoint, args) end
		end
	end
	exports.help = function(): string
		local names: {string} = {}
		for name in exports do if name ~= "help" then table.insert(names, name) end end
		table.sort(names)
		local lines = table.clone(intro)
		table.insert(lines, "Each function below names its route and reference page, " .. DOCS .. "<page>.")
		for _, name in names do
			local endpoint = endpoints[name]
			table.insert(lines, name .. signature(endpoint) .. ": " .. endpoint.about .. " " .. endpoint.method .. " " .. endpoint.path .. " (" .. endpoint.doc .. ")")
		end
		return table.concat(lines, "\n")
	end
	return exports
end
-- End of the shared request layer.

-- The connection's region host and organization slug or id. An invalid organization fails each
-- call rather than loading, so help still works.
local API = "https://" .. string.lower(config.region) .. "/api/0"
local ORG = string.lower(string.match(config.organization or "", "^%s*(.-)%s*$") :: string)
local ORG_VALID = string.match(ORG, "^[%w_%-]+$") ~= nil

-- Events can hold megabytes of frames, local variables, breadcrumbs, threads and debug images.
-- Results keep the innermost and in-app frames of each stack trace, the root and latest
-- exceptions, the latest breadcrumbs, the first spans, the crashed thread's stack, and short
-- strings; houstonTrimmed counts what was left out.
local MAX_EVENT_BYTES, MAX_FRAMES, MAX_IN_APP, MAX_CONTEXT, MAX_EXCEPTIONS, MAX_BREADCRUMBS, MAX_SPANS, MAX_STRING, MAX_DEPTH =
	4 * 1024 * 1024, 30, 20, 5, 5, 50, 50, 2048, 12

type Trimmed = {[string]: number}

local function count(trimmed: Trimmed, kind: string, n: number)
	if n > 0 then trimmed[kind] = (trimmed[kind] or 0) + n end
end

-- The last keep items of an array, or its first ones with first.
local function keep(list: any, limit: number, trimmed: Trimmed, kind: string, first: boolean?): any
	if type(list) ~= "table" or #list <= limit then return list end
	local kept: {any} = json.decode("[]")
	local start = if first then 1 else #list - limit + 1
	table.move(list, start, start + limit - 1, 1, kept)
	count(trimmed, kind, #list - limit)
	return kept
end

local function clip(value: any, trimmed: Trimmed, depth: number): any
	if type(value) == "string" then
		if #value <= MAX_STRING then return value end
		count(trimmed, "strings", 1)
		-- Cut at a UTF-8 character boundary.
		local cut = MAX_STRING
		while cut > 0 and bit32.band(string.byte(value, cut + 1), 0xC0) == 0x80 do cut -= 1 end
		return string.sub(value, 1, cut) .. "…"
	end
	if type(value) ~= "table" then return value end
	if depth >= MAX_DEPTH then
		count(trimmed, "nested", 1)
		return "[nested too deep]"
	end
	for key, item in value do value[key] = clip(item, trimmed, depth + 1) end
	return value
end

local function stacktrace(trace: any, trimmed: Trimmed)
	if type(trace) ~= "table" then return end
	local frames = trace.frames
	if type(frames) ~= "table" then return end
	-- Frames run outermost to innermost. Beyond the innermost ones, library code can hide the
	-- application's own frames, so up to MAX_IN_APP more of those stay too.
	if #frames > MAX_FRAMES then
		local first = #frames - MAX_FRAMES + 1
		local extra = 0
		while first > 1 and extra < MAX_IN_APP do
			local frame = frames[first - 1]
			if type(frame) == "table" and frame.inApp == true then extra += 1 end
			first -= 1
		end
		local kept: {any} = json.decode("[]")
		for index = first, #frames do
			local frame = frames[index]
			if index > #frames - MAX_FRAMES or (type(frame) == "table" and frame.inApp == true) then table.insert(kept, frame) end
		end
		count(trimmed, "frames", #frames - #kept)
		trace.frames = kept
	end
	for _, frame in trace.frames do
		if type(frame) == "table" then
			if type(frame.context) == "table" and type(frame.lineNo) == "number" and #frame.context > 2 * MAX_CONTEXT + 1 then
				-- context lists [line, text] pairs around the frame's line.
				local around: {any} = json.decode("[]")
				for _, line in frame.context do
					if type(line) == "table" and type(line[1]) == "number" and math.abs(line[1] - frame.lineNo) <= MAX_CONTEXT then
						table.insert(around, line)
					end
				end
				count(trimmed, "contextLines", #frame.context - #around)
				frame.context = around
			end
		end
	end
end

-- Raw (minified or unsymbolicated) stack traces repeat the frames already shown.
local function dropRaw(item: any, trimmed: Trimmed)
	if type(item) == "table" and type(item.rawStacktrace) == "table" then
		item.rawStacktrace = nil
		count(trimmed, "rawStacktraces", 1)
	end
end

local function entry(item: any, trimmed: Trimmed)
	local data = if type(item) == "table" then item.data else nil
	if type(data) ~= "table" then return end
	local kind = item.type
	if kind == "exception" then
		-- Chained exceptions run from the root cause, first, to the exception raised, last.
		local values = data.values
		if type(values) == "table" and #values > MAX_EXCEPTIONS then
			local kept: {any} = {values[1]}
			table.move(values, #values - MAX_EXCEPTIONS + 2, #values, 2, kept)
			count(trimmed, "exceptions", #values - MAX_EXCEPTIONS)
			data.values = kept
		end
		if type(data.values) == "table" then
			for _, value in data.values do
				if type(value) == "table" then
					stacktrace(value.stacktrace, trimmed)
					dropRaw(value, trimmed)
				end
			end
		end
	elseif kind == "threads" and type(data.values) == "table" then
		-- Without a crashed or current thread, the first one keeps its stack.
		local flagged = false
		for _, thread in data.values do
			if type(thread) == "table" and (thread.crashed or thread.current) then flagged = true end
		end
		for index, thread in data.values do
			if type(thread) == "table" then
				if thread.crashed or thread.current or (not flagged and index == 1) then
					stacktrace(thread.stacktrace, trimmed)
				elseif type(thread.stacktrace) == "table" then
					thread.stacktrace = nil
					count(trimmed, "threadStacktraces", 1)
				end
				dropRaw(thread, trimmed)
			end
		end
	elseif kind == "stacktrace" then
		stacktrace(data, trimmed)
	elseif kind == "breadcrumbs" then
		data.values = keep(data.values, MAX_BREADCRUMBS, trimmed, "breadcrumbs")
	elseif kind == "spans" then
		item.data = keep(data, MAX_SPANS, trimmed, "spans", true)
	elseif kind == "debugmeta" and type(data.images) == "table" then
		count(trimmed, "debugImages", #data.images)
		data.images = json.decode("[]")
	end
end

local function event(value: any): any
	if type(value) ~= "table" then return value end
	local trimmed: Trimmed = {}
	-- _meta records Sentry's own scrubbing and trimming, keyed by paths into the event.
	value._meta = nil
	if type(value.entries) == "table" then
		for _, item in value.entries do entry(item, trimmed) end
	end
	clip(value, trimmed, 0)
	if next(trimmed) then value.houstonTrimmed = trimmed end
	return value
end

-- Project details also carry its source-fetching security token, symbol server settings and
-- scrubbing rules, so they keep only these fields.
local PROJECT_FIELDS = {"id", "slug", "name", "platform", "platforms", "status", "dateCreated", "firstEvent", "firstTransactionEvent", "teams", "team",
	"latestRelease", "features", "defaultEnvironment", "resolveAge", "isBookmarked", "isMember", "hasAccess", "access", "hasSessions", "hasReplays",
	"hasProfiles", "hasMonitors", "hasLogs", "hasMinifiedStackTrace"}

local function project(value: any): any
	local kept: Options = {}
	for _, field in PROJECT_FIELDS do kept[field] = value[field] end
	return kept
end

-- Sentry errors are {detail} or, for invalid input, {field: [messages]}; rate limits add
-- X-Sentry-Rate-Limit-Reset in epoch seconds.
local function failStatus(name: string, response: HttpResponse): never
	local message = "Sentry HTTP " .. tostring(response.statusCode)
	local raw = await(response.body:readPrefix(16 * 1024))
	local ok, value = pcall(json.decode, raw)
	if ok and type(value) == "table" then
		local detail = if type(value.detail) == "string" then value.detail else json.encode(value)
		message ..= ": " .. string.sub(detail, 1, 600)
	end
	local reset = response.headers["x-sentry-rate-limit-reset"]
	if response.statusCode == 429 and reset and reset[1] then message ..= "; rate limit resets at Unix time " .. string.sub(reset[1], 1, 20) end
	return fail(name, response, message)
end

-- The cursor of the next page from Link: <...>; rel="next"; results="true"; cursor="0:100:0".
local function nextCursor(response: HttpResponse): any
	for _, link in response.headers.link or NONE do
		-- Each link is <url> followed by its attributes.
		for part in string.gmatch(link, "<[^>]*>([^<]*)") do
			if string.find(part, 'rel="next"', 1, true) and string.find(part, 'results="true"', 1, true) then
				local cursor = string.match(part, 'cursor="([^"]+)"')
				if cursor then return cursor end
			end
		end
	end
	return NULL
end

local function decode(name: string, endpoint: Endpoint, response: HttpResponse): any
	if response.statusCode < 200 or response.statusCode >= 300 then failStatus(name, response) end
	local value, list
	if endpoint.shape == "event" or endpoint.shape == "events" then
		-- Read events with a bound, so one oversized event fails clearly instead of exhausting memory.
		local raw = await(response.body:readPrefix(MAX_EVENT_BYTES + 1))
		if #raw > MAX_EVENT_BYTES then fail(name, response, "Sentry returned more than " .. MAX_EVENT_BYTES // (1024 * 1024) .. " MiB; request fewer events") end
		local ok, decoded = pcall(json.decode, raw)
		if not ok or type(decoded) ~= "table" then fail(name, response, "Sentry returned invalid JSON") end
		list = string.match(raw, "^%s*%[") ~= nil
		if list ~= (endpoint.shape == "events") then fail(name, response, if list then "Sentry returned an invalid event" else "Sentry returned an invalid list") end
		value = decoded
	else
		value, list = object(name, endpoint, response, endpoint.shape == "list")
	end
	if endpoint.shape == "event" then return event(value) end
	if endpoint.shape == "project" then return project(value) end
	if endpoint.shape == "list" or endpoint.shape == "events" then
		if not list then fail(name, response, "Sentry returned an invalid list") end
		if endpoint.shape == "events" then
			for _, item in value do event(item) end
		end
		local page: Options = {results = value, next = nextCursor(response)}
		local hits = response.headers["x-hits"]
		if hits and tonumber(hits[1]) then page.hits = tonumber(hits[1]) end
		return page
	end
	return value
end

local function request(name: string, endpoint: Endpoint, input: Options?): any
	assert(ORG_VALID, "The connection's Sentry organization must be its slug or id")
	local args = options(input)
	local path = string.gsub(endpoint.path, "{([%w_]+)}", function(field: string)
		local value = args[field]
		args[field] = nil
		assert(value ~= nil and value ~= NULL, field .. " is required")
		assert(type(value) == "string" or (type(value) == "number" and value == math.floor(value)), field .. " must be a string")
		local ok, segment = pcall(url.segment, tostring(value), field)
		assert(ok, field .. " must be a Sentry id, slug or version")
		return segment
	end)
	path = string.gsub(path, ":org", ORG)
	for _, field in endpoint.required or NONE do
		assert(args[field] ~= nil and args[field] ~= NULL, field .. " is required")
	end
	-- Sentry repeats the key for each value of an array, as project=1&project=2.
	local query: {string} = {}
	for _, field in endpoint.query or NONE do
		if args[field] ~= nil then
			for _, part in queryParts(args[field], field) do table.insert(query, field .. "=" .. part) end
		end
		args[field] = nil
	end
	if #query > 0 then path ..= "?" .. table.concat(query, "&") end
	if endpoint.fields then
		for field in args do assert(table.find(endpoint.fields :: {string}, field), name .. " has no option " .. field) end
	end
	local headers: HttpHeaders = {Accept = {"application/json"}}
	local body: string? = nil
	if hasBody(endpoint) then
		headers["Content-Type"] = {"application/json"}
		body = json.encode(args)
		args = {}
	end
	local unknown = next(args)
	assert(unknown == nil, name .. " has no option " .. tostring(unknown))
	return decode(name, endpoint, await(http.request({url = API .. path, method = endpoint.method, headers = headers, body = body})))
end

local intro = {
	"Sentry REST API v0 on " .. API .. ", for the organization " .. ORG .. ". Every function takes one named options object with Sentry's native names; ? marks optional fields and ...body the JSON body fields. Results are Sentry's JSON unchanged, except as noted. Connector calls return completed values: use them directly, without await.",
	"Routes are relative to " .. API .. " and :org is the connection's organization. Project, team and issue ids are numeric strings; projects also take their slug and issues their short id, such as WEB-1A. Release versions are strings such as 'web@1.2.0'. Times are ISO 8601.",
	"Lists return one page, {results, next, hits?}: while next is not null, pass it as cursor for the next page. per_page (or limit for issues) is at most 100.",
	"Events are trimmed to fit a call: each stack trace keeps its " .. MAX_FRAMES .. " innermost frames (the last ones) and up to " .. MAX_IN_APP .. " more in-app frames, with " .. MAX_CONTEXT .. " source lines around each, exceptions the first (the root cause) and the last " .. MAX_EXCEPTIONS - 1 .. " of a chain, breadcrumbs the latest " .. MAX_BREADCRUMBS .. ", spans the first " .. MAX_SPANS .. ", and only the crashed or current thread (else the first) keeps a stack trace; raw stack traces, debug images and Sentry's _meta are dropped and strings stop at " .. MAX_STRING .. " bytes. houstonTrimmed counts what was left out, by kind. Read the stack trace in entries[type='exception'].data.values[i].stacktrace.frames (filename, function, lineNo, inApp, context, vars) and breadcrumbs in entries[type='breadcrumbs'].data.values (timestamp, category, message, level, data). Responses over " .. MAX_EVENT_BYTES // (1024 * 1024) .. " MiB fail.",
	"Examples: local page = sentry.listIssues({query='is:unresolved level:error', project='web', statsPeriod='24h', limit=10}); local issue = page.results[1]; local e = sentry.getIssueEvent({issue_id=issue.id, event_id='recommended'}); sentry.listReleases({project='web', health='1', per_page=5}).",
	"The token's scopes and your Sentry role still apply: an HTTP 403 means a missing scope or role, and organization auth tokens (sntrys_...) reach releases only. Sentry limits requests per caller and endpoint over short windows; Houston retries an HTTP 429 twice, then reports when the limit resets. Errors report the HTTP status and Sentry's detail.",
}
if config.access == "read-write" then
	table.insert(intro, "Side effects: updateIssue changes the issue for everyone and can notify its subscribers; addIssueComment notifies its subscribers. Failures are not retried: after a timeout or 5xx, read the issue or its comments before repeating a write.")
else
	table.insert(intro, "This read-only connection omits writes.")
end

return operations(endpoints, request, intro)
