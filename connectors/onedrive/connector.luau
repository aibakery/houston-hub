-- Microsoft Graph v1.0 for the connected account's OneDrive. Arguments and results keep Graph's
-- native field names.
-- Request layer shared verbatim by the Microsoft Graph connectors (tools/validate checks they match).
type Options = {[string]: any}
type Endpoint = {method: string, path: string, read: boolean, query: {string}?, body: boolean?, defaults: Options?, list: boolean?, help: string}
local GRAPH = "https://graph.microsoft.com/v1.0"
local API = GRAPH .. "/me"
-- Preauthenticated OneDrive download links work without credentials, so results never carry them.
local SIGNED = "@microsoft.graph.downloadUrl"

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

-- Graph errors are {error = {code, message}}; throttling answers 429 or 503 with Retry-After.
-- Quota (507) and other server refusals are not transient.
local function fail(operation: string, response: HttpResponse): never
	local ok, decoded = pcall(json.decode, await(response.body:readPrefix(4096)))
	local problem = if ok and type(decoded) == "table" and type(decoded.error) == "table" then decoded.error else {}
	local status = response.statusCode
	local message = "Microsoft Graph HTTP " .. tostring(status)
	if type(problem.code) == "string" then message ..= " (" .. problem.code .. ")" end
	if type(problem.message) == "string" then message ..= ": " .. string.sub(problem.message, 1, 600) end
	local retry = response.headers["retry-after"]
	if retry and retry[1] then message ..= "; Retry-After: " .. retry[1] end
	return houston.fail({operation = operation, layer = "upstream", upstream_status = status, message = message,
		retryable = status == 429 or status == 500 or status == 502 or status == 503 or status == 504 or status == 509})
end

local function decode(operation: string, response: HttpResponse): any
	if response.statusCode < 200 or response.statusCode >= 300 then fail(operation, response) end
	local raw = await(response.body:readAll())
	if string.match(raw, "^%s*$") then return {success = true} end
	local ok, value = pcall(json.decode, raw)
	if not ok or type(value) ~= "table" or not string.match(raw, "^%s*{") then
		houston.fail({operation = operation, layer = "upstream", upstream_status = response.statusCode,
			retryable = false, message = "Microsoft Graph returned an invalid JSON object"})
	end
	value[SIGNED] = nil
	for _, item in (if type(value.value) == "table" then value.value else {}) :: {any} do
		if type(item) == "table" then item[SIGNED] = nil end
	end
	return value
end

local function call(operation: string, method: string, href: string, body: any?, headers: HttpHeaders?): any
	local sent: HttpHeaders = if headers then table.clone(headers) else {}
	if body ~= nil then sent["Content-Type"] = {"application/json"} end
	return decode(operation, await(http.request({method = method, url = href, headers = sent,
		body = if body ~= nil then json.encode(body) elseif method == "POST" then "" else nil})))
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

