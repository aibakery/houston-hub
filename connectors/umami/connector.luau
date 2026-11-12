-- Umami's JSON shapes are preserved. Resource namespaces guide discovery. Every request is one
-- bounded operation; endpoint records own routes, access, schemas and help.
type Options = {[string]: any}
type Parameter = {name: string, location: string, required: boolean, schema: string, description: string?}
type Endpoint = {export: string, method: string, path: string, group: string, read: boolean, cloud: boolean,
	parameters: string, description: string, body: string?, response: string?, text: boolean?, filters: boolean, example: string}
local endpoints: {[string]: Endpoint} = require("lib/endpoints.luau")
local namespaceDescriptions: {[string]: string} = require("lib/namespaces.luau")
local schemas = require("lib/schemas.luau")
local validate = require("lib/validate.luau")
local SELF_HOSTED = config.deployment == "self-hosted"
local PREFIX = if SELF_HOSTED then "/api" elseif config.deployment == "cloud" then "/v1" else "/v1/" .. config.deployment
local API = "https://" .. config.host .. PREFIX
local NULL = json.decode("null")
local MAX_BYTES = 8 * 1024 * 1024
local exports: {[string]: any} = {}
local FILTER_FIELDS = {path=true, entry=true, exit=true, referrer=true, domain=true, hostname=true,
	distinctId=true, title=true, query=true, os=true, browser=true, device=true, country=true,
	region=true, city=true, language=true, event=true, tag=true, eventType=true,
	utmSource=true, utmMedium=true, utmCampaign=true, utmContent=true, utmTerm=true}

local function object(value: any, label: string): Options
	assert(type(value) == "table" and value ~= NULL, label .. " must be an object")
	for key in value do assert(type(key) == "string", label .. " must have named fields") end
	return table.clone(value)
end

local function fail(name: string, status: number, message: string): never
	return houston.fail({operation = name, layer = "upstream", upstream_status = status,
		retryable = status == 429 or status >= 500, message = message})
end

local function responseJSON(name: string, endpoint: Endpoint, response: HttpResponse): any
	local status = response.statusCode
	if status < 200 or status >= 300 then
		local raw = await(response.body:readPrefix(4096))
		local ok, value = pcall(json.decode, raw)
		local message = "Umami HTTP " .. tostring(status)
		if ok and type(value) == "table" and type(value.error) == "table" then
			if type(value.error.code) == "string" then message ..= " (" .. string.sub(value.error.code, 1, 80) .. ")" end
			if type(value.error.message) == "string" then message ..= ": " .. string.sub(value.error.message, 1, 512) end
		end
		local retry = response.headers["retry-after"]
		if retry and retry[1] then message ..= "; Retry-After: " .. string.sub(retry[1], 1, 80) end
		return fail(name, status, message)
	end
	local raw = await(response.body:readAll(MAX_BYTES))
	if endpoint.text then return raw end
	local ok, value = pcall(json.decode, raw)
	if not ok then return fail(name, status, "Umami returned invalid JSON") end
	if type(value) == "table" and (value.error ~= nil or value.ok == false) then
		return fail(name, status, "Umami did not confirm the operation; inspect the resource before retrying")
	end
	if endpoint.response then
		local valid = pcall(validate, value, schemas[endpoint.response], "response")
		if not valid then return fail(name, status, "Umami returned an unexpected response shape") end
	end
	return value
end

local function queryValue(value: any, parameter: Parameter): string
	local schema = schemas[parameter.schema]
	-- These query parameters carry JSON arrays in Umami's API.
	if schema.type == "string" and (parameter.name == "steps" or parameter.name == "fields") and type(value) == "table" then value = json.encode(value) end
	if schema.type == "string" and type(value) == "boolean"
		and (parameter.name == "includeTeams" or parameter.name == "excludeBounce"
			or (schema.enum and table.find(schema.enum, tostring(value)))) then value = tostring(value) end
	validate(value, schema, parameter.name)
	assert(type(value) == "string" or type(value) == "number" or type(value) == "boolean", parameter.name .. " must be a scalar query value")
	return url.encode(value)
end

