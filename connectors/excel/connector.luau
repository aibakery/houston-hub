-- Microsoft Graph v1.0 workbook API for Excel workbooks in the connected account's OneDrive. Arguments
-- and results keep Graph's native field names.

-- Request layer shared verbatim by the Microsoft Graph connectors; Hub runs each copy against
-- every consumer's fixtures.
type Options = {[string]: any}
type Spec = {query: {string}?, body: boolean?, list: string?, defaults: Options?, headers: HttpHeaders?}
local GRAPH = "https://graph.microsoft.com/v1.0"
local API = GRAPH .. "/me"
-- Preauthenticated OneDrive download links, under either annotation, work without credentials,
-- so results never carry them.
local SIGNED = {"@microsoft.graph.downloadUrl", "@content.downloadUrl"}

local function text(value: any, field: string): string
	assert(type(value) == "string" and value ~= "", field .. " must be a nonempty string")
	return value
end

local function options(value: any): Options
	if value == nil then return {} end
	assert(type(value) == "table", "opts must be an object")
	for key in value do assert(type(key) == "string", "opts must have named fields") end
	return table.clone(value)
end

local function done(name: string, args: Options)
	local unknown = next(args)
	assert(unknown == nil, name .. " received an unknown option " .. tostring(unknown))
end

-- Moves the named fields from args into a query string. A $name is an OData option taken from
-- the field without $ (select, top, ...); arrays join with commas, as OData lists do.
local function query(args: Options, names: {string}): string
	local parts: {string} = {}
	for _, name in names do
		local field = if string.sub(name, 1, 1) == "$" then string.sub(name, 2) else name
		local value = args[field]
		args[field] = nil
		if value ~= nil then
			local items: {string} = {}
			for key, item in (if type(value) == "table" then value else {value}) do
				assert(type(key) == "number" and (type(item) == "string" or type(item) == "number" or type(item) == "boolean"), field .. " must be a string, number, boolean or an array of them")
				table.insert(items, url.encode(item))
			end
			assert(#items > 0, field .. " must not be an empty array")
			table.insert(parts, (if field == name then url.encode(name) else name) .. "=" .. table.concat(items, ","))
		end
	end
	return if #parts > 0 then "?" .. table.concat(parts, "&") else ""
end

-- Graph errors are {error = {code, message, innerError?}}; Excel puts its actionable code, such as
-- invalidSessionReCreatable, in innerError.code. Throttling answers 429 or 503 with Retry-After.
-- Quota (507) and other server refusals are not transient. A write that failed with a server error
-- may still have been applied, so only a refused (429) write is retryable.
local function fail(operation: string, response: HttpResponse, write: boolean?): never
	local ok, decoded = pcall(json.decode, await(response.body:readPrefix(4096)))
	local problem = if ok and type(decoded) == "table" and type(decoded.error) == "table" then decoded.error else {}
	local status = response.statusCode
	local message = "Microsoft Graph HTTP " .. tostring(status)
	if type(problem.code) == "string" then message ..= " (" .. problem.code .. ")" end
	if type(problem.message) == "string" then message ..= ": " .. string.sub(problem.message, 1, 600) end
	local detail = problem.innerError or problem.innererror
	local inner = if type(detail) == "table" then detail.code else nil
	if type(inner) == "string" and string.lower(inner) ~= string.lower(tostring(problem.code)) and not string.match(inner, "^%d+$") then
		message ..= "; innerError: " .. inner
	end
	local retry = response.headers["retry-after"]
	if retry and retry[1] then message ..= "; Retry-After: " .. retry[1] end
	return houston.fail({operation = operation, layer = "upstream", upstream_status = status, message = message,
		retryable = status == 429 or (not write and (status == 500 or status == 502 or status == 503 or status == 504 or status == 509))})
end

local function decode(operation: string, response: HttpResponse, write: boolean?): any
	if response.statusCode < 200 or response.statusCode >= 300 then fail(operation, response, write) end
	local raw = await(response.body:readAll())
	if string.match(raw, "^%s*$") then return {success = true} end
	local ok, value = pcall(json.decode, raw)
	if not ok or type(value) ~= "table" or not string.match(raw, "^%s*{") then
		houston.fail({operation = operation, layer = "upstream", upstream_status = response.statusCode,
			retryable = false, message = "Microsoft Graph returned an invalid JSON object"})
	end
	for _, key in SIGNED do
		value[key] = nil
		for _, item in (if type(value.value) == "table" then value.value else {}) :: {any} do
			if type(item) == "table" then item[key] = nil end
		end
	end
	return value
end

local function call(operation: string, method: string, href: string, body: any?, headers: HttpHeaders?): any
	local sent: HttpHeaders = if headers then table.clone(headers) else {}
	if body ~= nil then sent["Content-Type"] = {"application/json"} end
	return decode(operation, await(http.request({method = method, url = href, headers = sent,
		body = if body ~= nil then json.encode(body) elseif method == "POST" then "" else nil})), method ~= "GET")
end

-- Streams fetch()'s response to a session file; the path changes only when the whole body arrived.
local function save(operation: string, path: string, fetch: () -> HttpResponse): Options
	local output = fs.open(path, "w")
	local ok, err = pcall(function()
		local response = fetch()
		if response.statusCode ~= 200 then fail(operation, response) end
		output:write(response.body)
		await(output:close())
	end)
	if not ok then
		output:cancel()
		pcall(function() await(output:close()) end)
		error(err, 0)
	end
	return {path = path, url = await(fs.signedGetUrl(path)), size = await(fs.stat(path)).size}
end

-- Follows an @odata.nextLink of the list whose path ends with the pattern ending. It may carry only
-- paging options and a calendar view's time range: an $expand, or another route such as
-- thumbnails, could return attachment bytes or signed links. Graph may name entities by OData
-- key, as in mailFolders('inbox'), which the routes accept in their path form, mailFolders/inbox.
local PAGING = {select = true, top = true, skip = true, skiptoken = true, orderby = true, filter = true, search = true, count = true,
	startdatetime = true, enddatetime = true}
local function pageLink(link: string, ending: string): string
	local raw, search = string.match(link, "^([^?#]*)(%??[^#]*)$")
	assert(raw and search and string.sub(raw, 1, #GRAPH + 1) == GRAPH .. "/", "nextLink must be an @odata.nextLink from Microsoft Graph")
	local path = string.gsub((string.gsub(raw, "%%27", "'")), "/(%w+)%('([^'/]+)'%)", "/%1/%2")
	assert(string.find(path, ending), "nextLink must come from the same list")
	for pair in string.gmatch(string.sub(search, 2), "[^&]+") do
		local name = string.lower((string.gsub(string.match(pair, "^[^=]*") or "", "%%(%x%x)", function(hex: string): string
			return string.char(tonumber(hex, 16) or 0)
		end)))
		assert(PAGING[(string.gsub(name, "^%$", ""))], "nextLink may carry only paging options")
	end
	return path .. search
end

-- A list's nextLink, the previous page's @odata.nextLink, replaces every other option.
local function nextLink(name: string, args: Options, ending: string): string?
	if args.nextLink == nil then return nil end
	local link = text(args.nextLink, "nextLink")
	args.nextLink = nil
	assert(next(args) == nil, name .. " takes nextLink alone, from a previous page of the same list")
	return pageLink(link, ending)
end

-- One Graph request built from args: {field} placeholders take URL-encoded path segments, query
-- names the query fields and, with body, the other fields form the JSON body. A list (the Lua
-- pattern its path ends with) also accepts nextLink and always returns a value array.
local function request(name: string, method: string, path: string, input: any, spec: Spec?): any
	local args = options(input)
	local s: Spec = spec or {}
	local href = if s.list then nextLink(name, args, s.list) else nil
	if not href then
		local defaults: Options = s.defaults or {}
		for key, value in defaults do
			if args[key] == nil then args[key] = value end
		end
		local route = string.gsub(path, "{(%w+)}", function(field: string)
			local value = url.segment(text(args[field], field), field)
			args[field] = nil
			return value
		end)
		href = API .. route .. query(args, s.query or {})
		if not s.body then done(name, args) end
	end
	local result = call(name, method, href :: string, if s.body then args else nil, s.headers)
	if s.list and result.value == nil then result.value = json.decode("[]") end
	return result
end
-- End of the shared request layer.

local W = "/drive/items/{itemId}/workbook"
-- Search results keep the fields that identify a workbook; ranges return their values only by
-- default, since the full range object repeats the grid in seven forms.
local ITEM_FIELDS = "id,name,size,webUrl,lastModifiedDateTime,parentReference,file"
local RANGE_FIELDS = "address,rowCount,columnCount,values"

local help = {
	text = [[Microsoft Graph v1.0 workbook API for .xlsx workbooks in the connected work or school account's
own OneDrive; workbooks in SharePoint or shared from another OneDrive are out of reach. Operations
take one named options object with Graph's camelCase fields and return Graph's JSON unchanged;
deletes, clears and closes return {success=true}. Connector calls return completed values: use
them directly, without await.
itemId is the workbook's OneDrive item id, from findWorkbooks. A worksheet is named by its name
or its id; a name containing % works only by id. An address is A1-style, such as 'A1:C10', and
may carry its sheet: 'Sales!A1:D50', or "'Q1 Sales'!A1" when the name has spaces. Whole columns
or rows ('B:B', '2:5') return no values and cannot take values, formulas or formats: read and
write bounded ranges or a used range; clearRange, insertRange and deleteRange accept them.
Values are rows of cells: numbers, strings, booleans, '' for an empty cell, errors as strings
such as '#N/A'. Dates are serial numbers in values (days since 1899-12-30, or since 1904-01-01 in
workbooks using the 1904 date system) and formatted strings in text. Read large sheets in row
blocks, such as 'Sheet1!A1:Z5000': a request or response is limited to about 5 MB.
Send one request at a time per workbook: parallel calls on one workbook cause throttling,
timeouts and conflicts. Errors report the HTTP status, Graph's code and message, and Excel's
innerError code when there is one, e.g. 'Microsoft Graph HTTP 409 (conflict): ...; innerError:
itemAlreadyExists'. Errors marked retryable (429, and on reads 500, 502, 503, 504 or 509) carry
Retry-After when Graph sends one; an Excel 500 seldom succeeds when repeated unchanged. Houston itself retries only a short 429 wait.]] .. (if config.access == "read-write" then [[

Writes save to the file in OneDrive, with or without a session; the file's version history is
the only undo. Strings in values are read as if typed: '00123' becomes 123 and '2026-11-10' a
date, unless the cells' numberFormat is '@' (text). For more than two calls on one workbook,
createSession, pass its id as sessionId to each call, then closeSession. A session expires after
about 5 idle minutes (about 7 with persistChanges=false). An innerError code starting with
invalidSession means the session is unusable: after invalidSessionReCreatable, or a 502 or 503
within a session, create a new one; other codes, such as invalidSessionAccessConflict, need their
cause fixed first. A failed or timed-out write may already have been saved: read the range before
repeating it, especially addTableRows, which would add the rows twice.]] else ""),
	functions = {} :: {[string]: any},
}
local exports: {[string]: any} = {help = help}

-- Schemas and hints shared by several operations.
local ITEM = {type = "string", minLength = 1, description = "The workbook's OneDrive item id, from findWorkbooks."}
local ITEM_ID = "01BYE5RZ6QN3ZWBTUFOFD3GSPGOHDJD36K"
local SHEET = {type = "string", minLength = 1, description = "Worksheet name or id, from listWorksheets."}
local NAME = {type = "string", minLength = 1, description = "A named range, from listNames."}
local TABLE = {type = "string", minLength = 1, description = "Table name or id, from listTables."}
local ADDRESS = {type = "string", minLength = 1, description = "A1-style address such as 'A1:C10', optionally with its sheet: 'Sales!A1:D50' or \"'Q1 Sales'!A1\"."}
local SELECT = {type = {"string", "array"}, items = {type = "string"}, description = "Fields, comma-separated or as an array."}
local NEXT = {type = "string", description = "The previous page's @odata.nextLink; pass it alone."}
local GRID = {
	type = "array", minItems = 1,
	items = {type = "array", minItems = 1, items = {type = {"string", "number", "boolean", "null"}}},
	description = "Rows of cells, all the same length and matching the range's size.",
}
local FORMATS = {
	type = "array", minItems = 1,
	items = {type = "array", minItems = 1, items = {type = {"string", "null"}}},
	description = "Rows of number formats such as '0.00' or 'yyyy-mm-dd', matching the range's size.",
}
local READ = {readOnlyHint = true, openWorldHint = true}
local WRITE = {readOnlyHint = false, destructiveHint = false, openWorldHint = true}
local DESTRUCTIVE = {readOnlyHint = false, destructiveHint = true, openWorldHint = true}
-- Sessions exist only on read-write connections, which can create them.
local SESSION: Options = if config.access == "read-write"
	then {sessionId = {type = "string", minLength = 1, description = "A session id from createSession; omit for a one-off call."}}
	else {}

local function with(base: Options, extra: Options): Options
	local merged = table.clone(base)
	for key, value in extra do merged[key] = value end
	return merged
end

-- Moves sessionId from args into Graph's workbook-session-id header.
local function session(args: Options): HttpHeaders
	if config.access ~= "read-write" or args.sessionId == nil then return {} end
	local id = text(args.sessionId, "sessionId")
	assert(not string.find(id, "%c"), "sessionId must be a session id from createSession")
	args.sessionId = nil
	return {["workbook-session-id"] = {id}}
end

-- Splits an address into its sheet, unquoted, and its cells.
-- A named item's value, such as =Sheet1!$B$2:$H$12, works too.
local function split(value: any): (string?, string)
	local address = text(value, "address")
	address = (string.gsub(address, "^=", ""))
	local sheet, cells = string.match(address, "^(.+)!([^!]+)$")
	if sheet ~= nil then
		local quoted = string.match(sheet, "^'(.+)'$")
		if quoted ~= nil then sheet = (string.gsub(quoted, "''", "'")) end
	end
	local range = cells or address
	assert(string.match(range, "^[%w%$:]+$"), "address must be an A1-style range such as 'Sheet1!A1:C10'")
	return sheet, range
end

-- The sheet an address names, or else the worksheet field; both are consumed.
local function sheetOf(args: Options): (string, string)
	local sheet, cells = split(args.address)
	assert(sheet == nil or args.worksheet == nil, "name the worksheet in address or in worksheet, not both")
	local target = sheet or args.worksheet
	assert(target ~= nil, "address needs its worksheet, such as 'Sheet1!A1:B2', or pass worksheet")
	args.address, args.worksheet = nil, nil
	return text(target, "worksheet"), cells
end

-- The range an operation targets: an address, with its sheet in address or worksheet; a named
-- range; or, for reads, a table's cells or a worksheet's used range.
local function rangePath(args: Options, reads: boolean): string
	local name, tableId, valuesOnly = args.name, args.table, args.valuesOnly
	args.name, args.table, args.valuesOnly = nil, nil, nil
	if name ~= nil or tableId ~= nil then
		assert(args.address == nil and args.worksheet == nil and valuesOnly == nil and (name == nil or tableId == nil), "pass one of address, name or table")
		if name ~= nil then return W .. "/names/" .. url.segment(text(name, "name"), "name") .. "/range" end
		assert(reads, "table is only for reading; change a table's cells by address")
		return W .. "/tables/" .. url.segment(text(tableId, "table"), "table") .. "/range"
	end
	if args.address == nil then
		assert(reads, "address or name is required")
		local only = if valuesOnly == nil then true else valuesOnly
		assert(type(only) == "boolean", "valuesOnly must be a boolean")
		local sheet = text(args.worksheet, "worksheet")
		args.worksheet = nil
		return W .. "/worksheets/" .. url.segment(sheet, "worksheet") .. "/usedRange(valuesOnly=" .. tostring(only) .. ")"
	end
	assert(valuesOnly == nil, "valuesOnly applies only to a worksheet's used range")
	local sheet, cells = sheetOf(args)
	return W .. "/worksheets/" .. url.segment(sheet, "worksheet") .. "/range(address='" .. url.segment(cells, "address") .. "')"
end

-- Workbook lists return every item at once, as a value array.
local function list(result: Options): Options
	if result.value == nil then result.value = json.decode("[]") end
	return result
end

local NULL = json.decode("null")

-- A grid of cells: strings, numbers, booleans or null, or for formats strings or null.
local function grid(value: any, field: string, formats: boolean?)
	assert(type(value) == "table" and type(value[1]) == "table", field .. " must be rows of cells, such as {{'Item', 'Qty'}, {'Pear', 4}}")
	local width, count = #value[1], 0
	for index, row in value do
		count += 1
		assert(type(index) == "number", field .. " must be an array of rows")
		assert(type(row) == "table" and #row == width and width > 0, field .. " rows must all have the same, nonzero number of cells")
		for key, cell in row do
			local kind = type(cell)
			assert(type(key) == "number" and (cell == NULL or kind == "string" or (not formats and (kind == "number" or kind == "boolean"))),
				field .. (if formats then " cells must be strings or null" else " cells must be strings, numbers, booleans or null"))
		end
	end
	assert(count == #value, field .. " must be an array of rows")
end

-- Write bodies are closed: refuses options Graph would take as other range or sheet properties,
-- and checks each value before any request. Path and query fields are listed as true.
local function fields(name: string, args: Options, kinds: {[string]: any})
	for key, value in args do
		local kind = kinds[key]
		assert(kind ~= nil, name .. " received an unknown option " .. key)
		if kind == "grid" or kind == "formats" then
			grid(value, key, kind == "formats")
		elseif kind == "index" then
			assert(type(value) == "number" and value >= 0 and value < 2 ^ 53 and math.floor(value) == value, key .. " must be an integer of at least 0")
		elseif type(kind) == "table" then
			assert(table.find(kind, value) ~= nil, key .. " must be one of " .. table.concat(kind, ", "))
		elseif kind == "text" then
			text(value, key)
		elseif type(kind) == "string" then
			assert(type(value) == kind, key .. " must be a " .. kind)
		end
	end
end

help.functions.findWorkbooks = {
	description = [[One page of .xlsx workbooks in the user's own OneDrive whose name, metadata or content match q:
{value={{id, name, size, webUrl, lastModifiedDateTime, parentReference, file}},
['@odata.nextLink']?}. Other files and files shared from other drives are left out, so a page can
be empty while a nextLink remains. q cannot contain / or %.]],
	inputSchema = {
		type = "object",
		properties = {q = {type = "string", minLength = 1}, top = {type = "integer", minimum = 1}, nextLink = NEXT},
		anyOf = {{required = {"q"}}, {required = {"nextLink"}}} :: {any},
		additionalProperties = false,
		examples = {{q = "budget 2026", top = 25}},
	},
	annotations = READ,
}
function exports.findWorkbooks(input: any): Options
	local args = options(input)
	local path = ""
	if args.nextLink == nil then
		-- OData quotes a literal by doubling its single quotes.
		path = "/drive/root/search(q='" .. url.segment((string.gsub(text(args.q, "q"), "'", "''")), "q") .. "')"
		assert(args.top == nil or (type(args.top) == "number" and args.top >= 1 and math.floor(args.top) == args.top), "top must be a positive integer")
		assert(args.select == nil, "findWorkbooks received an unknown option select")
		args.q = nil
		-- remoteItem marks files shared from other drives, which are dropped below.
		args.select = ITEM_FIELDS .. ",remoteItem"
	end
	local result = request("findWorkbooks", "GET", path, args, {list = "[/%.]search%(.*%)$", query = {"$select", "$top"}})
	local workbooks = json.decode("[]")
	for _, item in result.value do
		if type(item) == "table" and type(item.file) == "table" and item.remoteItem == nil and type(item.name) == "string"
			and string.lower(string.sub(item.name, -5)) == ".xlsx" then
			table.insert(workbooks, item)
		end
	end
	result.value = workbooks
	return result
end

help.functions.getWorkbook = {
	description = "The workbook's OneDrive item: {id, name, size, webUrl, lastModifiedDateTime, parentReference, file={mimeType}}.",
	inputSchema = {type = "object", properties = {itemId = ITEM, select = SELECT}, required = {"itemId"}, additionalProperties = false, examples = {{itemId = ITEM_ID}}},
	annotations = READ,
}
function exports.getWorkbook(args: Options?): Options
	return request("getWorkbook", "GET", "/drive/items/{itemId}", args, {query = {"$select"}, defaults = {select = ITEM_FIELDS}})
end

help.functions.listWorksheets = {
	description = "The workbook's worksheets in order: {value={{id, name, position, visibility}}}. An id stays the same when the sheet is renamed.",
	inputSchema = {type = "object", properties = with({itemId = ITEM, select = SELECT}, SESSION), required = {"itemId"}, additionalProperties = false, examples = {{itemId = ITEM_ID}}},
	annotations = READ,
}
function exports.listWorksheets(input: any): Options
	local args = options(input)
	local headers = session(args)
	return list(request("listWorksheets", "GET", W .. "/worksheets", args, {headers = headers, query = {"$select"}, defaults = {select = "id,name,position,visibility"}}))
end

help.functions.listTables = {
	description = "The workbook's tables, or one worksheet's: {value={{id, name, showHeaders, showTotals, style}}}. getRange({table=...}) reads a table's cells.",
	inputSchema = {
		type = "object",
		properties = with({itemId = ITEM, worksheet = SHEET}, SESSION),
		required = {"itemId"},
		additionalProperties = false,
		examples = {{itemId = ITEM_ID}, {itemId = ITEM_ID, worksheet = "Sales"}} :: {any},
	},
	annotations = READ,
}
function exports.listTables(input: any): Options
	local args = options(input)
	local headers = session(args)
	return list(request("listTables", "GET", if args.worksheet == nil then W .. "/tables" else W .. "/worksheets/{worksheet}/tables", args, {headers = headers}))
end

help.functions.listNames = {
	description = [[The workbook's named items, or those scoped to one worksheet: {value={{name, type, value, scope,
visible, comment}}}. Workbook-scoped names of type 'Range' work with getRange({name=...}); pass a
worksheet-scoped name's value as address instead.]],
	inputSchema = {
		type = "object",
		properties = with({itemId = ITEM, worksheet = SHEET}, SESSION),
		required = {"itemId"},
		additionalProperties = false,
		examples = {{itemId = ITEM_ID}, {itemId = ITEM_ID, worksheet = "Sales"}} :: {any},
	},
	annotations = READ,
}
function exports.listNames(input: any): Options
	local args = options(input)
	local headers = session(args)
	return list(request("listNames", "GET", if args.worksheet == nil then W .. "/names" else W .. "/worksheets/{worksheet}/names", args, {headers = headers}))
end

help.functions.getRange = {
	description = [[Cells of an address, a named range, a table (with its header and totals rows) or a worksheet's
used range: {address, rowCount, columnCount, values}. address in the result carries the sheet.
Add text, formulas, numberFormat or valueTypes to select for those grids. The used range covers
cells with values; valuesOnly=false also counts formatted empty cells.]],
	inputSchema = {
		type = "object",
		properties = with({itemId = ITEM, address = ADDRESS, worksheet = SHEET, name = NAME, table = TABLE, valuesOnly = {type = "boolean"}, select = SELECT}, SESSION),
		required = {"itemId"},
		anyOf = {{required = {"address"}}, {required = {"name"}}, {required = {"table"}}, {required = {"worksheet"}}} :: {any},
		additionalProperties = false,
		examples = {
			{itemId = ITEM_ID, address = "Sales!A1:D50"},
			{itemId = ITEM_ID, worksheet = "Sheet1"},
			{itemId = ITEM_ID, table = "Table1"},
			{itemId = ITEM_ID, name = "Totals", select = "address,values,text"},
		} :: {any},
	},
	annotations = READ,
}
function exports.getRange(input: any): Options
	local args = options(input)
	local headers = session(args)
	return request("getRange", "GET", rangePath(args, true), args, {headers = headers, query = {"$select"}, defaults = {select = RANGE_FIELDS}})
end

if config.access == "read-write" then
	-- A minimal package: one empty worksheet, Sheet1, and the default Normal cell style.
	local XML = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
	local RELATIONSHIPS = "http://schemas.openxmlformats.org/package/2006/relationships"
	local OFFICE = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
	local SPREADSHEET = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
	local MEDIA = "application/vnd.openxmlformats-officedocument.spreadsheetml."
	local PACKAGE = {
		{name = "[Content_Types].xml", body = XML .. '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
			.. '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
			.. '<Default Extension="xml" ContentType="application/xml"/>'
			.. '<Override PartName="/xl/workbook.xml" ContentType="' .. MEDIA .. 'sheet.main+xml"/>'
			.. '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="' .. MEDIA .. 'worksheet+xml"/>'
			.. '<Override PartName="/xl/styles.xml" ContentType="' .. MEDIA .. 'styles+xml"/></Types>'},
		{name = "_rels/.rels", body = XML .. '<Relationships xmlns="' .. RELATIONSHIPS .. '">'
			.. '<Relationship Id="rId1" Type="' .. OFFICE .. '/officeDocument" Target="xl/workbook.xml"/></Relationships>'},
		{name = "xl/workbook.xml", body = XML .. '<workbook xmlns="' .. SPREADSHEET .. '" xmlns:r="' .. OFFICE .. '">'
			.. '<sheets><sheet name="Sheet1" sheetId="1" r:id="rId1"/></sheets></workbook>'},
		{name = "xl/_rels/workbook.xml.rels", body = XML .. '<Relationships xmlns="' .. RELATIONSHIPS .. '">'
			.. '<Relationship Id="rId1" Type="' .. OFFICE .. '/worksheet" Target="worksheets/sheet1.xml"/>'
			.. '<Relationship Id="rId2" Type="' .. OFFICE .. '/styles" Target="styles.xml"/></Relationships>'},
		{name = "xl/worksheets/sheet1.xml", body = XML .. '<worksheet xmlns="' .. SPREADSHEET .. '"><sheetData/></worksheet>'},
		{name = "xl/styles.xml", body = XML .. '<styleSheet xmlns="' .. SPREADSHEET .. '">'
			.. '<fonts count="1"><font><sz val="11"/><name val="Calibri"/></font></fonts>'
			.. '<fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>'
			.. '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>'
			.. '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
			.. '<cellXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/></cellXfs>'
			.. '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>'},
	}
	-- The archive's bytes, built on first use: a string body is sent with its length.
	local workbook: string? = nil

	help.functions.createWorkbook = {
		description = [[Creates an empty workbook with one worksheet, Sheet1, in parentId or the root folder and returns
its OneDrive item: {id, name, size, webUrl, lastModifiedDateTime, parentReference, file}. name
ends in .xlsx, does not start with a space and has none of " * : < > ? / \ | %. An existing
file is never replaced: its name fails with HTTP 409 (nameAlreadyExists). A failed call may
still have created the workbook, and repeating it then also fails with 409: look for it with
findWorkbooks. Fill the sheet with updateRange and rename it with updateWorksheet.]],
		inputSchema = {
			type = "object",
			properties = {
				name = {type = "string", minLength = 6, description = "File name ending in .xlsx, such as 'Budget 2026.xlsx'."},
				parentId = {type = "string", minLength = 1, description = "A folder's OneDrive item id, such as a workbook's parentReference.id; omit for the root folder."},
			},
			required = {"name"},
			additionalProperties = false,
			examples = {{name = "Budget 2026.xlsx"}, {name = "Q3 sales.xlsx", parentId = "01BYE5RZ56Y2GOVW7725BZO354PWSELRRZ"}} :: {any},
		},
		annotations = WRITE,
	}
	function exports.createWorkbook(input: any): Options
		local args = options(input)
		local name = text(args.name, "name")
		assert(string.lower(string.sub(name, -5)) == ".xlsx" and #name > 5, "name must end in .xlsx, such as 'Budget 2026.xlsx'")
		-- OneDrive refuses these characters in names; a colon would also end Graph's path-based
		-- addressing early.
		assert(not string.find(name, '[%c"*:<>?/\\|%%]') and not string.find(name, "^%s"),
			'name cannot start with a space or contain " * : < > ? / \\ | %')
		local folder = if args.parentId == nil then "/drive/root" else "/drive/items/" .. url.segment(text(args.parentId, "parentId"), "parentId")
		args.name, args.parentId = nil, nil
		done("createWorkbook", args)
		workbook = workbook or await(zip.create(PACKAGE):readAll())
		local item = decode("createWorkbook", await(http.request({
			method = "PUT",
			url = API .. folder .. ":/" .. url.segment(name, "name") .. ":/content?@microsoft.graph.conflictBehavior=fail",
			headers = {["Content-Type"] = {MEDIA .. "sheet"}},
			body = workbook,
		})), true)
		if type(item.id) ~= "string" then
			houston.fail({operation = "createWorkbook", layer = "upstream", retryable = false, message = "Microsoft Graph returned no item for the new workbook"})
		end
		local result: Options = {}
		for field in string.gmatch(ITEM_FIELDS, "[^,]+") do result[field] = item[field] end
		return result
	end

	help.functions.updateRange = {
		description = [[Writes values, formulas or number formats to an address or a named range and returns
{address, rowCount, columnCount, values}. Each grid matches the range's size. In values, null
(json.decode('null')) leaves a cell unchanged, '' clears it and a string starting with = is a
formula. Write dates as serial numbers with a numberFormat such as 'yyyy-mm-dd'.]],
		inputSchema = {
			type = "object",
			properties = with({itemId = ITEM, address = ADDRESS, worksheet = SHEET, name = NAME, values = GRID, formulas = GRID, numberFormat = FORMATS, select = SELECT}, SESSION),
			required = {"itemId"},
			allOf = {
				{anyOf = {{required = {"address"}}, {required = {"name"}}}},
				{anyOf = {{required = {"values"}}, {required = {"formulas"}}, {required = {"numberFormat"}}}},
			} :: {any},
			additionalProperties = false,
			examples = {
				{itemId = ITEM_ID, address = "Sheet1!A1:B2", values = {{"Item", "Qty"}, {"Pear", 4} :: {any}}},
				{itemId = ITEM_ID, address = "Sheet1!C2", formulas = {{"=B2*1.2"}}, numberFormat = {{"0.00"}}},
			} :: {any},
		},
		annotations = DESTRUCTIVE,
	}
	function exports.updateRange(input: any): Options
		local args = options(input)
		local headers = session(args)
		local path = rangePath(args, false)
		assert(args.values ~= nil or args.formulas ~= nil or args.numberFormat ~= nil, "updateRange requires values, formulas or numberFormat")
		fields("updateRange", args, {itemId = true, select = true, values = "grid", formulas = "grid", numberFormat = "formats"})
		return request("updateRange", "PATCH", path, args, {body = true, headers = headers, query = {"$select"}, defaults = {select = RANGE_FIELDS}})
	end

	help.functions.clearRange = {
		description = "Clears an address or a named range and returns {success=true}: applyTo Contents (the default) keeps formats, Formats keeps values, All clears both.",
		inputSchema = {
			type = "object",
			properties = with({itemId = ITEM, address = ADDRESS, worksheet = SHEET, name = NAME, applyTo = {type = "string", enum = {"Contents", "Formats", "All"}}}, SESSION),
			required = {"itemId"},
			anyOf = {{required = {"address"}}, {required = {"name"}}} :: {any},
			additionalProperties = false,
			examples = {{itemId = ITEM_ID, address = "Sheet1!A2:D100"}},
		},
		annotations = DESTRUCTIVE,
	}
	function exports.clearRange(input: any): Options
		local args = options(input)
		local headers = session(args)
		local path = rangePath(args, false) .. "/clear"
		fields("clearRange", args, {itemId = true, applyTo = {"Contents", "Formats", "All"}})
		return request("clearRange", "POST", path, args, {body = true, headers = headers, defaults = {applyTo = "Contents"}})
	end

	help.functions.insertRange = {
		description = "Inserts empty cells at an address, shifting the cells there Down or Right, and returns the new range with its cells. Insert whole rows or columns, such as 'Sheet1!5:7' for three rows, rather than large blocks, whose reply can exceed Graph's size limit.",
		inputSchema = {
			type = "object",
			properties = with({itemId = ITEM, address = ADDRESS, worksheet = SHEET, name = NAME, shift = {type = "string", enum = {"Down", "Right"}}}, SESSION),
			required = {"itemId", "shift"},
			anyOf = {{required = {"address"}}, {required = {"name"}}} :: {any},
			additionalProperties = false,
			examples = {{itemId = ITEM_ID, address = "Sheet1!5:7", shift = "Down"}},
		},
		annotations = WRITE,
	}
	function exports.insertRange(input: any): Options
		local args = options(input)
		local headers = session(args)
		local path = rangePath(args, false) .. "/insert"
		assert(args.shift ~= nil, "insertRange requires shift: Down or Right")
		fields("insertRange", args, {itemId = true, shift = {"Down", "Right"}})
		return request("insertRange", "POST", path, args, {body = true, headers = headers})
	end

	help.functions.deleteRange = {
		description = "Deletes the cells at an address, shifting the cells after them Up or Left, and returns {success=true}. 'Sheet1!5:5' deletes row 5.",
		inputSchema = {
			type = "object",
			properties = with({itemId = ITEM, address = ADDRESS, worksheet = SHEET, name = NAME, shift = {type = "string", enum = {"Up", "Left"}}}, SESSION),
			required = {"itemId", "shift"},
			anyOf = {{required = {"address"}}, {required = {"name"}}} :: {any},
			additionalProperties = false,
			examples = {{itemId = ITEM_ID, address = "Sheet1!5:5", shift = "Up"}},
		},
		annotations = DESTRUCTIVE,
	}
	function exports.deleteRange(input: any): Options
		local args = options(input)
		local headers = session(args)
		local path = rangePath(args, false) .. "/delete"
		assert(args.shift ~= nil, "deleteRange requires shift: Up or Left")
		fields("deleteRange", args, {itemId = true, shift = {"Up", "Left"}})
		return request("deleteRange", "POST", path, args, {body = true, headers = headers})
	end

	help.functions.addTableRows = {
		description = [[Adds rows to a table, one cell per table column, at the end or at a 0-based index, and returns
the added row: {index, values}. Add many rows per call rather than one call per row. A 504 may
still have added the rows: read the table before repeating the call.]],
		inputSchema = {
			type = "object",
			properties = with({itemId = ITEM, table = TABLE, values = GRID, index = {type = "integer", minimum = 0}}, SESSION),
			required = {"itemId", "table", "values"},
			additionalProperties = false,
			examples = {{itemId = ITEM_ID, table = "Table1", values = {{"2026-11-10", "Pear", 4} :: {any}, {"2026-11-10", "Fig", 2} :: {any}}}},
		},
		annotations = WRITE,
	}
	function exports.addTableRows(input: any): Options
		local args = options(input)
		local headers = session(args)
		assert(args.values ~= nil, "addTableRows requires values")
		fields("addTableRows", args, {itemId = true, table = true, values = "grid", index = "index"})
		return request("addTableRows", "POST", W .. "/tables/{table}/rows/add", args, {body = true, headers = headers})
	end

	help.functions.addTable = {
		description = [[Turns a range into a table and returns it: {id, name, showHeaders, ...}. Its first row is the
header; with hasHeaders=false, Excel adds a header row and shifts the data down one row. A range overlapping another table fails.]],
		inputSchema = {
			type = "object",
			properties = with({itemId = ITEM, address = ADDRESS, worksheet = SHEET, hasHeaders = {type = "boolean"}}, SESSION),
			required = {"itemId", "address"},
			additionalProperties = false,
			examples = {{itemId = ITEM_ID, address = "Sales!A1:D20"}},
		},
		annotations = WRITE,
	}
	function exports.addTable(input: any): Options
		local args = options(input)
		local headers = session(args)
		args.worksheet, args.address = sheetOf(args)
		fields("addTable", args, {itemId = true, worksheet = true, address = true, hasHeaders = "boolean"})
		return request("addTable", "POST", W .. "/worksheets/{worksheet}/tables/add", args, {body = true, headers = headers, defaults = {hasHeaders = true}})
	end

	help.functions.addWorksheet = {
		description = "Adds a worksheet after the others and returns it: {id, name, position, visibility}. Without name, Excel picks one such as Sheet2.",
		inputSchema = {
			type = "object",
			properties = with({itemId = ITEM, name = {type = "string", minLength = 1, description = "The new worksheet's name."}}, SESSION),
			required = {"itemId"},
			additionalProperties = false,
			examples = {{itemId = ITEM_ID, name = "Archive"}},
		},
		annotations = WRITE,
	}
	function exports.addWorksheet(input: any): Options
		local args = options(input)
		local headers = session(args)
		fields("addWorksheet", args, {itemId = true, name = "text"})
		return request("addWorksheet", "POST", W .. "/worksheets/add", args, {body = true, headers = headers})
	end

	help.functions.updateWorksheet = {
		description = "Renames, moves (0-based position) or hides a worksheet and returns it.",
		inputSchema = {
			type = "object",
			properties = with({
				itemId = ITEM, worksheet = SHEET, name = {type = "string", minLength = 1, description = "The worksheet's new name."},
				position = {type = "integer", minimum = 0}, visibility = {type = "string", enum = {"Visible", "Hidden", "VeryHidden"}},
			}, SESSION),
			required = {"itemId", "worksheet"},
			anyOf = {{required = {"name"}}, {required = {"position"}}, {required = {"visibility"}}} :: {any},
			additionalProperties = false,
			examples = {{itemId = ITEM_ID, worksheet = "Sheet2", name = "Archive"}},
		},
		annotations = WRITE,
	}
	function exports.updateWorksheet(input: any): Options
		local args = options(input)
		local headers = session(args)
		assert(args.name ~= nil or args.position ~= nil or args.visibility ~= nil, "updateWorksheet requires name, position or visibility")
		fields("updateWorksheet", args, {itemId = true, worksheet = true, name = "text", position = "index", visibility = {"Visible", "Hidden", "VeryHidden"}})
		return request("updateWorksheet", "PATCH", W .. "/worksheets/{worksheet}", args, {body = true, headers = headers})
	end

	help.functions.deleteWorksheet = {
		description = "Deletes a worksheet and its data and returns {success=true}.",
		inputSchema = {type = "object", properties = with({itemId = ITEM, worksheet = SHEET}, SESSION), required = {"itemId", "worksheet"}, additionalProperties = false, examples = {{itemId = ITEM_ID, worksheet = "Archive"}}},
		annotations = DESTRUCTIVE,
	}
	function exports.deleteWorksheet(input: any): Options
		local args = options(input)
		local headers = session(args)
		return request("deleteWorksheet", "DELETE", W .. "/worksheets/{worksheet}", args, {headers = headers})
	end

	help.functions.createSession = {
		description = [[Opens a workbook session and returns {id, persistChanges}; pass id as sessionId to the following
calls on that workbook, then closeSession. persistChanges=false makes a scratch copy whose changes
are dropped when the session ends.]],
		inputSchema = {type = "object", properties = {itemId = ITEM, persistChanges = {type = "boolean"}}, required = {"itemId"}, additionalProperties = false, examples = {{itemId = ITEM_ID}}},
		annotations = WRITE,
	}
	function exports.createSession(input: any): Options
		local args = options(input)
		fields("createSession", args, {itemId = true, persistChanges = "boolean"})
		return request("createSession", "POST", W .. "/createSession", args, {body = true, defaults = {persistChanges = true}})
	end

	help.functions.closeSession = {
		description = "Closes a workbook session and returns {success=true}.",
		inputSchema = {
			type = "object",
			properties = {itemId = ITEM, sessionId = SESSION.sessionId},
			required = {"itemId", "sessionId"},
			additionalProperties = false,
			examples = {{itemId = ITEM_ID, sessionId = "cluster=PAR1&session=15.SN3PEPF000074ED1.A82"}},
		},
		annotations = WRITE,
	}
	function exports.closeSession(input: any): Options
		local args = options(input)
		text(args.sessionId, "sessionId")
		local headers = session(args)
		return request("closeSession", "POST", W .. "/closeSession", args, {headers = headers})
	end
end

return exports
