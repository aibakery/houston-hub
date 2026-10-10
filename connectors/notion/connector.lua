-- Native Notion fields and responses are deliberately preserved, including nulls.
type Options = {[string]: any}
type Endpoint = {method: string, path: string, read: boolean, body: boolean, query: {string}, required: {string}, help: string}
local API = "https://api.notion.com"
local NULL = json.decode("null")
local ADMIN = auth.method == "admin"
local VERSION = if ADMIN then "2026-06-01" else "2026-03-11"
local endpoints: {[string]: Endpoint} = if ADMIN then require("lib/admin.lua") else require("lib/endpoints.lua")

local function text(value: any, field: string): string
	assert(type(value) == "string" and value ~= "", field .. " must be a nonempty string")
	return value
end

local function options(value: Options?): Options
	if value == nil then return {} end
	assert(type(value) == "table", "opts must be an object")
	for key in value do assert(type(key) == "string", "opts must have named fields") end
	return table.clone(value)
end

local function encode(value: string): string
	return (string.gsub(value, "[^A-Za-z0-9%-_%.~]", function(c: string)
		return string.format("%%%02X", string.byte(c))
	end))
end

local function identifier(value: any, field: string): string
	local id = text(value, field)
	-- Notion returns URL-encoded property IDs. Decode those once before encoding.
	if field == "property_id" then
		id = string.gsub(id, "%%(%x%x)", function(hex: string) return string.char(tonumber(hex, 16) :: number) end)
	end
	assert(id ~= "." and id ~= "..", field .. " must not be a dot path segment")
	return encode(id)
end

local function pageSize(value: any)
	if value ~= nil and value ~= NULL then
		assert(type(value) == "number" and value >= 1 and value <= 100 and value % 1 == 0, "page_size must be an integer from 1 to 100")
	end
end

local function scalar(value: any): string
	assert(type(value) == "string" or type(value) == "boolean" or (type(value) == "number" and value == value and math.abs(value) < math.huge), "query values must be strings, booleans or finite numbers")
	return tostring(value)
end

