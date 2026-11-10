-- Microsoft Graph v1.0 for the connected account's OneDrive. Arguments and results keep Graph's
-- native field names.
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

local ITEM = "id,name,size,file,folder,package,parentReference,createdDateTime,lastModifiedDateTime,webUrl"
local MAX_UPLOAD = 250 * 1024 * 1024
-- File content redirects to a short-lived preauthenticated URL on these hosts, fetched without credentials.
local DOWNLOAD_HOSTS = {"%.sharepoint%.com$", "%.files%.1drv%.com$", "%.livefilestore%.com$", "^my%.microsoftpersonalcontent%.com$", "%.svc%.ms$"}

local help = {
	text = [[Microsoft Graph v1.0 for the connected account's OneDrive. Operations take one named options
object with Graph's camelCase fields and return Graph's JSON unchanged; deletes and copies return
{success=true}. Connector calls return completed values: use them directly, without await.
Items are addressed by itemId; omit it for the root folder, and getItem({path='Folder/file.docx'})
finds an item by path. driveItems have folder on folders and file={mimeType} on files.
Lists return one page: while ['@odata.nextLink'] is present, pass it back as nextLink, alone.
Files move through session paths: downloads save to a path and return a signed Houston URL, uploads
read from a path. Never inline file bytes. Results omit preauthenticated download links.
No hidden paging; Houston itself retries only a short 429 wait. Errors report the HTTP status and
Graph's code and message, e.g. 'Microsoft Graph HTTP 404 (itemNotFound)'; 429, 503 and other
transient server errors are retryable, a full drive (507) is not. A failed or timed-out write may
already have succeeded: check before repeating.]],
	functions = {} :: {[string]: any},
}
local exports: {[string]: any} = {help = help}

-- Schemas and hints shared by several operations.
local ID = {type = "string", minLength = 1}
local SELECT = {type = {"string", "array"}, items = {type = "string"}, description = "driveItem fields, comma-separated or as an array; defaults to " .. ITEM .. "."}
local NEXT = {type = "string", description = "The previous page's @odata.nextLink; pass it alone."}
local CONFLICT = {type = "string", enum = {"rename", "replace", "fail"}, description = "What happens when the name exists."}
local REFERENCE = {type = "object", properties = {id = ID, driveId = ID}, required = {"id"}, description = "The destination folder."}
local READ = {readOnlyHint = true, openWorldHint = true}
local WRITE = {readOnlyHint = false, destructiveHint = false, openWorldHint = true}
local DESTRUCTIVE = {readOnlyHint = false, destructiveHint = true, openWorldHint = true}

-- An item by ID, or the root folder when id is nil.
local function itemPath(id: any, field: string): string
	if id == nil then return "/drive/root" end
	return "/drive/items/" .. url.segment(text(id, field), field)
end

-- OneDrive names cannot contain a colon, which would end path-based addressing early.
local function itemName(value: any, field: string): string
	assert(not string.find(text(value, field), ":", 1, true), field .. " cannot contain ':'")
	return url.segment(value, field)
end

local function conflictBehavior(value: any, default: string): string
	local behavior = if value == nil then default else value
	assert(behavior == "rename" or behavior == "replace" or behavior == "fail", "conflictBehavior must be rename, replace or fail")
	return behavior
end

-- One page of driveItems with the default fields, unless args holds a nextLink.
local function page(operation: string, href: string, ending: string, args: Options, names: {string}): Options
	local link = nextLink(operation, args, ending)
	if not link then
		if args.select == nil then args.select = ITEM end
		href ..= query(args, names)
		done(operation, args)
	end
	local result = call(operation, "GET", link or href)
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

help.functions.getDrive = {
	description = "The connected account's OneDrive: {id, driveType, owner, quota={total, used, remaining, state}}. id is the driveId copies need.",
	inputSchema = {type = "object", properties = {select = {type = {"string", "array"}, items = {type = "string"}}}, additionalProperties = false, examples = {{select = "id,driveType,quota"}}},
	annotations = READ,
}
function exports.getDrive(args: Options?): Options
	return request("getDrive", "GET", "/drive", args, {query = {"$select"}})
end

