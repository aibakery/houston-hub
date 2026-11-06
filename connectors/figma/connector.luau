-- Figma REST API v1. Arguments and results keep Figma's native snake_case field names.
type Options = {[string]: any}
type Endpoint = {method: string, path: string, query: {string}?, extra: {string}?, required: {string}?, write: boolean?, body: (boolean | string)?, example: Options,
	doc: string, about: string}

local PROVIDER = "Figma"
local API = "https://api.figma.com"
local DOCS = "https://developers.figma.com/docs/rest-api/"
local CURSORS = {"page_size", "after", "before"}

-- Operations in Figma's public OpenAPI (github.com/figma/rest-api-spec v0.46.0), checked on
-- 2026-10-27. Path {fields} are required; listed query fields are taken from the options and
-- the other fields form the JSON body.
local endpoints: {[string]: Endpoint} = {
	getMe = {method = "GET", path = "/v1/me", example = {}, doc = "users-endpoints/#get-me-endpoint", about = "You: {id, handle, email, img_url}."},

	getFile = {method = "GET", path = "/v1/files/{file_key}", example = {file_key="aBcDeFgHiJkLmNoPqRsTuV12",depth=2,branch_data=true}, query = {"version", "ids", "depth", "geometry", "plugin_data", "branch_data"},
		doc = "file-endpoints/#get-files-endpoint",
		about = "A file's document tree with its components and styles. Whole files can be very large: pass depth=1 for its pages, depth=2 for their top-level frames, or ids for some nodes."},
	getFileNodes = {method = "GET", path = "/v1/files/{file_key}/nodes", example = {file_key="aBcDeFgHiJkLmNoPqRsTuV12",ids={"1-2","I1:2;3:4","9:9"},depth=1}, query = {"ids", "version", "depth", "geometry", "plugin_data"}, required = {"ids"},
		doc = "file-endpoints/#get-file-nodes-endpoint", about = "{nodes={[id]={document, components, styles}}} for the given nodes; a missing node maps to null."},
	getFileMeta = {method = "GET", path = "/v1/files/{file_key}/meta", example = {file_key="https://www.figma.com/design/aBcDeFgHiJkLmNoPqRsTuV12/App?node-id=1-2&m=dev"}, doc = "file-endpoints/#get-file-metadata-endpoint",
		about = "{file={name, folder_name, last_touched_at, creator, thumbnail_url, editorType, role, link_access, url, version}} without the document."},
	listFileVersions = {method = "GET", path = "/v1/files/{file_key}/versions", example = {file_key="aBcDeFgHiJkLmNoPqRsTuV12",page_size=50,before=123}, query = CURSORS, doc = "version-history-endpoints/#get-file-versions-endpoint",
		about = "Saved versions, newest first, {versions, pagination}. page_size is at most 50; pass a version id as before for older ones."},
	renderImages = {method = "GET", path = "/v1/images/{file_key}", example = {file_key="aBcDeFgHiJkLmNoPqRsTuV12",ids={"1:2","1:3"},format="svg",scale=2,svg_include_id=true},
		query = {"ids", "scale", "format", "svg_outline_text", "svg_include_id", "svg_include_node_id", "svg_simplify_stroke", "contents_only", "use_absolute_bounds", "version"},
		extra = {"save_to"}, required = {"ids"}, doc = "file-endpoints/#get-images-endpoint",
		about = "Renders nodes, {err, images={[id]=url}}; a node that fails to render maps to null. format: png (default), jpg, svg or pdf; scale 0.01..4 (default 1). With save_to, a session folder, each image is saved there as <id>.<format> (at most 10 ids) and images maps ids to {path, size, url}."},
	getImageFills = {method = "GET", path = "/v1/files/{file_key}/images", example = {file_key="aBcDeFgHiJkLmNoPqRsTuV12"}, doc = "file-endpoints/#get-image-fills-endpoint",
		about = "Download links for the images used as fills, {meta={images={[imageRef]=url}}}; they expire within 14 days."},

	listTeamProjects = {method = "GET", path = "/v1/teams/{team_id}/projects", example = {team_id="42"}, doc = "projects-endpoints/#get-team-projects-endpoint",
		about = "{name, projects} of a team you can see. Read team_id from a team URL, figma.com/files/team/<team_id>/..."},
	listProjectFiles = {method = "GET", path = "/v1/projects/{project_id}/files", example = {project_id="77",branch_data=true}, query = {"branch_data"}, doc = "projects-endpoints/#get-project-files-endpoint",
		about = "{name, files: [{key, name, thumbnail_url, last_modified}]} of a project."},

	listTeamComponents = {method = "GET", path = "/v1/teams/{team_id}/components", example = {team_id="1234567890",page_size=30,after=0}, query = CURSORS, doc = "component-endpoints/#get-team-components-endpoint",
		about = "Published components of a team's libraries, {meta={components, cursor}}. page_size is at most 1000; pass meta.cursor.after as after."},
	listTeamComponentSets = {method = "GET", path = "/v1/teams/{team_id}/component_sets", example = {team_id="42"}, query = CURSORS, doc = "component-endpoints/#get-team-component-sets-endpoint",
		about = "Published component sets (variants), paged like listTeamComponents."},
	listTeamStyles = {method = "GET", path = "/v1/teams/{team_id}/styles", example = {team_id="42",before=10}, query = CURSORS, doc = "component-endpoints/#get-team-styles-endpoint",
		about = "Published styles, paged like listTeamComponents."},
	listFileComponents = {method = "GET", path = "/v1/files/{file_key}/components", example = {file_key="aBcDeFgHiJkLmNoPqRsTuV12"}, doc = "component-endpoints/#get-file-components-endpoint",
		about = "Published components of a library file, {meta={components}}."},
	listFileComponentSets = {method = "GET", path = "/v1/files/{file_key}/component_sets", example = {file_key="aBcDeFgHiJkLmNoPqRsTuV12"}, doc = "component-endpoints/#get-file-component-sets-endpoint",
		about = "Published component sets of a library file."},
	listFileStyles = {method = "GET", path = "/v1/files/{file_key}/styles", example = {file_key="aBcDeFgHiJkLmNoPqRsTuV12"}, doc = "component-endpoints/#get-file-styles-endpoint",
		about = "Published styles of a library file."},
	getComponent = {method = "GET", path = "/v1/components/{key}", example = {key="abc123"}, doc = "component-endpoints/#get-component-endpoint",
		about = "A published component by its key (not its node id)."},
	getComponentSet = {method = "GET", path = "/v1/component_sets/{key}", example = {key="def456"}, doc = "component-endpoints/#get-component-set-endpoint",
		about = "A published component set by its key."},
	getStyle = {method = "GET", path = "/v1/styles/{key}", example = {key="0f0f"}, doc = "component-endpoints/#get-style-endpoint", about = "A published style by its key."},

	listComments = {method = "GET", path = "/v1/files/{file_key}/comments", example = {file_key="aBcDeFgHiJkLmNoPqRsTuV12",as_md=true}, query = {"as_md"}, doc = "comments-endpoints/#get-comments-endpoint",
		about = "All comments of a file, unpaginated, {comments: [{id, message, parent_id, user, created_at, resolved_at, client_meta, order_id, reactions}]}. parent_id marks a reply; as_md=true returns messages in Markdown."},
	listCommentReactions = {method = "GET", path = "/v1/files/{file_key}/comments/{comment_id}/reactions", example = {file_key="aBcDeFgHiJkLmNoPqRsTuV12",comment_id="7",cursor="c2"}, query = {"cursor"},
		doc = "comments-endpoints/#get-comment-reactions-endpoint", about = "{reactions, pagination}; pass pagination.next_page as cursor for the next page."},
	postComment = {method = "POST", path = "/v1/files/{file_key}/comments", example = {file_key="https://www.figma.com/design/aBcDeFgHiJkLmNoPqRsTuV12/App",message="Looks good",comment_id="7"}, required = {"message"}, doc = "comments-endpoints/#post-comments-endpoint",
		about = "Body {message, comment_id?, client_meta?}. comment_id replies to a top-level comment. client_meta pins it: {x, y}, {node_id, node_offset={x, y}}, or a region adding region_width and region_height. Figma notifies the people mentioned or following the thread."},
	deleteComment = {method = "DELETE", path = "/v1/files/{file_key}/comments/{comment_id}", example = {file_key="aBcDeFgHiJkLmNoPqRsTuV12",comment_id="8"}, doc = "comments-endpoints/#delete-comments-endpoint",
		about = "Deletes one of your own comments."},
	addCommentReaction = {method = "POST", path = "/v1/files/{file_key}/comments/{comment_id}/reactions", example = {file_key="aBcDeFgHiJkLmNoPqRsTuV12",comment_id="7",emoji=":+1:"}, required = {"emoji"},
		doc = "comments-endpoints/#post-comment-reactions-endpoint", about = "Body {emoji}, a shortcode such as ':+1:' or ':heart:'."},
	removeCommentReaction = {method = "DELETE", path = "/v1/files/{file_key}/comments/{comment_id}/reactions", example = {file_key="aBcDeFgHiJkLmNoPqRsTuV12",comment_id="7",emoji=":+1:"}, query = {"emoji"}, required = {"emoji"},
		doc = "comments-endpoints/#delete-comment-reactions-endpoint", about = "Removes your reaction with that emoji."},
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

-- Export and document exactly the operations enabled for this connection.
local function operations(endpoints: {[string]: Endpoint}, request: (string, Endpoint, Options?) -> any, intro: {string}, documentation: {[string]: any}): {[string]: any}
	local exports: {[string]: any}, docs: {[string]: any} = {}, {}
	for name in documentation do assert(endpoints[name], "documentation without endpoint: " .. name) end
	for name, endpoint in endpoints do
		assert(documentation[name], "missing documentation for " .. name)
		if not writes(endpoint) or config.access == "read-write" then
			exports[name] = function(args: Options?): any return request(name, endpoint, args) end
			local record = table.clone(documentation[name])
			record.description = endpoint.about .. " " .. endpoint.method .. " " .. endpoint.path .. ". Reference: " .. DOCS .. endpoint.doc
				.. (if record.description then "\n\n" .. record.description else "")
			if record.annotations == nil then record.annotations = {readOnlyHint = not writes(endpoint)} end
			docs[name] = record
		end
	end
	exports.help = {text = table.concat(intro, "\n\n"), functions = docs}
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
local MAX_SAVED, CLEANUP_WAIT, DOWNLOAD_WAIT = 10, 1000, 15000

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
	for index, id in ids do downloads[index] = http.request({method = "GET", url = rendered.images[id], timeoutMs = DOWNLOAD_WAIT}) end
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
	local closes = {}
	local written = pcall(function()
		for index, id in ids do
			paths[index] = folder .. "/" .. fileName(id, format)
			local output = fs.open(paths[index], "w")
			output:write(responses[index].body)
			closes[index] = output:close()
		end
		awaitAll(closes)
	end)
	if not written then
		for _, close in closes do pcall(function() await(close, CLEANUP_WAIT) end) end
		closeAll(downloads)
		return failRender(name, 0, true, "Saving the renders in " .. string.sub(folder, 1, 200) .. " failed; some renders were not saved")
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
	"Figma REST API v1. Every function takes one named options object with Figma's snake_case names. Results are Figma's JSON unchanged, except renderImages with save_to replaces download links with saved-file records, and an empty write response becomes {success=true}. Connector calls return completed values: use them directly, without await.",
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

-- Schemas describe the provider fields and the connector's URL/id conveniences. Endpoint
-- paths, required fields, examples and access remain the shared registration source.
local text = {type = "string"}
local nullableText: any = {type = {"string", "null"}}
local boolean: any = {type = "boolean"}
local numericId: any = {type = "string", pattern = "^[0-9]+$", description = "Keep the full decimal ID as a string."}
local nodePattern = "[A-Za-z0-9:;\\-]|%3[AaBb]"
local node: any = {type = "string", pattern = "^\\s*(?:" .. nodePattern .. ")+\\s*$", description = "Node ID; URL dashes and percent-encoded colons/semicolons are normalized."}
local ids: any = {anyOf = {({type = "array", minItems = 1, items = node} :: any),
	{type = "string", pattern = "^,*(?:\\s*(?:" .. nodePattern .. ")+\\s*,+)*\\s*(?:" .. nodePattern .. ")+\\s*,*$"}},
	description = "Nonempty node-ID array or comma-separated string."}
local kinds: {string}, formats: {string} = {}, {}
for kind in FILE_KINDS do table.insert(kinds, kind :: string) end
for format in FORMATS do table.insert(formats, format :: string) end
table.sort(kinds)
table.sort(formats)
local file = {type = "string", pattern = "^(?:[A-Za-z0-9]+|(?:https?://)?(?:[A-Za-z0-9.-]+\\.)?[Ff][Ii][Gg][Mm][Aa]\\.[Cc][Oo][Mm]/(?:" .. table.concat(kinds, "|") .. ")/[A-Za-z0-9]+[^\\r\\n]*)$",
	description = "File/branch key or Figma URL. A /branch/<key> URL uses the branch key. Community and team URLs are not file URLs."}
local vector: any = {type = "object", properties = {x = {type = "number"}, y = {type = "number"}}, required = {"x", "y"}}
local pin: any = {type = "object", properties = {x = {type = "number"}, y = {type = "number"}, node_id = node, node_offset = vector,
	region_width = {type = "number", exclusiveMinimum = 0}, region_height = {type = "number", exclusiveMinimum = 0},
	comment_pin_corner = {type = "string", enum = {"top-left", "top-right", "bottom-left", "bottom-right"}, default = "bottom-right"}},
	anyOf = {{required = {"x", "y"}}, {required = {"node_id", "node_offset"}}},
	dependentRequired = {region_width = {"region_height"}, region_height = {"region_width"}},
	description = "Canvas coordinates or frame-relative offset; include both positive dimensions for a region. Additional provider fields pass through."}
local query: {[string]: any} = {
	ids = ids, version = {type = "string", description = "Saved version ID; omitted reads the current version."},
	depth = {type = "integer", minimum = 1, description = "getFile counts depth from the document root; getFileNodes counts from each requested node. Omitted returns full subtrees."},
	geometry = {type = "string", const = "paths", description = "Include vector path data."},
	plugin_data = {anyOf = {text, {type = "array", minItems = 1, items = text}}, description = "Comma-separated plugin IDs and/or shared, or an array joined with commas."},
	branch_data = {type = "boolean", default = false},
	before = {anyOf = {({type = "integer", minimum = 0} :: any), {type = "string", pattern = "^[0-9]+$"}}, description = "Provider pagination cursor; versions use a version ID. Use either before or after."},
	after = {anyOf = {({type = "integer", minimum = 0} :: any), {type = "string", pattern = "^[0-9]+$"}}, description = "Provider pagination cursor; use either before or after."},
	scale = {type = "number", minimum = 0.01, maximum = 4, default = 1},
	format = {type = "string", enum = formats, default = "png"},
	svg_outline_text = {type = "boolean", default = true}, svg_include_id = {type = "boolean", default = false},
	svg_include_node_id = {type = "boolean", default = false}, svg_simplify_stroke = {type = "boolean", default = true},
	contents_only = {type = "boolean", default = true}, use_absolute_bounds = {type = "boolean", default = false}, as_md = {type = "boolean", default = false},
	cursor = {type = "string", description = "Reaction cursor or the complete pagination.next_page URL; URLs must contain a cursor query value."},
	emoji = {type = "string", minLength = 3, pattern = "^:.*:$", description = "Figma emoji shortcode, for example :+1: or :heart:."},
}
local user: any = {type = "object", properties = {id = text, handle = text, email = text, img_url = text}}
local comment: any = {type = "object", properties = {id = text, message = text, parent_id = text, user = user,
	created_at = text, resolved_at = nullableText, client_meta = {type = {"object", "null"}}}}
local saved: any = {type = "object", properties = {path = text, size = {type = "integer", minimum = 0}, url = text}, required = {"path", "size", "url"}}
local outputs: {[string]: any} = {
	getMe = user, postComment = comment,
	getFile = {type = "object", properties = {name = text, document = {type = "object"}, components = {type = "object"}, styles = {type = "object"}}},
	getFileNodes = {type = "object", properties = {nodes = {type = "object", additionalProperties = {type = {"object", "null"}}}}},
	getFileMeta = {type = "object", properties = {file = {type = "object", properties = {name = text, version = text, url = text}}}},
	renderImages = {type = "object", properties = {err = nullableText, images = {type = {"object", "null"}, additionalProperties = {anyOf = {nullableText, saved}}}}},
	getImageFills = {type = "object", properties = {meta = {type = "object", properties = {images = {type = "object", additionalProperties = text}}}}},
	listComments = {type = "object", properties = {comments = {type = "array", items = comment}}},
	listCommentReactions = {type = "object", properties = {reactions = {type = "array", items = {type = "object"}}, pagination = {type = "object"}}},
	listFileVersions = {type = "object", properties = {versions = {type = "array", items = {type = "object"}}, pagination = {type = "object"}}},
	listTeamProjects = {type = "object", properties = {name = text, projects = {type = "array", items = {type = "object"}}}},
	listProjectFiles = {type = "object", properties = {name = text, files = {type = "array", items = {type = "object"}}}},
}
local docs: {[string]: any} = {}
for name, endpoint in endpoints do
	local properties: {[string]: any}, required: {string} = {}, {}
	for field in string.gmatch(endpoint.path, "{([%w_]+)}") do
		properties[field] = if field == "file_key" then file elseif field == "key" then {type = "string", pattern = "^[A-Fa-f0-9]+$", description = "Published library asset key, not a node ID."} else numericId
		table.insert(required, field)
	end
	for _, field in endpoint.query or NONE do
		properties[field] = if field == "page_size" then {type = "integer", minimum = 1, maximum = if name == "listFileVersions" then 50 else 1000} else query[field]
		assert(properties[field], "missing query schema: " .. field)
	end
	for _, field in endpoint.required or NONE do table.insert(required, field) end
	if name == "postComment" then properties.message, properties.comment_id, properties.client_meta = text, numericId, pin end
	if name == "addCommentReaction" then properties.emoji = query.emoji end
	local schema: any = {type = "object", properties = properties, required = if #required > 0 then required else nil, additionalProperties = hasBody(endpoint), examples = {endpoint.example}}
	if name == "postComment" then
		table.insert(schema.examples, {file_key = endpoints.getFile.example.file_key, message = "Pinned", client_meta = {node_id = "1-2", node_offset = {x = 10, y = 20}}})
	end
	if name == "renderImages" then
		properties.save_to = {type = "string", pattern = "[^/]", description = "Session folder. Saves at most " .. tostring(MAX_SAVED) .. " nodes, overwriting matching filenames; may partially save on failure. Omit to return provider URLs."}
		schema.allOf = {{["if"] = {required = {"save_to"}}, ["then"] = {properties = {ids = {anyOf = {
			({type = "array", maxItems = MAX_SAVED} :: any), {type = "string", pattern = "^,*(?:[^,]+,+){0," .. tostring(MAX_SAVED - 1) .. "}[^,]+,*$"},
		}}}}}}
		table.insert(schema.examples, {file_key = endpoints.getFile.example.file_key, ids = {"1:2", "I3:4;5:6", "7:8"}, scale = 2, save_to = "renders/"})
	end
	local output = outputs[name]
	if output == nil then
		output = if writes(endpoint) then {type = "object", properties = {success = boolean, status = {type = "number"}, error = boolean}}
			else {type = "object", properties = {status = {type = "number"}, error = boolean, meta = {type = "object"}}}
	end
	docs[name] = {inputSchema = schema, args = if name == "getMe" then {} else nil, outputSchema = output, annotations = {readOnlyHint = not writes(endpoint) and name ~= "renderImages",
		destructiveHint = endpoint.method == "DELETE" or name == "renderImages", idempotentHint = endpoint.method ~= "POST"}}
end
local exports = operations(endpoints, request, {intro[1], intro[6]}, docs)
local help = exports.help
help.sections = {identifiers = intro[2], workflow = intro[3], limits = intro[4], errors = intro[5],
	paging = "Each list returns one provider page unless documented as unpaginated. For versions, pass a version ID as before; for team library assets pass meta.cursor.after as after. Reaction lists accept pagination.next_page as cursor. Keep the same filters across pages. JSON null is truthy in Luau; check type(nextPage) == 'string' before following a link."}
exports.help = help
return exports
