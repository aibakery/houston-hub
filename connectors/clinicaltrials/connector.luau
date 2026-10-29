-- ClinicalTrials.gov data API v2, public and read-only. Arguments and results keep ClinicalTrials.gov's native field names.
type Options = {[string]: any}

local API = "https://clinicaltrials.gov/api/v2"
local DEFAULT_LIMIT, MAX_LIMIT, PAGE_SIZE, MAX_PAGES = 100, 2000, 1000, 10
local MAX_BYTES = 4 * 1024 * 1024
local MAX_TEXT, MAX_IDS = 2000, 500
local SUMMARY_FIELDS = table.freeze({"NCTId", "BriefTitle", "OverallStatus", "Phase", "StudyType", "Condition",
	"InterventionName", "LeadSponsorName", "EnrollmentCount", "StartDate", "PrimaryCompletionDate", "HasResults"})
local STATUSES = table.freeze({"ACTIVE_NOT_RECRUITING", "COMPLETED", "ENROLLING_BY_INVITATION", "NOT_YET_RECRUITING",
	"RECRUITING", "SUSPENDED", "TERMINATED", "WITHDRAWN", "AVAILABLE", "NO_LONGER_AVAILABLE",
	"TEMPORARILY_NOT_AVAILABLE", "APPROVED_FOR_MARKETING", "WITHHELD", "UNKNOWN"})
-- Essie expressions passed as single strings.
local TEXT_PARAMS = table.freeze({"query.cond", "query.term", "query.intr", "query.locn", "query.titles", "query.outc",
	"query.spons", "query.lead", "query.id", "query.patient", "filter.geo", "filter.advanced"})

local function text(value: any, field: string): string
	assert(type(value) == "string" and value ~= "" and #value <= MAX_TEXT,
		field .. " must be a nonempty string of at most " .. tostring(MAX_TEXT) .. " bytes")
	return value
end

local function isNctId(value: any): boolean
	return type(value) == "string" and string.match(value, "^NCT%d%d%d%d%d%d%d%d$") ~= nil
end