help.functions.getItem = {
	description = [[One driveItem {id, name, size, file?={mimeType}, folder?={childCount}, parentReference,
lastModifiedDateTime, webUrl}: by itemId, by path relative to the root such as
'Documents/Q3 report.pdf', or the root folder without either. Names containing % or : can only be
reached by itemId.]],
	inputSchema = {
		type = "object",
		properties = {itemId = ID, path = {type = "string", minLength = 1}, select = SELECT},
		["not"] = {required = {"itemId", "path"}},
		additionalProperties = false,
		examples = {{path = "Documents/Q3 report.pdf"}, {itemId = "01BYE5RZ6QN3ZWBTUFOFD3GSPGOHDJD36K", select = "id,name,size"}} :: {any},
	},
	annotations = READ,
}
function exports.getItem(input: any): Options
	local args = options(input)
	local href = API .. itemPath(args.itemId, "itemId")
	if args.path ~= nil then
		assert(args.itemId == nil, "getItem takes itemId or path, not both")
		local segments: {string} = {}
		for part in string.gmatch(text(args.path, "path"), "[^/]+") do table.insert(segments, itemName(part, "path")) end
		if #segments > 0 then href ..= ":/" .. table.concat(segments, "/") .. ":" end
	end
	args.itemId, args.path = nil, nil
	if args.select == nil then args.select = ITEM end
	href ..= query(args, {"$select"})
	done("getItem", args)
	return call("getItem", "GET", href)
end

help.functions.listChildren = {
	description = "One page of a folder's driveItems, the root folder without itemId: {value={driveItem}, ['@odata.nextLink']?}. top is at most 999 (default 200); orderby is e.g. 'name' or 'lastModifiedDateTime desc'.",
	inputSchema = {
		type = "object",
		properties = {itemId = ID, select = SELECT, top = {type = "integer", minimum = 1, maximum = 999}, orderby = {type = "string"}, nextLink = NEXT},
		additionalProperties = false,
		examples = {{itemId = "01BYE5RZ6QN3ZWBTUFOFD3GSPGOHDJD36K", top = 50, orderby = "name"}},
	},
	annotations = READ,
}
function exports.listChildren(input: any): Options
	local args = options(input)
	local href = ""
	if args.nextLink == nil then
		href = API .. itemPath(args.itemId, "itemId") .. "/children"
		args.itemId = nil
	end
	return page("listChildren", href, "/children$", args, {"$select", "$top", "$orderby"})
end

help.functions.searchItems = {
	description = "One page of driveItems whose name, metadata or content match q, across the drive: {value={driveItem}, ['@odata.nextLink']?}. q cannot contain / or %.",
	inputSchema = {
		type = "object",
		properties = {q = {type = "string", minLength = 1}, select = SELECT, top = {type = "integer", minimum = 1}, nextLink = NEXT},
		additionalProperties = false,
		examples = {{q = "quarterly budget", top = 10}},
	},
	annotations = READ,
}
function exports.searchItems(input: any): Options
	local args = options(input)
	local href = ""
	if args.nextLink == nil then
		-- OData quotes a literal by doubling its single quotes.
		href = API .. "/drive/root/search(q='" .. url.segment((string.gsub(text(args.q, "q"), "'", "''")), "q") .. "')"
		args.q = nil
	end
	return page("searchItems", href, "[/%.]search%(.*%)$", args, {"$select", "$top"})
end

help.functions.listPermissions = {
	description = "Who can access an item, including its sharing links: {value={{id, roles, link?, grantedToV2?, invitation?}}, ['@odata.nextLink']?}.",
	inputSchema = {type = "object", properties = {itemId = ID, nextLink = NEXT}, additionalProperties = false, examples = {{itemId = "01BYE5RZ6QN3ZWBTUFOFD3GSPGOHDJD36K"}}},
	annotations = READ,
}
function exports.listPermissions(args: Options?): Options
	return request("listPermissions", "GET", "/drive/items/{itemId}/permissions", args, {list = "/permissions$"})
end

-- Fixed-signature file lookup shared with other storage connectors.
help.functions.statFile = {
	description = "One item's {id, name, isFolder, size?}; size is absent for folders.",
	args = {"itemId"},
	inputSchema = {type = "object", properties = {itemId = ID}, required = {"itemId"}, additionalProperties = false, examples = {{itemId = "01BYE5RZ6QN3ZWBTUFOFD3GSPGOHDJD36K"}}},
	outputSchema = {
		type = "object",
		properties = {id = ID, name = {type = "string"}, isFolder = {type = "boolean"}, size = {type = "integer", minimum = 0}},
		required = {"id", "name", "isFolder"},
		additionalProperties = false,
	},
	annotations = READ,
}
function exports.statFile(...: any): {id: string, name: string, isFolder: boolean, size: number?}
	assert(select("#", ...) == 1, "statFile takes exactly one item ID")
	local file = call("statFile", "GET", API .. itemPath(text((...), "item ID"), "item ID") .. "?$select=id,name,size,folder")
	local isFolder = file.folder ~= nil
	local size = if isFolder then nil else file.size
	if type(file.id) ~= "string" or file.id == "" or type(file.name) ~= "string"
		or (not isFolder and (type(size) ~= "number" or size < 0 or size % 1 ~= 0 or size > 9007199254740991)) then
		houston.fail({operation = "statFile", layer = "upstream", retryable = false, message = "Microsoft Graph returned invalid item metadata"})
	end
	return {id = file.id, name = file.name, isFolder = isFolder, size = size}
