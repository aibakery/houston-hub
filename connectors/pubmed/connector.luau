-- NCBI E-utilities for PubMed and the BioC API for PMC open-access full text, public and read-only. Arguments and results keep NCBI's native field names.
type Options = {[string]: any}

local EUTILS = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/"
local BIOC = "https://www.ncbi.nlm.nih.gov/research/bionlp/RESTful/pmcoa.cgi/BioC_json/"
-- NCBI asks each request to name the software and its developer's contact address, never an end user's.
local CONTACT = "tool=houston&email=" .. url.encode("hello@ok-houston.com")
-- Each call makes one request. Houston ends a call after 30 s and the sandbox has no clock, so a fixed split of
-- 27 s gives the response body, an error body included, 19 s and the headers the rest. NCBI sends headers within
-- 0.3 s and then streams the body: 1.7 s for 200 MEDLINE records, 0.1 s per PMID for ELink, which gives up after
-- about 15 s with an empty 200; the 8 s for headers leave room for Houston's two short waits after an HTTP 429.
local CALL_TIME, BODY_TIME = 27000, 19000
local MAX_BYTES = 4 * 1024 * 1024
local MAX_IDS, MAX_LINK_IDS, MAX_TERM, DEFAULT_RETMAX = 200, 100, 4000, 20
-- PubMed returns only the first 9,999 matches of a search.
local MAX_RESULTS = 9999
local SORTS = table.freeze({"relevance", "pub_date", "Author", "JournalName"})
local DATETYPES = table.freeze({"edat", "pdat", "mdat"})
-- Link names to PubMed and PMC records, in help order, with what each returns.
local LINKS = table.freeze({
	{"pubmed_pubmed", "similar articles, most similar first; the list can include the article itself"},
	{"pubmed_pubmed_reviews", "similar review articles"},
	{"pubmed_pubmed_citedin", "PubMed articles citing it, from reference lists deposited in PMC, highest PMID (newest) first"},
	{"pubmed_pubmed_refs", "the PubMed articles it cites, when its reference list is in PMC"},
	{"pubmed_pmc", "its PMC copy, as a PMC number without the PMC prefix (getFullText takes \"PMC\" .. number)"},
	{"pubmed_pmc_refs", "PMC articles citing it, as PMC numbers"},
})
local LINK_NAMES: {[string]: boolean}, linkNames: {string} = {}, {}
for _, link in LINKS do
	LINK_NAMES[link[1]] = true
	table.insert(linkNames, link[1])
end
local LINK_LIST = table.concat(linkNames, ", ")
-- MEDLINE tags that occur at most once per record come back as strings; every other tag is an array of strings.
local SINGLE_TAGS = "PMID OWN STAT DCOM LR VI IP DP TI BTI VTI TT PG AB CI JT TA JID PL EDAT MHDA CRDT PST SO PMC DEP"
local SINGLE: {[string]: boolean} = {}
for tag in string.gmatch(SINGLE_TAGS, "%S+") do SINGLE[tag] = true end
-- Tags that describe the author named by the FAU or AU line before them.
local AUTHOR = table.freeze({FAU = true, AU = true, AUID = true, AD = true})

local function finite(value: any): boolean
	return type(value) == "number" and value == value and math.abs(value) < 2 ^ 53
end

local function integer(value: any, field: string, minimum: number, maximum: number): number
	assert(finite(value) and value % 1 == 0 and value >= minimum and value <= maximum,
		field .. " must be an integer from " .. tostring(minimum) .. " to " .. tostring(maximum))
	return value
end

local function choice(value: any, field: string, values: {string}): string
	assert(type(value) == "string" and table.find(values, value), field .. " must be one of " .. table.concat(values, ", "))
	return value
end

local function options(value: any, operation: string): Options
	assert(value == nil or type(value) == "table", operation .. " options must be a table")
	return table.clone((value or {}) :: Options)
end

local function noneLeft(args: Options, operation: string)
	local unknown = next(args)
	assert(unknown == nil, operation .. " received an unknown option " .. string.sub(tostring(unknown), 1, 64))
