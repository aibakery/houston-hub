-- Figma REST API v1. Arguments and results keep Figma's native snake_case field names.
type Options = {[string]: any}
type Endpoint = {method: string, path: string, query: {string}?, extra: {string}?, required: {string}?, write: boolean?, body: (boolean | string)?,
	doc: string, about: string}

local PROVIDER = "Figma"
local API = "https://api.figma.com"
local DOCS = "https://developers.figma.com/docs/rest-api/"
local CURSORS = {"page_size", "after", "before"}

-- Operations in Figma's public OpenAPI (github.com/figma/rest-api-spec v0.46.0), checked on
-- 2026-10-27. Path {fields} are required; listed query fields are taken from the options and
-- the other fields form the JSON body.
local endpoints: {[string]: Endpoint} = {
	getMe = {method = "GET", path = "/v1/me", doc = "users-endpoints/#get-me-endpoint", about = "You: {id, handle, email, img_url}."},

	getFile = {method = "GET", path = "/v1/files/{file_key}", query = {"version", "ids", "depth", "geometry", "plugin_data", "branch_data"},
		doc = "file-endpoints/#get-files-endpoint",
		about = "A file's document tree with its components and styles. Whole files can be very large: pass depth=1 for its pages, depth=2 for their top-level frames, or ids for some nodes."},
	getFileNodes = {method = "GET", path = "/v1/files/{file_key}/nodes", query = {"ids", "version", "depth", "geometry", "plugin_data"}, required = {"ids"},
		doc = "file-endpoints/#get-file-nodes-endpoint", about = "{nodes={[id]={document, components, styles}}} for the given nodes; a missing node maps to null."},
	getFileMeta = {method = "GET", path = "/v1/files/{file_key}/meta", doc = "file-endpoints/#get-file-metadata-endpoint",
		about = "{file={name, folder_name, last_touched_at, creator, thumbnail_url, editorType, role, link_access, url, version}} without the document."},
	listFileVersions = {method = "GET", path = "/v1/files/{file_key}/versions", query = CURSORS, doc = "version-history-endpoints/#get-file-versions-endpoint",
		about = "Saved versions, newest first, {versions, pagination}. page_size is at most 50; pass a version id as before for older ones."},
	renderImages = {method = "GET", path = "/v1/images/{file_key}",
		query = {"ids", "scale", "format", "svg_outline_text", "svg_include_id", "svg_include_node_id", "svg_simplify_stroke", "contents_only", "use_absolute_bounds", "version"},
		extra = {"save_to"}, required = {"ids"}, doc = "file-endpoints/#get-images-endpoint",
		about = "Renders nodes, {err, images={[id]=url}}; a node that fails to render maps to null. format: png (default), jpg, svg or pdf; scale 0.01..4 (default 1). With save_to, a session folder, each image is saved there as <id>.<format> (at most 10 ids) and images maps ids to {path, size, url}."},
	getImageFills = {method = "GET", path = "/v1/files/{file_key}/images", doc = "file-endpoints/#get-image-fills-endpoint",
		about = "Download links for the images used as fills, {meta={images={[imageRef]=url}}}; they expire within 14 days."},

	listTeamProjects = {method = "GET", path = "/v1/teams/{team_id}/projects", doc = "projects-endpoints/#get-team-projects-endpoint",
		about = "{name, projects} of a team you can see. Read team_id from a team URL, figma.com/files/team/<team_id>/..."},
	listProjectFiles = {method = "GET", path = "/v1/projects/{project_id}/files", query = {"branch_data"}, doc = "projects-endpoints/#get-project-files-endpoint",
		about = "{name, files: [{key, name, thumbnail_url, last_modified}]} of a project."},

	listTeamComponents = {method = "GET", path = "/v1/teams/{team_id}/components", query = CURSORS, doc = "component-endpoints/#get-team-components-endpoint",
		about = "Published components of a team's libraries, {meta={components, cursor}}. page_size is at most 1000; pass meta.cursor.after as after."},
	listTeamComponentSets = {method = "GET", path = "/v1/teams/{team_id}/component_sets", query = CURSORS, doc = "component-endpoints/#get-team-component-sets-endpoint",
		about = "Published component sets (variants), paged like listTeamComponents."},
	listTeamStyles = {method = "GET", path = "/v1/teams/{team_id}/styles", query = CURSORS, doc = "component-endpoints/#get-team-styles-endpoint",
		about = "Published styles, paged like listTeamComponents."},
	listFileComponents = {method = "GET", path = "/v1/files/{file_key}/components", doc = "component-endpoints/#get-file-components-endpoint",
		about = "Published components of a library file, {meta={components}}."},
	listFileComponentSets = {method = "GET", path = "/v1/files/{file_key}/component_sets", doc = "component-endpoints/#get-file-component-sets-endpoint",
		about = "Published component sets of a library file."},
	listFileStyles = {method = "GET", path = "/v1/files/{file_key}/styles", doc = "component-endpoints/#get-file-styles-endpoint",
		about = "Published styles of a library file."},
	getComponent = {method = "GET", path = "/v1/components/{key}", doc = "component-endpoints/#get-component-endpoint",
		about = "A published component by its key (not its node id)."},
	getComponentSet = {method = "GET", path = "/v1/component_sets/{key}", doc = "component-endpoints/#get-component-set-endpoint",
		about = "A published component set by its key."},
	getStyle = {method = "GET", path = "/v1/styles/{key}", doc = "component-endpoints/#get-style-endpoint", about = "A published style by its key."},

	listComments = {method = "GET", path = "/v1/files/{file_key}/comments", query = {"as_md"}, doc = "comments-endpoints/#get-comments-endpoint",
		about = "All comments of a file, unpaginated, {comments: [{id, message, parent_id, user, created_at, resolved_at, client_meta, order_id, reactions}]}. parent_id marks a reply; as_md=true returns messages in Markdown."},
	listCommentReactions = {method = "GET", path = "/v1/files/{file_key}/comments/{comment_id}/reactions", query = {"cursor"},
		doc = "comments-endpoints/#get-comment-reactions-endpoint", about = "{reactions, pagination}; pass pagination.next_page as cursor for the next page."},
	postComment = {method = "POST", path = "/v1/files/{file_key}/comments", required = {"message"}, doc = "comments-endpoints/#post-comments-endpoint",
		about = "Body {message, comment_id?, client_meta?}. comment_id replies to a top-level comment. client_meta pins it: {x, y}, {node_id, node_offset={x, y}}, or a region adding region_width and region_height. Figma notifies the people mentioned or following the thread."},
	deleteComment = {method = "DELETE", path = "/v1/files/{file_key}/comments/{comment_id}", doc = "comments-endpoints/#delete-comments-endpoint",
		about = "Deletes one of your own comments."},
	addCommentReaction = {method = "POST", path = "/v1/files/{file_key}/comments/{comment_id}/reactions", required = {"emoji"},
		doc = "comments-endpoints/#post-comment-reactions-endpoint", about = "Body {emoji}, a shortcode such as ':+1:' or ':heart:'."},
	removeCommentReaction = {method = "DELETE", path = "/v1/files/{file_key}/comments/{comment_id}/reactions", query = {"emoji"}, required = {"emoji"},
		doc = "comments-endpoints/#delete-comment-reactions-endpoint", about = "Removes your reaction with that emoji."},
}

