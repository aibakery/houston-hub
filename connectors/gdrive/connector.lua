-- Google Drive API v3. Arguments and results keep Google's native field names.
local API = "https://www.googleapis.com/drive/v3"
local UPLOAD = "https://www.googleapis.com/upload/drive/v3"
local FOLDER = "application/vnd.google-apps.folder"

-- Request layer shared verbatim by the Google connectors (tools/validate checks they match).
type Options = {[string]: any}
type Endpoint = {method: string, path: string, read: boolean, query: {string}?, body: boolean?, defaults: Options?, list: string?, required: {[string]: string}?, help: string}

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
		for key, item in (if type(value) == "table" then value else {value}) do
			assert(type(key) == "number" and (type(item) == "string" or type(item) == "number" or type(item) == "boolean"), name .. " must be a string, number, boolean or an array of them")
			table.insert(parts, url.encode(name) .. "=" .. url.encode(item))
		end
	end
	return if #parts > 0 then "?" .. table.concat(parts, "&") else ""
end

local function fail(operation: string, response: HttpResponse): never
	local ok, decoded = pcall(json.decode, await(response.body:readPrefix(4096)))
	local problem = if ok and type(decoded) == "table" and type(decoded.error) == "table" then decoded.error else {}
	-- Older APIs name the reason in errors[], newer ones in an ErrorInfo detail.
	local reasons: {any} = if type(problem.errors) == "table" then problem.errors elseif type(problem.details) == "table" then problem.details else {}
	local reason: string? = nil
	for _, item in reasons do
		if type(item) == "table" and type(item.reason) == "string" then
			reason = item.reason
			break
		end
	end
	local message = "Google HTTP " .. tostring(response.statusCode)
	if type(problem.status) == "string" then message ..= " (" .. problem.status .. ")" end
	if type(problem.message) == "string" then message ..= ": " .. string.sub(problem.message, 1, 600) end
	if reason then message ..= " [" .. reason .. "]" end
	local retry = response.headers["retry-after"]
	if retry and retry[1] then message ..= "; Retry-After: " .. retry[1] end
	local limited = reason ~= nil and string.find((string.gsub(string.lower(reason), "_", "")), "ratelimitexceeded", 1, true) ~= nil
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

-- Accepts a docs.google.com editor URL in place of its file ID; published and responder links (/d/e/...) carry no ID.
local function docsId(value: any, product: string, field: string): any
	if type(value) ~= "string" then return value end
	local rest = string.match(value, "^https://docs%.google%.com/" .. product .. "/d/(.*)$")
		or string.match(value, "^https://docs%.google%.com/" .. product .. "/u/%d+/d/(.*)$")
		or string.match(value, "^https://docs%.google%.com/a/[^/]+/" .. product .. "/d/(.*)$")
	local id: string = if rest then string.match(rest, "^[^/?#]*") or "" else value
	assert(string.match(id, "^[%w_%-]+$") and id ~= "e", field .. " must be an ID or its https://docs.google.com/" .. product .. "/d/<id> URL")
	return id
end

-- Moves {placeholders} and declared query fields from args into the URL; remaining fields form the JSON body.
local function target(name: string, endpoint: Endpoint, args: Options): string
	local defaults: Options = endpoint.defaults or {}
	for key, value in defaults do
		if args[key] == nil then args[key] = value end
	end
	local required: {[string]: string} = endpoint.required or {}
	for field, kind in required do
		local value = args[field]
		assert(if kind == "array" then type(value) == "table" and value[1] ~= nil elseif kind == "string" then type(value) == "string" and value ~= "" elseif kind == "object" then type(value) == "table" and next(value) ~= nil and value[1] == nil else false,
			name .. " requires " .. field .. " as a nonempty " .. kind)
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