local function request(name: string, endpoint: Endpoint, input: Options?): any
	local args = object(input or {}, "options")
	local filter: Options = if args.filter ~= nil then object(args.filter, "filter") else {}
	args.filter = nil
	local parameters: {Parameter} = schemas[endpoint.parameters].parameters
	local path = endpoint.path
	local query: {string} = {}
	for _, parameter in parameters do
		local field = parameter.name
		local value = args[field]
		args[field] = nil
		if parameter.location == "query" and filter[field] ~= nil then
			assert(value == nil, field .. " is present both in options and filter")
			value = filter[field]
			filter[field] = nil
		end
		assert(not parameter.required or value ~= nil, field .. " is required")
		-- Umami treats any nonempty string as enabled for these presence flags.
		if (field == "includeTeams" or field == "excludeBounce") and value == false then value = nil end
		if value ~= nil then
			if parameter.location == "path" then
				validate(value, schemas[parameter.schema], field)
				local segment = url.segment(value, field)
				path = string.gsub(path, "{" .. field .. "}", function() return segment end)
			else
				table.insert(query, url.encode(field) .. "=" .. queryValue(value, parameter))
			end
		end
	end
	-- Umami retains numbered dimensions and custom event/session properties in
	-- analytics queries. Keep them inside filter so they cannot override options.
	for field, value in filter do
		local base = string.gsub(field, "%d+$", "")
		local dynamic = FILTER_FIELDS[base] or string.match(field, "^pf_.+")
			or string.match(field, "^epf%d+$") or string.match(field, "^spf%d+$")
		assert(endpoint.filters and dynamic, name .. " received an unsupported filter")
		assert(type(value) == "string" and #value <= 8192, "dynamic filters must be strings of at most 8192 bytes")
		table.insert(query, url.encode(field) .. "=" .. url.encode(value))
	end
	local body = args.body
	args.body = nil
	if endpoint.body then
		assert(body ~= nil, "body is required")
		validate(body, schemas[endpoint.body], "body")
	else
		assert(body == nil, name .. " does not accept a body")
	end
	local headers: HttpHeaders = {["Accept"] = {if endpoint.text then "text/javascript" else "application/json"}}
	if endpoint.group == "collection" then
		if args.cache ~= nil then
			assert(type(args.cache) == "string" and #args.cache > 0 and #args.cache <= 16384, "cache must be a session cache token")
			headers["x-umami-cache"] = {args.cache}
		end
		if name == "record" and body and body.payload and #body.payload.events > 0 then assert(args.cache ~= nil, "record requires the cache returned by send") end
		args.cache = nil
	end
	local destination = if name == "exportWebsite" then args.destination else nil
	if name == "exportWebsite" then args.destination = nil end
	if destination ~= nil then assert(type(destination) == "string" and destination ~= "", "destination must be a session file path") end
	assert(next(args) == nil, name .. " received an unknown option")
	if #query > 0 then path ..= "?" .. table.concat(query, "&") end
	local encoded: string? = nil
	if body ~= nil then
		local bytes = json.encode(body)
		assert(#bytes <= (if name == "record" then 1000000 else MAX_BYTES), "request body is too large")
		encoded = bytes
		headers["Content-Type"] = {"application/json"}
	end
	local value = responseJSON(name, endpoint, await(http.request({method = endpoint.method,
		url = API .. path, headers = headers, body = encoded})))
	if destination then
		-- The provider itself returns base64 JSON, so this export is necessarily
		-- bounded in memory. Regular JSON operations never open session files.
		local bytes = base64.decode(value.zip)
		local output = fs.open(destination, "w")
		local saved, err = pcall(function() output:write(bytes); await(output:close()) end)
		if not saved then output:cancel(); pcall(function() await(output:close()) end); error(err, 0) end
		return {path = destination, size = await(fs.stat(destination)).size, url = await(fs.signedGetUrl(destination))}
	end
	return value
end

local usage = {
		"Umami 3.4.1 API. Call functions directly, without await. Read help() on a resource namespace, then help('functionName') for complete request/response schemas. Only configured operations are listed.",
		"Each function takes one options object: path IDs and query options at the top level, JSON request bodies under body. A filter object accepts the operation's query fields (for example country, browser, path, event, search); do not repeat a field at both levels. Native filter strings preserve Umami operators such as eq.US and c.pricing. match='all' or 'any' applies where listed. Arrays for steps/fields are JSON-encoded automatically.",
		"Dates use startAt/endAt Unix milliseconds or the operation's documented date/period alternatives. Lists fetch one page: increment page while page*pageSize<count, or use limit/offset where listed. No hidden paging, polling or mutation retries. Smaller pages/date ranges keep JSON responses within 8 MiB. Preserve null with json.decode('null') and empty arrays with json.decode('[]').",
		"Results retain Umami fields and pagination. batch returns processed/errors/details: inspect each failure before resending. A failed or timed-out write may already have succeeded. HTTP errors include status, provider code/message and Retry-After. Cloud allows 50 calls per 15 seconds; provider roles and feature availability still apply.",
		"Collection send/batch/record accept cache (the x-umami-cache token returned by send/batch). Nonempty record requires cache and accepts at most 200 events and 1,000,000 encoded bytes. websites.export optionally accepts destination to save the provider's base64 ZIP to a session file and return {path,size,url}; without it the original {zip} is returned. system.telemetryScript returns JavaScript as text, never executes it.",
		"API keys and bearer tokens are configured in connection settings, never operation arguments. Login and two-factor login verification happen outside caller scripts. Account write access includes credential administration and can issue new credentials; grant it only when intended. Cloud hides user-management and password-change operations.",
		"Examples: websites.list({page=1,pageSize=20,filter={search='Store',includeTeams=true}}); websites.analytics.metrics({websiteId='123e4567-e89b-42d3-a456-426614174000',startAt=1767225600000,endAt=1767312000000,type='path',filter={country='US',browser='Chrome'}}); websites.create({body={name='Demo',domain='example.com'}}).",
	}

local usageText = table.concat(usage, "\n")

local function expand(schema: any): any
 if type(schema) ~= "table" then return schema end
 if schema["$ref"] then return expand(schemas[schema["$ref"]]) end
 local result: Options = {}
 for key, value in schema do
  if key ~= "enum" or #value > 0 then result[key] = expand(value) end
 end
 return result
end

-- Ordinary nested tables are the callable surface. Namespace metadata contains
-- only local functions/children, so the root overview stays small.
exports.help = {text = "Umami 3.4.1 API. Explore resource namespaces with help(), then call a namespace's help('functionName') for parameters and examples. Only configured operations are listed.",
 functions = {}, namespaces = {}, sections = {usage = usageText}}
local function namespace(path: string): (Options, string)
 local parts = string.split(path, ".")
 local node = exports
 local prefix = ""
 for index = 1, #parts - 1 do
  local part = parts[index]
  prefix = if prefix == "" then part else prefix .. "." .. part
  if node[part] == nil then
   local description = namespaceDescriptions[prefix]
   assert(description ~= nil, "missing namespace summary: " .. prefix)
   node[part] = {help = {text = description, functions = {}, namespaces = {}, sections = {usage = usageText}}}
   node.help.namespaces[part] = description
  end
  node = node[part]
 end
 return node, parts[#parts]
end
for name, endpoint in endpoints do
 local access = if config.access == "custom" then config[endpoint.group] else config.access
 if (SELF_HOSTED or endpoint.cloud) and (access == "read-write" or (access == "read-only" and endpoint.read)) then
  local properties: Options = {}
  local filters: Options = {}
  local required: {string} = json.decode("[]")
  for _, p in schemas[endpoint.parameters].parameters do
   local schema = expand(schemas[p.schema])
   schema.description = if type(p.description) == "string" then p.description else p.name
   if p.location == "query" then
    if schema.type == "string" and (p.name == "includeTeams" or p.name == "excludeBounce"
      or (schema.enum and table.find(schema.enum,"true") and table.find(schema.enum,"false"))) then
     schema = {anyOf={schema,{type="boolean"}},description=schema.description}
    end
    if schema.type == "string" and (p.name == "steps" or p.name == "fields") then schema = {anyOf={schema,{type="array"}}} end
    filters[p.name] = schema
   elseif p.required then table.insert(required, p.name) end
   properties[p.name] = schema
  end
  properties.filter = {type="object",properties=filters,additionalProperties=endpoint.filters,
   description="Combine the documented query fields. Analytics also accept numbered dimensions (country1), pf_property, epf0 and spf0 property filters in Umami's native string syntax. Required query fields must appear here or at the top level."}
  if endpoint.body then properties.body = expand(schemas[endpoint.body]); table.insert(required,"body") end
  if endpoint.group == "collection" then properties.cache = {type="string",minLength=1,maxLength=16384,description="Session cache token returned by send/batch; required for nonempty record."} end
  if name == "exportWebsite" then properties.destination = {type="string",minLength=1,description="Optional session path for the decoded ZIP; returns {path,size,url} instead of {zip}."} end
  local input: Options = {type="object",properties=properties,required=required,additionalProperties=false,examples={json.decode(endpoint.example)}}
  if name == "listWebsites" then input.examples = {{page=1,pageSize=20,filter={search="Store",includeTeams=true}}}
  elseif name == "getWebsiteMetrics" then input.examples = {{websiteId="123e4567-e89b-42d3-a456-426614174000",startAt=1767225600000,endAt=1767312000000,type="path",filter={country="US",browser="Chrome"}}}
  elseif name == "createWebsite" then input.examples = {{body={name="Demo",domain="example.com"}}} end
  local returns = if endpoint.text then "JavaScript source text (never executed)." elseif endpoint.response then json.encode(expand(schemas[endpoint.response])) else "Provider JSON."
  local node, localName = namespace(endpoint.export)
  node.help.functions[localName] = {description=endpoint.description .. " Access area: " .. endpoint.group .. ". Read help('usage') for shared request, filter and pagination conventions. Returns: " .. returns,
   inputSchema=input,annotations={readOnlyHint=endpoint.read,openWorldHint=true}}
  node[localName] = function(args: Options?): any return request(name, endpoint, args) end
 end
end
return exports
