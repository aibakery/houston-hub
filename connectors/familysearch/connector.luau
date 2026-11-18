-- FamilySearch's published operations, with native GEDCOM X request/response documents.
-- Authentication is injected by houston.json; no credential is visible to this module.
type Object = {[string]: any}
type Parameter = {location: string, schema: Object, required: boolean?}
type Endpoint = {
	export: string, method: string, path: string, read: boolean, description: string, doc: string,
	accept: string, params: {[string]: Parameter}, example: Object, success: {number},
	body: {contentType: string, schema: Object, required: boolean}?, custom: boolean?, dynamicQuery: boolean?,
}
local catalog: {[string]: Endpoint} = require("catalog.luau")
local namespaceDescriptions: {[string]: string} = require("namespaces.luau")
local API = if config.environment == "beta" then "https://apibeta.familysearch.org" else "https://api.familysearch.org"
local NULL = json.decode("null")
local MAX_COUNT = 1000
local COMMON_HEADERS = {
	["Accept-Language"] = {type = "string", description = "Preferred response language, for example en."},
	["If-Match"] = {type = "string", description = "Previously returned ETag, for a conditional mutation."},
	["If-None-Match"] = {type = "string", description = "Previously returned ETag, for a conditional read."},
	["If-Modified-Since"] = {type = "string", description = "HTTP date for a conditional read."},
	["X-FS-Feature-Tag"] = {type = "string", description = "Explicit opt-in to a documented pending FamilySearch modification."},
}
local RESPONSE_HEADERS = {
	location = true, link = true, etag = true, ["last-modified"] = true,
	["content-type"] = true, ["content-location"] = true, ["content-disposition"] = true,
	["x-entity-id"] = true, ["retry-after"] = true, ["x-fs-page-size"] = true,
	["x-fs-total-results"] = true, ["x-fs-current-page"] = true, warning = true, allow = true,
}
local resultSchema = {
	type = "object", properties = {
		statusCode = {type = "integer"}, data = {},
		headers = {type = "object", additionalProperties = {type = "array", items = {type = "string"}}},
	}, required = {"statusCode", "headers"}, additionalProperties = false,
}
local usage = "Calls return completed values; do not await them. Each operation accepts one named object. Read a resource namespace's help(), then help('functionName') for full parameters and examples. Only configured operations are listed. Read-only connections also allow POST-based name composition, matching and change queries. FamilySearch application approval and account permissions remain authoritative."
local exports: Object = {help = {
	text = "FamilySearch " .. (if config.environment == "beta" then "Beta" else "production") .. ". Explore resource namespaces with help(); use a resource's help('functionName') for parameters and examples.",
	functions = {}, namespaces = {}, sections = {usage = usage},
}}