-- Request layer shared verbatim by the Cal.com, Calendly, Carta, Carta CRM, Figma, Gusto, Resend and Vercel connectors
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

-- A file key, or the key in a Figma file URL such as https://www.figma.com/design/<key>/<name>,
-- where /branch/<key> names a branch.
local FILE_KINDS = {file = true, design = true, board = true, proto = true, slides = true, deck = true, site = true, make = true, buzz = true}

local function fileKey(value: any): string
	assert(type(value) == "string", "file_key must be a Figma file key or URL")
	local key: string? = value
	-- Links pasted without a scheme, or with http://, are file URLs too.
	local link = string.gsub(value, "^http://", "https://")
	if string.find(link, "^[%w%.%-]*figma%.com/") then link = "https://" .. link end
	if string.find(link, "^https://") then
		local host, rest = string.match(link, "^https://([%w%.%-]+)/([^?#]*)")
		local figma = host ~= nil and (string.lower(host) == "figma.com" or string.sub(string.lower(host), -10) == ".figma.com")
		assert(figma, "file_key must be a Figma file key or URL")
		local kind, main, tail = string.match(rest :: string, "^([%w%-]+)/(%w+)(.*)$")
		key = if kind and FILE_KINDS[kind] then string.match(tail :: string, "^/branch/(%w+)") or main else nil
	end
	assert(key and string.match(key, "^%w+$"), "file_key must be a Figma file key or URL")
	return key :: string
