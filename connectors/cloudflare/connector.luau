-- Cloudflare API v4 and its GraphQL Analytics API. Arguments and results keep Cloudflare's native snake_case field names.
type Options = {[string]: any}
type Endpoint = {method: string, path: string, query: {string}?, extra: {string}?, required: {string}?, write: boolean?, body: (boolean | string)?,
	fields: {string}?, perPage: number?, doc: string, about: string}

local PROVIDER = "Cloudflare"
local DOCS = "https://developers.cloudflare.com/"
local PAGE = {"page", "per_page"}
local DNS_FIELDS = {"type", "name", "content", "ttl", "proxied", "comment", "tags", "priority", "data", "settings", "private_routing"}

local function with(...: {string}): {string}
	local fields: {string} = {}
	for _, group in {...} do table.move(group, 1, #group, #fields + 1, fields) end
	return fields
end

-- Operations in Cloudflare's public OpenAPI (github.com/cloudflare/api-schemas), checked on
-- 2026-10-30, plus the GraphQL Analytics API. Path {fields} are required; listed query fields
-- are taken from the options and the other fields form the JSON body.
local endpoints: {[string]: Endpoint} = {
	listAccounts = {method = "GET", path = "/accounts", query = with({"name", "direction"}, PAGE), doc = "api/resources/accounts/methods/list/",
		about = "Accounts the token can reach: {id, name, type, settings, created_on}. An account token sees only its own account. per_page is 5 to 50."},
	getAccount = {method = "GET", path = "/accounts/{account_id}", doc = "api/resources/accounts/methods/get/", about = "One account."},

	listZones = {method = "GET", path = "/zones", query = with({"name", "status", "type", "account.id", "account.name", "match", "order", "direction"}, PAGE),
		doc = "api/resources/zones/methods/list/",
		about = "Zones (domains): {id, name, status, paused, type, name_servers, account={id, name}, plan, meta, created_on, modified_on}. name matches exactly, or with a prefix such as 'contains:shop' (also starts_with:, ends_with:). status: initializing, pending, active or moved. type: full, partial or secondary, or an array. order: name, status, account.id, account.name or plan.id; direction asc or desc. per_page is 5 to 50."},
	getZone = {method = "GET", path = "/zones/{zone_id}", doc = "api/resources/zones/methods/get/", about = "One zone, with its plan, name servers and status."},

	listDnsRecords = {method = "GET", path = "/zones/{zone_id}/dns_records",
		query = with({"type", "name", "name.contains", "name.startswith", "name.endswith", "content", "content.contains", "proxied", "comment.contains", "tag", "search", "match", "order", "direction"}, PAGE),
		perPage = 1000, doc = "api/resources/dns/subresources/records/methods/list/",
		about = "DNS records: {id, type, name, content, proxied, proxiable, ttl (1 is automatic), priority?, data?, comment, tags, settings, created_on, modified_on}. name is the full hostname, such as www.example.com. type: A, AAAA, CNAME, MX, TXT, NS, SRV, CAA and others. search matches any field; match='any' ORs the other filters. order: type (default), name, content, ttl or proxied. per_page is at most 1000 here (default 100)."},
	getDnsRecord = {method = "GET", path = "/zones/{zone_id}/dns_records/{dns_record_id}", doc = "api/resources/dns/subresources/records/methods/get/", about = "One DNS record."},

	getZoneAnalytics = {method = "POST", path = "/graphql", write = false, body = false, extra = {"zone_id", "since", "until", "granularity", "breakdowns"},
		required = {"zone_id", "since", "until"}, doc = "analytics/graphql-api/",
		about = "A zone's HTTP traffic over time, from Cloudflare's GraphQL Analytics API, as {data={viewer={zones=[{groups=[{dimensions={date or datetime}, sum={requests, cachedRequests, bytes, cachedBytes, encryptedRequests, encryptedBytes, threats, pageViews, ...breakdowns}, uniq={uniques}}]}]}}, errors}, oldest first. granularity 'day' (default) takes since and until as inclusive dates such as '2026-10-01'; 'hour' takes whole UTC hours such as '2026-10-29T00:00:00Z', with until excluded. breakdowns adds per-group lists, an array of: responseStatusMap {edgeResponseStatus, requests}, countryMap {clientCountryName, requests, bytes, threats}, contentTypeMap {edgeResponseContentTypeName, requests, bytes}, browserMap {uaBrowserFamily, pageViews}, clientSSLMap {clientSSLProtocol, requests}, clientHTTPVersionMap {clientHTTPProtocol, requests}, ipClassMap {ipType, requests}, threatPathingMap {threatPathingName, requests}. One request covers at most 1000 days or hours, or 100 with breakdowns; the zone's plan may allow less, and limits how far back data goes."},

	listWorkerScripts = {method = "GET", path = "/accounts/{account_id}/workers/scripts", query = {"tags"}, doc = "api/resources/workers/subresources/scripts/methods/list/",
		about = "The account's Workers, all at once: {id (the script name), created_on, modified_on, usage_model, handlers, compatibility_date, placement, tags, ...}."},
	listWorkerDeployments = {method = "GET", path = "/accounts/{account_id}/workers/scripts/{script_name}/deployments", query = with({"since", "until"}, PAGE),
		doc = "api/resources/workers/subresources/scripts/subresources/deployments/methods/list/",
		about = "A Worker's deployments, newest first, in result.deployments: {id, created_on, source, strategy='percentage', versions=[{version_id, percentage}], author_email, annotations={'workers/message', 'workers/triggered_by'}}. The first is the one serving traffic. since and until filter creation times (ISO 8601); per_page is at most 100 (default 10)."},
	listWorkerVersions = {method = "GET", path = "/accounts/{account_id}/workers/scripts/{script_name}/versions", query = with({"deployable"}, PAGE),
		doc = "api/resources/workers/subresources/scripts/subresources/versions/methods/list/",
		about = "A Worker's uploaded versions, newest first, in result.items: {id, number, metadata={created_on, author_email, source, hasPreview}, annotations}. deployable=true keeps those that can still be deployed."},
	getWorkerVersion = {method = "GET", path = "/accounts/{account_id}/workers/scripts/{script_name}/versions/{version_id}",
		doc = "api/resources/workers/subresources/scripts/subresources/versions/methods/get/",
		about = "One version with its bindings (names, types and non-secret values such as plain_text text and json; secret values are never returned), compatibility settings and metadata, but not its code."},

	listPagesProjects = {method = "GET", path = "/accounts/{account_id}/pages/projects", query = PAGE, doc = "api/resources/pages/subresources/projects/methods/list/",
		about = "Pages projects: {id, name, subdomain, domains, production_branch, source, build_config, latest_deployment, canonical_deployment, created_on}."},
	getPagesProject = {method = "GET", path = "/accounts/{account_id}/pages/projects/{project_name}", doc = "api/resources/pages/subresources/projects/methods/get/",
		about = "One project, with its deployment settings per environment (deployment_configs.production and .preview)."},
	listPagesDeployments = {method = "GET", path = "/accounts/{account_id}/pages/projects/{project_name}/deployments", query = with({"env"}, PAGE),
		doc = "api/resources/pages/subresources/projects/subresources/deployments/methods/list/",
		about = "A project's deployments, newest first: {id, short_id, url, environment, created_on, latest_stage={name, status}, deployment_trigger={type, metadata={branch, commit_hash, commit_message}}, aliases, is_skipped_build}. env: production or preview."},
	getPagesDeployment = {method = "GET", path = "/accounts/{account_id}/pages/projects/{project_name}/deployments/{deployment_id}",
		doc = "api/resources/pages/subresources/projects/subresources/deployments/methods/get/", about = "One deployment, with its build stages."},
	getPagesDeploymentLogs = {method = "GET", path = "/accounts/{account_id}/pages/projects/{project_name}/deployments/{deployment_id}/history/logs",
		doc = "api/resources/pages/subresources/projects/subresources/deployments/subresources/history/subresources/logs/methods/get/",
		about = "A deployment's build log: {total, includes_container_logs, data=[{ts, line}]}."},

	listR2Buckets = {method = "GET", path = "/accounts/{account_id}/r2/buckets", query = {"name_contains", "start_after", "per_page", "order", "direction", "cursor"},
		extra = {"jurisdiction"}, doc = "api/resources/r2/subresources/buckets/methods/list/",
		about = "R2 buckets in result.buckets: {name, creation_date, location, jurisdiction, storage_class}. Pages with cursor=result_info.cursor; per_page is at most 1000. jurisdiction 'eu', 'us', 'fedramp' or 'fedramp-high' lists the buckets kept there instead."},
	getR2Bucket = {method = "GET", path = "/accounts/{account_id}/r2/buckets/{bucket_name}", extra = {"jurisdiction"},
		doc = "api/resources/r2/subresources/buckets/methods/get/", about = "One bucket; pass jurisdiction for a bucket in one."},

	createDnsRecord = {method = "POST", path = "/zones/{zone_id}/dns_records", required = {"type", "name"}, fields = DNS_FIELDS,
		doc = "api/resources/dns/subresources/records/methods/create/",
		about = "Creates a record and returns it. Body {type, name, content, ttl? (1 automatic, else 60 to 86400 seconds, 30 on Enterprise), proxied? (A, AAAA and CNAME only), comment?, tags? ('name:value' strings), priority? (MX), data? (SRV, CAA and other structured types), settings?, private_routing?}. Cloudflare refuses an identical record and a CNAME next to other records of the same name."},
	updateDnsRecord = {method = "PATCH", path = "/zones/{zone_id}/dns_records/{dns_record_id}", fields = DNS_FIELDS,
		doc = "api/resources/dns/subresources/records/methods/edit/", about = "Changes only the given fields of a record and returns it."},
	deleteDnsRecord = {method = "DELETE", path = "/zones/{zone_id}/dns_records/{dns_record_id}", doc = "api/resources/dns/subresources/records/methods/delete/",
		about = "Deletes a record and returns {result={id}}."},
	purgeCache = {method = "POST", path = "/zones/{zone_id}/purge_cache", fields = {"purge_everything", "files", "tags", "hosts", "prefixes"},
		doc = "api/resources/cache/methods/purge/",
		about = "Removes cached content from every Cloudflare data center, so the next requests go to the origin. Body: exactly one of purge_everything=true, files (full URLs, or {url, headers} for cache keys with headers), tags (Cache-Tag values), hosts or prefixes (such as 'www.example.com/blog/'), at most 100 items (500 URLs on Enterprise). Free plans allow 5 purges of everything, hosts, tags or prefixes per minute."},
	createWorkerDeployment = {method = "POST", path = "/accounts/{account_id}/workers/scripts/{script_name}/deployments", required = {"strategy", "versions"},
		fields = {"strategy", "versions", "annotations"}, doc = "api/resources/workers/subresources/scripts/subresources/deployments/methods/create/",
		about = "Deploys existing versions, which serve traffic at once, and returns the deployment. Body {strategy='percentage', versions=[{version_id, percentage}] totalling 100, annotations?={['workers/message']=text}}. Roll back with one earlier version at 100 (one of the 100 most recent); Cloudflare refuses when a KV namespace, R2 bucket or queue it binds no longer exists, or Durable Object classes changed since. Bindings, routes and secrets stay as they are."},
	rollbackPagesDeployment = {method = "POST", path = "/accounts/{account_id}/pages/projects/{project_name}/deployments/{deployment_id}/rollback", body = false,
		doc = "api/resources/pages/subresources/projects/subresources/deployments/methods/rollback/",
		about = "Serves production from an earlier successful production deployment at once, without rebuilding, and returns it. Preview deployments are not valid targets."},
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

local API = "https://api.cloudflare.com/client/v4"

-- The GraphQL datasets behind getZoneAnalytics: daily or hourly HTTP request groups, which
-- every plan has. Each granularity takes one fixed format: a date, or a whole UTC hour.
local GRANULARITIES = {
	day = {node = "httpRequests1dGroups", dimension = "date", type = "Date", upto = "date_leq", format = "^%d%d%d%d%-%d%d%-%d%d$", example = "date such as 2026-10-01"},
	hour = {node = "httpRequests1hGroups", dimension = "datetime", type = "Time", upto = "datetime_lt", format = "^%d%d%d%d%-%d%d%-%d%dT%d%d:00:00Z$",
		example = "whole UTC hour such as 2026-10-01T00:00:00Z"},
}
local BREAKDOWNS = {
	responseStatusMap = "edgeResponseStatus requests", countryMap = "clientCountryName requests bytes threats",
	contentTypeMap = "edgeResponseContentTypeName requests bytes", browserMap = "uaBrowserFamily pageViews", clientSSLMap = "clientSSLProtocol requests",
	clientHTTPVersionMap = "clientHTTPProtocol requests", ipClassMap = "ipType requests", threatPathingMap = "threatPathingName requests",
}

-- At most this many groups per request, fewer with breakdowns, so each answer stays well
-- under the 8 MiB response bound.
local MAX_GROUPS, MAX_BREAKDOWN_GROUPS = 1000, 100

local DAYS_IN_MONTH = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31}

-- Hours since 1970-01-01 of a real date or whole UTC hour in the granularity's format, or nil.
-- Days use Howard Hinnant's days_from_civil.
local function hours(value: any, format: string): number?
	if type(value) ~= "string" or not string.match(value, format) then return nil end
	local y, m, d = tonumber(string.sub(value, 1, 4)) :: number, tonumber(string.sub(value, 6, 7)) :: number, tonumber(string.sub(value, 9, 10)) :: number
	local h = tonumber(string.sub(value, 12, 13)) or 0
	local leap = y % 4 == 0 and (y % 100 ~= 0 or y % 400 == 0)
	if m < 1 or m > 12 or d < 1 or d > DAYS_IN_MONTH[m] + (if m == 2 and leap then 1 else 0) or h > 23 then return nil end
	if m <= 2 then y -= 1 end
	local era = y // 400
	local yoe = y - era * 400
	local doy = (153 * (if m > 2 then m - 3 else m + 9) + 2) // 5 + d - 1
	return ((era * 146097 + yoe * 365 + yoe // 4 - yoe // 100 + doy) - 719468) * 24 + h
end

-- The analytics request body. The query text depends only on the granularity and breakdowns;
-- caller values travel as GraphQL variables.
local function analytics(endpoint: Endpoint, args: Options): string
	local zone, since, upto, granularity, breakdowns = args.zone_id, args.since, args["until"], args.granularity or "day", args.breakdowns
	for _, field in endpoint.extra or NONE do args[field] = nil end
	local set = if type(granularity) == "string" then GRANULARITIES[granularity] else nil
	assert(set, "granularity must be day or hour")
	assert(type(zone) == "string" and string.match(zone, "^%x+$"), "zone_id must be a zone id from listZones")
	local from, to = hours(since, set.format), hours(upto, set.format)
	assert(from, "since must be a real " .. set.example)
	assert(to, "until must be a real " .. set.example)
	local maps: {string} = {}
	if breakdowns ~= nil then
		assert(type(breakdowns) == "table", "breakdowns must be an array")
		for index, name in breakdowns do
			assert(type(index) == "number" and type(name) == "string" and BREAKDOWNS[name], "breakdowns has no item " .. tostring(name))
			table.insert(maps, name .. " { " .. BREAKDOWNS[name] .. " } ")
		end
	end
	local limit = if #maps > 0 then MAX_BREAKDOWN_GROUPS else MAX_GROUPS
	local groups = if granularity == "day" then (to - from) // 24 + 1 else to - from
	assert(groups > 0, "since must come before until")
	assert(groups <= limit, "since to until spans " .. groups .. " " .. granularity .. "s; ask for at most " .. limit)
	local query = string.format("query ZoneAnalytics($zoneTag: string, $since: %s, $until: %s) { viewer { zones(filter: {zoneTag: $zoneTag}) { "
		.. "groups: %s(limit: %d, orderBy: [%s_ASC], filter: {%s_geq: $since, %s: $until}) { dimensions { %s } "
		.. "sum { requests cachedRequests bytes cachedBytes encryptedRequests encryptedBytes threats pageViews %s} uniq { uniques } } } } }",
		set.type, set.type, set.node, limit, set.dimension, set.dimension, set.upto, set.dimension, table.concat(maps))
	return json.encode({query = query, variables = {zoneTag = string.lower(zone), since = since, ["until"] = upto}})
end

-- Cloudflare answers {success, errors=[{code, message, error_chain?}], messages, result,
-- result_info?}, and GraphQL {data, errors=[{message, path, extensions}]}, with errors null
-- on success. Either errors list becomes the failure message.
local function errorText(value: any): string?
	if type(value) ~= "table" or type(value.errors) ~= "table" or #value.errors == 0 then return nil end
	local parts: {string} = {}
	for _, item in value.errors do
		if type(item) == "table" then
			local text = if type(item.message) == "string" then item.message else json.encode(item)
			if type(item.code) == "number" then text = item.code .. " " .. text end
			if type(item.error_chain) == "table" then
				for _, cause in item.error_chain do
					if type(cause) == "table" and type(cause.message) == "string" then text ..= " (" .. cause.message .. ")" end
				end
			end
			table.insert(parts, text)
		end
	end
	return string.sub(table.concat(parts, "; "), 1, 600)
end

local function failStatus(name: string, response: HttpResponse): never
	local message = "Cloudflare HTTP " .. tostring(response.statusCode)
	local raw = await(response.body:readPrefix(16 * 1024))
	local ok, value = pcall(json.decode, raw)
	local text = if ok then errorText(value) else nil
	if text then message ..= ": " .. text end
	local retry = response.headers["retry-after"]
	if response.statusCode == 429 and retry and retry[1] then
		-- Retry-After is either delay seconds or an HTTP date.
		local value = string.sub(retry[1], 1, 32)
		message ..= "; retry after " .. value .. (if string.match(value, "^%d+$") then "s" else "")
	end
	return fail(name, response, message)
end

local function request(name: string, endpoint: Endpoint, input: Options?): any
	local args = options(input)
	local path = string.gsub(endpoint.path, "{([%w_]+)}", function(field: string)
		local value = args[field]
		args[field] = nil
		assert(type(value) == "string", field .. " is required and must be a string")
		local ok, segment = pcall(url.segment, value, field)
		assert(ok, field .. " must be a Cloudflare id or name")
		return segment
	end)
	for _, field in endpoint.required or NONE do
		assert(args[field] ~= nil and args[field] ~= NULL, field .. " is required")
	end
	if endpoint.perPage and args.per_page ~= nil then
		assert(type(args.per_page) == "number" and args.per_page >= 1 and args.per_page <= endpoint.perPage, "per_page must be 1 to " .. endpoint.perPage)
	end
	-- Cloudflare takes an array as comma-separated values, as type=full,partial.
	local query: {string} = {}
	for _, field in endpoint.query or NONE do
		if args[field] ~= nil then table.insert(query, field .. "=" .. table.concat(queryParts(args[field], field), ",")) end
		args[field] = nil
	end
	if #query > 0 then path ..= "?" .. table.concat(query, "&") end
	local headers: HttpHeaders = {Accept = {"application/json"}}
	if table.find(endpoint.extra or NONE, "jurisdiction") and args.jurisdiction ~= nil then
		assert(type(args.jurisdiction) == "string" and string.match(args.jurisdiction, "^[%a%-]+$"), "jurisdiction must be a name such as eu")
		headers["cf-r2-jurisdiction"] = {args.jurisdiction}
		args.jurisdiction = nil
	end
	if endpoint.fields then
		for field in args do assert(table.find(endpoint.fields :: {string}, field), name .. " has no option " .. field) end
	end
	local body: string? = nil
	if endpoint == endpoints.getZoneAnalytics then
		body = analytics(endpoint, args)
	elseif hasBody(endpoint) then
		assert(next(args) ~= nil, name .. " needs a body field")
		body = json.encode(args)
		args = {}
	end
	if body then headers["Content-Type"] = {"application/json"} end
	local unknown = next(args)
	assert(unknown == nil, name .. " has no option " .. tostring(unknown))
	local response = await(http.request({url = API .. path, method = endpoint.method, headers = headers, body = body}))
	if response.statusCode < 200 or response.statusCode >= 300 then failStatus(name, response) end
	local value = object(name, endpoint, response)
	local text = errorText(value)
	if text or (type(value) == "table" and value.success == false) then fail(name, response, "Cloudflare reported an error: " .. (text or "no details")) end
	return value
end

local intro = {
	"Cloudflare API v4 on " .. API .. ". Every function takes one named options object with Cloudflare's native names; ? marks optional fields and ...body the JSON body fields. Connector calls return completed values: use them directly, without await.",
	"Results are Cloudflare's JSON unchanged: {success, errors, messages, result, result_info?}; read result. Lists return one page with result_info={page, per_page, count, total_count, total_pages}: pass page=result_info.page + 1 while it is below total_pages. R2 buckets page with a cursor instead. getZoneAnalytics returns GraphQL's {data, errors}.",
	"Account, zone and DNS record ids are 32-character hex strings: start with listAccounts and listZones (zone.account.id is its account). Workers are named by script_name, Pages projects by project_name and R2 buckets by bucket_name; Workers version and deployment ids and Pages deployment ids are UUIDs. Times are ISO 8601 UTC. Write until as ['until'] in Luau, since until is a keyword.",
	"Examples: local zone = cloudflare.listZones({name='example.com'}).result[1]; cloudflare.listDnsRecords({zone_id=zone.id, type='CNAME', per_page=100}); cloudflare.getZoneAnalytics({zone_id=zone.id, since='2026-10-01', ['until']='2026-10-07', breakdowns={'responseStatusMap'}}).",
	"The token's permissions and resources still apply: HTTP 403 (usually code 10000 'Authentication error') means the token lacks a permission for that account or zone, or doesn't cover it. Cloudflare allows 1200 requests per 5 minutes per token (GraphQL about 300) and then refuses requests for up to 5 minutes; Houston retries an HTTP 429 at most twice, when Retry-After is absent or at most 5 seconds, and the error reports Retry-After when Cloudflare sends one. A GraphQL 429 about query cost or too many nodes needs a shorter period or fewer breakdowns, not a retry. Errors report the HTTP status and Cloudflare's codes and messages. 5xx and 429 are retryable.",
}
if config.access == "read-write" then
	table.insert(intro, "Writes change production at once: DNS changes reach Cloudflare's network within seconds, while resolvers may keep old answers for the record's TTL (deleting or editing a record can take a site or its mail offline), purgeCache sends the next requests to the origin, which can overload it, and Worker deployments and Pages rollbacks switch live traffic. Confirm the exact change with the user first, and read the current state (getDnsRecord, listWorkerDeployments, listPagesDeployments) before changing it so it can be restored. Writes are retried only after an HTTP 429, which Cloudflare refused before acting: after a timeout or 5xx, read the state again before repeating one.")
else
	table.insert(intro, "This read-only connection omits writes.")
end

return operations(endpoints, request, intro)