-- Only enabled operations create scope nodes, so every listed namespace is usable.
local function namespace(path: string): (Object, string)
	local parts = string.split(path, ".")
	local node = exports
	local prefix = ""
	for index = 1, #parts - 1 do
		local part = parts[index]
		prefix = if prefix == "" then part else prefix .. "." .. part
		if node[part] == nil then
			local description = namespaceDescriptions[prefix]
			assert(description ~= nil, "missing namespace summary: " .. prefix)
			node[part] = {help = {text = description, functions = {}, namespaces = {}, sections = {usage = usage}}}
			node.help.namespaces[part] = description
		end
		node = node[part]
	end
	return node, parts[#parts]
end

local function options(input: Object?): Object
	if input == nil then return {} end
	assert(type(input) == "table" and input ~= NULL, "options must be an object")
	for key in input do assert(type(key) == "string", "options must have named fields") end
	return table.clone(input)
end

local function scalar(value: any, schema: Object, field: string): string
	local kind = type(value)
	local expected = schema.type
	assert(value ~= NULL and (kind == "string" or kind == "number" or kind == "boolean"), field .. " must be a scalar")
	assert(expected == nil or expected == kind or (expected == "integer" and kind == "number"), field .. " must be " .. tostring(expected))
	if kind == "number" then
		assert(value == value and math.abs(value) < math.huge, field .. " must be finite")
		if expected == "integer" then assert(value == math.floor(value), field .. " must be an integer") end
		if schema.minimum ~= nil then assert(value >= schema.minimum, field .. " is below its minimum") end
		if schema.maximum ~= nil then assert(value <= schema.maximum, field .. " is above its maximum") end
	elseif kind == "string" then
		assert(not string.find(value, "[%z\1-\8\11\12\14-\31\127]"), field .. " contains a control character")
		if schema.minLength ~= nil then assert(#value >= schema.minLength, field .. " is too short") end
		if schema.maxLength ~= nil then assert(#value <= schema.maxLength, field .. " is too long") end
	end
	if schema.enum then assert(table.find(schema.enum, value), field .. " is not a supported value") end
	return tostring(value)
end

local function responseHeaders(response: HttpResponse): {[string]: {string}}
	local headers: {[string]: {string}} = {}
	for key, value in response.headers do
		local lower = string.lower(key)
		if RESPONSE_HEADERS[lower] then headers[lower] = value end
	end
	return headers
end

local function fail(name: string, endpoint: Endpoint, response: HttpResponse): never
	local raw = await(response.body:readPrefix(4096))
	local ok, body = pcall(json.decode, raw)
	local detail = ""
	if ok and type(body) == "table" then
		local message = body.message or body.error_description
		if type(body.errors) == "table" and type(body.errors[1]) == "table" then message = body.errors[1].message or message end
		if type(message) == "string" then detail = ": " .. string.sub(message, 1, 500) end
	end
	local status = response.statusCode
	if status == 401 then detail ..= ". Reconnect the FamilySearch account or replace the expired access token."
	elseif status == 403 then detail ..= ". The account or approved application does not have permission for this operation." end
	local retry = response.headers["retry-after"]
	if retry and retry[1] then detail ..= " Retry-After: " .. string.sub(retry[1], 1, 64) end
	if not endpoint.read then detail ..= " A failed write may already have applied; inspect the resource before retrying." end
	return houston.fail({operation = name, layer = "upstream", upstream_status = status,
		retryable = endpoint.read and (status == 429 or status >= 500), message = "FamilySearch HTTP " .. tostring(status) .. detail})
end

local function accepted(name: string, endpoint: Endpoint, response: HttpResponse)
	local status = response.statusCode
	local notModified = status == 304 and endpoint.read and (endpoint.method == "GET" or endpoint.method == "HEAD")
	if status < 200 or (status >= 300 and not notModified and not table.find(endpoint.success, status)) then fail(name, endpoint, response) end
end

local function decode(name: string, endpoint: Endpoint, response: HttpResponse): Object
	accepted(name, endpoint, response)
	local result: Object = {statusCode = response.statusCode, headers = responseHeaders(response)}
	if endpoint.method == "HEAD" or response.statusCode == 204 or response.statusCode == 304 or response.statusCode >= 300 then
		response.body:close()
		return result
	end
	local raw = await(response.body:readAll())
	if string.match(raw, "^%s*$") then
		if endpoint.read and endpoint.method == "GET" then
			houston.fail({operation = name, layer = "upstream", upstream_status = response.statusCode, retryable = false,
				message = "FamilySearch returned an empty JSON response for a successful read."})
		end
		return result
	end
	local ok, value = pcall(json.decode, raw)
	if not ok then
		houston.fail({operation = name, layer = "upstream", upstream_status = response.statusCode, retryable = false,
			message = "FamilySearch returned invalid JSON. A successful mutation may already have applied; inspect the resource before retrying."})
	end
	result.data = value
	return result
end

local function prepare(endpoint: Endpoint, input: Object?): (string, {[string]: {string}}, Object)
	local args = options(input)
	local path = string.gsub(endpoint.path, "{([%w_]+)}", function(field: string): string
		local value = args[field]
		args[field] = nil
		local parameter = endpoint.params[field]
		if parameter then scalar(value, parameter.schema, field) end
		return url.segment(value, field)
	end)
	local headers: {[string]: {string}} = {Accept = {endpoint.accept}}
	local inputHeaders = args.headers
	args.headers = nil
	if inputHeaders ~= nil then
		assert(type(inputHeaders) == "table" and inputHeaders ~= NULL, "headers must be an object")
		for field, value in inputHeaders do
			local parameter = endpoint.params[field]
			local schema = COMMON_HEADERS[field] or (if parameter and parameter.location == "header" then parameter.schema else nil)
			assert(schema ~= nil, "unsupported header " .. tostring(field))
			local text = scalar(value, schema, field)
			assert(not string.find(text, "[\r\n]"), "headers cannot contain line breaks")
			headers[field] = {text}
		end
	end
	for field, parameter in endpoint.params do
		if parameter.location == "header" and parameter.required then assert(headers[field], field .. " header is required") end
	end
	local query: {string} = {}
	for field, parameter in endpoint.params do
		if parameter.location == "query" then
			local value = args[field]
			args[field] = nil
			local schema = parameter.schema
			if field == "count" then
				schema = table.clone(schema)
				schema.type = "integer" -- A few provider pages label numeric counts as strings.
				if value == nil then value = math.min(100, schema.maximum or MAX_COUNT) end
			end
			if value ~= nil then
				if field == "count" then assert(type(value) == "number" and value >= 1 and value <= MAX_COUNT and value == math.floor(value), "count must be an integer from 1 to 1000") end
				table.insert(query, url.encode(field) .. "=" .. url.encode(scalar(value, schema, field)))
			else assert(not parameter.required, field .. " is required") end
		end
	end
	if endpoint.dynamicQuery then
		for field, value in args do
			if string.match(field, "^[qfc]%.[%w_.]+$") then
				table.insert(query, url.encode(field) .. "=" .. url.encode(scalar(value, {type = "string"}, field)))
				args[field] = nil
			end
		end
	end
	table.sort(query)
	return API .. path .. (if #query > 0 then "?" .. table.concat(query, "&") else ""), headers, args
end

local function noExtra(args: Object)
	local key = next(args)
	assert(key == nil, "unsupported option " .. tostring(key))
end

local function request(name: string, endpoint: Endpoint, input: Object?): Object
	local target, headers, args = prepare(endpoint, input)
	local body = args.body
	args.body = nil
	local encoded: string? = nil
	if endpoint.body then
		assert(body ~= nil or not endpoint.body.required, "body is required")
		if body ~= nil then
			assert(type(body) == "table" and body ~= NULL, "body must be a JSON document object")
			for key in body do assert(type(key) == "string", "body must be a JSON document object") end
			headers["Content-Type"] = {endpoint.body.contentType}
			encoded = json.encode(body)
		end
	else assert(body == nil, "this operation has no request body") end
	noExtra(args)
	return decode(name, endpoint, await(http.request({method = endpoint.method, url = target, headers = headers, body = encoded})))
end

local function inputSchema(endpoint: Endpoint): Object
	local properties: Object = {}
	local required: {string} = {}
	local headerProperties: Object = table.clone(COMMON_HEADERS)
	local headerRequired: {string} = {}
	for field, parameter in endpoint.params do
		if parameter.location == "header" then
			headerProperties[field] = parameter.schema
			if parameter.required then table.insert(headerRequired, field) end
		else
			properties[field] = parameter.schema
			if parameter.required then table.insert(required, field) end
		end
	end
	if properties.count then
		properties.count = table.clone(properties.count)
		properties.count.type = "integer"
		properties.count.minimum = math.max(properties.count.minimum or 1, 1)
		properties.count.maximum = math.min(properties.count.maximum or MAX_COUNT, MAX_COUNT)
		properties.count.default = math.min(100, properties.count.maximum)
	end
	properties.headers = {type = "object", properties = headerProperties, additionalProperties = false}
	if #headerRequired > 0 then properties.headers.required = headerRequired; table.insert(required, "headers") end
	if endpoint.body then
		properties.body = endpoint.body.schema
		if endpoint.body.required then table.insert(required, "body") end
	end
	local schema: Object = {type = "object", properties = properties, additionalProperties = false, examples = {endpoint.example}}
	if endpoint.dynamicQuery then schema.patternProperties = {["^[qfc]\\.[A-Za-z0-9_.]+$"] = {type = "string"}} end
	if #required > 0 then table.sort(required); schema.required = required end
	return schema
end

for name, endpoint in catalog do
	if not endpoint.custom and (endpoint.read or houston.allows("data:write")) then
		local node, localName = namespace(endpoint.export)
		node.help.functions[localName] = {
			description = endpoint.description .. "\n" .. endpoint.method .. " " .. endpoint.path .. "\n" .. endpoint.doc
				.. "\nReturns {statusCode, data?, headers}; data is the unmodified JSON document, including any errors or partial results: inspect those before assuming every requested resource succeeded. Headers use lowercase names and string arrays. Empty 204/304/HEAD and documented redirects have no data; inspect Location for moved/current resources. One provider page per call: use its returned links and the named offset/start/from/count options for the next call; no automatic traversal. count defaults to 100 when supported, maximum 1000 (or the endpoint's smaller limit). Preserve all filters when paging. JSON null is truthy in Luau."
				.. (if endpoint.read then "" else "\nChanges FamilySearch data. Inspect HTTP status and returned Location/X-Entity-Id; 204 confirms a completed update/deletion. Do not automatically replay an interrupted or failed write: it may have applied."),
			inputSchema = inputSchema(endpoint), outputSchema = resultSchema,
			annotations = {readOnlyHint = endpoint.read, openWorldHint = true},
		}
		node[localName] = function(input: Object?): Object return request(name, endpoint, input) end
	end
end

-- Binary uploads use session files, never byte strings in the operation arguments.
local function uploadTypes(name: string, useMultipart: boolean?): {string}
	if name == "createGenealogiesMedia" or name == "updateGenealogiesMedia" then return {"text/html"} end
	if name == "updateMemoryArtifact" then return {"text/plain"} end
	if useMultipart then return {"image/jpeg", "image/png", "image/gif", "image/bmp", "image/tiff", "application/pdf", "text/plain", "audio/mpeg", "audio/mp4"} end
	if name == "createPersonMemory" then return {"image/jpeg", "image/png", "image/gif", "application/pdf", "text/plain"} end
	return {"image/jpeg", "image/png", "application/pdf", "text/plain"}
end

local function upload(name: string, input: Object): Object
	local endpoint = catalog[name]
	local target, headers, args = prepare(endpoint, input)
	local path, contentType = args.path, args.contentType
	local useMultipart = args.multipart
	args.path, args.contentType, args.multipart = nil, nil, nil
	assert(type(path) == "string" and #path > 0, "path must name a session file")
	assert(useMultipart == nil or type(useMultipart) == "boolean", "multipart must be a boolean")
	assert(not useMultipart or name == "createMemories" or name == "createPersonMemory", "multipart is supported for creating memories only")
	local allowed = uploadTypes(name, useMultipart)
	assert(type(contentType) == "string" and table.find(allowed, contentType), "contentType must be a supported memory media type; artifact replacement supports text/plain stories")
	noExtra(args)
	headers["Content-Type"] = {contentType}
	local filename = input.filename or string.match(path, "[^/]+$")
	if useMultipart then assert(type(filename) == "string" and #filename > 0 and #filename <= 255 and not string.find(filename, "[%c]"), "filename must be a nonempty filename without controls, at most 255 bytes") end
	local file = fs.open(path, "r")
	local body: Reader = file
	if useMultipart then
		local ok, form = pcall(multipart.create, {{name = "artifact", filename = filename, contentType = contentType, body = file}})
		if not ok then await(file:close()); error(form, 0) end
		body = form.body
		headers["Content-Type"] = {form.contentType}
	end
	local result = decode(name, endpoint, await(http.request({method = "POST", url = target, headers = headers, body = body})))
	if name == "createMemories" or name == "createPersonMemory" or name == "createGenealogiesMedia" then
		local location, entity = result.headers.location, result.headers["x-entity-id"]
		if not ((location and type(location[1]) == "string" and #location[1] > 0) or (entity and type(entity[1]) == "string" and #entity[1] > 0)) then
			houston.fail({operation = name, layer = "upstream", upstream_status = result.statusCode, retryable = false,
				message = "FamilySearch accepted the upload but returned no Location or X-Entity-Id. It may have been created; inspect existing media before retrying."})
		end
	end
	return result
end

local function uploadHelp(name: string): Object
	local endpoint = catalog[name]
	local schema = inputSchema(endpoint)
	schema.properties.path = {type = "string", minLength = 1, description = "Session file to stream."}
	schema.properties.contentType = {type = "string", enum = uploadTypes(name, true)}
	if name == "createMemories" or name == "createPersonMemory" then
		schema.properties.multipart = {type = "boolean", default = false, description = "Use a streamed multipart/form-data artifact part. Required for BMP/TIFF/GIF (where not accepted raw) and MP3/M4A audio."}
	end
	local required = schema.required or {}
	table.insert(required, "path")
	table.insert(required, "contentType")
	schema.required = required
	local detail = if name == "createGenealogiesMedia" or name == "updateGenealogiesMedia"
		then "Streams an HTML session file as the raw request body."
		else "Streams one session file. Raw upload accepts the endpoint's documented JPEG/PNG/PDF/plain-text media (person memories also GIF). Set multipart=true for a native streaming artifact part; this also supports image/gif, image/bmp, image/tiff, audio/mpeg (MP3) and audio/mp4 (M4A). filename defaults to the session basename. Supply title/description/filename/type query metadata where documented. Multi-file multipart/mixed batches are not exposed: upload each file separately. Artifact replacement currently accepts text/plain stories only. FamilySearch enforces media limits. Supported formats: https://developers.familysearch.org/main/docs/compatibility-checklist and https://developers.familysearch.org/main/docs/memories-dir"
	return {description = endpoint.description .. "\n" .. endpoint.doc
		.. "\n" .. detail .. " Returns {statusCode, data?, headers}; Location identifies created media. A failed/interrupted upload may already have created it; check before retrying. Upload only content the account holder has permission to share and has agreed to FamilySearch's upload terms.",
		inputSchema = schema, outputSchema = resultSchema, annotations = {readOnlyHint = false, openWorldHint = true}}
end

if houston.allows("data:write") then
	local memories = namespace(catalog.createMemories.export)
	memories.help.functions.createMemories = uploadHelp("createMemories")
	function memories.createMemories(input: Object): Object return upload("createMemories", input) end

	local personMemories = namespace(catalog.createPersonMemory.export)
	personMemories.help.functions.createPersonMemory = uploadHelp("createPersonMemory")
	function personMemories.createPersonMemory(input: Object): Object return upload("createPersonMemory", input) end

	local artifacts = namespace(catalog.updateMemoryArtifact.export)
	artifacts.help.functions.updateMemoryArtifact = uploadHelp("updateMemoryArtifact")
	function artifacts.updateMemoryArtifact(input: Object): Object return upload("updateMemoryArtifact", input) end

	local media = namespace(catalog.createGenealogiesMedia.export)
	media.help.functions.createGenealogiesMedia = uploadHelp("createGenealogiesMedia")
	function media.createGenealogiesMedia(input: Object): Object return upload("createGenealogiesMedia", input) end

	local updatedMedia = namespace(catalog.updateGenealogiesMedia.export)
	updatedMedia.help.functions.updateGenealogiesMedia = uploadHelp("updateGenealogiesMedia")
	function updatedMedia.updateGenealogiesMedia(input: Object): Object return upload("updateGenealogiesMedia", input) end
end

local function download(name: string, endpoint: Endpoint, target: string, headers: {[string]: {string}}, path: string): Object
	local response = await(http.request({method = "GET", url = target, headers = headers}))
	accepted(name, endpoint, response)
	local result: Object = {statusCode = response.statusCode, headers = responseHeaders(response)}
	if response.statusCode ~= 200 then response.body:close(); return result end
	local output = fs.open(path, "w")
	output:write(response.body)
	await(output:close())
	result.path, result.url, result.size = path, await(fs.signedGetUrl(path)), await(fs.stat(path)).size
	return result
end

local downloadSchema = {type = "object", properties = {
	statusCode = {type = "integer"}, headers = resultSchema.properties.headers,
	path = {type = "string"}, url = {type = "string"}, size = {type = "integer"},
}, required = {"statusCode", "headers"}, additionalProperties = false}

local mediaSchema = inputSchema(catalog.readGenealogiesMedia)
mediaSchema.properties.path = {type = "string", minLength = 1}
table.insert(mediaSchema.required, "path")
local media = namespace(catalog.readGenealogiesMedia.export)
media.help.functions.readGenealogiesMedia = {
	description = catalog.readGenealogiesMedia.description .. " Returns {statusCode, headers, path?, url?, size?}; url is a signed Houston download link. Redirects are returned with their Location and are not followed. " .. catalog.readGenealogiesMedia.doc,
	inputSchema = mediaSchema, outputSchema = downloadSchema, annotations = {readOnlyHint = true, openWorldHint = true},
}
function media.readGenealogiesMedia(input: Object): Object
	local endpoint = catalog.readGenealogiesMedia
	local target, headers, args = prepare(endpoint, input)
	local path = args.path
	args.path = nil
	assert(type(path) == "string" and #path > 0, "path must name a session file")
	noExtra(args)
	return download("readGenealogiesMedia", endpoint, target, headers, path)
end

local artifacts = namespace(catalog.downloadMemoryArtifact.export)
artifacts.help.functions.downloadMemoryArtifact = {
	description = "Stream a memory's artifact from the documented /platform/memories/artifacts/{mid} route to a session file. variant selects original (default), thumbnail or icon. Returns {statusCode, headers, path?, url?, size?}; url is a signed Houston download link. If the provider redirects, returns only statusCode and headers so the caller can inspect Location; external hosts are never followed. Documentation: https://developers.familysearch.org/main/docs/read-memory",
	inputSchema = {type = "object", properties = {
		mid = {type = "string", minLength = 1}, path = {type = "string", minLength = 1},
		variant = {type = "string", enum = {"original", "thumbnail", "icon"}},
	}, required = {"mid", "path"}, additionalProperties = false, examples = {{mid = "ARXX-MMM", path = "downloads/memory.jpg"}}},
	outputSchema = downloadSchema,
	annotations = {readOnlyHint = true, openWorldHint = true},
}
function artifacts.downloadMemoryArtifact(input: Object): Object
	local args = options(input)
	local mid, path, variant = args.mid, args.path, args.variant or "original"
	args.mid, args.path, args.variant = nil, nil, nil
	noExtra(args)
	assert(type(path) == "string" and #path > 0, "path must name a session file")
	assert(table.find({"original", "thumbnail", "icon"}, variant), "variant must be original, thumbnail or icon")
	local endpoint = catalog.downloadMemoryArtifact
	local target, headers = prepare(endpoint, {mid = mid})
	if variant ~= "original" then target ..= "?" .. variant end
	return download("downloadMemoryArtifact", endpoint, target, headers, path)
end

return exports