local FILE_FIELDS = "id,name,mimeType,size,createdTime,modifiedTime,parents,webViewLink,trashed,description,owners(displayName,emailAddress)"
local FILE = {fields = FILE_FIELDS, supportsAllDrives = true}
local FILE_QUERY = {"fields", "supportsAllDrives"}
local ALL_DRIVES = {supportsAllDrives = true}
local endpoints: {[string]: Endpoint} = {
	getAbout = {method = "GET", path = "/about", read = true, defaults = {fields = "user,storageQuota"}, query = {"fields"},
		help = "getAbout({fields?}) -> {user, storageQuota}. The connected account and its storage use."},
	listFiles = {method = "GET", path = "/files", read = true, list = "files",
		defaults = {fields = "nextPageToken,incompleteSearch,files(" .. FILE_FIELDS .. ")", supportsAllDrives = true, includeItemsFromAllDrives = true},
		query = {"q", "pageSize", "pageToken", "orderBy", "fields", "corpora", "driveId", "spaces", "includeItemsFromAllDrives", "supportsAllDrives"},
		help = "listFiles({q?, pageSize?, pageToken?, orderBy?, corpora?, driveId?, fields?}) -> {files, nextPageToken?, incompleteSearch}. q uses Drive search syntax, e.g. \"name contains 'report' and trashed = false\" or \"'<folderId>' in parents\". pageSize ≤1000. Includes shared drives."},
	getFile = {method = "GET", path = "/files/{fileId}", read = true, defaults = FILE, query = FILE_QUERY,
		help = "getFile({fileId, fields?}) -> file metadata. Pass fields='*' for every field."},
	listDrives = {method = "GET", path = "/drives", read = true, list = "drives", query = {"q", "pageSize", "pageToken"},
		help = "listDrives({q?, pageSize?, pageToken?}) -> {drives, nextPageToken?}. Shared drives the account can access."},
	listPermissions = {method = "GET", path = "/files/{fileId}/permissions", read = true, list = "permissions",
		defaults = {fields = "nextPageToken,permissions(id,type,role,emailAddress,domain,displayName)", supportsAllDrives = true},
		query = {"pageSize", "pageToken", "fields", "supportsAllDrives"},
		help = "listPermissions({fileId, pageSize?, pageToken?}) -> {permissions, nextPageToken?}. Who can access a file."},
	createFile = {method = "POST", path = "/files", read = false, body = true, defaults = FILE, query = FILE_QUERY,
		help = "createFile({name, mimeType?, parents?, description?, ...}) -> file. Metadata only: creates folders (mimeType='" .. FOLDER .. "'), shortcuts or empty Google Docs. Use uploadFile for content."},
	updateFile = {method = "PATCH", path = "/files/{fileId}", read = false, body = true, defaults = FILE, query = {"addParents", "removeParents", "fields", "supportsAllDrives"},
		help = "updateFile({fileId, addParents?, removeParents?, name?, description?, trashed?, ...}) -> file. Renames, moves (addParents/removeParents as comma-separated folder IDs) or trashes (trashed=true)."},
	copyFile = {method = "POST", path = "/files/{fileId}/copy", read = false, body = true, defaults = FILE, query = FILE_QUERY,
		help = "copyFile({fileId, name?, parents?}) -> the new file."},
	deleteFile = {method = "DELETE", path = "/files/{fileId}", read = false, defaults = ALL_DRIVES, query = {"supportsAllDrives"},
		help = "deleteFile({fileId}) -> {success=true}. Permanently deletes, skipping the trash; prefer updateFile({fileId, trashed=true})."},
	createPermission = {method = "POST", path = "/files/{fileId}/permissions", read = false, body = true, defaults = ALL_DRIVES,
		query = {"sendNotificationEmail", "emailMessage", "transferOwnership", "supportsAllDrives", "fields"},
		help = "createPermission({fileId, type='user'|'group'|'domain'|'anyone', role='reader'|'commenter'|'writer'|..., emailAddress?, domain?, sendNotificationEmail?, emailMessage?}) -> permission. Shares a file."},
	deletePermission = {method = "DELETE", path = "/files/{fileId}/permissions/{permissionId}", read = false, defaults = ALL_DRIVES, query = {"supportsAllDrives"},
		help = "deletePermission({fileId, permissionId}) -> {success=true}. Revokes access."},
}

-- Downloads stream the response body to a session file.
local downloads: {[string]: Endpoint} = {
	downloadFile = {method = "GET", path = "/files/{fileId}", read = true, defaults = {alt = "media", supportsAllDrives = true}, query = {"alt", "supportsAllDrives", "acknowledgeAbuse"},
		help = "downloadFile({fileId, path}) -> {path, url, size}. Saves a stored file's bytes to a session path; url is a signed Houston download link. Google Docs, Sheets and Slides have no stored bytes: use exportFile."},
	exportFile = {method = "GET", path = "/files/{fileId}/export", read = true, query = {"mimeType"},
		help = "exportFile({fileId, mimeType, path}) -> {path, url, size}. Converts a Google Doc, Sheet or Slides file, e.g. mimeType='text/markdown', 'text/plain', 'text/csv', 'application/pdf' or an Office format. Exports are limited to 10 MB."},
}

local function download(name: string, endpoint: Endpoint, input: any): Options
	local args = options(input)
	local path = text(args.path, "path")
	args.path = nil
	local response = await(http.request({method = "GET", url = target(name, endpoint, args)}))
	if response.statusCode < 200 or response.statusCode >= 300 then fail(name, response) end
	local output = fs.open(path, "w")
	output:write(response.body)
	await(output:close())
	return {path = path, url = await(fs.signedGetUrl(path)), size = await(fs.stat(path)).size}
