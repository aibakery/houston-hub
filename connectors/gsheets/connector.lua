-- Google Sheets API v4. Arguments and results keep Google's native field names.
type Options = {[string]: any}
type Endpoint = {method: string, path: string, read: boolean, query: {string}?, body: boolean?, defaults: Options?, list: string?, required: {string}?, help: string}
local API = "https://sheets.googleapis.com/v4"

-- Request layer shared verbatim by the Google connectors (tools/validate checks they match).
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

-- Moves the named fields from args into a query string; arrays repeat the key.
local function query(args: Options, names: {string}): string
	local parts: {string} = {}
	for _, name in names do
		local value = args[name]
		args[name] = nil
		for _, item in (if type(value) == "table" then value else {value}) do
			assert(type(item) == "string" or type(item) == "number" or type(item) == "boolean", name .. " must be a string, number, boolean or an array of them")
			table.insert(parts, url.encode(name) .. "=" .. url.encode(item))
		end
	end
	return if #parts > 0 then "?" .. table.concat(parts, "&") else ""
end

local function fail(operation: string, response: HttpResponse): never
	local ok, decoded = pcall(json.decode, await(response.body:readPrefix(4096)))
	local problem = if ok and type(decoded) == "table" and type(decoded.error) == "table" then decoded.error else {}
	local reason = type(problem.errors) == "table" and type(problem.errors[1]) == "table" and problem.errors[1].reason
	local message = "Google HTTP " .. tostring(response.statusCode)
	if type(problem.status) == "string" then message ..= " (" .. problem.status .. ")" end
	if type(problem.message) == "string" then message ..= ": " .. string.sub(problem.message, 1, 600) end
	if type(reason) == "string" then message ..= " [" .. reason .. "]" end
	local retry = response.headers["retry-after"]
	if retry and retry[1] then message ..= "; Retry-After: " .. retry[1] end
	local limited = type(reason) == "string" and string.find(string.lower(reason), "ratelimitexceeded", 1, true) ~= nil
	return houston.fail({operation = operation, layer = "upstream", upstream_status = response.statusCode,
		retryable = response.statusCode == 429 or response.statusCode >= 500 or limited, message = message})
end

local function decode(operation: string, response: HttpResponse): any
	if response.statusCode < 200 or response.statusCode >= 300 then fail(operation, response) end
	local raw = await(response.body:readAll())
	if raw == "" then return {success = true} end
	local ok, value = pcall(json.decode, raw)
	if not ok or type(value) ~= "table" or not string.match(raw, "^%s*{") then
		houston.fail({operation = operation, layer = "upstream", upstream_status = response.statusCode,
			retryable = false, message = "Google returned an invalid JSON object"})
	end
	return value
end

local function call(operation: string, method: string, href: string, body: any?): any
	return decode(operation, await(http.request({method = method, url = href,
		headers = if body ~= nil then {["Content-Type"] = {"application/json"}} else nil,
		body = if body ~= nil then json.encode(body) else nil})))
end

-- Moves {placeholders} and declared query fields from args into the URL; remaining fields form the JSON body.
local function target(name: string, endpoint: Endpoint, args: Options): string
	local defaults: Options = endpoint.defaults or {}
	for key, value in defaults do
		if args[key] == nil then args[key] = value end
	end
	local path = string.gsub(endpoint.path, "{(%w+)}", function(field: string)
		local value = url.segment(text(args[field], field), field)
		args[field] = nil
		return value
	end)
	path ..= query(args, endpoint.query or {})
	if not endpoint.body then assert(next(args) == nil, name .. " received an unknown option") end
	return API .. path
end

local function invoke(name: string, endpoint: Endpoint, input: any): any
	local args = options(input)
	local result = call(name, endpoint.method, target(name, endpoint, args), if endpoint.body then args else nil)
	if endpoint.list and result[endpoint.list] == nil then result[endpoint.list] = json.decode("[]") end
	return result
end

local exports: {[string]: any} = {}
local help: {[string]: string} = {}

-- Exposes an operation when it only reads or the connection allows writes.
local function export(name: string, isRead: boolean, fn: (any) -> any, doc: string)
	if isRead or config.access == "read-write" then
		exports[name], help[name] = fn, doc
	end
end

local function exportEndpoints(endpoints: {[string]: Endpoint})
	for name, endpoint in endpoints do
		export(name, endpoint.read, function(args: Options?): any return invoke(name, endpoint, args) end, endpoint.help)
	end
end

-- help() introduces the API, then documents exactly the configured operations.
local function helpWith(overview: {string}): () -> string
	return function(): string
		local names: {string} = {}
		for name in help do table.insert(names, name) end
		table.sort(names)
		local lines = table.clone(overview)
		for _, name in names do table.insert(lines, help[name]) end
		return table.concat(lines, "\n")
	end
end
-- End of the shared request layer.

