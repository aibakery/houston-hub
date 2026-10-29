-- bioRxiv and medRxiv API (https://api.biorxiv.org), Europe PMC search and the servers' PDF files, public and read-only. Arguments and results keep the providers' native field names.
type Options = {[string]: any}
type Server = {name: string, site: string, categories: {string}}

local API = "https://api.biorxiv.org"
local EUROPE_PMC = "https://www.ebi.ac.uk/europepmc/webservices/rest/search"
-- Houston ends a call after 30 s and the sandbox has no clock, so each request gets a fixed share of 27 s as
-- {total, body}. The bioRxiv API prepares a whole page before its headers (0.3 to 3.5 s, up to 8 s when busy) and
-- then sends its 70 to 230 KB within 1.5 s; it serves about three requests at a time. A call reading one answer or
-- file gives the body 19 s, enough for the slowest Europe PMC answers and PDFs. A date range gives its first page 15 s
-- whatever the limit, then reads up to three more pages at once in the remaining 12 s.
local MAX_BYTES = 4 * 1024 * 1024
local CALL, FIRST = table.freeze({27000, 19000}), table.freeze({15000, 7000})
local LATER = table.freeze({CALL[1] - FIRST[1], 3000})
local MAX_PAGES = 1 + 3
-- The API serves fixed pages: 30 preprints, or 100 published-article links.
local DETAILS_PAGE, PUBS_PAGE = 30, 100
local MAX_CURSOR = 2 ^ 31 - 1
local MAX_QUERY, DEFAULT_SEARCH = 2000, 25
-- Upper bounds of one Europe PMC record's average size in bytes, which cap limit within the byte budget. 250 highly
-- cited core records with large author lists took 2.75 MB (11 KB each, up to 72 KB) and 17.7 s; lite records stay under
-- 1.4 KB. Europe PMC serves at most 1,000 records a page.
local RECORD_BYTES: {[string]: number} = table.freeze({core = 40 * 1024, lite = 4 * 1024})
local MAX_SEARCH: {[string]: number} = table.freeze({core = math.min(1000, MAX_BYTES // RECORD_BYTES.core),
	lite = math.min(1000, MAX_BYTES // RECORD_BYTES.lite)})
local SORTS = table.freeze({"relevance", "FIRST_PDATE_D desc", "FIRST_PDATE_D asc", "CITED desc"})
local RESULT_TYPES = table.freeze({"core", "lite"})

local function names(list: string): {string}
	return table.freeze(string.split(list, ", "))
end

local SERVERS: {[string]: Server} = table.freeze({
	biorxiv = {name = "bioRxiv", site = "https://www.biorxiv.org", categories = names("animal behavior and cognition, "
		.. "biochemistry, bioengineering, bioinformatics, biophysics, cancer biology, cell biology, developmental biology, "
		.. "ecology, evolutionary biology, genetics, genomics, immunology, microbiology, molecular biology, neuroscience, "
		.. "paleontology, pathology, pharmacology and toxicology, physiology, plant biology, "
		.. "scientific communication and education, synthetic biology, systems biology, zoology")},
	medrxiv = {name = "medRxiv", site = "https://www.medrxiv.org", categories = names("addiction medicine, "
		.. "allergy and immunology, anesthesia, cardiovascular medicine, dentistry and oral medicine, dermatology, "
		.. "emergency medicine, endocrinology, epidemiology, forensic medicine, gastroenterology, "
		.. "genetic and genomic medicine, geriatric medicine, health economics, health informatics, health policy, "
		.. "health systems and quality improvement, hematology, hiv aids, infectious diseases, "
		.. "intensive care and critical care medicine, medical education, medical ethics, nephrology, neurology, nursing, "
		.. "nutrition, obstetrics and gynecology, occupational and environmental health, oncology, ophthalmology, "
		.. "orthopedics, otolaryngology, pain medicine, palliative medicine, pathology, pediatrics, "
		.. "pharmacology and therapeutics, primary care research, psychiatry and clinical psychology, "
		.. "public and global health, radiology and imaging, rehabilitation medicine and physical therapy, "
		.. "respiratory medicine, rheumatology, sexual and reproductive health, sports medicine, surgery, toxicology, "
		.. "transplantation, urology")},
} :: {[string]: Server})

local function finite(value: any): boolean
	return type(value) == "number" and value == value and math.abs(value) < 2 ^ 53
end

local function integer(value: any, field: string, minimum: number, maximum: number): number
	if not (finite(value) and value % 1 == 0 and value >= minimum and value <= maximum) then
		error(field .. " must be an integer from " .. string.format("%d", minimum) .. " to " .. string.format("%d", maximum), 0)
	end
	return value
end

local function choice(value: any, field: string, values: {string}): string
	if not (type(value) == "string" and table.find(values, value)) then error(field .. " must be one of " .. table.concat(values, ", "), 0) end
	return value
end

local function options(value: any, operation: string): Options
	if type(value) ~= "table" then error(operation .. " takes one options table", 0) end
	return table.clone(value :: Options)
end

local function noneLeft(args: Options, operation: string)
	local unknown = next(args)
	if unknown ~= nil then error(operation .. " received an unknown option " .. string.sub(tostring(unknown), 1, 64), 0) end
end

local function take(args: Options, field: string): any
	local value = args[field]
	args[field] = nil
	return value
end

-- Takes an option, or its default when it is absent; false is a value, so it is rejected later.
local function optional(args: Options, field: string, default: any): any
	local value = take(args, field)
	return if value == nil then default else value
end

local function server(args: Options): (string, Server)
	local key = take(args, "server")
	assert(type(key) == "string" and SERVERS[key], "server must be biorxiv or medrxiv")
	return key, SERVERS[key]
end

-- A preprint DOI is 10.1101/ or 10.64898/ followed by digits and dots, such as 10.1101/2025.03.20.644356.
local function preprintDoi(value: any): string?
	local prefix, suffix = string.match(if type(value) == "string" then value else "", "^10%.(%d+)/(%d[%d%.]*)$")
	return if (prefix == "1101" or prefix == "64898") and #(suffix :: string) <= 40 and string.sub(suffix :: string, -1) ~= "."
		then value else nil
end

local function doi(value: any): string
	local id = preprintDoi(value)
	if not id then
		error("doi must be a bare bioRxiv or medRxiv DOI such as 10.1101/339747 or 10.64898/2026.10.15.759504, without a "
			.. "version, doi: or https://doi.org/", 0)
	end
	return id
end

local DAYS = table.freeze({31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31})

-- A real YYYY-MM-DD date; the API answers other dates with an error or nothing.
local function date(value: any, field: string): string
	local y, m, d = string.match(if type(value) == "string" then value else "", "^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
	local year, month, day = tonumber(y), tonumber(m), tonumber(d)
	local leap = year and year % 4 == 0 and (year % 100 ~= 0 or year % 400 == 0)
	local days = if month and month >= 1 and month <= 12 then DAYS[month] + (if month == 2 and leap then 1 else 0) else nil
	if not (year and days and day and day >= 1 and day <= days) then error(field .. " must be a date such as 2025-03-21", 0) end
	return value
end

local function range(args: Options): (string, string)
	local from, to = take(args, "from"), take(args, "to")
	assert(from ~= nil and to ~= nil, "from and to go together")
	assert(date(from, "from") <= date(to, "to"), "from must not be after to")
	return from, to
end

local function errorCode(err: any): any
	return if type(err) == "table" then err.code else nil
end

local function fail(operation: string, status: number?, retryable: boolean, message: string): never
	return houston.fail({operation = operation, layer = "upstream", upstream_status = status, retryable = retryable,
		message = message})
end

local function seconds(ms: number): string
	return string.format("%g", ms / 1000) .. " s"
end

-- houston.fail repairs a character split by the cut.
local function tidy(message: string): string
	return string.sub(string.match(string.gsub(message, "%s+", " "), "^ ?(.-) ?$") :: string, 1, 300)
end

-- Europe PMC reports errors as {errCode, errMsg}; other error bodies, such as HTML or Cloudflare pages, are never shown.
local function failure(operation: string, provider: string, response: HttpResponse, time: {number}, hint: string?): never
	local status = response.statusCode
	local detail = ""
	if status >= 300 and status < 400 then
		response.body:close()
		detail = "unexpected redirect"
	else
		-- An error body that stalls or breaks counts as empty.
		local read, prefix = pcall(function() return await(response.body:readPrefix(4096), time[2]) end)
		-- readPrefix closes the body; after a failed read, close it explicitly.
		if not read then pcall(function() response.body:close() end) end
		if not read and errorCode(prefix) == "cancelled" then error(prefix, 0) end
		local ok, decoded = false, nil
		if read and string.match(prefix, "^%s*{") then ok, decoded = pcall(json.decode, prefix) end
		if ok and type(decoded) == "table" and type(decoded.errMsg) == "string" then detail = tidy(decoded.errMsg) end
	end
	local message = provider .. " HTTP " .. tostring(status) .. (if detail == "" then "" else ": " .. detail)
	local retry = response.headers["retry-after"]
	if (status == 429 or status == 503) and retry and retry[1] then
		-- Retry-After is either delay seconds or an HTTP date.
		local value = string.sub(retry[1], 1, 32)
		message ..= "; retry after " .. value .. (if string.match(value, "^%d+$") then "s" else "")
	end
	-- Input is validated first, so 4xx answers other than 429 are final.
	return fail(operation, status, status == 429 or status >= 500, message .. (if hint then hint else ""))
end

-- Sends a GET whose headers must arrive within time[1] - time[2].
local function send(operation: string, provider: string, target: string, accept: string, time: {number}): HttpResponse
	local sent, response = pcall(function()
		return await(http.request({method = "GET", url = target, headers = {Accept = {accept}}, timeoutMs = time[1] - time[2]}))
	end)
	if not sent then
		if errorCode(response) ~= "timeout" then error(response, 0) end
		fail(operation, nil, true, provider .. " did not answer within " .. seconds(time[1] - time[2]) .. "; retry")
	end
	return response
end

-- Decodes a JSON object; the anchored check is cheap, so a large page that is not JSON is never decoded.
local function decode(operation: string, provider: string, raw: string): any
	local ok, value = false, nil
	if string.match(raw, "^%s*{") then ok, value = pcall(json.decode, raw) end
	if not ok or type(value) ~= "table" then fail(operation, 200, false, provider .. " returned an invalid JSON object") end
	return value
end

-- Reads and decodes a JSON object of at most budget bytes; tooMuch says why a smaller answer cannot be had.
local function fetch(operation: string, provider: string, target: string, time: {number}, budget: number, tooMuch: string,
	hint: string?): (any, number)
	local response = send(operation, provider, target, "application/json", time)
	if response.statusCode ~= 200 then failure(operation, provider, response, time, hint) end
	local read, raw = pcall(function() return await(response.body:readAll(budget), time[2]) end)
	if not read then
		local code = errorCode(raw)
		if code == "limit_exceeded" then
			fail(operation, 200, false, provider .. " returned more data than one call can hold; " .. tooMuch)
		elseif code == "timeout" then
			fail(operation, 200, true, provider .. " did not finish sending its answer within " .. seconds(time[2]) .. "; retry")
		elseif code == "cancelled" then
			error(raw, 0)
		end
		local detail = if type(raw) == "table" and type(raw.message) == "string" then raw.message else tostring(raw)
		fail(operation, 200, true, provider .. " response failed: " .. string.sub(detail, 1, 300))
	end
	return decode(operation, provider, raw), #raw
end

-- Statuses the API reports, always with HTTP 200, for input it rejects.
local REJECTIONS = table.freeze({"must be", "not recognized", "not recognizable", "not found"})

-- Reads an API answer: {status = "ok", collection} on success, or a status text such as "no posts found". Returns the
-- collection and message, or nil when the status is one of empty's answers for no rows.
local function apiAnswer(operation: string, body: any, empty: (string) -> boolean): (any, any)
	local message = if type(body.messages) == "table" then body.messages[1] else nil
	local status = if type(message) == "table" then message.status else nil
	if type(status) ~= "string" or type(body.collection) ~= "table" then
		fail(operation, 200, false, "bioRxiv API returned an unexpected answer")
	end
	if status == "ok" then return body.collection, message end
	if empty(status) then return nil, message end
	local lower = string.lower(status)
	local rejected = false
	for _, phrase in REJECTIONS do rejected = rejected or string.find(lower, phrase, 1, true) ~= nil end
	return fail(operation, 200, not rejected, "bioRxiv API: " .. tidy(status))
end

local function apiPage(operation: string, target: string, time: {number}, empty: (string) -> boolean, tooMuch: string): (any, any, number)
	local body, bytes = fetch(operation, "bioRxiv API", target, time, MAX_BYTES, tooMuch)
	local rows, message = apiAnswer(operation, body, empty)
	return rows, message, bytes
end

local function pdfUrl(site: string, id: string, version: string): string
	return site .. "/content/" .. id .. "v" .. version .. ".full.pdf"
end

-- Copies a decoded list into a JSON array, so an empty one still encodes as [].
local function array(list: any): any
	local out = json.decode("[]")
	for _, item in list do table.insert(out, item) end
	return out
end

-- Adds each version's PDF address, which the API does not return.
local function withPdf(rows: any, site: string): any
	for _, row in rows do
		if type(row) == "table" and preprintDoi(row.doi) and type(row.version) == "string" and string.match(row.version, "^%d+$") then
			row.pdf_url = pdfUrl(site, row.doi, row.version)
		end
	end
	return rows
end

local function noPosts(status: string): boolean
	return status == "no posts found"
end

-- Reads up to pages later pages at once, from offset start, and returns their answers in order until the first that
-- fails. They share the time and the bytes left: each request's own timeout bounds its headers, and the bodies get one
-- deadline together.
local function laterPages(operation: string, target: (number) -> string, start: number, size: number, pages: number,
	budget: number): {any}
	local requests: {{any}} = {}
	for page = 1, pages do
		requests[page] = {pcall(function()
			return http.request({method = "GET", url = target(start + (page - 1) * size),
				headers = {Accept = {"application/json"}}, timeoutMs = LATER[1] - LATER[2]})
		end)}
	end
	-- Every operation is observed, so no failure goes unhandled; only the leading run of 200 answers is read.
	local responses: {HttpResponse} = {}
	for page = 1, pages do
		local ok, response = requests[page][1], requests[page][2]
		if ok then ok, response = pcall(await, response) end
		if ok and response.statusCode == 200 and #responses == page - 1 then
			table.insert(responses, response)
		elseif ok then
			response.body:close()
		elseif errorCode(response) == "cancelled" then
			error(response, 0)
		end
	end
	local reads: {any} = {}
	-- Reads start only while every earlier page started; the bodies after a failure are closed unread.
	for page, response in responses do
		local started, read = false, nil
		if #reads == page - 1 then
			started, read = pcall(function() return response.body:readAll(budget // #responses) end)
		end
		if started then table.insert(reads, read) else pcall(function() response.body:close() end) end
	end
	if #reads > 0 then
		local ok, err = pcall(awaitAll, reads, LATER[2])
		if not ok and errorCode(err) == "cancelled" then error(err, 0) end
	end
	local answers: {any} = {}
	for page = 1, #reads do
		-- A zero wait returns a settled read and cancels one still running.
		local ok, raw = pcall(await, reads[page], 0)
		local valid, body = false, nil
		if ok then valid, body = pcall(decode, operation, "bioRxiv API", raw) end
		if valid and #answers == page - 1 then table.insert(answers, body) end
	end
	return answers
end

-- Reads a date range from cursor within limit rows, the byte budget and the call time. The first page gets the same
-- time whatever the limit, so asking for more rows never fails a call that one page would complete; the rest are read
-- at once in the time left, and a failure among them returns the rows so far with next_cursor.
local function collect(operation: string, args: Options, path: string, query: string, size: number, site: string?): Options
	local cursor = integer(optional(args, "cursor", 0), "cursor", 0, MAX_CURSOR)
	local limit = integer(optional(args, "limit", size), "limit", 1, size * MAX_PAGES)
	noneLeft(args, operation)
	local function target(offset: number): string
		return API .. path .. "/" .. string.format("%d", offset) .. query
	end
	local rows = json.decode("[]")
	local result: Options = {collection = rows}
	local found, message, used = apiPage(operation, target(cursor), FIRST, noPosts,
		"the API's page of " .. tostring(size) .. " is too large for one call")
	-- No posts: the range is empty, or cursor is at or past its end, and the API reports no total.
	if found == nil then return result end
	local total = tonumber(message.total) or math.huge
	if not finite(total) then fail(operation, 200, false, "bioRxiv API returned a page without its total") end
	result.total = total
	local fresh = tonumber(message.count_new_papers)
	if finite(fresh) then result.count_new_papers = fresh end
	-- Adds a page's rows up to limit and tells whether the range goes on.
	local function add(page: any): boolean
		for _, row in page do
			if #rows >= limit then break end
			table.insert(rows, row)
		end
		return #page > 0
	end
	local going = add(found)
	local start = cursor + #rows
	if going and #rows < limit and start < total then
		local pages = math.min(MAX_PAGES - 1, math.ceil(math.min(limit - #rows, total - start) / size))
		for _, body in laterPages(operation, target, start, size, pages, MAX_BYTES - used) do
			local valid, later, reported = pcall(apiAnswer, operation, body, noPosts)
			if not valid or (later and not finite(tonumber(reported.total))) then break end
			going = later ~= nil and add(later)
			if not going then break end
		end
	end
	if site then withPdf(rows, site) end
	if going and cursor + #rows < total then result.next_cursor = cursor + #rows end
	return result
end

local function category(args: Options, entry: Server): string
	local value = take(args, "category")
	if value == nil then return "" end
	local name = if type(value) == "string" then string.gsub(string.lower(value), "_", " ") else ""
	if not table.find(entry.categories, name) then
		error("category must be one of the " .. entry.name .. " categories: " .. table.concat(entry.categories, ", "), 0)
	end
	return "?category=" .. string.gsub(name, " ", "_")
end

-- A ROR ID's last 9 characters: 0, six lowercase letters or digits, and a two-digit checksum.
local function funder(value: any): string
	local id = if type(value) == "string" then string.match(value, "^https://ror%.org/(.*)$") or value else ""
	assert(string.match(id, "^0[%l%d][%l%d][%l%d][%l%d][%l%d][%l%d]%d%d$"),
		"funder must be a ROR ID such as 00k4n6c32 or https://ror.org/00k4n6c32")
	return id
end

local function listPreprints(input: any): Options
	local args = options(input, "listPreprints")
	local key, entry = server(args)
	local from, to = range(args)
	local query = "/json" .. category(args, entry)
	local ror = take(args, "funder")
	local path = if ror == nil then "/details/" .. key .. "/" .. from .. "/" .. to
		else "/funder/" .. key .. "/" .. from .. "/" .. to .. "/" .. funder(ror)
	return collect("listPreprints", args, path, query, DETAILS_PAGE, entry.site)
end

local function getPreprint(input: any): Options
	local args = options(input, "getPreprint")
	local key, entry = server(args)
	local id = doi(take(args, "doi"))
	noneLeft(args, "getPreprint")
	local rows = apiPage("getPreprint", API .. "/details/" .. key .. "/" .. id .. "/na/json", CALL, noPosts,
		"this preprint's versions are too large for one call")
	if rows == nil then
		fail("getPreprint", 200, false, entry.name .. " has no preprint with DOI " .. id
			.. "; check the server, since bioRxiv and medRxiv DOIs share the 10.1101 prefix")
	end
	return {collection = withPdf(array(rows), entry.site)}
end

-- A DOI with one slash, such as 10.1371/journal.pone.0256482 or 10.1016/S0140-6736(20)30183-5, as a path whose suffix
-- is URL-encoded. The API reads the DOI from two path segments, so it cannot look up a suffix containing a slash.
local function anyDoi(value: any): string
	local prefix, suffix = string.match(if type(value) == "string" and #value <= 200 then value else "", "^(10%.%d%d%d%d+)/([%w%-%._;:()<>%[%]+]+)$")
	if not prefix or string.match(suffix :: string, "^%.+$") then
		error("doi must be a bare DOI with one slash, such as 10.1101/339747 or 10.1016/S0140-6736(20)30183-5; the API cannot "
			.. "look up DOIs with several slashes", 0)
	end
	return prefix .. "/" .. url.encode(suffix :: string)
end

-- "no articles found for published version of ..." (a preprint not yet published) and "Preprint for DOI ... not found"
-- (an article without a preprint) are both answers without a link.
local function unlinked(status: string): boolean
	return string.find(status, "^no articles found") ~= nil or string.find(status, "^Preprint for DOI .* not found$") ~= nil
end

local function getPublication(input: any): Options
	local args = options(input, "getPublication")
	local key = server(args)
	local id = anyDoi(take(args, "doi"))
	noneLeft(args, "getPublication")
	local rows = apiPage("getPublication", API .. "/pubs/" .. key .. "/" .. id .. "/na/json", CALL, unlinked,
		"this link is too large for one call")
	return {collection = if rows then array(rows) else json.decode("[]")}
end

local function listPublications(input: any): Options
	local args = options(input, "listPublications")
	local key = server(args)
	local from, to = range(args)
	return collect("listPublications", args, "/pubs/" .. key .. "/" .. from .. "/" .. to, "", PUBS_PAGE, nil)
end

-- Checks that a query's parentheses and quotes are balanced, so it cannot escape the preprint filter around it.
local function balanced(query: string): boolean
	local depth, quoted, escaped = 0, false, false
	for index = 1, #query do
		local char = string.sub(query, index, index)
		if escaped then
			escaped = false
		elseif char == "\\" then
			escaped = true
		elseif char == '"' then
			quoted = not quoted
		elseif not quoted and char == "(" then
			depth += 1
		elseif not quoted and char == ")" then
			depth -= 1
			if depth < 0 then return false end
		end
	end
	return depth == 0 and not quoted and not escaped
end

local function searchPreprints(input: any): Options
	local args = options(input, "searchPreprints")
	local query = take(args, "query")
	if not (type(query) == "string" and string.find(query, "%S") and #query <= MAX_QUERY) then
		error("query must be a Europe PMC query of at most " .. tostring(MAX_QUERY) .. " bytes, not only spaces", 0)
	end
	assert(balanced(query), "query must balance its parentheses and double quotes")
	local full = "(" .. query .. ") AND SRC:PPR AND "
	if args.server == nil then
		full ..= '(PUBLISHER:"bioRxiv" OR PUBLISHER:"medRxiv")'
	else
		local _, entry = server(args)
		full ..= 'PUBLISHER:"' .. entry.name .. '"'
	end
	if args.from ~= nil or args.to ~= nil then
		local from, to = range(args)
		full ..= " AND FIRST_PDATE:[" .. from .. " TO " .. to .. "]"
	end
	local sort = take(args, "sort")
	if sort ~= nil then choice(sort, "sort", SORTS) end
	local resultType = choice(optional(args, "resultType", "core"), "resultType", RESULT_TYPES)
	local limit = integer(optional(args, "limit", DEFAULT_SEARCH), "limit", 1, MAX_SEARCH[resultType])
	local cursorMark = take(args, "cursorMark")
	assert(cursorMark == nil or (type(cursorMark) == "string" and #cursorMark <= 256 and string.match(cursorMark, "^[%w+/=*]+$")),
		"cursorMark must be the nextCursorMark of an earlier searchPreprints result")
	noneLeft(args, "searchPreprints")
	local target = EUROPE_PMC .. "?query=" .. url.encode(full) .. "&resultType=" .. resultType .. "&pageSize=" .. tostring(limit)
		.. "&format=json&cursorMark=" .. url.encode(cursorMark or "*")
		.. (if sort and sort ~= "relevance" then "&sort=" .. url.encode(sort) else "")
	-- Europe PMC answers an unusable cursorMark with a 503 "temporarily unavailable".
	local body = fetch("searchPreprints", "Europe PMC", target, CALL, MAX_BYTES,
		"call again with a lower limit or resultType lite",
		if cursorMark then "; if this persists, the cursorMark may not belong to this query: search again without it" else nil)
	local list = if type(body.resultList) == "table" then body.resultList.result else nil
	if not finite(body.hitCount) or type(list) ~= "table" then
		fail("searchPreprints", 200, false, "Europe PMC returned an unexpected answer")
	end
	local results = array(list)
	local result: Options = {hitCount = body.hitCount, results = results}
	-- Europe PMC returns a cursor after every full page, the last one included.
	if #results == limit and type(body.nextCursorMark) == "string" and body.nextCursorMark ~= cursorMark then
		result.nextCursorMark = body.nextCursorMark
	end
	return result
end

local function downloadPdf(input: any): Options
	local args = options(input, "downloadPdf")
	local _, entry = server(args)
	local id = doi(take(args, "doi"))
	local version = take(args, "version")
	version = string.format("%d", integer(if type(version) == "string" and string.match(version, "^%d+$")
		then tonumber(version) else version, "version", 1, 999))
	local path = take(args, "session_path")
	assert(type(path) == "string" and path ~= "", "session_path must name a session file, such as preprint.pdf")
	noneLeft(args, "downloadPdf")
	local target = pdfUrl(entry.site, id, version)
	local browser = "; open " .. target .. " in a browser instead"
	-- Checking the session path first refuses an invalid one before any request, without creating or changing a file;
	-- the file is opened only for a PDF, so a refused download leaves an existing one unchanged.
	await(fs.exists(path))
	local response = send("downloadPdf", entry.name, target, "application/pdf", CALL)
	local status = response.statusCode
	if status ~= 200 then
		-- Cloudflare in front of both sites blocks some automated clients outright.
		local reason = if status == 403 then "blocked the automated download"
			elseif status == 404 then "has no PDF of version " .. version .. " of " .. id .. "; getPreprint lists the versions"
			elseif status >= 300 and status < 400 then "answered with an unexpected redirect"
			else nil
		if reason == nil then failure("downloadPdf", entry.name, response, CALL, browser) end
		response.body:close()
		fail("downloadPdf", status, false, entry.name .. " HTTP " .. tostring(status) .. ": " .. reason
			.. (if status == 404 then "" else browser))
	end
	local kind = response.headers["content-type"]
	if not (kind and kind[1] and string.find(string.lower(kind[1]), "pdf", 1, true)) then
		response.body:close()
		fail("downloadPdf", 200, false, entry.name .. " returned a web page instead of the PDF" .. browser)
	end
	local opened, output = pcall(function() return fs.open(path, "w") end)
	if not opened then
		response.body:close()
		error(output, 0)
	end
	output:write(response.body)
	local written, err = pcall(function() await(output:close(), CALL[2]) end)
	if not written then
		local code = errorCode(err)
		if code == "timeout" then
			fail("downloadPdf", 200, true, entry.name .. " did not finish sending the PDF within " .. seconds(CALL[2]) .. "; retry")
		elseif code == "cancelled" then
			error(err, 0)
		end
		local detail = if type(err) == "table" and type(err.message) == "string" then err.message else tostring(err)
		fail("downloadPdf", 200, true, entry.name .. " download failed: " .. string.sub(detail, 1, 300))
	end
	return {session_path = path, url = await(fs.signedGetUrl(path)), size = await(fs.stat(path)).size, pdf_url = target}
end

local function help(): string
	local categories: {string} = {}
	for _, key in {"biorxiv", "medrxiv"} do
		table.insert(categories, "- " .. key .. ": " .. table.concat(SERVERS[key].categories, ", ") .. ".")
	end
	local details = tostring(DETAILS_PAGE * MAX_PAGES)
	local pubs = tostring(PUBS_PAGE * MAX_PAGES)
	return [[bioRxiv and medRxiv: search and read preprints in biology (bioRxiv) and health sciences (medRxiv) through the servers' public API (https://api.biorxiv.org), with keyword search powered by Europe PMC (https://europepmc.org, EMBL-EBI), and download their PDFs. No account or credentials. Read-only. Calls return completed values; do not wrap them in await(). Every function takes one options table; unknown options are rejected. Results keep the providers' field names and values. Preprints are not peer reviewed; each carries its own license (the license field, such as cc_by or cc_no). Credit bioRxiv or medRxiv, and Europe PMC for search results.

server is "biorxiv" or "medrxiv"; both servers share the 10.1101 DOI prefix, and recent preprints use 10.64898. doi is a bare preprint DOI such as 10.1101/339747 or 10.64898/2026.10.15.759504, without a version suffix, doi: or https://doi.org/. Dates are real YYYY-MM-DD dates, with from not after to.

## searchPreprints({query, server?, from?, to?, sort?, resultType?, limit?, cursorMark?})

Europe PMC search, restricted to bioRxiv and medRxiv preprints (both unless server is given); the API itself has no search. Europe PMC is current to about a day ago. Returns `{hitCount, results, nextCursorMark?}`. Each result has id (a Europe PMC PPR ID), doi, title, authorString, pubYear, firstPublicationDate, bookOrReportDetails.publisher ("bioRxiv" or "medRxiv"; lowercased it is the server for the other functions) and, with resultType "core" (the default), abstractText, authorList, license, citedByCount and more; "lite" leaves out abstracts and author details.
- query: Europe PMC syntax, at most ]] .. tostring(MAX_QUERY) .. [[ bytes with balanced parentheses and quotes, for example `crispr AND "base editing"`, `TITLE:"single-cell" AND AUTH:"Smith J"`, `ABSTRACT:zebrafish` or `DOI:"10.1101/2021.10.22.465130"`. AND, OR and NOT must be capitalized.
- from and to together filter firstPublicationDate, when Europe PMC first listed the preprint.
- sort: ]] .. table.concat(SORTS, ", ") .. [[ (relevance by default; CITED desc puts the most cited first).
- limit: results to return, 1 to ]] .. tostring(MAX_SEARCH.core) .. [[ with resultType core and 1 to ]] .. tostring(MAX_SEARCH.lite) .. [[ with lite, which fit one call (default ]] .. tostring(DEFAULT_SEARCH) .. [[). For the next page, call again with the same options and cursorMark = nextCursorMark. nextCursorMark is present after every full page while results may remain: when the last results exactly fill limit, continuing returns no results and no nextCursorMark.
Europe PMC lists one record per preprint: read its versions and the full abstract with getPreprint.

## listPreprints({server, from, to, category?, funder?, limit?, cursor?})

Preprint versions posted from from to to, inclusive. A revised version of an older preprint appears on the date it was posted. Returns `{collection, total?, count_new_papers?, next_cursor?}`: total counts the versions in the range, count_new_papers its first versions. When the API finds no posts from cursor on (an empty range, or a cursor at or past its end) it reports no total, so collection is empty and total absent. Each version has doi, title, authors ("Last, F.; ..."), author_corresponding, author_corresponding_institution, date, version (a string), type, license, category, abstract, jatsxml (the JATS XML address on the server's website), published (the journal DOI, or "NA") and server, plus pdf_url, the address of its PDF, added by Houston. date may lack zero padding, as in 2026-8-17.
- category: one of the server's categories below (underscores accepted for spaces); the API would silently ignore any other.
- funder: a ROR ID such as 00k4n6c32 (European Commission) or https://ror.org/00k4n6c32, to list only preprints declaring that funder; versions then also carry funder, an array of {name, id, id-type, award}. Funder data starts on 2025-04-10.
- limit: versions to return, 1 to ]] .. details .. [[ (default ]] .. tostring(DETAILS_PAGE) .. [[). The API serves pages of ]] .. tostring(DETAILS_PAGE) .. [[: a call reads the first, then up to ]] .. tostring(MAX_PAGES - 1) .. [[ more at once. cursor: versions to skip (default 0). For the next page, call again with the same options and cursor = next_cursor. next_cursor is present while cursor plus the versions returned is below total; a call can return fewer than limit versions when a later page is slow, too large or fails, and next_cursor then continues after them. A month of bioRxiv holds about 7,000 versions, so narrow with category or a short range, or use searchPreprints.

## getPreprint({server, doi})

Every version of one preprint, oldest first: `{collection}` with the fields of listPreprints. A DOI unknown to that server fails as not found; check the server.

## getPublication({server, doi})

The journal article a preprint became: `{collection}` with at most one link {preprint_doi, published_doi, published_journal, preprint_platform, preprint_title, preprint_authors, preprint_category, preprint_date, published_date, preprint_abstract, preprint_author_corresponding, preprint_author_corresponding_institution}, or an empty collection when there is none. The API answers alike when the preprint is not published yet, when no preprint matches an article DOI, and when a preprint DOI belongs to the other server (both share 10.1101), so check the server with getPreprint before reading an empty collection as unpublished. doi is the preprint's DOI or the article's own DOI (such as 10.1016/S0140-6736(20)30183-5), which finds the preprint of an article; the API cannot look up DOIs with several slashes, such as 10.1093/nar/gkaf118.

## listPublications({server, from, to, limit?, cursor?})

Preprints whose journal article was recorded from from to to: `{collection, total?, next_cursor?}` of the links getPublication returns. limit: 1 to ]] .. pubs .. [[ (default ]] .. tostring(PUBS_PAGE) .. [[), in pages of ]] .. tostring(PUBS_PAGE) .. [[; cursor and next_cursor work as in listPreprints.

## downloadPdf({server, doi, version, session_path})

Saves the PDF of one version (an integer, or listPreprints' version string) to the session file session_path and returns `{session_path, url, size, pdf_url}`: url is a signed link to the saved file, pdf_url the PDF's address on the server's website. The website is behind Cloudflare, which limits and blocks automated downloads: HTTP 429 fails as retryable with the wait it asks (often one or two minutes), and HTTP 403, which medRxiv answers to automated PDF downloads, fails as not retryable. Either way, give people pdf_url to open in a browser. A refused download leaves session_path unchanged; one that breaks while the PDF streams can leave a partial file there.

## Errors and limits

Invalid input fails before any request. Provider errors come back as upstream errors with the HTTP status and message; HTTP 429 and 5xx are retryable. The API answers HTTP 200 even to errors and reports them as a status, which comes back as the message. Each call reads at most ]] .. tostring(MAX_BYTES // 1048576) .. [[ MiB of JSON and has ]] .. seconds(CALL[1]) .. [[: a call reading one answer or file gives its headers ]] .. seconds(CALL[1] - CALL[2]) .. [[ and its body ]] .. seconds(CALL[2]) .. [[. A date range gives its first page ]] .. seconds(FIRST[1]) .. [[ whatever the limit (]] .. seconds(FIRST[1] - FIRST[2]) .. [[ for headers), so a larger limit never fails a call that one page would complete, and reads the later pages at once in the remaining ]] .. seconds(LATER[1]) .. [[. A call that runs out of time before it has any result fails as retryable; the API's page sizes are fixed, so a lower limit does not help then.

Categories:
]] .. table.concat(categories, "\n") .. [[


## Example

Here rxiv is the configured bioRxiv and medRxiv connection.

```lua
local found = rxiv.searchPreprints({query = 'TITLE:"base editing"', server = "biorxiv", sort = "FIRST_PDATE_D desc", limit = 10})
print(found.hitCount)
if #found.results == 0 then return end
local hit = found.results[1]
local versions = rxiv.getPreprint({server = string.lower(hit.bookOrReportDetails.publisher), doi = hit.doi}).collection
local latest = versions[#versions]
print(latest.title, latest.version, latest.date, latest.published, latest.pdf_url)
print(latest.abstract)

local page = rxiv.listPreprints({server = "medrxiv", from = "2025-03-01", to = "2025-03-07", category = "epidemiology", limit = 90})
for _, preprint in page.collection do print(preprint.doi, preprint.version, preprint.title) end
-- More: rxiv.listPreprints({server = "medrxiv", from = "2025-03-01", to = "2025-03-07", category = "epidemiology",
--	limit = 90, cursor = page.next_cursor}) while page.next_cursor.

local ok, saved = pcall(rxiv.downloadPdf, {server = "biorxiv", doi = latest.doi, version = latest.version, session_path = "preprint.pdf"})
print(if ok then saved.url else "Open " .. latest.pdf_url)
```]]
end

return {searchPreprints = searchPreprints, listPreprints = listPreprints, getPreprint = getPreprint,
	getPublication = getPublication, listPublications = listPublications, downloadPdf = downloadPdf, help = help}