end

-- Resumable upload: Google returns a session URL for the metadata, then receives the streamed file.
local function upload(input: any): any
	local args = options(input)
	local path = text(args.path, "path")
	local fileId = if args.fileId == nil then nil else text(args.fileId, "fileId")
	local contentType = text(args.contentType or "application/octet-stream", "contentType")
	args.path, args.fileId, args.contentType = nil, nil, nil
	if fileId == nil and args.name == nil then args.name = string.match(path, "[^/]+$") end
	local start = UPLOAD .. "/files" .. (if fileId then "/" .. url.segment(fileId, "fileId") else "") .. "?uploadType=resumable&supportsAllDrives=true&fields=" .. url.encode(FILE_FIELDS)
	local session = await(http.request({method = if fileId then "PATCH" else "POST", url = start, body = json.encode(args),
		headers = {["Content-Type"] = {"application/json; charset=UTF-8"}, ["X-Upload-Content-Type"] = {contentType}}}))
	if session.statusCode < 200 or session.statusCode >= 300 then fail("uploadFile", session) end
	session.body:close()
	local location = session.headers.location
	if not location or not location[1] then
		houston.fail({operation = "uploadFile", layer = "upstream", upstream_status = session.statusCode, retryable = false, message = "Google returned no upload session URL"})
	end
	return decode("uploadFile", await(http.request({method = "PUT", url = location[1], headers = {["Content-Type"] = {contentType}}, body = fs.open(path, "r")})))
end

exportEndpoints(endpoints)
-- DELETE /files/trash is Drive's emptyTrash, which the {fileId} route would otherwise reach.
local deleteFile = exports.deleteFile
if deleteFile then
	exports.deleteFile = function(args: any): any
		assert(type(args) ~= "table" or args.fileId ~= "trash", "fileId 'trash' is not a file")
		return deleteFile(args)
	end
end
for name, endpoint in downloads do
	export(name, true, function(args: Options): Options return download(name, endpoint, args) end, endpoint.help)
end

-- Fixed-signature file lookup shared with other storage connectors.
export("statFile", true, function(...: any): {id: string, name: string, isFolder: boolean, size: number?}
	assert(select("#", ...) == 1, "statFile takes exactly one file ID")
	local id = text((...), "file ID")
	local file = call("statFile", "GET", API .. "/files/" .. url.segment(id, "file ID") .. "?fields=id%2Cname%2CmimeType%2Csize&supportsAllDrives=true")
	local size = if file.size == nil then nil else tonumber(file.size)
	if type(file.id) ~= "string" or file.id == "" or type(file.name) ~= "string"
		or (file.size ~= nil and (size == nil or size < 0 or size % 1 ~= 0 or size > 9007199254740991)) then
		houston.fail({operation = "statFile", layer = "upstream", retryable = false, message = "Google returned invalid file metadata"})
	end
	return {id = file.id, name = file.name, isFolder = file.mimeType == FOLDER, size = size}
end, "statFile(fileId) -> {id, name, isFolder, size?}. One positional file ID; size is absent for folders and Google Docs.")

export("uploadFile", false, upload, "uploadFile({path, name?, parents?, mimeType?, contentType?, fileId?, ...metadata}) -> file. Streams a session file to Drive. name defaults to the path's basename; contentType describes the bytes (default application/octet-stream). Setting mimeType to a Google type converts, e.g. a .docx with mimeType='application/vnd.google-apps.document'. With fileId, replaces that file's content (and applies any metadata). A failed upload may leave nothing or a complete file: check with listFiles before retrying.")

exports.help = helpWith({
	"Google Drive API v3. Operations take one named options object with Google's camelCase fields and return Google's JSON unchanged; deletes return {success=true}. Shared drives are included by default.",
	"File metadata defaults to " .. FILE_FIELDS .. "; pass fields to choose others ('*' for all). Lists return one page: pass nextPageToken as pageToken until it is absent.",
	"Files move through session paths: downloads save to a path and return a signed URL, uploads read from a path. Never inline file bytes.",
	"No hidden paging or retries. Errors report the HTTP status, Google's message and reason. A failed or timed-out write may already have succeeded; check before repeating.",
	"Example: listFiles({q=\"mimeType = 'application/pdf' and trashed = false\", orderBy='modifiedTime desc', pageSize=20}); exportFile({fileId='...', mimeType='text/markdown', path='notes.md'}).",
})
return exports