-- Follows an @odata.nextLink, which may carry only paging options: an $expand could inline
-- attachment bytes or signed links. Graph may name entities by OData key, as in
-- mailFolders('inbox'), which the routes accept in their path form, mailFolders/inbox.
local PAGING = {select = true, top = true, skip = true, skiptoken = true, orderby = true, filter = true, search = true, count = true}
local function pageLink(link: string): string
	local path, search = string.match(link, "^([^?#]*)(%??[^#]*)$")
	assert(path and search and string.sub(path, 1, #GRAPH + 1) == GRAPH .. "/", "nextLink must be an @odata.nextLink from Microsoft Graph")
	for pair in string.gmatch(string.sub(search, 2), "[^&]+") do
		local name = string.lower((string.gsub(string.match(pair, "^[^=]*") or "", "%%(%x%x)", function(hex: string): string
			return string.char(tonumber(hex, 16) or 0)
		end)))
		assert(PAGING[(string.gsub(name, "^%$", ""))], "nextLink may carry only paging options")
	end
	return (string.gsub((string.gsub(path, "%%27", "'")), "/(%w+)%('([^'/]+)'%)", "/%1/%2")) .. search
end

-- A list's nextLink, the previous page's @odata.nextLink, replaces every other option.
local function nextLink(name: string, args: Options): string?
	if args.nextLink == nil then return nil end
	local link = text(args.nextLink, "nextLink")
	args.nextLink = nil
	assert(next(args) == nil, name .. " takes nextLink alone, from a previous page of the same list")
	return pageLink(link)
end

-- Moves {placeholders} and declared query fields from args into the URL; remaining fields form the
-- JSON body.
local function target(name: string, endpoint: Endpoint, args: Options): string
	local link = if endpoint.list then nextLink(name, args) else nil
	if link then return link end
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
	if not endpoint.body then done(name, args) end
	return API .. path
end

local function invoke(name: string, endpoint: Endpoint, input: any): any
	local args = options(input)
	local href = target(name, endpoint, args)
	local result = call(name, endpoint.method, href, if endpoint.body then args else nil)
	if endpoint.list and result.value == nil then result.value = json.decode("[]") end
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

local ITEM = "id,name,size,file,folder,package,parentReference,createdDateTime,lastModifiedDateTime,webUrl"
local MAX_UPLOAD = 250 * 1024 * 1024
-- File content redirects to a short-lived preauthenticated URL on these hosts, fetched without credentials.
local DOWNLOAD_HOSTS = {"%.sharepoint%.com$", "%.files%.1drv%.com$", "%.livefilestore%.com$", "^my%.microsoftpersonalcontent%.com$", "%.svc%.ms$"}

local endpoints: {[string]: Endpoint} = {
	getDrive = {method = "GET", path = "/drive", read = true, query = {"$select"},
		help = "getDrive({select?}) -> {id, driveType, owner, quota={total, used, remaining, state}}. The connected account's OneDrive; id is the driveId copies need."},
	listPermissions = {method = "GET", path = "/drive/items/{itemId}/permissions", read = true, list = true,
		help = "listPermissions({itemId}) -> {value={{id, roles, link?, grantedToV2?, invitation?}}}. Who can access an item, including its sharing links."},
	updateItem = {method = "PATCH", path = "/drive/items/{itemId}", read = false, body = true, defaults = {select = ITEM}, query = {"$select"},
		help = "updateItem({itemId, name?, description?, parentReference?={id}}) -> driveItem. Renames, or moves with parentReference={id=<folder itemId>}."},
	copyItem = {method = "POST", path = "/drive/items/{itemId}/copy", read = false, body = true,
		help = "copyItem({itemId, parentReference={driveId, id}, name?}) -> {success=true}. driveId is getDrive().id or an item's parentReference.driveId; name is required to copy into the same folder. OneDrive copies in the background and reports no later failure, such as a name conflict: list the destination to find the copy."},
	deleteItem = {method = "DELETE", path = "/drive/items/{itemId}", read = false,
		help = "deleteItem({itemId}) -> {success=true}. Moves the item to the OneDrive recycle bin."},
	createLink = {method = "POST", path = "/drive/items/{itemId}/createLink", read = false, body = true,
		help = "createLink({itemId, type='view'|'edit'|'embed', scope?='anonymous'|'organization'|'users', expirationDateTime?, password?}) -> permission with link.webUrl. Anyone with an anonymous link can open the item; organizations may disable them."},
	invite = {method = "POST", path = "/drive/items/{itemId}/invite", read = false, body = true,
		help = "invite({itemId, recipients={{email}}, roles={'read'|'write'}, requireSignIn?=true, sendInvitation?=true, message?}) -> {value={permission}}. Shares an item with people; sendInvitation emails them."},
	deletePermission = {method = "DELETE", path = "/drive/items/{itemId}/permissions/{permissionId}", read = false,
		help = "deletePermission({itemId, permissionId}) -> {success=true}. Revokes a sharing link or a person's access."},
}

-- An item by ID, or the root folder when id is nil.
local function itemPath(id: any, field: string): string
	if id == nil then return "/drive/root" end
	return "/drive/items/" .. url.segment(text(id, field), field)
end

local function conflictBehavior(value: any, default: string): string
	local behavior = if value == nil then default else value
	assert(behavior == "rename" or behavior == "replace" or behavior == "fail", "conflictBehavior must be rename, replace or fail")
	return behavior
end

-- One page of driveItems with the default fields, unless args holds a nextLink.
local function page(name: string, href: string, args: Options, names: {string}): Options
	local link = nextLink(name, args)
	if not link then
		if args.select == nil then args.select = ITEM end
		href ..= query(args, names)
		done(name, args)
	end
	local result = call(name, "GET", link or href)
	if result.value == nil then result.value = json.decode("[]") end
	return result
end

local function allowedDownload(location: string): boolean
	local host = string.match(location, "^https://([%w%.%-]+)[/?]")
	if host == nil then return false end
	host = string.lower(host)
	for _, pattern in DOWNLOAD_HOSTS do
		if string.find(host, pattern) then return true end
	end
	return false
end

-- Graph answers with a redirect to the file's preauthenticated link, which expires within minutes.
local function download(input: any): Options
	local args = options(input)
	local href = API .. itemPath(text(args.itemId, "itemId"), "itemId") .. "/content"
	local path = text(args.path, "path")
	assert(args.format == nil or args.format == "pdf", "format must be 'pdf'")
	args.itemId, args.path = nil, nil
	href ..= query(args, {"format"})
	done("downloadFile", args)
	return save("downloadFile", path, function(): HttpResponse
		local response = await(http.request({method = "GET", url = href}))
		if response.statusCode < 300 or response.statusCode >= 400 then return response end
		local location = response.headers.location
		local link: string = if location and location[1] then location[1] else ""
		response.body:close()
		if not allowedDownload(link) then
			houston.fail({operation = "downloadFile", layer = "upstream", upstream_status = response.statusCode, retryable = false,
				message = if link == "" then "OneDrive redirected the download without a location" else "OneDrive redirected the download to an unexpected host"})
		end
		local signed = await(http.request({method = "GET", url = link}))
		local status = signed.statusCode
		if status ~= 200 then
			signed.body:close()
			local fresh = status == 403 or status == 429 or status >= 500
			houston.fail({operation = "downloadFile", layer = "upstream", upstream_status = status, retryable = fresh,
				message = "The OneDrive download link failed with HTTP " .. tostring(status) .. (if fresh then "; call again for a fresh link" else "")})
		end
		return signed
	end)
end

-- Simple upload streams the session file in one request; with itemId it replaces that file's content.
local function upload(input: any): Options
	local args = options(input)
	local path = text(args.path, "path")
	local contentType = text(args.contentType or "application/octet-stream", "contentType")
	local href: string
	if args.itemId ~= nil then
		assert(args.parentId == nil and args.name == nil and args.conflictBehavior == nil,
			"uploadFile with itemId replaces content only; omit parentId, name and conflictBehavior")
		href = API .. itemPath(text(args.itemId, "itemId"), "itemId") .. "/content"
	else
		local name = url.segment(text(args.name or string.match(path, "[^/]+$"), "name"), "name")
		href = API .. itemPath(args.parentId, "parentId") .. ":/" .. name .. ":/content?@microsoft.graph.conflictBehavior="
			.. conflictBehavior(args.conflictBehavior, "rename")
	end
	args.path, args.contentType, args.itemId, args.parentId, args.name, args.conflictBehavior = nil, nil, nil, nil, nil, nil
	done("uploadFile", args)
	assert(await(fs.stat(path)).size <= MAX_UPLOAD, "uploadFile handles files up to 250 MB")
	return decode("uploadFile", await(http.request({method = "PUT", url = href,
		headers = {["Content-Type"] = {contentType}}, body = fs.open(path, "r")})))
end

exportEndpoints(endpoints)

export("getItem", true, function(input: any): Options
	local args = options(input)
	local href = API .. itemPath(args.itemId, "itemId")
	if args.path ~= nil then
		assert(args.itemId == nil, "getItem takes itemId or path, not both")
		local segments: {string} = {}
		for part in string.gmatch(text(args.path, "path"), "[^/]+") do table.insert(segments, url.segment(part, "path")) end
		if #segments > 0 then href ..= ":/" .. table.concat(segments, "/") .. ":" end
	end
	args.itemId, args.path = nil, nil
	if args.select == nil then args.select = ITEM end
	href ..= query(args, {"$select"})
	done("getItem", args)
	return call("getItem", "GET", href)
end, "getItem({itemId? | path?, select?}) -> driveItem {id, name, size, file?={mimeType}, folder?={childCount}, parentReference, lastModifiedDateTime, webUrl}. Without either, the root folder; path is relative to the root, e.g. 'Documents/Q3 report.pdf', and names containing % can only be reached by itemId.")

export("listChildren", true, function(input: any): Options
	local args = options(input)
	local href = ""
	if args.nextLink == nil then
		href = API .. itemPath(args.itemId, "itemId") .. "/children"
		args.itemId = nil
	end
	return page("listChildren", href, args, {"$select", "$top", "$orderby"})
end, "listChildren({itemId?, select?, top?, orderby?, nextLink?}) -> {value={driveItem}, @odata.nextLink?}. A folder's items, the root folder without itemId. top ≤999 (default 200); orderby e.g. 'name' or 'lastModifiedDateTime desc'.")

export("searchItems", true, function(input: any): Options
	local args = options(input)
	local href = ""
	if args.nextLink == nil then
		-- OData quotes a literal by doubling its single quotes.
		href = API .. "/drive/root/search(q='" .. url.segment((string.gsub(text(args.q, "q"), "'", "''")), "q") .. "')"
		args.q = nil
	end
	return page("searchItems", href, args, {"$select", "$top"})
end, "searchItems({q, select?, top?, nextLink?}) -> {value={driveItem}, @odata.nextLink?}. Matches names, metadata and file content across the drive. q cannot contain / or %.")

-- Fixed-signature file lookup shared with other storage connectors.
export("statFile", true, function(...: any): {id: string, name: string, isFolder: boolean, size: number?}
	assert(select("#", ...) == 1, "statFile takes exactly one item ID")
	local file = call("statFile", "GET", API .. itemPath(text((...), "item ID"), "item ID") .. "?$select=id,name,size,folder")
	local isFolder = file.folder ~= nil
	local size = if isFolder then nil else file.size
	if type(file.id) ~= "string" or file.id == "" or type(file.name) ~= "string"
		or (not isFolder and (type(size) ~= "number" or size < 0 or size % 1 ~= 0 or size > 9007199254740991)) then
		houston.fail({operation = "statFile", layer = "upstream", retryable = false, message = "Microsoft Graph returned invalid item metadata"})
	end
	return {id = file.id, name = file.name, isFolder = isFolder, size = size}
end, "statFile(itemId) -> {id, name, isFolder, size?}. One positional item ID; size is absent for folders.")

export("downloadFile", true, download,
	"downloadFile({itemId, path, format?='pdf'}) -> {path, url, size}. Saves a file's bytes to a session path; url is a signed Houston download link. format='pdf' converts Word, Excel, PowerPoint and other documents of up to 2 MB to PDF.")

export("createFolder", false, function(input: any): Options
	local args = options(input)
	local href = API .. itemPath(args.parentId, "parentId") .. "/children"
	local body = {name = text(args.name, "name"), folder = {}, ["@microsoft.graph.conflictBehavior"] = conflictBehavior(args.conflictBehavior, "fail")}
	args.parentId, args.name, args.conflictBehavior = nil, nil, nil
	done("createFolder", args)
	return call("createFolder", "POST", href, body)
end, "createFolder({name, parentId?, conflictBehavior?='fail'|'rename'|'replace'}) -> driveItem. Creates the folder in parentId, or in the root folder.")

export("uploadFile", false, upload,
	"uploadFile({path, parentId?, name?, conflictBehavior?='rename'|'replace'|'fail', contentType?}) -> driveItem. Streams a session file of up to 250 MB into parentId or the root folder; name defaults to the path's basename and cannot contain %, and by default an existing name gets a numbered copy. uploadFile({path, itemId}) replaces that file's content instead. A failed upload may leave nothing or a complete file: check with listChildren before retrying.")

exports.help = helpWith({
	"Microsoft Graph v1.0 for the connected account's OneDrive. Operations take one named options object with Graph's camelCase fields and return Graph's JSON unchanged; deletes and copies return {success=true}. Connector calls return completed values: use them directly, without await.",
	"Items are addressed by itemId; omit it for the root folder, and getItem({path='Folder/file.docx'}) finds an item by path. select lists driveItem fields, defaulting to " .. ITEM .. "; folder is present on folders and file={mimeType} on files.",
	"Lists return one page: while ['@odata.nextLink'] is present, pass it back as nextLink (alone) for the next page.",
	"Files move through session paths: downloads save to a path and return a signed URL, uploads read from a path. Never inline file bytes. Results omit @microsoft.graph.downloadUrl.",
	"No hidden paging; Houston itself retries only a short 429 wait. Errors report the HTTP status and Graph's error code and message, e.g. 'Microsoft Graph HTTP 404 (itemNotFound)'; 429, 503 and other transient server errors are retryable after Retry-After, a full drive (507) is not. A failed or timed-out write may already have succeeded; check before repeating.",
	"Example: local hits = onedrive.searchItems({q='budget', top=10}); local saved = onedrive.downloadFile({itemId=hits.value[1].id, path='budget.xlsx'}).",
})
return exports