end

-- A PMID is a positive integer of at most 9 digits, given as a number or a string.
local function pmid(value: any): string?
	local id = if finite(value) and value % 1 == 0 then string.format("%d", value) elseif type(value) == "string" then value else ""
	return if #id <= 9 and string.match(id, "^[1-9]%d*$") then id else nil
end

-- Takes one PMID, an array of them or one string separated by commas or spaces; drops repeats and keeps the order.
local function pmids(value: any, maximum: number): {string}
	local items: {any} = {}
	if type(value) == "string" then
		for item in string.gmatch(value, "[^,%s]+") do table.insert(items, item) end
	elseif type(value) == "table" then
		for index, item in value do
			assert(index == #items + 1, "ids must be a dense array")
			table.insert(items, item)
		end
	else
		items = {value}
	end
	local out: {string}, seen: {[string]: boolean} = {}, {}
	for _, item in items do
		local id = pmid(item)
		assert(id, "ids must contain PMIDs, positive integers such as 31452104")
		if not seen[id] then
			seen[id] = true
			table.insert(out, id)
		end
	end
	assert(#out > 0 and #out <= maximum, "ids must list 1 to " .. tostring(maximum) .. " PMIDs")
	return out
end

local function errorCode(err: any): any
	return if type(err) == "table" then err.code else nil
end

local function fail(operation: string, status: number?, retryable: boolean, message: string): never
	return houston.fail({operation = operation, layer = "upstream", upstream_status = status, retryable = retryable,
		message = message})
end

-- NCBI reports errors as JSON in several shapes, or as XML from efetch.
local function reported(value: any): string?
	if type(value) ~= "table" then return nil end
	local message = value.error or value.ERROR
		or (type(value.esearchresult) == "table" and value.esearchresult.ERROR)
		or (type(value.esummaryresult) == "table" and value.esummaryresult[1])
	return if type(message) == "string" then message else nil
end

-- houston.fail repairs a character split by the cut.
local function tidy(message: string): string
	return string.sub(string.match(string.gsub(message, "%s+", " "), "^ ?(.-) ?$") :: string, 1, 300)
end

-- Phrases of NCBI's messages about input it rejects, which retrying cannot fix, even inside a successful answer.
local REJECTIONS = table.freeze({"invalid", "too many", "cannot be larger", "empty term", "nothing todo", "not wellformed"})

-- Fails with an error NCBI reported in a 200 answer: a rejection is final, any other failure, such as
-- "Search Backend failed", a server fault.
local function reportedFailure(operation: string, message: string): never
	local lower = string.lower(message)
	local rejected = false
	for _, phrase in REJECTIONS do rejected = rejected or string.find(lower, phrase, 1, true) ~= nil end
	return fail(operation, 200, not rejected, "NCBI: " .. tidy(message))
end

local function reason(body: string): string
	local ok, decoded = pcall(json.decode, body)
	local message = (if ok then reported(decoded) else nil) or string.match(body, "<ERROR>(.-)</ERROR>")
	return if message then tidy(message) else ""
end

local function failure(operation: string, response: HttpResponse): never
	local status = response.statusCode
	local detail = ""
	if status >= 300 and status < 400 then
		response.body:close()
		detail = "unexpected redirect"
	else
		-- An error body that stalls or breaks counts as empty; HTML pages are never shown.
		local read, prefix = pcall(function() return await(response.body:readPrefix(4096), BODY_TIME) end)
		if not read and errorCode(prefix) == "cancelled" then error(prefix, 0) end
		if read then detail = reason(prefix) end
	end
	local message = "NCBI HTTP " .. tostring(status) .. (if detail == "" then "" else ": " .. detail)
	local retry = response.headers["retry-after"]
	if (status == 429 or status == 503) and retry and retry[1] then
		-- Retry-After is either delay seconds or an HTTP date.
		local value = string.sub(retry[1], 1, 32)
		message ..= "; retry after " .. value .. (if string.match(value, "^%d+$") then "s" else "")
	end
	-- Input is validated first, so NCBI's 4xx answers are final and its 5xx answers are server faults.
	return fail(operation, status, status == 429 or status >= 500, message)
end

-- Returns the body of a 200 response and its headers; tooMuch tells the caller how to fit the byte budget.
local function fetch(operation: string, request: Options, tooMuch: string): (string, {[string]: {string}})
	request.timeoutMs = CALL_TIME - BODY_TIME
	local sent, response = pcall(function() return await(http.request(request :: any)) end)
	if not sent then
		if errorCode(response) ~= "timeout" then error(response, 0) end
		fail(operation, nil, true, "NCBI did not answer within " .. tostring((CALL_TIME - BODY_TIME) // 1000) .. " s; retry")
	end
	if response.statusCode ~= 200 then failure(operation, response) end
	local read, raw = pcall(function() return await(response.body:readAll(MAX_BYTES), BODY_TIME) end)
	if not read then
		local code = errorCode(raw)
		if code == "limit_exceeded" then
			fail(operation, 200, false, "NCBI returned more data than one call can hold; " .. tooMuch)
		elseif code == "timeout" then
			fail(operation, 200, true, "NCBI did not finish sending its answer within " .. tostring(BODY_TIME // 1000) .. " s; retry")
		elseif code == "cancelled" then
			error(raw, 0)
		end
		local detail = if type(raw) == "table" and type(raw.message) == "string" then raw.message else tostring(raw)
		fail(operation, 200, true, "NCBI response failed: " .. string.sub(detail, 1, 300))
	end
	return raw, response.headers
end

-- Calls one E-utility, posted as a form so long ID lists and queries fit.
local function eutility(operation: string, name: string, params: {string}, tooMuch: string): string
	return (fetch(operation, {method = "POST", url = EUTILS .. name .. ".fcgi",
		headers = {["Content-Type"] = {"application/x-www-form-urlencoded"}},
		body = table.concat(params, "&") .. "&" .. CONTACT}, tooMuch))
end

local function decode(operation: string, raw: string, key: string): any
	-- ELink gives up after about 15 s and still answers 200, with an empty body.
	if not string.find(raw, "%S") then fail(operation, 200, true, "NCBI returned an empty answer; retry, or pass fewer ids") end
	local ok, value = pcall(json.decode, raw)
	if not ok or type(value) ~= "table" or not string.match(raw, "^%s*{") then
		fail(operation, 200, false, "NCBI returned an invalid JSON object")
	end
	local message = reported(value)
	if message then reportedFailure(operation, message) end
	if type(value[key]) ~= "table" then fail(operation, 200, false, "NCBI returned an unexpected answer") end
	return value[key]
end

local DAYS = table.freeze({31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31})

-- Checks a YYYY, YYYY/MM or YYYY/MM/DD date, which NCBI would otherwise answer with no matches, and returns the
-- first and last day it covers as comparable YYYY/MM/DD strings.
local function dateRange(value: any, field: string): (string, string)
	local y: any, m: any, d: any
	if type(value) == "string" then
		y = string.match(value, "^(%d%d%d%d)$")
		if not y then y, m = string.match(value, "^(%d%d%d%d)/(%d%d)$") end
		if not y then y, m, d = string.match(value, "^(%d%d%d%d)/(%d%d)/(%d%d)$") end
	end
	local year: any, month: any, day: any = tonumber(y), tonumber(m), tonumber(d)
	local leap = year and year % 4 == 0 and (year % 100 ~= 0 or year % 400 == 0)
	local days = if month and month >= 1 and month <= 12 then DAYS[month] + (if month == 2 and leap then 1 else 0) else nil
	assert(year and year >= 1 and (m == nil or days) and (d == nil or (day >= 1 and day <= days)),
		field .. " must be YYYY, YYYY/MM or YYYY/MM/DD")
	return string.format("%04d/%02d/%02d", year, month or 1, day or 1),
		string.format("%04d/%02d/%02d", year, month or 12, day or days or 31)
end

local function searchArticles(input: Options?): any
	local args = options(input, "searchArticles")
	local term = args.term
	assert(type(term) == "string" and string.find(term, "%S") and #term <= MAX_TERM,
		"term must be a PubMed query of at most " .. tostring(MAX_TERM) .. " bytes, not only spaces")
	local params = {"db=pubmed", "retmode=json", "term=" .. url.encode(term),
		"retstart=" .. tostring(integer(if args.retstart == nil then 0 else args.retstart, "retstart", 0, MAX_RESULTS - 1)),
		"retmax=" .. tostring(integer(if args.retmax == nil then DEFAULT_RETMAX else args.retmax, "retmax", 0, MAX_RESULTS))}
	if args.sort ~= nil then table.insert(params, "sort=" .. choice(args.sort, "sort", SORTS)) end
	assert((args.mindate == nil) == (args.maxdate == nil), "mindate and maxdate go together")
	if args.mindate ~= nil then
		local from = dateRange(args.mindate, "mindate")
		local _, to = dateRange(args.maxdate, "maxdate")
		assert(from <= to, "mindate must not be after maxdate")
		table.insert(params, "mindate=" .. url.encode(args.mindate))
		table.insert(params, "maxdate=" .. url.encode(args.maxdate))
	end
	if args.reldate ~= nil then table.insert(params, "reldate=" .. tostring(integer(args.reldate, "reldate", 1, 100000))) end
	if args.datetype ~= nil then
		assert(args.mindate ~= nil or args.reldate ~= nil, "datetype applies only with mindate and maxdate, or reldate")
		table.insert(params, "datetype=" .. choice(args.datetype, "datetype", DATETYPES))
	end
	for _, field in {"term", "retstart", "retmax", "sort", "mindate", "maxdate", "reldate", "datetype"} do args[field] = nil end
	noneLeft(args, "searchArticles")
	return decode("searchArticles", eutility("searchArticles", "esearch", params, "lower retmax"), "esearchresult")
end

local function idParam(ids: any): string
	return "id=" .. url.encode(table.concat(pmids(ids, MAX_IDS), ","))
end

local function getSummaries(ids: any): any
	return decode("getSummaries", eutility("getSummaries", "esummary", {"db=pubmed", "retmode=json", idParam(ids)},
		"request fewer IDs"), "result")
end

-- A tagged value and its trimmed lines, joined with single spaces as Biopython joins them.
type Field = {tag: string, lines: {string}}

local function trim(text: string): string
	return string.match(text, "^%s*(.-)%s*$") :: string
end

-- Groups a record's tagged values: authors in order, single tags as strings, other tags as arrays.
local function record(fields: {Field}): Options
	local out: Options = {}
	local authors: {Options} = {}
	local author: Options? = nil
	for _, field in fields do
		local tag, value = field.tag, table.concat(field.lines, " ")
		if tag == "FAU" or (tag == "AU" and (author == nil or author.AU ~= nil)) then
			author = {}
			table.insert(authors, author :: Options)
		end
		local target: Options = if AUTHOR[tag] and author then author else out
		if SINGLE[tag] or tag == "FAU" or tag == "AU" then
			if target[tag] == nil then target[tag] = value end
		elseif target[tag] then
			table.insert(target[tag], value)
		else
			target[tag] = {value}
		end
	end
	out.authors = if #authors > 0 then authors else json.decode("[]")
	return out
end

-- Parses MEDLINE text: empty lines separate records, a line is a tag padded to 4 characters, "- " and a value, and
-- lines indented by 6 spaces continue the value before them.
local function medline(raw: string): {Options}
	local records = json.decode("[]")
	local fields: {Field} = {}
	for _, line in string.split(raw, "\n") do
		line = string.gsub(line, "\r$", "")
		if line == "" then
			if #fields > 0 then table.insert(records, record(fields)) end
			fields = {}
		elseif not string.find(line, "%S") then
			continue
		elseif string.sub(line, 1, 6) == "      " and #fields > 0 then
			local text = trim(line)
			if text ~= "" then table.insert(fields[#fields].lines, text) end
		else
			local tag = string.match(string.sub(line, 1, 4), "^(%u[%u%d]*) *$")
			if not tag or string.sub(line, 5, 6) ~= "- " then
				local detail = reason(raw)
				fail("getRecords", 200, detail ~= "", if detail ~= "" then "NCBI: " .. detail else "NCBI returned an unexpected MEDLINE record")
			end
			local text = trim(string.sub(line, 7))
			table.insert(fields, {tag = tag :: string, lines = if text == "" then {} else {text}})
		end
	end
	if #fields > 0 then table.insert(records, record(fields)) end
	for _, entry in records do
		if type(entry.PMID) ~= "string" then fail("getRecords", 200, false, "NCBI returned a MEDLINE record without a PMID") end
	end
	return records
end

local function getRecords(ids: any): any
	local raw = eutility("getRecords", "efetch", {"db=pubmed", "rettype=medline", "retmode=text", idParam(ids)}, "request fewer IDs")
	return {records = medline(raw)}
end

local function getLinks(ids: any, linkname: any, input: Options?): any
	local params = {"dbfrom=pubmed", "retmode=json"}
	for _, id in pmids(ids, MAX_LINK_IDS) do table.insert(params, "id=" .. id) end
	assert(type(linkname) == "string" and LINK_NAMES[linkname], "linkname must be one of " .. LINK_LIST)
	table.insert(params, "linkname=" .. linkname)
	local args = options(input, "getLinks")
	assert(args.scores == nil or type(args.scores) == "boolean", "scores must be true or false")
	table.insert(params, "cmd=" .. (if args.scores then "neighbor_score" else "neighbor"))
	args.scores = nil
	noneLeft(args, "getLinks")
	return decode("getLinks", eutility("getLinks", "elink", params, "request fewer IDs"), "linksets")
end

local function getFullText(value: any): any
	local id = if type(value) == "string" then string.upper(value) else pmid(value) or ""
	assert((#id <= 12 and string.match(id, "^PMC[1-9]%d*$")) or pmid(id),
		"id must be a PMCID such as PMC4412151 or a PMID such as 25977807")
	local raw, headers = fetch("getFullText", {method = "GET", url = BIOC .. id .. "/unicode"},
		"this article's full text is too large for one call")
	local kind = headers["content-type"]
	-- Without open-access full text, the service answers 200 with an HTML error page.
	if not (kind and kind[1] and string.find(kind[1], "json", 1, true)) then
		if string.find(raw, "No result can be found", 1, true) then
			fail("getFullText", 200, false, "PMC has no open-access full text for " .. id
				.. "; only open-access and author manuscript articles have one, so read its abstract with getRecords")
		end
		fail("getFullText", 200, false, "NCBI returned an unexpected full-text answer")
	end
	local ok, collection = pcall(json.decode, raw)
	local documents = if ok and type(collection) == "table" and type(collection[1]) == "table" then collection[1].documents else nil
	local document = if type(documents) == "table" then documents[1] else nil
	if type(document) ~= "table" or type(document.passages) ~= "table" then
		fail("getFullText", 200, false, "NCBI returned an unexpected full-text answer")
	end
	return document
end

local function help(): string
	local links: {string} = {}
	for _, link in LINKS do table.insert(links, "- " .. link[1] .. ": " .. link[2] .. ".") end
	return [[PubMed: search and read NLM's database of biomedical literature citations and abstracts through NCBI's E-utilities (https://www.ncbi.nlm.nih.gov/books/NBK25501/), and the open-access full text of PubMed Central (PMC) articles through NCBI's BioC API. No account needed; an optional NCBI API key only raises the rate limit. Read-only. Calls return completed values; do not wrap them in await(). Results keep NCBI's field names and values: numbers such as count come back as strings. Each call makes one NCBI request. Abstracts can be protected by copyright and PMC articles carry their own licenses (see each document's license); NCBI's disclaimer and copyright notice: https://www.ncbi.nlm.nih.gov/About/disclaimer.html.

IDs are PMIDs, positive integers such as 31452104, given as a number or a string. ids takes one PMID, an array of up to ]] .. tostring(MAX_IDS) .. [[ (]] .. tostring(MAX_LINK_IDS) .. [[ for getLinks) or one string separated by commas or spaces; repeats are dropped.

## searchArticles({term, retstart?, retmax?, sort?, datetype?, mindate?, maxdate?, reldate?})

ESearch. Returns `{count, retstart, retmax, idlist, querytranslation, translationset, warninglist?, errorlist?}`: count is the number of matches, idlist the PMIDs of this page, querytranslation how PubMed read the query (with MeSH expansion), warninglist and errorlist phrases and fields PubMed ignored. Unknown options are rejected.
- term: a query in PubMed syntax, at most ]] .. tostring(MAX_TERM) .. [[ bytes, for example `crispr[tiab] AND review[pt]`, `"Smith J"[au]`, `asthma[majr]`, `Nature[ta] AND 2024[dp]` or `31452104[pmid]`. Tags include [tiab] (title or abstract), [ti], [au], [1au] (first author), [ad] (affiliation), [mh] (MeSH, with subheadings), [majr] (major MeSH topic), [pt] (publication type), [ta] (journal), [dp] (publication date), [la] (language), [ot] (keyword) and [sb] (subset, such as free full text[sb]); combine with AND, OR, NOT and parentheses.
- retmax: PMIDs to return, 0 to ]] .. tostring(MAX_RESULTS) .. [[ (default ]] .. tostring(DEFAULT_RETMAX) .. [[; 0 returns only count). retstart: matches to skip, 0 to ]] .. tostring(MAX_RESULTS - 1) .. [[ (default 0). For the next page, call again with retstart + retmax as retstart while that is below both count and ]] .. tostring(MAX_RESULTS) .. [[. PubMed returns only the first ]] .. tostring(MAX_RESULTS) .. [[ matches: retstart plus the PMIDs returned never exceeds ]] .. tostring(MAX_RESULTS) .. [[ (retstart = 9990 with retmax = 20 returns 9), so narrow larger result sets, for example by date.
- sort: ]] .. table.concat(SORTS, ", ") .. [[. relevance (PubMed's Best Match) is the default; pub_date sorts newest first, Author and JournalName ascending.
- mindate and maxdate together: YYYY, YYYY/MM or YYYY/MM/DD, real dates with mindate not after maxdate (NCBI would answer other dates with no matches). reldate: only the last n days. datetype selects the date they filter: edat (added to PubMed, the default), pdat (publication) or mdat (modification).

## getSummaries(ids)

ESummary. Returns `{uids, [pmid] = summary}`: uids lists the PMIDs in order and each summary has uid, title, authors (array of {name, authtype}), lastauthor, source (journal abbreviation), fulljournalname, pubdate, epubdate, volume, issue, pages, elocationid, lang, pubtype, articleids (array of {idtype, value}, idtype pubmed, doi, pmc, pmcid, pii or mid), attributes (such as "Has Abstract"), pmcrefcount and sortpubdate. A summary has no abstract or MeSH terms; use getRecords. An unknown PMID gets `{uid, error = "cannot get document summary"}`.

## getRecords(ids)

EFetch in MEDLINE format. Returns `{records}`, one complete record per known PMID in the order given; unknown PMIDs are left out, so the array can be empty. Records use MEDLINE tags as keys. These are strings: ]] .. string.gsub(SINGLE_TAGS, " ", ", ") .. [[; every other tag is an array of strings in record order. authors is always an array of {FAU (full name), AU (short name), AUID? (array, such as "ORCID: 0000-0002-4242-7526"), AD? (array of affiliations)} in author order; corporate authors are CN.
Main tags: PMID; TI title; AB abstract (structured abstracts keep labels such as "BACKGROUND:"); DP publication date; TA journal abbreviation and JT full title; VI, IP and PG volume, issue and pages; LID and AID identifiers such as "10.1136/bmj.n71 [doi]"; PMC the PMCID; MH MeSH headings, where `*` marks a major topic and `/` a subheading, as in "*Molecular Docking Simulation" or "Proteins/chemistry"; OT keywords; PT publication types (such as "Review" or "Retracted Publication"); RN substances; GR grants; LA languages; CIN, EIN and RIN comments, errata and retractions; SO the citation.

## getLinks(ids, linkname, opts?)

ELink, one linkset per PMID. Returns an array of `{dbfrom, ids, linksetdbs?}` in the order given, where linksetdbs is `{{dbto, linkname, links}}`, absent when the article has none. links are PMIDs, or PMC numbers for the pubmed_pmc links. opts.scores = true returns links as `{id, score}` objects instead; similar-article links score numerically, other links with an empty string. linkname:
]] .. table.concat(links, "\n") .. [[


A long list, such as the citations of a highly cited article, comes back whole: pass fewer ids if a call holds too much. ELink takes about 0.1 s per PMID and gives up after about 15 s with an empty answer, which fails as retryable: pass fewer ids.

## getFullText(id)

PMC open-access full text as one BioC document: `{id, infons, passages}`, where id is the PMCID, infons.license the license (such as "CC BY"), and each passage is `{offset, infons, text}` with infons.section_type (TITLE, ABSTRACT, INTRO, METHODS, RESULTS, DISCUSSION, CONCL, REF, FIG, TABLE and others) and infons.type (front, abstract, paragraph, title_1, ref, fig_caption...). The first passage's infons hold article IDs, keywords and the license text. id is a PMCID such as PMC4412151 or a PMID such as 25977807. Only articles in the PMC open-access subset and author manuscript collection have one; any other fails as not found, so read its abstract with getRecords. Find an article's PMCID with getRecords (PMC tag) or getLinks(ids, "pubmed_pmc").

## Errors and limits

Invalid input fails before any request. NCBI errors come back as upstream errors with the HTTP status and NCBI's message; HTTP 429 and 5xx are retryable, as are failures NCBI reports inside a successful answer (such as "Search Backend failed"), except its rejections of input (messages about invalid or too many values or an empty term). Without an API key, NCBI accepts 3 requests per second from Houston as a whole, and 10 per connection with one; Houston waits and retries a refused request briefly, so prefer fewer calls with more IDs over many small ones. Each call reads at most ]] .. tostring(MAX_BYTES // 1048576) .. [[ MiB and gives NCBI ]] .. tostring(CALL_TIME // 1000) .. [[ s: ]] .. tostring((CALL_TIME - BODY_TIME) // 1000) .. [[ to start answering and ]] .. tostring(BODY_TIME // 1000) .. [[ to send the body; a call that runs out of time fails as retryable. Too much data fails as not retryable: pass fewer ids; a larger full text cannot be read.

## Example

Here pubmed is the configured PubMed connection.

```lua
local found = pubmed.searchArticles({term = "crispr[tiab] AND review[pt]", sort = "pub_date", retmax = 20,
	datetype = "pdat", mindate = "2024", maxdate = "2025"})
print(found.count)
local summaries = pubmed.getSummaries(found.idlist)
for _, uid in summaries.uids do print(uid, summaries[uid].title, summaries[uid].source, summaries[uid].pubdate) end
local record = pubmed.getRecords(found.idlist[1]).records[1]
print(record.TI, record.AB, record.authors[1].FAU)
local linkset = pubmed.getLinks(found.idlist[1], "pubmed_pubmed_citedin")[1]
local citingIds = if linkset.linksetdbs then linkset.linksetdbs[1].links else {}
if record.PMC then
	local article = pubmed.getFullText(record.PMC)
	for _, passage in article.passages do
		if passage.infons.section_type == "METHODS" then print(passage.text) end
	end
end
```]]
end

return {searchArticles = searchArticles, getSummaries = getSummaries, getRecords = getRecords, getLinks = getLinks,
	getFullText = getFullText, help = help}
