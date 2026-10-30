-- Exa API (OpenAPI 2.0.0, https://exa.ai/docs/exa-spec.yaml) for web search, page contents, similar pages and cited answers. Arguments and results keep Exa's native field names.
type Options = {[string]: any}
type Check = (any, string) -> any

local API = "https://api.exa.ai"
-- Houston ends a call after 30 s and the sandbox has no clock. Exa sends its whole answer once it is ready (about
-- 1 s for auto, 4 to 15 s for deep, plus up to livecrawlTimeout for fresh pages), so headers get most of the time.
local CALL_TIME, BODY_TIME = 27000, 4000
local MAX_BYTES = 4 * 1024 * 1024
-- Every call spends Exa credits. These bounds keep a call's cost and answer predictable: Exa bills each result above
-- 10, and without a limit returns up to 5,000,000 characters of text per page. Text and sized highlights share one budget.
local MAX_RESULTS, DEFAULT_RESULTS = 25, 10
local TEXT_DEFAULT, TEXT_BUDGET = 10000, 500000
-- A fresh fetch waits up to livecrawlTimeout before Exa answers, so it must leave room within the header budget.
local HIGHLIGHTS_MAX, LINKS_MAX, LIVECRAWL_MAX = 10000, 20, 8000
local MAX_QUERY, MAX_PROMPT, MAX_URL, MAX_DOMAINS = 4096, 4096, 2048, 1200
-- Exa's recommended search types; the legacy instant, fast and deep-reasoning are left out.
local TYPES = table.freeze({"auto", "lite", "deep-lite", "deep"})
local CATEGORIES = table.freeze({"company", "people", "news", "publication", "financial report", "personal site"})
-- exa-research is left out: its latency is undocumented and may pass the call limit, billed all the same.
local MODELS = table.freeze({"exa", "exa-pro", "exa-fast"})
local VERBOSITY = table.freeze({"compact", "standard", "full"})
local SECTIONS = table.freeze({"header", "navigation", "banner", "body", "sidebar", "footer", "metadata"})

local function finite(value: any): boolean
	return type(value) == "number" and value == value and math.abs(value) < 2 ^ 53
end

local function integer(minimum: number, maximum: number): Check
	return function(value: any, field: string): any
		assert(finite(value) and value % 1 == 0 and value >= minimum and value <= maximum,
			field .. " must be an integer from " .. tostring(minimum) .. " to " .. tostring(maximum))
		return value
	end
end

local function flag(value: any, field: string): any
	assert(type(value) == "boolean", field .. " must be true or false")
	return value
end

local function text(maximum: number): Check
	return function(value: any, field: string): any
		assert(type(value) == "string" and string.find(value, "%S") and #value <= maximum,
			field .. " must be a string of at most " .. tostring(maximum) .. " bytes, not only spaces")
		return value
	end
end

local function choice(values: {string}): Check
	return function(value: any, field: string): any
		assert(type(value) == "string" and table.find(values, value), field .. " must be one of " .. table.concat(values, ", "))
		return value
	end
end

local function list(maximum: number, item: Check): Check
	return function(value: any, field: string): any
		assert(type(value) == "table", field .. " must be an array")
		local count = 0
		for index, entry in value do
			assert(type(index) == "number" and index >= 1 and index % 1 == 0, field .. " must be a dense array")
			item(entry, field .. "[" .. tostring(index) .. "]")
			count += 1
		end
		assert(count == #value and count >= 1 and count <= maximum,
			field .. " must be a dense array of 1 to " .. tostring(maximum) .. " entries")
		return value
	end
end

-- URLs and domain filters: no spaces or control characters, which would silently match nothing.
local function link(value: any, field: string): any
	assert(type(value) == "string" and #value <= MAX_URL and string.match(value, "^[^%s%c]+$"),
		field .. " must be a URL or host of at most " .. tostring(MAX_URL) .. " bytes without spaces")
	return value
end

local DAYS = table.freeze({31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31})

local function within(digits: string?, minimum: number, maximum: number): boolean
	local number = if digits then tonumber(digits) else nil
	return number ~= nil and number >= minimum and number <= maximum
end

-- A real date, or a date-time with seconds, optional fractions and a Z or +hh:mm offset.
local function isDate(value: any): boolean
	if type(value) ~= "string" or #value > 40 then return false end
	local y, m, d, rest = string.match(value, "^(%d%d%d%d)%-(%d%d)%-(%d%d)(.*)$")
	if not y or not within(m, 1, 12) then return false end
	local year, month = tonumber(y) :: number, tonumber(m) :: number
	local leap = year % 4 == 0 and (year % 100 ~= 0 or year % 400 == 0)
	if not within(d, 1, if month == 2 and not leap then 28 else DAYS[month]) then return false end
	if rest == "" then return true end
	local hour, minute, second, zone = string.match(rest or "", "^T(%d%d):(%d%d):(%d%d)(.*)$")
	if not (within(hour, 0, 23) and within(minute, 0, 59) and within(second, 0, 59)) then return false end
	-- Optional fractional seconds: a dot and at least one digit.
	if string.sub(zone or "", 1, 1) == "." then zone = string.match(zone :: string, "^%.%d+(.*)$") end
	if zone == "Z" then return true end
	local zoneHour, zoneMinute = string.match(zone or "", "^[+-](%d%d):(%d%d)$")
	return within(zoneHour, 0, 23) and within(zoneMinute, 0, 59)
end

local DATE_RULE = " must be an ISO 8601 date such as 2026-01-31 or date-time such as 2026-01-31T12:00:00Z"

-- Published-date filters take date-times only, so a date alone covers its whole UTC day. Snapshots take either.
local function published(suffix: string): Check
	return function(value: any, field: string): any
		assert(isDate(value), field .. DATE_RULE)
		return if #value == 10 then value .. suffix else value
	end
end

local function schema(value: any, field: string): any
	assert(type(value) == "table" and next(value) ~= nil and #value == 0, field .. " must be a JSON Schema object")
	return value
end

local function location(value: any, field: string): any
	if type(value) == "string" then
		assert(string.match(value, "^%a%a$"), field .. " must be a two-letter country code such as US")
		return value
	end
	assert(type(value) == "table", field .. " must be a country code or {country?, latitude?, longitude?}")
	local out: Options = {}
	for key, item in value do
		if key == "country" then
			assert(type(item) == "string" and string.match(item, "^%a%a$"), field .. ".country must be a two-letter country code")
		elseif key == "latitude" or key == "longitude" then
			local limit = if key == "latitude" then 90 else 180
			assert(finite(item) and math.abs(item) <= limit, field .. "." .. key .. " must be a number from -" .. limit .. " to " .. limit)
		else
			error(field .. " received an unknown option " .. string.sub(tostring(key), 1, 64), 0)
		end
		out[key] = item
	end
	assert((out.latitude == nil) == (out.longitude == nil) and (out.country ~= nil or out.latitude ~= nil),
		field .. " needs country, or latitude and longitude together")
	return out
end

-- Copies the known fields of an options table, checked, so unknown fields and the caller's table never reach Exa.
local function fields(value: any, spec: {[string]: Check}, name: string, prefix: string): Options
	assert(type(value) == "table", name .. " must be an options table")
	local out: Options = {}
	for key, item in value do
		local check = if type(key) == "string" then spec[key] else nil
		assert(check, name .. " received an unknown option " .. string.sub(tostring(key), 1, 64))
		out[key] = check(item, prefix .. key)
	end
	return out
end

local function nested(spec: {[string]: Check}): Check
	return function(value: any, field: string): any return fields(value, spec, field, field .. ".") end
end

local function extend(base: {[string]: Check}, more: {[string]: Check}): {[string]: Check}
	local out = table.clone(base)
	for key, check in more do out[key] = check end
	return table.freeze(out)
end

local TEXT = table.freeze({maxCharacters = integer(1, TEXT_BUDGET), includeHtmlTags = flag, verbosity = choice(VERBOSITY),
	includeSections = list(#SECTIONS, choice(SECTIONS)), excludeSections = list(#SECTIONS, choice(SECTIONS))})
local HIGHLIGHTS = table.freeze({query = text(MAX_PROMPT), maxCharacters = integer(1, HIGHLIGHTS_MAX)})
local SUMMARY = table.freeze({query = text(MAX_PROMPT), schema = schema})

-- A content type is true or an options table, or false to leave it out. Without defaults, true is sent as is.
local function view(spec: {[string]: Check}, default: Options?): Check
	return function(value: any, field: string): any
		if value == false then return nil end
		if value == true and default == nil then return true end
		local out = fields(if value == true then {} else value, spec, field, field .. ".")
		local defaults: Options = default or {}
		for key, item in defaults do
			if out[key] == nil then out[key] = item end
		end
		return out
	end
end

-- Full text always gets a character limit; a summary is an object even when empty.
local CONTENTS: {[string]: Check} = table.freeze({
	text = view(TEXT, {maxCharacters = TEXT_DEFAULT}),
	highlights = view(HIGHLIGHTS),
	summary = view(SUMMARY, {}),
	extras = nested({links = integer(0, LINKS_MAX), imageLinks = integer(0, LINKS_MAX), richImageLinks = integer(0, LINKS_MAX)}),
	livecrawlTimeout = integer(1, LIVECRAWL_MAX),
	maxAgeHours = integer(-1, 720),
	snapshotAsOf = published(""),
})
local RESULTS: {[string]: Check} = table.freeze({
	numResults = integer(1, MAX_RESULTS),
	includeDomains = list(MAX_DOMAINS, link),
	excludeDomains = list(MAX_DOMAINS, link),
	startPublishedDate = published("T00:00:00.000Z"),
	endPublishedDate = published("T23:59:59.999Z"),
	category = choice(CATEGORIES),
	contents = nested(CONTENTS),
})
local SEARCH = extend(RESULTS, {
	query = text(MAX_QUERY),
	type = choice(TYPES),
	additionalQueries = list(10, text(MAX_QUERY)),
	userLocation = location,
	moderation = flag,
	objective = text(MAX_PROMPT),
	systemPrompt = text(MAX_PROMPT),
	outputSchema = schema,
})
local SIMILAR = extend(RESULTS, {url = link, excludeSourceDomain = flag})
local GET_CONTENTS = extend(CONTENTS, {urls = list(MAX_RESULTS, link)})
local ANSWER: {[string]: Check} = table.freeze({query = text(MAX_QUERY), model = choice(MODELS), systemPrompt = text(MAX_PROMPT),
	userLocation = location, outputSchema = schema})

local function required(body: Options, field: string, operation: string)
	assert(body[field] ~= nil, operation .. " requires " .. field)
end

-- Bounds the text and sized highlights one call can return, which Exa sends for every result.
local function budget(contents: Options?, count: number)
	local perPage = 0
	for _, kind in {"text", "highlights"} do
		local options = if contents then contents[kind] else nil
		if type(options) == "table" and options.maxCharacters then perPage += options.maxCharacters end
	end
	assert(count * perPage <= TEXT_BUDGET, "text.maxCharacters (default " .. tostring(TEXT_DEFAULT)
		.. ") plus highlights.maxCharacters, times the number of results, must be at most " .. tostring(TEXT_BUDGET))
end

local function errorCode(err: any): any
	return if type(err) == "table" then err.code else nil
end

local function fail(operation: string, status: number?, retryable: boolean, message: string): never
	return houston.fail({operation = operation, layer = "upstream", upstream_status = status, retryable = retryable,
		message = message})
end

-- houston.fail repairs a character split by the cut.
local function tidy(message: string): string
	return string.sub(string.match(string.gsub(message, "%s+", " "), "^ ?(.-) ?$") :: string, 1, 300)
end

-- Exa's error envelope is {requestId, error, tag}, given as " TAG: error (request id)"; other bodies, such as gateway
-- pages, are never shown.
local function reason(body: string): string
	local ok, value = false, nil
	if string.match(body, "^%s*{") then ok, value = pcall(json.decode, body) end
	if not ok or type(value) ~= "table" or type(value.error) ~= "string" then return "" end
	local tag = if type(value.tag) == "string" and string.match(value.tag, "^[%w_]+$") then " " .. string.sub(value.tag, 1, 64) else ""
	local id = if type(value.requestId) == "string" and string.match(value.requestId, "^%w+$")
		then " (request " .. string.sub(value.requestId, 1, 64) .. ")" else ""
	return tag .. ": " .. tidy(value.error) .. id
end

local function failure(operation: string, response: HttpResponse): never
	local status = response.statusCode
	local detail = ""
	if status >= 300 and status < 400 then
		response.body:close()
		detail = ": unexpected redirect"
	else
		-- An error body that stalls or breaks counts as empty.
		local read, prefix = pcall(function() return await(response.body:readPrefix(4096), BODY_TIME) end)
		if not read and errorCode(prefix) == "cancelled" then error(prefix, 0) end
		if read then detail = reason(prefix) end
	end
	if detail == "" and status == 401 then detail = ": check the connection's Exa API key" end
	local message = "Exa HTTP " .. tostring(status) .. detail
	local retry = response.headers["retry-after"]
	if (status == 429 or status == 503) and retry and retry[1] then
		-- Retry-After is either delay seconds or an HTTP date.
		local value = string.sub(retry[1], 1, 32)
		message ..= "; retry after " .. value .. (if string.match(value, "^%d+$") then "s" else "")
	end
	-- Input is checked first, so Exa's 4xx answers (bad requests, keys, credits, plans) are final.
	return fail(operation, status, status == 429 or status >= 500, message)
end

-- Posts one request and returns Exa's JSON object, which must hold the given field.
local function call(operation: string, path: string, body: Options, field: string): any
	local sent, response = pcall(function()
		return await(http.request({method = "POST", url = API .. path, timeoutMs = CALL_TIME - BODY_TIME,
			headers = {["Content-Type"] = {"application/json"}, Accept = {"application/json"}}, body = json.encode(body)}))
	end)
	if not sent then
		if errorCode(response) ~= "timeout" then error(response, 0) end
		fail(operation, nil, false, "Exa did not answer within " .. tostring((CALL_TIME - BODY_TIME) // 1000)
			.. " s; Exa may still bill it. Use a faster type or model, fewer results or a lower livecrawlTimeout")
	end
	if response.statusCode ~= 200 then failure(operation, response) end
	local read, raw = pcall(function() return await(response.body:readAll(MAX_BYTES), BODY_TIME) end)
	if not read then
		local code = errorCode(raw)
		if code == "limit_exceeded" then
			fail(operation, 200, false, "Exa returned more than " .. tostring(MAX_BYTES // 1048576)
				.. " MiB; request fewer results or less text")
		elseif code == "timeout" then
			fail(operation, 200, true, "Exa did not finish sending its answer within " .. tostring(BODY_TIME // 1000) .. " s; retry")
		elseif code == "cancelled" then
			error(raw, 0)
		end
		local detail = if type(raw) == "table" and type(raw.message) == "string" then raw.message else tostring(raw)
		fail(operation, 200, true, "Exa response failed: " .. string.sub(detail, 1, 300))
	end
	local ok, value = false, nil
	if string.match(raw, "^%s*{") then ok, value = pcall(json.decode, raw) end
	-- results is an array and answer a string or an object; an explicit JSON null (userdata) is neither.
	local result = if ok and type(value) == "table" then value[field] else nil
	if not (type(result) == "table" or (field == "answer" and type(result) == "string")) then
		fail(operation, 200, false, "Exa returned an unexpected answer")
	end
	return value
end

local function search(input: Options?): any
	local body = fields(input, SEARCH, "search", "")
	required(body, "query", "search")
	budget(body.contents, body.numResults or DEFAULT_RESULTS)
	return call("search", "/search", body, "results")
end

local function findSimilar(input: Options?): any
	local body = fields(input, SIMILAR, "findSimilar", "")
	required(body, "url", "findSimilar")
	budget(body.contents, body.numResults or DEFAULT_RESULTS)
	return call("findSimilar", "/findSimilar", body, "results")
end

local function getContents(input: Options?): any
	local body = fields(input, GET_CONTENTS, "getContents", "")
	required(body, "urls", "getContents")
	assert(body.text ~= nil or body.highlights ~= nil or body.summary ~= nil, "getContents requires text, highlights or summary")
	budget(body, #body.urls)
	return call("getContents", "/contents", body, "results")
end

local function answer(input: Options?): any
	local body = fields(input, ANSWER, "answer", "")
	required(body, "query", "answer")
	return call("answer", "/answer", body, "answer")
end

local function help(): string
	local n = tostring
	return [[Exa: web search built for agents (https://exa.ai/docs), with your connection's Exa API key. Credentials stay on Houston. Read-only: nothing is created or changed in Exa or on the web. Calls return completed values; do not wrap them in await(). Each call makes one Exa request with no paging (Houston retries an HTTP 429 briefly, nothing else), and results keep Exa's field names and values (requestId, results, costDollars, warnings, notices...).

Every call spends the connection's Exa credits (about $0.004 to $0.012 per search, $0.005 per answer, $0.001 per page and content type for getContents; each search result above 10 and each AI summary add $0.001). Read costDollars in each result. Search once with the content you need instead of searching, then fetching each page. Bounds: numResults and urls 1 to ]] .. n(MAX_RESULTS) .. [[ (default ]] .. n(DEFAULT_RESULTS) .. [[); text.maxCharacters defaults to ]] .. n(TEXT_DEFAULT) .. [[ (also for text = true) and highlights.maxCharacters is at most ]] .. n(HIGHLIGHTS_MAX) .. [[; together, times the number of results, they allow at most ]] .. n(TEXT_BUDGET) .. [[ characters per call (one page of ]] .. n(TEXT_BUDGET) .. [[, or 25 of 20000). Unknown options and invalid values fail before any request, so they cost nothing.

## search({query, type?, numResults?, category?, includeDomains?, excludeDomains?, startPublishedDate?, endPublishedDate?, userLocation?, moderation?, objective?, additionalQueries?, systemPrompt?, outputSchema?, contents?})

POST /search. Returns `{requestId, results, costDollars, searchTime, output?, warnings?, notices?}`; there is no paging. Each result has id (its URL, also accepted by getContents), url, title, publishedDate?, author?, image?, favicon?, and the requested text, highlights (array of strings), summary, extras, or entities (structured company, person or publication data for those categories). Pass notices to the reader with the results; warnings name request fields that had no effect.
- query: natural language describing the pages wanted, such as "recent papers comparing hybrid and dense retrieval", at most ]] .. n(MAX_QUERY) .. [[ bytes. Prefer includeDomains over site: in the query.
- type: auto (default, about 1 s), lite (cheapest, about 0.5 s, cached content only; rejects additionalQueries, outputSchema, systemPrompt, summary, extras, livecrawlTimeout and maxAgeHours), deep-lite (about 4 s, synthesized) or deep (4 to 15 s, multi-step research with synthesis).
- category: ]] .. table.concat(CATEGORIES, ", ") .. [[. company and people return profiles and reject published dates; people also rejects excludeDomains.
- includeDomains, excludeDomains: arrays of hosts, host paths or *.subdomain wildcards, such as {"arxiv.org", "github.com/exa-labs", "*.gov"}.
- startPublishedDate, endPublishedDate: ISO 8601 date (a whole UTC day: from its start, or through its end) or date-time with seconds.
- userLocation: two-letter country code such as "US", or {country?, latitude?, longitude?}. moderation: true filters unsafe content.
- objective: the task behind the query, what should rank first and what to extract. additionalQueries: 1 to 10 extra phrasings, deep types only.
- outputSchema: {type = "text", description} or a JSON Schema object (at most 10 properties, 2 levels); adds about 2 s and returns output = {content, grounding} citing results. systemPrompt guides that synthesis.
- contents: what to return for each result; without it, results carry only metadata. Each content type is billed separately, so request one unless the task needs more.
  - highlights: true (recommended: excerpts sized to their relevance) or {query?, maxCharacters?}; query steers which excerpts are chosen.
  - text: true or {maxCharacters?, verbosity? (compact, standard or full), includeHtmlTags?, includeSections?, excludeSections?}; sections are ]] .. table.concat(SECTIONS, ", ") .. [[.
  - summary: true or {query?, schema?}; an AI summary string per page; with schema, a JSON string matching it, to read with json.decode.
  - extras: {links?, imageLinks?, richImageLinks?}, 0 to ]] .. n(LINKS_MAX) .. [[ links per page.
  - maxAgeHours: -1 (cache only) to 720; 0 always fetches the live page. livecrawlTimeout: 1 to ]] .. n(LIVECRAWL_MAX) .. [[ ms (Exa's default 10000); with a fresh fetch, set it low, especially on deep types, so the call finishes in time. snapshotAsOf: a past date or date-time, served from stored versions.

## findSimilar({url, numResults?, excludeSourceDomain?, category?, includeDomains?, excludeDomains?, startPublishedDate?, endPublishedDate?, contents?})

POST /findSimilar. Pages similar to url, with the same result and contents shapes as search plus score (higher is more similar, comparable within one response). excludeSourceDomain = true leaves out url's own site. Exa deprecates this endpoint in favor of search with a query describing the source, so prefer that when you can describe it.

## getContents({urls, text?, highlights?, summary?, extras?, maxAgeHours?, livecrawlTimeout?, snapshotAsOf?})

POST /contents. Contents for 1 to ]] .. n(MAX_RESULTS) .. [[ URLs, with the contents options of search at the top level; at least one of text, highlights or summary is required. Returns `{requestId, results, statuses, costDollars}`: results are only the pages read, and statuses holds one {id, status = "success" or "error", source?, error = {tag, httpStatusCode}?} per URL. Tags include CRAWL_NOT_FOUND, CRAWL_HTTP_403, CRAWL_TIMEOUT, CRAWL_LIVECRAWL_TIMEOUT and SOURCE_NOT_AVAILABLE; a failed URL does not fail the call. Contents are billed per page and content type.

## answer({query, model?, systemPrompt?, userLocation?, outputSchema?})

POST /answer. Exa searches and answers with an LLM: `{requestId, answer, citations, costDollars}`, where answer is a string, or an object matching outputSchema (a JSON Schema), and citations are {id, url, title, publishedDate?, author?} of the sources used. model: ]] .. table.concat(MODELS, ", ") .. [[ (default exa). Read a citation's page with getContents.

## Errors and limits

Exa errors fail as upstream errors with the HTTP status, Exa's tag and message and its request ID, such as "Exa HTTP 402 NO_MORE_CREDITS: ...". 401 means the API key is invalid; 402 that credits or a spending budget ran out; 403 that the plan lacks a feature or moderation refused the request; 400 that options conflict (such as an option lite does not accept). HTTP 429, 500, 503 and 504 are retryable: Exa allows 10 searches or answers and 5 deep searches per second per team, and Houston waits and retries a refused request briefly. A call gives Exa ]] .. n((CALL_TIME - BODY_TIME) // 1000) .. [[ s to answer and reads at most ]] .. n(MAX_BYTES // 1048576) .. [[ MiB; past that it fails, and Exa may still bill it. A timed-out call is not retryable: make it faster (another type or model, fewer results, a lower livecrawlTimeout) before calling again. Not exposed: Exa Agent runs, the exa-research answer model, monitors, batches, Websets, team and API key management, streaming, subpage crawling and Exa's deprecated options.

## Example

Here exa is the configured Exa connection.

```lua
local found = exa.search({query = "open-source vector databases benchmarked in 2026", numResults = 5,
	startPublishedDate = "2026-01-01", contents = {highlights = {query = "benchmark results"}}})
for _, result in found.results do print(result.title, result.url, result.highlights and result.highlights[1]) end
print(found.costDollars.total)
if found.results[1] then
	local page = exa.getContents({urls = {found.results[1].url}, text = {maxCharacters = 20000}})
	if page.results[1] then print(page.results[1].text) else print(page.statuses[1].error.tag) end
end
local reply = exa.answer({query = "Which company makes the Exa search API?"})
print(reply.answer, reply.citations[1] and reply.citations[1].url)
```]]
end

return {search = search, findSimilar = findSimilar, getContents = getContents, answer = answer, help = help}