end

help.functions.downloadFile = {
	description = "Saves a file's bytes to a session path and returns {path, url, size}, where url is a signed Houston download link. format='pdf' converts Word, Excel, PowerPoint and other documents of up to 2 MB to PDF.",
	inputSchema = {
		type = "object",
		properties = {itemId = ID, path = {type = "string", minLength = 1, description = "Session file path to write."}, format = {type = "string", enum = {"pdf"}}},
		required = {"itemId", "path"},
		additionalProperties = false,
		examples = {{itemId = "01BYE5RZ6QN3ZWBTUFOFD3GSPGOHDJD36K", path = "report.docx"}, {itemId = "01BYE5RZ6QN3ZWBTUFOFD3GSPGOHDJD36K", path = "report.pdf", format = "pdf"}} :: {any},
	},
	annotations = READ,
}
-- Graph answers with a redirect to the file's preauthenticated link, which expires within minutes.
function exports.downloadFile(input: any): Options
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

if config.access == "read-write" then
	help.functions.createFolder = {
		description = "Creates a folder in parentId, or in the root folder, and returns its driveItem. conflictBehavior defaults to 'fail'.",
		inputSchema = {
			type = "object",
			properties = {name = {type = "string", minLength = 1}, parentId = ID, conflictBehavior = CONFLICT},
			required = {"name"},
			additionalProperties = false,
			examples = {{name = "Reports"}, {name = "2026", parentId = "01BYE5RZ6QN3ZWBTUFOFD3GSPGOHDJD36K", conflictBehavior = "rename"}} :: {any},
		},
		annotations = WRITE,
	}
	function exports.createFolder(input: any): Options
		local args = options(input)
		local href = API .. itemPath(args.parentId, "parentId") .. "/children"
		local body = {name = text(args.name, "name"), folder = {}, ["@microsoft.graph.conflictBehavior"] = conflictBehavior(args.conflictBehavior, "fail")}
		args.parentId, args.name, args.conflictBehavior = nil, nil, nil
		done("createFolder", args)
		return call("createFolder", "POST", href, body)
	end

	help.functions.uploadFile = {
		description = [[Streams a session file of up to 250 MB into parentId or the root folder and returns its driveItem.
name defaults to the path's basename and cannot contain % or :; by default an existing name gets a
numbered copy. With itemId instead, replaces that file's content. A failed upload may leave nothing
or a complete file: check with listChildren before retrying.]],
		inputSchema = {
			type = "object",
			properties = {
				path = {type = "string", minLength = 1, description = "Session file to upload."},
				parentId = ID, name = {type = "string", minLength = 1}, conflictBehavior = CONFLICT,
				itemId = {type = "string", minLength = 1, description = "A file whose content to replace; excludes parentId, name and conflictBehavior."},
				contentType = {type = "string", minLength = 1, description = "Defaults to application/octet-stream."},
			},
			required = {"path"},
			additionalProperties = false,
			examples = {{path = "report.pdf", parentId = "01BYE5RZ6QN3ZWBTUFOFD3GSPGOHDJD36K", contentType = "application/pdf"}, {path = "report.pdf", itemId = "01BYE5RZ6QN3ZWBTUFOFD3GSPGOHDJD36K"}} :: {any},
		},
		annotations = WRITE,
	}
	function exports.uploadFile(input: any): Options
		local args = options(input)
		local path = text(args.path, "path")
		local contentType = text(args.contentType or "application/octet-stream", "contentType")
		local href: string
		if args.itemId ~= nil then
			assert(args.parentId == nil and args.name == nil and args.conflictBehavior == nil,
				"uploadFile with itemId replaces content only; omit parentId, name and conflictBehavior")
			href = API .. itemPath(text(args.itemId, "itemId"), "itemId") .. "/content"
		else
			href = API .. itemPath(args.parentId, "parentId") .. ":/" .. itemName(args.name or string.match(path, "[^/]+$"), "name")
				.. ":/content?@microsoft.graph.conflictBehavior=" .. conflictBehavior(args.conflictBehavior, "rename")
		end
		args.path, args.contentType, args.itemId, args.parentId, args.name, args.conflictBehavior = nil, nil, nil, nil, nil, nil
		done("uploadFile", args)
		assert(await(fs.stat(path)).size <= MAX_UPLOAD, "uploadFile handles files up to 250 MB")
		return decode("uploadFile", await(http.request({method = "PUT", url = href,
			headers = {["Content-Type"] = {contentType}}, body = fs.open(path, "r")})))
	end

	help.functions.updateItem = {
		description = "Renames an item, changes its description, or moves it with parentReference={id=<folder itemId>}; returns the driveItem.",
		inputSchema = {
			type = "object",
			properties = {itemId = ID, name = {type = "string", minLength = 1}, description = {type = "string"}, parentReference = REFERENCE, select = SELECT},
			required = {"itemId"},
			additionalProperties = true,
			examples = {{itemId = "01BYE5RZ6QN3ZWBTUFOFD3GSPGOHDJD36K", name = "Q3 report (final).pdf"}},
		},
		annotations = WRITE,
	}
	function exports.updateItem(args: Options?): Options
		return request("updateItem", "PATCH", "/drive/items/{itemId}", args, {body = true, defaults = {select = ITEM}, query = {"$select"}})
	end

	help.functions.copyItem = {
		description = [[Copies an item into parentReference={driveId, id}, where driveId is getDrive().id or an item's
parentReference.driveId; name is required to copy into the same folder. Returns {success=true}:
OneDrive copies in the background and reports no later failure, such as a name conflict, so list the
destination to find the copy.]],
		inputSchema = {
			type = "object",
			properties = {itemId = ID, parentReference = REFERENCE, name = {type = "string", minLength = 1}},
			required = {"itemId", "parentReference"},
			additionalProperties = false,
			examples = {{itemId = "01BYE5RZ6QN3ZWBTUFOFD3GSPGOHDJD36K", parentReference = {driveId = "b!x-1", id = "01BYE5RZ2BXHFM2TBFTJ7QXAG6KD4V4S7L"}, name = "Q3 report copy.pdf"}},
		},
		annotations = WRITE,
	}
	function exports.copyItem(args: Options?): Options
		return request("copyItem", "POST", "/drive/items/{itemId}/copy", args, {body = true})
	end

	help.functions.deleteItem = {
		description = "Moves an item to the OneDrive recycle bin and returns {success=true}.",
		inputSchema = {type = "object", properties = {itemId = ID}, required = {"itemId"}, additionalProperties = false, examples = {{itemId = "01BYE5RZ6QN3ZWBTUFOFD3GSPGOHDJD36K"}}},
		annotations = DESTRUCTIVE,
	}
	function exports.deleteItem(args: Options?): Options
		return request("deleteItem", "DELETE", "/drive/items/{itemId}", args)
	end

	help.functions.createLink = {
		description = "Creates or returns a sharing link: a permission with link.webUrl. Anyone with an anonymous link can open the item; organizations may disable them.",
		inputSchema = {
			type = "object",
			properties = {
				itemId = ID, type = {type = "string", enum = {"view", "edit", "embed"}},
				scope = {type = "string", enum = {"anonymous", "organization", "users"}},
				expirationDateTime = {type = "string"}, password = {type = "string"},
			},
			required = {"itemId", "type"},
			additionalProperties = false,
			examples = {{itemId = "01BYE5RZ6QN3ZWBTUFOFD3GSPGOHDJD36K", type = "view", scope = "organization"}},
		},
		annotations = WRITE,
	}
	function exports.createLink(args: Options?): Options
		return request("createLink", "POST", "/drive/items/{itemId}/createLink", args, {body = true})
	end

	help.functions.invite = {
		description = "Shares an item with people and returns {value={permission}}; sendInvitation (default true) emails them.",
		inputSchema = {
			type = "object",
			properties = {
				itemId = ID,
				recipients = {type = "array", minItems = 1, items = {type = "object", properties = {email = {type = "string", minLength = 1}}, required = {"email"}}},
				roles = {type = "array", minItems = 1, items = {type = "string", enum = {"read", "write"}}},
				requireSignIn = {type = "boolean"}, sendInvitation = {type = "boolean"}, message = {type = "string"},
			},
			required = {"itemId", "recipients", "roles"},
			additionalProperties = false,
			examples = {{itemId = "01BYE5RZ6QN3ZWBTUFOFD3GSPGOHDJD36K", recipients = {{email = "ana@example.com"}}, roles = {"read"}, sendInvitation = false}},
		},
		annotations = WRITE,
	}
	function exports.invite(args: Options?): Options
		return request("invite", "POST", "/drive/items/{itemId}/invite", args, {body = true})
	end

	help.functions.deletePermission = {
		description = "Revokes a sharing link or a person's access and returns {success=true}.",
		inputSchema = {
			type = "object",
			properties = {itemId = ID, permissionId = ID},
			required = {"itemId", "permissionId"},
			additionalProperties = false,
			examples = {{itemId = "01BYE5RZ6QN3ZWBTUFOFD3GSPGOHDJD36K", permissionId = "aTowIy5mfG1lbWJlcnNoaXA"}},
		},
		annotations = DESTRUCTIVE,
	}
	function exports.deletePermission(args: Options?): Options
		return request("deletePermission", "DELETE", "/drive/items/{itemId}/permissions/{permissionId}", args)
	end
end

return exports