local SPREADSHEET_FIELDS = "spreadsheetId,spreadsheetUrl,properties(title,locale,timeZone),sheets.properties,namedRanges"
local READ_QUERY = {"majorDimension", "valueRenderOption", "dateTimeRenderOption"}
local WRITE_QUERY = {"valueInputOption", "includeValuesInResponse", "responseValueRenderOption", "responseDateTimeRenderOption"}
local RAW = {valueInputOption = "RAW"}
local APPEND_QUERY = table.clone(WRITE_QUERY)
table.insert(APPEND_QUERY, "insertDataOption")
local endpoints: {[string]: Endpoint} = {
	getSpreadsheet = {method = "GET", path = "/spreadsheets/{spreadsheetId}", read = true, defaults = {fields = SPREADSHEET_FIELDS},
		query = {"fields", "ranges", "excludeTablesInBandedRanges"},
		help = "getSpreadsheet({spreadsheetId, fields?, ranges?}) -> {spreadsheetId, spreadsheetUrl, properties, sheets=[{properties={sheetId, title, index, gridProperties={rowCount, columnCount, ...}}}], namedRanges?}. Lists the tabs and their sizes. fields is a Google field mask: e.g. fields='sheets(data(rowData(values(formattedValue,note,hyperlink))))' with ranges={'Sheet1!A1:C3'} reads cell notes and links. Always pass ranges with data fields: responses over 8 MiB fail."},
	getValues = {method = "GET", path = "/spreadsheets/{spreadsheetId}/values/{range}", read = true, list = "values", query = READ_QUERY,
		help = "getValues({spreadsheetId, range, valueRenderOption?, dateTimeRenderOption?, majorDimension?}) -> {range, majorDimension, values}. One cell: getValues({spreadsheetId=..., range='Sheet1!B2'}).values[1] is {'42'}, or nil when B2 is empty."},
	batchGetValues = {method = "GET", path = "/spreadsheets/{spreadsheetId}/values:batchGet", read = true, list = "valueRanges", required = {"ranges"},
		query = {"ranges", table.unpack(READ_QUERY)},
		help = "batchGetValues({spreadsheetId, ranges={'Sheet1!A1:B2', 'Totals!C3'}, valueRenderOption?, dateTimeRenderOption?, majorDimension?}) -> {spreadsheetId, valueRanges=[{range, majorDimension, values}]}. Reads several ranges in one request, in the order given; an empty range has values=[]."},
	updateValues = {method = "PUT", path = "/spreadsheets/{spreadsheetId}/values/{range}", read = false, body = true, defaults = RAW, query = WRITE_QUERY, required = {"values"},
		help = "updateValues({spreadsheetId, range, values, valueInputOption?, majorDimension?, includeValuesInResponse?}) -> {spreadsheetId, updatedRange, updatedRows, updatedColumns, updatedCells}. Writes values from range's top-left cell, e.g. range='Sheet1!B2', values={{42}}."},
	appendValues = {method = "POST", path = "/spreadsheets/{spreadsheetId}/values/{range}:append", read = false, body = true, defaults = RAW, required = {"values"}, query = APPEND_QUERY,
		help = "appendValues({spreadsheetId, range, values, valueInputOption?, insertDataOption?}) -> {spreadsheetId, tableRange, updates}. Adds rows after the table Google finds in range, e.g. range='Log!A:D', values={{'2026-10-16', 'paid', 120}}, valueInputOption='USER_ENTERED' to store the date as a date. insertDataOption='INSERT_ROWS' inserts rows rather than filling the empty cells below (OVERWRITE, the default). Repeating it adds the rows again."},
	clearValues = {method = "POST", path = "/spreadsheets/{spreadsheetId}/values/{range}:clear", read = false, body = true,
		help = "clearValues({spreadsheetId, range}) -> {spreadsheetId, clearedRange}. Clears values and keeps formatting."},
	batchUpdateValues = {method = "POST", path = "/spreadsheets/{spreadsheetId}/values:batchUpdate", read = false, body = true, defaults = RAW, required = {"data"},
		help = "batchUpdateValues({spreadsheetId, data={{range='Sheet1!A1', values={{1, 2}}}, ...}, valueInputOption?, includeValuesInResponse?}) -> {spreadsheetId, totalUpdatedCells, responses}. Writes several ranges in one request."},
	batchClearValues = {method = "POST", path = "/spreadsheets/{spreadsheetId}/values:batchClear", read = false, body = true, required = {"ranges"},
		help = "batchClearValues({spreadsheetId, ranges={'Sheet1!A2:D', ...}}) -> {spreadsheetId, clearedRanges}."},
	createSpreadsheet = {method = "POST", path = "/spreadsheets", read = false, body = true,
		help = "createSpreadsheet({properties={title='Report'}, sheets?={{properties={title='Data'}}}}) -> the new spreadsheet, with spreadsheetId and spreadsheetUrl. It is created in the root of My Drive."},
	batchUpdate = {method = "POST", path = "/spreadsheets/{spreadsheetId}:batchUpdate", read = false, body = true, required = {"requests"},
		help = "batchUpdate({spreadsheetId, requests, includeSpreadsheetInResponse?}) -> {spreadsheetId, replies}. Structure and formatting, applied all or nothing, e.g. requests={{addSheet={properties={title='Archive'}}}}. Request kinds include addSheet, deleteSheet, duplicateSheet, updateSheetProperties (rename or freeze, with a fields mask), insertDimension, deleteDimension (rows or columns), findReplace, sortRange, repeatCell (formatting), mergeCells, setDataValidation and addTable. They address cells with GridRange {sheetId, startRowIndex, endRowIndex, startColumnIndex, endColumnIndex}: zero-based, ends exclusive, sheetId from getSpreadsheet. Deleting a tab, rows or columns removes their data; only the spreadsheet's version history restores it."},
}