end

-- Path fields other than file_key: team, project and comment ids are numeric, component and
-- style keys hexadecimal.
local function identifier(value: any, field: string): string
	if field == "file_key" then return fileKey(value) end
	local pattern = if field == "key" then "^%x+$" else "^%d+$"
	assert(type(value) == "string" and string.match(value, pattern), field .. (if field == "key" then " must be a Figma key" else " must be a numeric id string"))
	return value
end

-- Reaction pages link the next one as a URL; its cursor value is already encoded.
local function cursor(value: any): string
	if type(value) == "string" and string.find(value, "^https://api%.figma%.com/") then
		local encoded = string.match(value, "[?&]cursor=([^&#]+)")
		assert(encoded and string.match(encoded, "^[%w%%%-%._~]+$"), "cursor must be a cursor or pagination.next_page")
		return encoded
	end
	local parts = queryParts(value, "cursor")
	assert(#parts == 1, "cursor must be one value")
	return parts[1]
end

-- A node id such as 1:2 or I1:2;3:4. URLs write 1:2 as 1-2, and older links percent-encode
-- : and ;.
local function nodeId(item: string, field: string): string
	local id = string.match(item, "^%s*(.-)%s*$") :: string
	id = string.gsub(id, "%%3[Aa]", ":")
	id = string.gsub(id, "%%3[Bb]", ";")
	id = string.gsub(id, "-", ":")
	assert(string.match(id, "^[%w:;]+$"), field .. " must be node ids such as 1:2")
	return id
end

-- Node ids as a list or comma-separated.
local function nodeIds(value: any): {string}
	local items: {string} = {}
	if type(value) == "string" then
		for item in string.gmatch(value, "[^,]+") do table.insert(items, item) end
	else
		assert(type(value) == "table", "ids must be a list or comma-separated string of node ids")
		for index, item in value do
			assert(type(index) == "number" and index == #items + 1 and type(item) == "string", "ids must be a list or comma-separated string of node ids")
			table.insert(items, item)
		end
	end
	assert(#items > 0, "ids must name at least one node")
	for index, item in items do items[index] = url.encode(nodeId(item, "ids")) end
	return items
end

-- Figma errors are {status, err} or {error=true, status, message}; rate limits add Retry-After
-- and the seat's limit type.
local function failStatus(name: string, response: HttpResponse): never
	local message = "Figma HTTP " .. tostring(response.statusCode)
	local ok, value = pcall(json.decode, await(response.body:readPrefix(16 * 1024)))
	if ok and type(value) == "table" then
		local text = if type(value.err) == "string" then value.err else value.message
		if type(text) == "string" then message ..= ": " .. string.sub(text, 1, 600) end
	end
	if response.statusCode == 429 then
		for _, header in {"retry-after", "x-figma-rate-limit-type", "x-figma-plan-tier"} do
			local values = response.headers[header]
			if values and values[1] then message ..= "; " .. header .. " " .. string.sub(values[1], 1, 100) end
		end
	end
	return fail(name, response, message)
end

local function decode(name: string, endpoint: Endpoint, response: HttpResponse): any
	if response.statusCode < 200 or response.statusCode >= 300 then failStatus(name, response) end
	-- Deletions may answer without a body.
	return object(name, endpoint, response) or {success = true}
end

-- Renders live on a public bucket, fetched without credentials.
local RENDERS = "https://figma-alpha-api.s3.us-west-2.amazonaws.com/images/"
local FORMATS = {png = true, jpg = true, svg = true, pdf = true}
local MAX_SAVED, CLEANUP_WAIT = 10, 1000

local function failRender(name: string, status: number, retryable: boolean, message: string): never
	return houston.fail({operation = name, layer = "upstream", upstream_status = status, retryable = retryable, message = message})
end

-- A render's file name: 1:2 saves as 1-2 and I1:2;3:4 as I1-2_3-4, so distinct ids never share one.
local function fileName(id: string, format: string): string
	local name = string.gsub(id, ":", "-")
	name = string.gsub(name, ";", "_")
	return name .. "." .. format
end

local function closeAll(downloads: {any})
	for _, download in downloads do pcall(function() await(download, CLEANUP_WAIT).body:close() end) end
end

-- Downloads every render at once, so a batch fits the invocation's 30 seconds.
local function save(name: string, rendered: any, folder: string, format: string): any
	if type(rendered) ~= "table" or type(rendered.images) ~= "table" then
		return failRender(name, 200, false, "Figma rendered no images"
			.. (if type(rendered) == "table" and type(rendered.err) == "string" then ": " .. string.sub(rendered.err, 1, 600) else ""))
	end
	local ids: {string} = {}
	for id, link in rendered.images do
		if type(link) ~= "string" then continue end
		if string.find(link, RENDERS, 1, true) ~= 1 then return failRender(name, 200, false, "Figma returned a render on an unexpected host") end
		table.insert(ids, id)
	end
	table.sort(ids)
	if #ids == 0 then return rendered end
	local downloads = {}
	for index, id in ids do downloads[index] = http.request({method = "GET", url = rendered.images[id]}) end
	local fetched, responses = pcall(awaitAll, downloads)
	if not fetched then
		closeAll(downloads)
		return failRender(name, 0, true, "Downloading the renders failed before Figma's bucket answered")
	end
	for index, id in ids do
		local status = responses[index].statusCode
		if status ~= 200 then
			closeAll(downloads)
			return failRender(name, status, status == 403 or status >= 500, "Downloading the render of " .. id .. " failed with HTTP " .. tostring(status))
		end
	end
	local paths = {}
	local written = pcall(function()
		local closes = {}
		for index, id in ids do
			paths[index] = folder .. "/" .. fileName(id, format)
			local output = fs.open(paths[index], "w")
			output:write(responses[index].body)
			closes[index] = output:close()
		end
		awaitAll(closes)
	end)
	if not written then
		closeAll(downloads)
		return failRender(name, 0, true, "Saving the renders in " .. string.sub(folder, 1, 200) .. " failed; some files there may be partial")
	end
	local stats, links = {}, {}
	for index in ids do
		stats[index] = fs.stat(paths[index])
		links[index] = fs.signedGetUrl(paths[index])
	end
	local sizes, urls = awaitAll(stats), awaitAll(links)
	for index, id in ids do
		rendered.images[id] = {path = paths[index], size = sizes[index].size, url = urls[index]}
	end
	return rendered
end

local function request(name: string, endpoint: Endpoint, input: Options?): any
	local args = options(input)
	local path = string.gsub(endpoint.path, "{([%w_]+)}", function(field: string)
		local value = identifier(args[field], field)
		args[field] = nil
		return value
	end)
	for _, field in endpoint.required or NONE do
		assert(args[field] ~= nil and args[field] ~= NULL, field .. " is required")
	end
	-- Comment pins take node ids in their URL form too.
	if type(args.client_meta) == "table" and type(args.client_meta.node_id) == "string" then
		args.client_meta = table.clone(args.client_meta)
		args.client_meta.node_id = nodeId(args.client_meta.node_id, "client_meta.node_id")
	end
	local folder: string? = nil
	local format = args.format or "png"
	if table.find(endpoint.extra or NONE, "save_to") and args.save_to ~= nil then
		local target = args.save_to
		assert(type(target) == "string", "save_to must be a session folder path")
		folder = (string.gsub(target, "/+$", ""))
		assert(folder ~= "", "save_to must be a session folder path")
		assert(FORMATS[format], "format must be png, jpg, svg or pdf")
		args.save_to = nil
	end
	local query: {string} = {}
	for _, field in endpoint.query or NONE do
		if args[field] ~= nil then
			local parts = if field == "ids" then nodeIds(args[field]) elseif field == "cursor" then {cursor(args[field])} else queryParts(args[field], field)
			if field == "ids" and folder ~= nil then assert(#parts <= MAX_SAVED, "save_to saves at most " .. MAX_SAVED .. " ids at once") end
			table.insert(query, field .. "=" .. table.concat(parts, ","))
		end
		args[field] = nil
	end
	if #query > 0 then path ..= "?" .. table.concat(query, "&") end
	local headers: HttpHeaders = {Accept = {"application/json"}}
	local body: string? = nil
	if hasBody(endpoint) then
		headers["Content-Type"] = {"application/json"}
		body = json.encode(args)
		args = {}
	end
	local unknown = next(args)
	assert(unknown == nil, name .. " has no option " .. tostring(unknown))
	local result = decode(name, endpoint, await(http.request({url = API .. path, method = endpoint.method, headers = headers, body = body})))
	if folder ~= nil then return save(name, result, folder, format) end
	return result
end

local intro = {
	"Figma REST API v1. Every function takes one named options object with Figma's snake_case names; ? marks optional fields and ...body the JSON body fields. Results are Figma's JSON unchanged. Connector calls return completed values: use them directly, without await.",
	"file_key takes a file or branch key, or a Figma file URL such as https://www.figma.com/design/<key>/<name>?node-id=1-2. Node ids are like 1:2 or I1:2;3:4; ids takes a list or comma-separated string, and the URL form 1-2 also works. team_id is the number after /team/ in a team's URL in the file browser; no endpoint lists your teams. Keep ids as strings.",
	"Examples: local file = figma.getFile({file_key=link, depth=2}); figma.getFileNodes({file_key=link, ids={'1:2'}}); figma.renderImages({file_key=link, ids={'1:2', '1:3'}, format='png', scale=2, save_to='renders'}); figma.listComments({file_key=link, as_md=true}).",
	"Figma limits requests by endpoint tier, seat and plan: file, node and render calls are tier 1, 10 to 20 a minute on Dev and Full seats of paid plans but at most 20 a month on View and Collab seats and 6 a month for files on the Starter plan; comments, versions and projects are tier 2, metadata and libraries tier 3. Houston retries an HTTP 429 twice when Retry-After is 5 seconds or less, then reports Retry-After, the seat's limit type and the plan. Results above 8 MiB fail: narrow getFile with depth or ids. A call, saved renders included, must finish within 30 seconds: save fewer ids or a smaller scale when renders are large.",
	"Errors report the HTTP status and Figma's message.",
}
if config.access == "read-write" then
	table.insert(intro, "Side effects: postComment and addCommentReaction notify the file's followers and mentioned people; deleteComment works on your own comments only. Other failures are not retried: after a timeout or 5xx, list the comments before repeating a write.")
else
	table.insert(intro, "This read-only connection omits writes.")
end

return operations(endpoints, request, intro)