local function queryValue(parts: {string}, key: string, value: any)
	if value == nil or value == NULL then return end
	if type(value) == "table" then
		local count = 0
		for index in value do
			assert(type(index) == "number" and index >= 1 and index % 1 == 0, key .. " must be a dense array")
			count += 1
		end
		assert(count == #value, key .. " must be a dense array")
		for _, item in value do table.insert(parts, encode(key .. "[]") .. "=" .. encode(scalar(item))) end
	else
		table.insert(parts, encode(key) .. "=" .. encode(scalar(value)))
	end
end

local function fail(operation: string, response: HttpResponse): never
	local chunk = await(response.body:read(4096))
	response.body:close()
	local raw = if chunk.done then "" else chunk.data
	local ok, decoded = pcall(json.decode, raw)
	local message = "Notion HTTP " .. tostring(response.statusCode)
	if ok and type(decoded) == "table" then
		if type(decoded.code) == "string" then message ..= " (" .. decoded.code .. ")" end
		if type(decoded.message) == "string" then message ..= ": " .. string.sub(decoded.message, 1, 600) end
		if type(decoded.request_id) == "string" then message ..= " [request " .. decoded.request_id .. "]" end
	end
	local retry = response.headers["retry-after"]
	if retry and retry[1] then message ..= "; Retry-After: " .. retry[1] end
	return houston.fail({operation = operation, layer = "upstream", upstream_status = response.statusCode,
		retryable = response.statusCode == 429 or response.statusCode >= 500, message = message})
end

local function responseJSON(operation: string, response: HttpResponse): any
	if response.statusCode < 200 or response.statusCode >= 300 then fail(operation, response) end
	if response.statusCode == 204 then response.body:close(); return {success = true} end
	local raw = await(response.body:readAll())
	local ok, value = pcall(json.decode, raw)
	if not ok or type(value) ~= "table" or not string.match(raw, "^%s*{") then
		houston.fail({operation = operation, layer = "upstream", upstream_status = response.statusCode,
			retryable = false, message = "Notion returned an invalid JSON object"})
	end
	if value.object == "error" or value.type == "error" then
		houston.fail({operation = operation, layer = "upstream", upstream_status = response.statusCode,
			retryable = false, message = "Notion error: " .. tostring(value.code) .. ": " .. tostring(value.message)})
	end
	return value
end

local function headers(): HttpHeaders
	return {["Accept"] = {"application/json"}, ["Content-Type"] = {"application/json"}, ["Notion-Version"] = {VERSION}}
end

local function request(name: string, endpoint: Endpoint, input: Options?): any
	local args = options(input)
	pageSize(args.page_size)
	local path = string.gsub(endpoint.path, "{([%w_]+)}", function(field: string)
		local value = identifier(args[field], field)
		args[field] = nil
		return value
	end)
	for _, field in endpoint.required do text(args[field], field) end
	local query: {string} = {}
	for _, field in endpoint.query do queryValue(query, field, args[field]); args[field] = nil end
	if #query > 0 then path ..= "?" .. table.concat(query, "&") end
	if not endpoint.body then assert(next(args) == nil, name .. " received an unknown option") end
	if name == "updateSession" then assert(args.continue_from == nil, "continue_from requires streamSession") end
	return responseJSON(name, await(http.request({method = endpoint.method, url = API .. path,
		headers = headers(), body = if endpoint.body then json.encode(args) else nil})))
end

local function saveResponse(name: string, response: HttpResponse, path: string): Options
	if response.statusCode < 200 or response.statusCode >= 300 then fail(name, response) end
	local output = fs.open(path, "w")
	output:write(response.body)
	await(output:close())
	return {path = path, url = await(fs.signedGetUrl(path)), size = await(fs.stat(path)).size}
end

local exports: {[string]: any} = {}
local help: {[string]: string} = {}
for name, endpoint in endpoints do
	if name ~= "sendFileUpload" and (endpoint.read or config.access == "read-write") then
		exports[name] = function(args: Options?): any return request(name, endpoint, args) end
		help[name] = endpoint.help
	end
end

exports.downloadFile = function(input: Options): Options
	local args = options(input)
	local url, path = text(args.url, "url"), text(args.path, "path")
	assert(string.sub(url, 1, 8) == "https://", "url must be HTTPS")
	-- The manifest restricts this to Notion's download hosts and strips credentials.
	return saveResponse("downloadFile", await(http.request({method = "GET", url = url})), path)
end
help.downloadFile = "downloadFile({url, path}) -> {path, url, size}. Stream a fresh Notion signed file/plugin/export URL into a session file. The returned URL is Houston's signed download URL. Only documented Notion storage origins are allowed; external file URLs use caller HTTP instead. Redirects are not followed. A failed transfer can leave a partial destination."

if not ADMIN and config.access == "read-write" then
	exports.sendFileUpload = function(input: Options): any
		local args = options(input)
		local id = identifier(args.file_upload_id, "file_upload_id")
		local path = text(args.path, "path")
		local filename = text(args.filename or string.match(path, "[^/]+$"), "filename")
		local contentType = text(args.content_type or "application/octet-stream", "content_type")
		local part = args.part_number
		assert(part == nil or (type(part) == "number" and part >= 1 and part <= 10000 and part % 1 == 0), "part_number must be an integer from 1 to 10000")
		local parts: {MultipartPart} = {}
		if part ~= nil then table.insert(parts, {name = "part_number", body = tostring(part)}) end
		table.insert(parts, {name = "file", filename = filename, contentType = contentType, body = fs.open(path, "r")})
		local body, multipartType = http.multipart(parts)
		local h = headers()
		h["Content-Type"] = {multipartType}
		return responseJSON("sendFileUpload", await(http.request({method = "POST", url = API .. "/v1/file_uploads/" .. id .. "/send", headers = h, body = body})))
	end
	help.sendFileUpload = "sendFileUpload({file_upload_id, path, filename?, content_type?, part_number?}) -> Notion file_upload. Streams a session file via native multipart. filename defaults to the path basename; content_type defaults to application/octet-stream. For multi_part uploads send each prepared part file with its 1-based part_number, then completeFileUpload. Creation/import modes and number_of_parts are supplied to createFileUpload. Attach the completed file_upload ID to a page/block/comment before Notion's expiry. No automatic retry."
	exports.streamSession = function(input: Options): Options
		local args = options(input)
		local path = text(args.path, "path")
		args.path = nil
		local h = headers()
		h.Accept = {"text/event-stream"}
		local response = await(http.request({method = "POST", url = API .. "/v1/sessions", headers = h, body = json.encode(args)}))
		if response.statusCode >= 200 and response.statusCode < 300 then
			local contentType = response.headers["content-type"]
			local mediaType = if contentType then string.lower(string.match(contentType[1] or "", "^%s*([^;]+)") or "") else ""
			mediaType = string.gsub(mediaType, "%s+$", "")
			if mediaType ~= "text/event-stream" then
				response.body:close()
				error("streamSession expected text/event-stream")
			end
		end
		return saveResponse("streamSession", response, path)
	end
	help.streamSession = "streamSession({path, ...Notion session body}) -> {path, url, size}. Sends POST /v1/sessions with Accept:text/event-stream, saves raw SSE to a session file and returns after the stream ends. Supports session_id + continue_from (committed event ID), message/agent_id, or actions. A timeout may leave a partial file and a running remote session: inspect getSession/querySessionEvents before retrying; replay with continue_from."
end

exports.help = function(): string
	local names: {string} = {}
	for name in exports do if name ~= "help" then table.insert(names, name) end end
	table.sort(names)
	local lines = {
		"Notion " .. VERSION .. (if ADMIN then " Admin API (Enterprise organization bot)." else " Data, Agents and Skills API."),
		"Every operation takes one named options object using Notion's snake_case fields. Path/query fields are separated automatically; all remaining fields are the unmodified JSON body. Returns the complete Notion JSON object, preserving nulls, arrays, pagination and future fields; HTTP 204 returns {success=true}.",
		"Lists return one page only. Pass next_cursor as start_cursor while has_more is true; admin endpoints may use cursor. page_size is 1..100. Query arrays use bracket encoding. Use json.decode('[]') for empty arrays and json.decode('null') to clear nullable fields. Property IDs may be passed URL-encoded as returned by Notion.",
		"Capabilities and shared-page permissions are enforced by Notion; 403/404 may require granting the connection access. Some Agent/Skills/meeting features require a PAT or additional Notion entitlements. Search searches shared titles, not full content. Use data sources for schema/query operations, databases for containers. To trash/restore a page use updatePage({page_id=..., in_trash=true/false}).",
		"No hidden paging, polling or retries. Inspect getAsyncTask/getSession after asynchronous writes. Errors report status, provider code/message, request ID and Retry-After when available. A failed/timeout write may already have succeeded; verify before repeating. Read-only connections omit mutations; createViewQuery is a read query that creates a temporary results cache.",
		"OAuth exchange/refresh are managed by Houston; credentials never enter Lua. OAuth token creation/introspection/revocation are credential administration, not callable data operations. Webhook subscriptions are configured in Notion's developer portal, not through a REST endpoint. Legacy pre-2025 database endpoints are superseded by data sources.",
		"Example: search({query='Roadmap',page_size=10}); getPage({page_id='...'}); queryDataSource({data_source_id='...',filter={property='Status',status={equals='Done'}},filter_properties={'title'}}). Read the endpoint documentation linked below for complete nested body types and provider limits.",
	}
	for _, name in names do table.insert(lines, name .. "(opts): " .. help[name]) end
	return table.concat(lines, "\n")
end
return exports