-- Accepts the spreadsheet's URL in place of its ID; publish-to-web links carry no ID.
local function spreadsheetId(value: any): any
	if type(value) ~= "string" then return value end
	local rest = string.match(value, "^https://docs%.google%.com/spreadsheets/d/(.*)$")
		or string.match(value, "^https://docs%.google%.com/spreadsheets/u/%d+/d/(.*)$")
		or string.match(value, "^https://docs%.google%.com/a/[^/]+/spreadsheets/d/(.*)$")
	local id: string = if rest then string.match(rest, "^[^/?#]*") or "" else value
	assert(string.match(id, "^[%w_%-]+$") and id ~= "e", "spreadsheetId must be a spreadsheet ID or its https://docs.google.com/spreadsheets/d/<id> URL")
	return id
end

local NONE: {string} = table.freeze({})
-- Ranges are opaque path segments (the proxy allows encoded / and %), so tab names like '10/16' work.
local function withRange(endpoint: Endpoint, args: Options): Endpoint
	if not string.find(endpoint.path, "{range}", 1, true) then return endpoint end
	local range = url.encode(text(args.range, "range"))
	args.range = nil
	local resolved = table.clone(endpoint)
	resolved.path = string.gsub(endpoint.path, "{range}", function(): string return range end)
	return resolved
end
for name, endpoint in endpoints do
	export(name, endpoint.read, function(input: any): any
		local args = options(input)
		if string.find(endpoint.path, "{spreadsheetId}", 1, true) then
			args.spreadsheetId = spreadsheetId(args.spreadsheetId)
		else
			assert(args.spreadsheetId == nil, name .. " assigns the spreadsheetId")
		end
		for _, field in endpoint.required or NONE do
			local value = args[field]
			assert(type(value) == "table" and value[1] ~= nil, name .. " requires " .. field .. " as a nonempty array")
		end
		local result = invoke(name, withRange(endpoint, args), args)
		for _, range in result.valueRanges or NONE do
			if range.values == nil then range.values = json.decode("[]") end
		end
		return result
	end, endpoint.help)
end

local overview = {
	"Google Sheets API v4. Operations take one named options object with Google's camelCase fields and return Google's JSON unchanged. Calls return completed values: use instance.getValues(...) directly, without await.",
	"spreadsheetId is the ID or the spreadsheet's https://docs.google.com/spreadsheets/d/<id>/edit URL. This connector cannot search for files: ask for the URL, or find the ID with the Google Drive connector (listFiles with q=\"mimeType = 'application/vnd.google-apps.spreadsheet' and trashed = false\"). Excel files opened in Sheets are refused with HTTP 400 until saved as Google Sheets (File > Save as Google Sheets).",
	"Ranges use A1 notation: 'Sheet1!B2', 'Sheet1!A1:C10', 'Sheet1!A:A', a whole tab 'Sheet1' or a named range. Quote tab names with spaces or punctuation, and tab names that look like cells, doubling apostrophes: \"'Q1 Sales'!A1\", \"'Q1'!A1\". Without a tab, a range means the first visible tab.",
	"values are rows of cells (majorDimension='COLUMNS' gives columns). Trailing empty rows and cells are omitted; values is [] for an empty range. valueRenderOption is FORMATTED_VALUE (default, as displayed), UNFORMATTED_VALUE (numbers as numbers; dates as serial numbers unless dateTimeRenderOption='FORMATTED_STRING') or FORMULA.",
	"Google allows about 60 reads per minute per user; HTTP 429 errors are retryable after a pause. No hidden paging or retries. Errors report the HTTP status and Google's message.",
}
if config.access == "read-write" then
	table.insert(overview, "Writes default to valueInputOption='RAW', storing values exactly as given, so '2026-10-16' stays text; pass 'USER_ENTERED' to parse numbers, dates and formulas as if typed. In values, json null leaves a cell unchanged and '' clears it. An empty Luau table encodes as a JSON object, which Google rejects: write an empty row or array as json.decode('[]'). Google allows about 60 writes per minute per user. A failed or timed-out write may already have succeeded: read the range before repeating it.")
end
exports.help = helpWith(overview)
return exports