-- A list option takes an array or one string separated by commas or pipes.
local function list(value: any, field: string, check: (string) -> boolean, maximum: number): {string}
	local items: {string} = {}
	if type(value) == "string" then
		for item in string.gmatch(value, "[^,|]+") do
			local trimmed = string.match(item, "^%s*(.-)%s*$") :: string
			if trimmed ~= "" then table.insert(items, trimmed) end
		end
	else
		assert(type(value) == "table", field .. " must be a string or an array of strings")
		for index, item in value do
			assert(index == #items + 1 and type(item) == "string", field .. " must be a dense array of strings")
			table.insert(items, item)
		end
	end
	assert(#items > 0 and #items <= maximum, field .. " must list 1 to " .. tostring(maximum) .. " values")
	for _, item in items do
		assert(check(item), field .. " contains an invalid value: " .. string.sub(item, 1, 64))
	end
	return items
end

local function fieldName(name: string): boolean
	return #name <= 200 and string.match(name, "^%a[%w%-%. ]*$") ~= nil
end

local function searchField(name: string): boolean
	return name == "@query" or fieldName(name)
end

local function sortKey(key: string): boolean
	local field, direction = string.match(key, "^([^:]+):?(%a*)$")
	return field ~= nil and (field == "@relevance" or fieldName(field))
		and (direction == "" or direction == "asc" or direction == "desc")
end

local function failure(name: string, response: HttpResponse, id: string?): never
	local status = response.statusCode
	local message
	if status >= 300 and status < 400 then
		response.body:close()
		local location = response.headers.location
		local target = if location and location[1] then string.match(location[1], "^/api/v2/studies/(NCT%d%d%d%d%d%d%d%d)$") else nil
		message = if target and id
			then "ClinicalTrials.gov HTTP " .. tostring(status) .. ": " .. id .. " is an alias of " .. target .. "; call getStudy with " .. target
			else "ClinicalTrials.gov HTTP " .. tostring(status) .. ": unexpected redirect"
	else
		-- Errors are plain text; keep a bounded snippet that ends on a whole UTF-8 character.
		local snippet = string.match(string.gsub(await(response.body:readPrefix(300)), "%s+", " "), "^ ?(.-) ?$") :: string
		while snippet ~= "" and not utf8.len(snippet) do snippet = string.sub(snippet, 1, -2) end
		message = "ClinicalTrials.gov HTTP " .. tostring(status) .. (if snippet == "" then "" else ": " .. snippet)
	end
	local retry = response.headers["retry-after"]
	if (status == 429 or status == 503) and retry and retry[1] then message ..= "; retry after " .. string.sub(retry[1], 1, 32) .. "s" end
	return houston.fail({operation = name, layer = "upstream", upstream_status = status,
		retryable = status == 429 or status >= 500, message = message})
end

-- Returns the decoded JSON object and the bytes read, refusing bodies over budget.
local function fetch(name: string, target: string, budget: number, id: string?): (any, number)
	local response = await(http.request({method = "GET", url = target, headers = {Accept = {"application/json"}}}))
	if response.statusCode ~= 200 then failure(name, response, id) end
	local read, raw = pcall(function() return await(response.body:readAll(budget)) end)
	if not read then
		houston.fail({operation = name, layer = "upstream", upstream_status = 200, retryable = false,
			message = "ClinicalTrials.gov returned more data than one call can hold; request fewer fields or a lower limit"})
	end
	local ok, value = pcall(json.decode, raw)
	if not ok or type(value) ~= "table" or not string.match(raw, "^%s*{") then
		houston.fail({operation = name, layer = "upstream", upstream_status = 200, retryable = false,
			message = "ClinicalTrials.gov returned an invalid JSON object"})
	end
	return value, #raw
end

local function options(value: any, name: string): Options
	assert(value == nil or type(value) == "table", name .. " options must be a table")
	return table.clone((value or {}) :: Options)
end

local function fieldsParam(args: Options, check: (string) -> boolean, default: {string}?): string?
	local value = args.fields
	args.fields = nil
	if value == nil and default == nil then return nil end
	local fields = if value == nil then default :: {string} else list(value, "fields", check, 200)
	return "fields=" .. url.encode(table.concat(fields, ","))
end

-- Builds the search's fixed query string; only pageSize, countTotal and pageToken vary between pages.
local function searchQuery(args: Options): string
	local query: {string} = {}
	for _, field in TEXT_PARAMS do
		if args[field] ~= nil then table.insert(query, field .. "=" .. url.encode(text(args[field], field))) end
		args[field] = nil
	end
	if args["filter.overallStatus"] ~= nil then
		local statuses = list(args["filter.overallStatus"], "filter.overallStatus", function(item)
			return table.find(STATUSES, item) ~= nil
		end, #STATUSES)
		table.insert(query, "filter.overallStatus=" .. url.encode(table.concat(statuses, ",")))
		args["filter.overallStatus"] = nil
	end
	if args["filter.ids"] ~= nil then
		local ids = list(args["filter.ids"], "filter.ids", isNctId, MAX_IDS)
		table.insert(query, "filter.ids=" .. url.encode(table.concat(ids, ",")))
		args["filter.ids"] = nil
	end
	if args.sort ~= nil then
		table.insert(query, "sort=" .. url.encode(table.concat(list(args.sort, "sort", sortKey, 2), ",")))
		args.sort = nil
	end
	table.insert(query, fieldsParam(args, searchField, SUMMARY_FIELDS) :: string)
	table.sort(query)
	return table.concat(query, "&")
end

local function searchStudies(input: Options?)
	local args = options(input, "searchStudies")
	local limit = if args.limit == nil then DEFAULT_LIMIT else args.limit
	assert(type(limit) == "number" and limit % 1 == 0 and limit >= 1 and limit <= MAX_LIMIT,
		"limit must be an integer from 1 to " .. tostring(MAX_LIMIT))
	args.limit = nil
	local query: string, token: string?, countTotal = "", nil, false
	if args.pageToken ~= nil then
		local ok, cursor = pcall(houston.unseal, args.pageToken)
		assert(ok and type(cursor) == "table" and cursor.operation == "searchStudies" and type(cursor.query) == "string"
			and type(cursor.token) == "string", "pageToken must be the nextPageToken of an earlier searchStudies result")
		args.pageToken = nil
		assert(next(args) == nil, "pageToken continues an earlier search with its own criteria; pass only pageToken and limit")
		query, token = cursor.query, cursor.token
	else
		if args.countTotal ~= nil then
			assert(type(args.countTotal) == "boolean", "countTotal must be a boolean")
			countTotal = args.countTotal
			args.countTotal = nil
		end
		query = searchQuery(args)
		local unknown = next(args)
		assert(unknown == nil, "searchStudies received an unknown option " .. string.sub(tostring(unknown), 1, 64))
	end
	local studies = json.decode("[]")
	local result: Options = {studies = studies}
	local used = 0
	for page = 1, MAX_PAGES do
		local size = math.min(limit - #studies, PAGE_SIZE)
		if page > 1 then
			-- Size later pages from the bytes per study so far, so they fit the remaining budget.
			size = math.min(size, (MAX_BYTES - used) // (2 * used / #studies))
			if size < 1 then break end
		end
		local target = API .. "/studies?" .. query .. "&pageSize=" .. tostring(size)
			.. (if countTotal and page == 1 then "&countTotal=true" else "")
			.. (if token then "&pageToken=" .. url.encode(token) else "")
		local body, bytes = fetch("searchStudies", target, MAX_BYTES - used)
		used += bytes
		if type(body.studies) ~= "table" or (body.nextPageToken ~= nil and type(body.nextPageToken) ~= "string") then
			houston.fail({operation = "searchStudies", layer = "upstream", upstream_status = 200, retryable = false,
				message = "ClinicalTrials.gov returned an unexpected search page"})
		end
		if page == 1 and body.totalCount ~= nil then result.totalCount = body.totalCount end
		for _, study in body.studies do table.insert(studies, study) end
		-- An exactly full last page still carries a token, followed by an empty page.
		token = if #body.studies > 0 and body.nextPageToken ~= "" then body.nextPageToken else nil
		if token == nil or #studies >= limit then break end
	end
	if token then
		result.nextPageToken = houston.seal({operation = "searchStudies", query = query, token = token})
	end
	return result
end

local function getStudy(id: any, input: Options?)
	local args = options(input, "getStudy")
	if type(id) == "table" then
		assert(input == nil, "getStudy takes (nctId, opts?) or one table with nctId")
		args = options(id, "getStudy")
		id = args.nctId
		args.nctId = nil
	end
	assert(isNctId(id), "nctId must be NCT followed by 8 digits, such as NCT04368728")
	local fields = fieldsParam(args, fieldName, nil)
	local unknown = next(args)
	assert(unknown == nil, "getStudy received an unknown option " .. string.sub(tostring(unknown), 1, 64))
	local target = API .. "/studies/" .. id .. (if fields then "?" .. fields else "")
	return (fetch("getStudy", target, MAX_BYTES, id))
end

local function help(): string
	return [[ClinicalTrials.gov: search and read the public registry of clinical studies (data API v2, https://clinicaltrials.gov/data-api/api). No account or credentials. Read-only. Calls return completed values; do not wrap them in await(). Records keep ClinicalTrials.gov's JSON unchanged: protocolSection (identification, status, sponsor, description, conditions, design, arms and interventions, outcomes, eligibility, contacts and locations), resultsSection (participant flow, baseline, outcome measures, adverse events), derivedSection (MeSH terms) and hasResults. Data refreshes Monday to Friday. Credit "Source: ClinicalTrials.gov, U.S. National Library of Medicine" when presenting results.

## searchStudies(opts?)

GET /api/v2/studies. Returns `{studies, totalCount?, nextPageToken?}`. Options use the API's own names (quote dotted keys: `["query.cond"] = "..."`); unknown options are rejected.
- Essie text queries, which also rank by relevance: query.cond (condition or disease), query.intr (intervention or treatment), query.locn (city, state, country or facility), query.term (any field), query.titles, query.outc (outcome measures), query.spons (any sponsor), query.lead (lead sponsor), query.id (NCT and other study IDs), query.patient (patient-oriented search). Essie supports AND, OR, NOT, quotes and AREA[Field]value, for example `["query.cond"] = "lung cancer AND NOT small cell"`.
- filter.overallStatus: array or comma-separated string of RECRUITING, NOT_YET_RECRUITING, ENROLLING_BY_INVITATION, ACTIVE_NOT_RECRUITING, COMPLETED, SUSPENDED, TERMINATED, WITHDRAWN, UNKNOWN, and for expanded access AVAILABLE, NO_LONGER_AVAILABLE, TEMPORARILY_NOT_AVAILABLE, APPROVED_FOR_MARKETING, WITHHELD.
- filter.advanced: an Essie expression. There is no phase parameter: filter phases with `["filter.advanced"] = "AREA[Phase](PHASE2 OR PHASE3)"` (NA, EARLY_PHASE1, PHASE1, PHASE2, PHASE3, PHASE4). Other examples: `AREA[StudyType]INTERVENTIONAL`, `AREA[HasResults]true`, `AREA[LastUpdatePostDate]RANGE[2025-01-01,MAX]`, `AREA[MinimumAge]RANGE[MIN, 16 years]`; combine with AND.
- filter.geo: `distance(42.36,-71.06,25mi)` (km also accepted). filter.ids: up to 500 NCT IDs (aliases match too). A query.* value made only of NCT IDs makes ClinicalTrials.gov ignore every filter, so look IDs up with filter.ids.
- sort: up to 2 keys such as `LastUpdatePostDate:desc`, `EnrollmentCount:desc` or `@relevance`; only date and numeric fields sort. Without sort and without a text query, order is unspecified.
- fields: array or comma-separated names of fields, modules or sections, such as `NCTId`, `BriefSummary`, `EligibilityModule`, `ContactsLocationsModule`, `ProtocolSection`, or `@query` (the fields the query matched). Default: NCTId, BriefTitle, OverallStatus, Phase, StudyType, Condition, InterventionName, LeadSponsorName, EnrollmentCount, StartDate, PrimaryCompletionDate, HasResults. Selected fields keep their nested position, for example Phase is protocolSection.designModule.phases.
- countTotal: true adds totalCount, the number of matching studies.
- limit: studies to return, 1 to 2000 (default 100). The call pages internally, up to 1000 per request.
- pageToken: pass an earlier result's nextPageToken, with only limit, to continue that same search. nextPageToken is absent once every match is returned. A call may return fewer than limit studies when they would exceed one call's size budget; continue with nextPageToken.

## getStudy(nctId, opts?)

GET /api/v2/studies/{nctId}. Returns one full study record. nctId is NCT plus 8 digits, such as NCT04368728; shorter forms are rejected rather than padded. Also accepts one table `{nctId = ..., fields = ...}`. opts.fields selects parts, like searchStudies fields (without @query): for posted results use `{"ResultsSection"}` or modules such as `OutcomeMeasuresModule`, `AdverseEventsModule`, `ParticipantFlowModule`, `BaselineCharacteristicsModule`. A study without results returns {} for ResultsSection; check hasResults first. Most records are 10 to 50 KB, but some with results exceed 3 MB, so select modules when only part is needed. An unknown ID fails with HTTP 404. An old ID that became an alias fails with HTTP 301 and names the current NCT ID to use.

## Errors and limits

Invalid options fail before any request. ClinicalTrials.gov errors (plain text, such as an Essie syntax error or an invalid field name) come back as upstream errors with the HTTP status; HTTP 429 and 5xx are retryable. The API publishes no rate limit: keep calls few and use limit and fields rather than many small requests. Each call reads at most 4 MiB.

## Example

Here trials is the configured ClinicalTrials.gov connection.

```lua
local found = trials.searchStudies({
	["query.cond"] = "type 2 diabetes",
	["query.locn"] = "Boston",
	["filter.overallStatus"] = {"RECRUITING", "NOT_YET_RECRUITING"},
	["filter.advanced"] = "AREA[Phase](PHASE2 OR PHASE3)",
	countTotal = true,
	limit = 50,
})
for _, study in found.studies do
	local id = study.protocolSection.identificationModule
	print(id.nctId, id.briefTitle)
end
-- More: trials.searchStudies({pageToken = found.nextPageToken, limit = 50}) while found.nextPageToken.
local record = trials.getStudy(found.studies[1].protocolSection.identificationModule.nctId,
	{fields = {"EligibilityModule", "ContactsLocationsModule"}})
```]]
end

return {searchStudies = searchStudies, getStudy = getStudy, help = help}
