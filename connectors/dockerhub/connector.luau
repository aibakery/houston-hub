-- Docker Hub API v2 (https://docs.docker.com/reference/api/hub/latest/), read anonymously. Arguments and results keep Docker Hub's native field names.
type Options = {[string]: any}
type Endpoint = {method: string, path: string, query: {string}?, extra: {string}?, required: {string}?, write: boolean?, body: (boolean | string)?,
	reach: number?, doc: string, about: string}

local PROVIDER = "Docker Hub"
local DOCS = "https://docs.docker.com/reference/api/hub/latest/#tag/repositories/operation/"
local API = "https://hub.docker.com/v2"

-- The reads of Docker Hub's OpenAPI (docs.docker.com/reference/api/hub/latest.yaml), checked on 2026-10-30, that answer
-- without signing in. Path {fields} are required; tags' name filter is the one Docker Hub's website uses, outside the
-- published schema. Lists answer with one page; reach is how many items Docker Hub lists without signing in (probed then).
local endpoints: {[string]: Endpoint} = {
	listRepositories = {method = "GET", path = "/namespaces/{namespace}/repositories", query = {"name", "ordering", "page", "page_size"}, reach = 100, doc = "listNamespaceRepositories",
		about = "A namespace's public repositories: {count, next, previous, results}, each {name, namespace, repository_type, status_description, description, is_private, star_count, pull_count, last_updated (last push), last_modified, date_registered, media_types, content_types, categories: [{name, slug}], storage_size (bytes), registry_region}. name keeps repositories whose name contains it. ordering: name or -name (A to Z, Z to A), last_updated (newest push first) or -last_updated, pull_count (most pulled first) or -pull_count; Docker Hub's reference documents these last two pairs the other way round. Without ordering, the earliest registered come first. A namespace that doesn't exist, or has no public repository, answers count 0."},
	getRepository = {method = "GET", path = "/namespaces/{namespace}/repositories/{repository}", doc = "GetRepository",
		about = "A public repository: {name, namespace, user, hub_user, repository_type, status_description, description, full_description (the repository overview in Markdown, up to 25,000 characters), is_private, is_automated, star_count, pull_count, last_updated (last push), last_modified, date_registered, collaborator_count, has_starred, permissions {read, write, admin}, media_types, content_types, categories, immutable_tags_settings {enabled, rules}, storage_size (bytes), source}."},
	listTags = {method = "GET", path = "/namespaces/{namespace}/repositories/{repository}/tags", query = {"name", "page", "page_size"}, reach = 1000, doc = "ListRepositoryTags",
		about = "A public repository's tags, most recently pushed first: {count, next, previous, results}, each as in getTag. name keeps tags whose name contains it, such as 'alpine' or '1.27'."},
	getTag = {method = "GET", path = "/namespaces/{namespace}/repositories/{repository}/tags/{tag}", doc = "GetRepositoryTag",
		about = "A tag: {name, digest (what docker pull resolves: the image index of a multi-platform tag, else its single manifest), media_type, content_type, full_size, tag_status (active or inactive), tag_last_pushed, tag_last_pulled, last_updated, last_updater_username, id, repository, images}. images (null for some old tags) has one manifest per platform: {architecture, os, variant, os_version, digest, size, status, last_pushed, last_pulled}; entries whose architecture and os are 'unknown' are build attestations, such as provenance and SBOMs, not runnable images. full_size is one platform's size, not the sum, and can be 0 for old tags."},
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

-- Docker Hub's naming rules, so an argument can't add path segments or reach another route.
local SEGMENTS: {[string]: {pattern: string, max: number, about: string}} = {
	namespace = {pattern = "^[%l%d][%l%d._%-]*$", max = 255, about = "a Docker Hub user or organization name in lowercase, such as library or bitnami"},
	repository = {pattern = "^[%l%d][%l%d._%-]*$", max = 255, about = "a repository name in lowercase, such as nginx"},
	tag = {pattern = "^[%w_][%w_.%-]*$", max = 128, about = "a tag such as latest or 1.27-alpine"},
}
local ORDERINGS = {"name", "-name", "last_updated", "-last_updated", "pull_count", "-pull_count"}
local REACH = "Houston reads Docker Hub without signing in, so lists stop after the first 100 repositories or 1,000 tags; narrow the list with name"
-- Houston ends a call after 30 s and the sandbox has no clock. Headers get 15 s, leaving the rest for a 200 body (read by
-- the shared layer without a deadline; the largest page is about 470 KB) and Houston's short 429 waits; an error body gets 7 s.
local HEADERS_TIME, BODY_TIME = 15000, 7000

local function integer(value: any, field: string, max: number): string
	assert(type(value) == "number" and value == math.floor(value) and value >= 1 and value <= max,
		field .. " must be an integer from 1 to " .. tostring(max))
	return string.format("%d", value)
end

-- A page can't start beyond reach, and reach caps page too, with a page_size of 1.
local function queryValue(field: string, value: any, reach: number): string
	if field == "page" then return integer(value, field, reach) end
	if field == "page_size" then return integer(value, field, 100) end
	if field == "ordering" then
		assert(type(value) == "string" and table.find(ORDERINGS, value), "ordering must be one of " .. table.concat(ORDERINGS, ", "))
		return value
	end
	assert(type(value) == "string" and string.find(value, "%S") and #value <= 255, field .. " must be a nonempty string of at most 255 bytes")
	return url.encode(value)
end

-- Docker Hub errors are {message, errinfo}, or {text, fields} in older routes; rate limits add Retry-After in seconds.
local function failStatus(name: string, response: HttpResponse): never
	local status = response.statusCode
	local message = PROVIDER .. " HTTP " .. tostring(status)
	if status >= 300 and status < 400 then
		response.body:close()
		return fail(name, response, message .. ": unexpected redirect")
	end
	-- An error body that stalls or breaks counts as empty, so the status and retryable survive.
	local read, raw: any = pcall(function() return await(response.body:readPrefix(4096), BODY_TIME) end)
	if not read and type(raw) == "table" and raw.code == "cancelled" then error(raw, 0) end
	local ok, value = false, nil
	if read then ok, value = pcall(json.decode, raw) end
	local detail = if ok and type(value) == "table" and type(value.message) == "string" then value.message
		elseif ok and type(value) == "table" and type(value.text) == "string" then value.text
		else nil
	if detail then message ..= ": " .. string.sub(detail, 1, 300) end
	if status == 403 and detail and string.find(detail, "pagination offset", 1, true) then
		message ..= ". " .. REACH
	elseif status == 404 and detail == "object not found" then
		message ..= ". The repository doesn't exist or is private, and Houston reads public repositories only"
	end
	local retry = response.headers["retry-after"]
	if (status == 429 or status == 503) and retry and retry[1] then
		local wait = string.sub(retry[1], 1, 32)
		message ..= "; retry after " .. wait .. (if string.match(wait, "^%d+$") then "s" else "")
	end
	return fail(name, response, message)
end

local function request(name: string, endpoint: Endpoint, input: Options?): any
	local args = options(input)
	local path = string.gsub(endpoint.path, "{([%w_]+)}", function(field: string): string
		local value, rule = args[field], SEGMENTS[field]
		args[field] = nil
		assert(type(value) == "string" and #value <= rule.max and string.match(value, rule.pattern), field .. " must be " .. rule.about)
		return value
	end)
	local query: {string} = {}
	-- Docker Hub's defaults, for the offset check below.
	local paging: {[string]: number} = {page = 1, page_size = 10}
	for _, field in endpoint.query or NONE do
		local value = args[field]
		args[field] = nil
		if value ~= nil and value ~= NULL then
			table.insert(query, field .. "=" .. queryValue(field, value, endpoint.reach or 1))
			if paging[field] then paging[field] = value end
		end
	end
	local unknown = next(args)
	assert(unknown == nil, name .. " has no option " .. string.sub(tostring(unknown), 1, 64))
	assert(endpoint.reach == nil or (paging.page - 1) * paging.page_size < endpoint.reach, name .. ": " .. REACH)
	if #query > 0 then path ..= "?" .. table.concat(query, "&") end
	local sent, result: any = pcall(function()
		return await(http.request({method = "GET", url = API .. path, headers = {Accept = {"application/json"}}, timeoutMs = HEADERS_TIME}))
	end)
	if not sent then
		if type(result) == "table" and result.code == "timeout" then
			houston.fail({operation = name, layer = "upstream", retryable = true,
				message = PROVIDER .. " did not answer within " .. tostring(HEADERS_TIME // 1000) .. " s; retry"})
		end
		error(result, 0)
	end
	local response: HttpResponse = result
	if response.statusCode ~= 200 then failStatus(name, response) end
	local value = object(name, endpoint, response)
	if endpoint.query and type(value.results) ~= "table" then fail(name, response, PROVIDER .. " returned an invalid list") end
	return value
end

local intro = {
	"Docker Hub API v2 on " .. API .. ", read anonymously: public repositories and their tags only. Docker Hub accepts access tokens only after exchanging them for a short-lived session token, which Houston connectors can't do yet, so this connection holds no Docker credential. Private repositories answer HTTP 404 as if they didn't exist, organizations, teams and members can't be read, and nothing can be changed: no repository descriptions, no tag deletion, no Docker Scout vulnerability reports.",
	"Every function takes one named options object with Docker Hub's native names; ? marks optional fields. Results are Docker Hub's JSON unchanged. Connector calls return completed values: use them directly, without await.",
	"namespace is a user or organization, such as bitnami or docker. Docker Official Images, such as nginx, python or postgres, are in the namespace library. An image reference such as bitnami/redis:7.4 is namespace bitnami, repository redis and tag 7.4; one without a slash, such as nginx:latest, is in library. Names are lowercase.",
	"Lists return one page, {count, next, previous, results}. page starts at 1; page_size is 1 to 100, 10 by default. next is null on the last page, else the URL of the following one: call again with page + 1 and the same options. JSON null is truthy in Luau, so test type(page.next) == 'string'. Without signing in, Docker Hub lists only the first 100 repositories and the first 1,000 tags, though count and next go on: stop there, since a page starting beyond fails before any request. Narrow long lists with name.",
	"Times are ISO 8601 in UTC; sizes are compressed bytes. Example: local page = dockerhub.listTags({namespace='library', repository='nginx', name='alpine', page_size=25}); for _, t in page.results do print(t.name, t.digest, t.tag_last_pushed) end; local tag = dockerhub.getTag({namespace='library', repository='nginx', tag='latest'}); local repo = dockerhub.getRepository({namespace='bitnami', repository='redis'}).",
	"Docker Hub allows 180 requests per minute per IP address, and every Houston connection shares Houston's addresses. Houston retries an HTTP 429 at most twice, waiting as Retry-After asks when that is 5 s or less, or 1 s and then 2 s without a readable one; a longer wait or a third 429 fails as retryable, with the wait. Errors report the HTTP status and Docker Hub's message; 429, 5xx and a Docker Hub that doesn't answer within " .. tostring(HEADERS_TIME // 1000) .. " s are retryable. This connection is read-only.",
}

return operations(endpoints, request, intro)
