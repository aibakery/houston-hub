-- Google Drive connector: metadata, vendor links, and session-file transfer.
-- Host primitives used: http.send (via connector_http) and fs.signedGetUrl.
-- Public functions are the storage/drive contract later providers reuse;
-- only the HTTP paths and filter compilation below are Drive-specific.
-- File bytes do not travel in the MCP RPC envelope.

local BASE = "https://www.googleapis.com/drive/v3"
local UPLOAD_BASE = "https://www.googleapis.com/upload/drive/v3"
local FOLDER_MIME = "application/vnd.google-apps.folder"
local FILE_FIELDS =
	"id,name,mimeType,size,md5Checksum,webViewLink,webContentLink,exportLinks,modifiedTime"
local LIST_FIELDS = "nextPageToken,files(" .. FILE_FIELDS .. ")"

local function encode(s)
	return connector_http.encode(s)
end

local function query_string(params)
	return connector_http.query_string(params)
end

local function request(ctx, method, path, params, operation, cursor, body)
	if type(ctx) ~= "table" or type(ctx.id) ~= "string" or ctx.id == "" then
		error("gdrive connector id is required")
	end
	local url = BASE .. path
	local qs = query_string(params)
	if qs ~= "" then
		url = url .. "?" .. qs
	end
	if cursor == nil and type(params) == "table" then
		cursor = params.pageToken
	end
	local headers, payload = nil, nil
	if body ~= nil then
		headers = { ["Content-Type"] = "application/json" }
		payload = json.encode(body)
	end
	return connector_http.send({
		connector = "gdrive",
		operation = operation,
		method = method,
		path = path,
		url = url,
		headers = headers,
		body = payload,
		connector_id = ctx.id,
		affected_cursor = cursor,
	})
end

local function drive_quote(value)
	local s = tostring(value)
	s = string.gsub(s, "\\", "\\\\")
	s = string.gsub(s, "'", "\\'")
	return "'" .. s .. "'"
end

local function rfc3339(value)
	local s = tostring(value)
	local y, m, d = string.match(s, "^(%d%d%d%d)%D(%d%d)%D(%d%d)")
	if not y then
		return s
	end
	local rest = string.match(s, "^%d%d%d%d%D%d%d%D%d%d(.*)$") or ""
	if rest == "" then
		return y .. "-" .. m .. "-" .. d .. "T00:00:00"
	end
	if string.sub(rest, 1, 1) == "T" then
		return y .. "-" .. m .. "-" .. d .. rest
	end
	return y .. "-" .. m .. "-" .. d .. "T00:00:00"
end

local function each_value(value, fn)
	if value == nil then
		return
	end
	if type(value) == "table" then
		for _, item in value do
			each_value(item, fn)
		end
		return
	end
	local s = tostring(value)
	if s ~= "" then
		fn(s)
	end
end

local function compile_query(opts)
	local terms = {}
	each_value(opts.name, function(s)
		terms[#terms + 1] = "name contains " .. drive_quote(s)
	end)
	each_value(opts.mime, function(s)
		terms[#terms + 1] = "mimeType = " .. drive_quote(s)
	end)
	each_value(opts.folder, function(s)
		terms[#terms + 1] = drive_quote(s) .. " in parents"
	end)
	if opts.after ~= nil and tostring(opts.after) ~= "" then
		terms[#terms + 1] = "modifiedTime > " .. drive_quote(rfc3339(opts.after))
	end
	if opts.before ~= nil and tostring(opts.before) ~= "" then
		terms[#terms + 1] = "modifiedTime < " .. drive_quote(rfc3339(opts.before))
	end
	each_value(opts.text, function(s)
		terms[#terms + 1] = "fullText contains " .. drive_quote(s)
	end)
	if opts.q ~= nil and tostring(opts.q) ~= "" then
		local raw = tostring(opts.q)
		if #terms > 0 then
			terms[#terms + 1] = "(" .. raw .. ")"
		else
			terms[#terms + 1] = raw
		end
	end
	if #terms == 0 then
		return nil
	end
	return table.concat(terms, " and ")
end

local function list_params(opts)
	opts = opts or {}
	return {
		pageSize = opts.pageSize or opts.maxResults,
		pageToken = opts.pageToken,
		q = compile_query(opts),
		orderBy = opts.orderBy,
		fields = opts.fields or LIST_FIELDS,
	}
end

local function get_params(opts)
	opts = opts or {}
	return {
		fields = opts.fields or FILE_FIELDS,
	}
end

local function vendor_links(meta)
	if type(meta) ~= "table" then
		return meta
	end
	-- Relayed Google links must never include an access token.
	local function scrub(url)
		if type(url) ~= "string" then
			return url
		end
		if string.find(url, "access_token=", 1, true) or string.find(url, "token=", 1, true) then
			return nil
		end
		return url
	end
	meta.webContentLink = scrub(meta.webContentLink)
	meta.webViewLink = scrub(meta.webViewLink)
	if type(meta.exportLinks) == "table" then
		local clean = {}
		for k, v in meta.exportLinks do
			clean[k] = scrub(v)
		end
		meta.exportLinks = clean
	end
	return meta
end

local function decorate_file(meta)
	if type(meta) ~= "table" then
		return meta
	end
	vendor_links(meta)
	if meta.mime == nil then
		meta.mime = meta.mimeType
	end
	if meta.modified == nil then
		meta.modified = meta.modifiedTime
	end
	if type(meta.size) == "string" then
		local n = tonumber(meta.size)
		if n ~= nil then
			meta.size = n
		end
	end
	if meta.folder == nil then
		meta.folder = meta.mime == FOLDER_MIME or meta.mimeType == FOLDER_MIME
	end
	return meta
end

local function decorate_list(raw)
	if type(raw) == "table" and type(raw.files) == "table" then
		for _, file in raw.files do
			decorate_file(file)
		end
	end
	return raw
end

local function request_file(ctx, method, url, path, operation, cursor, headers)
	if type(ctx) ~= "table" or type(ctx.id) ~= "string" or ctx.id == "" then
		error("gdrive connector id is required")
	end
	return connector_http.send({
		connector = "gdrive",
		operation = operation,
		method = method,
		path = path,
		url = url,
		headers = headers,
		dest = path,
		connector_id = ctx.id,
		affected_cursor = cursor,
	})
end

local function upload_file_body(ctx, method, url, path, operation, headers)
	if type(ctx) ~= "table" or type(ctx.id) ~= "string" or ctx.id == "" then
		error("gdrive connector id is required")
	end
	return connector_http.send({
		connector = "gdrive",
		operation = operation,
		method = method,
		path = path,
		url = url,
		headers = headers,
		src = path,
		connector_id = ctx.id,
	})
end

local functions = {}

function functions.listFiles(ctx, opts)
	return decorate_list(request(ctx, "GET", "/files", list_params(opts), "listFiles"))
end

function functions.getFile(ctx, id, opts)
	if type(id) == "table" then
		opts = id
		id = id.id
	end
	if type(id) ~= "string" or id == "" then
		error("gdrive.getFile requires a file id")
	end
	return decorate_file(request(ctx, "GET", "/files/" .. encode(id), get_params(opts), "getFile", id))
end

function functions.downloadFile(ctx, id, path, opts)
	if type(id) == "table" then
		opts = id
		path = id.path
		id = id.id
	end
	opts = opts or {}
	if type(id) ~= "string" or id == "" then
		error("gdrive.downloadFile requires a file id")
	end
	if type(path) ~= "string" or path == "" then
		error("gdrive.downloadFile requires a session path")
	end
	local url
	if type(opts.mimeType) == "string" and opts.mimeType ~= "" then
		url = BASE .. "/files/" .. encode(id) .. "/export?mimeType=" .. encode(opts.mimeType)
	else
		url = BASE .. "/files/" .. encode(id) .. "?alt=media"
	end
	local saved = request_file(ctx, "GET", url, path, "downloadFile", id)
	local signed = nil
	if type(fs) == "table" and type(fs.signedGetUrl) == "function" then
		signed = fs.signedGetUrl(path)
	end
	return {
		path = path,
		url = signed,
		bytes = saved and saved.bytes,
	}
end

local writes = {}

function writes.createFile(ctx, meta)
	if meta ~= nil and type(meta) ~= "table" then
		error("gdrive.createFile requires a metadata table")
	end
	return request(ctx, "POST", "/files", nil, "createFile", nil, meta or {})
end

function writes.deleteFile(ctx, id)
	if type(id) == "table" then
		id = id.id
	end
	if type(id) ~= "string" or id == "" then
		error("gdrive.deleteFile requires a file id")
	end
	return request(ctx, "DELETE", "/files/" .. encode(id), nil, "deleteFile", id)
end

function writes.uploadFile(ctx, path, meta)
	if type(path) == "table" then
		meta = path
		path = path.path
	end
	if type(path) ~= "string" or path == "" then
		error("gdrive.uploadFile requires a session path")
	end
	meta = meta or {}
	local mime = meta.mimeType or "application/octet-stream"
	local created = upload_file_body(
		ctx,
		"POST",
		UPLOAD_BASE .. "/files?uploadType=media",
		path,
		"uploadFile",
		{ ["Content-Type"] = mime }
	)
	if type(created) ~= "table" or type(created.id) ~= "string" or created.id == "" then
		return created
	end
	local patch = {}
	local has_patch = false
	if type(meta.name) == "string" and meta.name ~= "" then
		patch.name = meta.name
		has_patch = true
	end
	if type(meta.parents) == "table" then
		patch.parents = meta.parents
		has_patch = true
	end
	if not has_patch then
		return created
	end
	return request(ctx, "PATCH", "/files/" .. encode(created.id), nil, "uploadFile", created.id, patch)
end

return {
	name = "gdrive",
	description = "Read a connected Google Drive account.",
	signatures = {
		listFiles = "listFiles(opts?)",
		getFile = "getFile(id, opts?)",
		downloadFile = "downloadFile(id, path, opts?)",
		createFile = "createFile(meta?)",
		deleteFile = "deleteFile(id)",
		uploadFile = "uploadFile(path, meta?)",
	},
	help = [[
# Google Drive

Read files for one connected Google Drive account. Credentials stay on the
Houston server. This is the storage/drive contract: later file-drive
providers implement the same functions. Use the instance from
`houston.connectors()` — do not call provider URLs yourself.

List-connector signatures are enough to call. Return compact rows;
`truncate` defaults true. Loop pagination in one `run`.

## listFiles(opts?)

Search and list files. Rows already have `id`, `name`, `mime`, `size`,
`modified`, and `folder` (boolean) — do not `getFile` every row. Optional
filters on `opts`:

- `folder` (Drive folder id)
- `name`, `mime`, `text` (string, or array of strings)
- `after`, `before` (YYYY-MM-DD)
- `pageSize` or `maxResults` (number)
- `pageToken` (string)
- `orderBy` (string)
- `q` (raw Drive search string; escape hatch, compiled with the filters)

Filters are compiled to Drive `q` inside this module (`name contains`,
`mimeType =`, `'id' in parents`, `modifiedTime`, `fullText contains`).
Pass `q` only when you need a vendor clause the filters do not cover.

Returns `files` and `nextPageToken`. Loop pages in the same `run`.

## getFile(id, opts?)

One file. `id` may be a string or a table with `id`. Same shared fields as
`listFiles`, plus `webViewLink`, `webContentLink`, and `exportLinks` when
Drive provides them. Use those vendor links when you do not need to
process bytes — they do not include a Google access token.

`getFile("abc")` and `getFile({ id = "abc" })` are the same call.
This does not download file bytes into Houston.

## downloadFile(id, path, opts?)

Downloads file bytes onto the session path (streams past the proxy buffer)
and returns `{ path, url, bytes }` where `url` is a Houston signed GET URL.
Optional `opts.mimeType` uses Drive `files.export` for Google-native types.
Do not return the file bytes from `run`; give the caller the signed URL.

Write functions are bound only when this instance is read-write.

## createFile(meta?)

Drive `files.create`. `meta` is the File resource metadata (for example
`{ name = "notes.md", mimeType = "text/markdown" }`).

## deleteFile(id)

Drive `files.delete`. `id` may be a string or a table with `id`.

## uploadFile(path, meta?)

Uploads a session file (PUT bytes there first with `fs.signedPutUrl` when
the caller is sending a file). `meta` may include `name`, `mimeType`, and
`parents`. Streams the file through Houston; does not inline bytes in MCP.

## Example

	return {
		run = function()
			return c.listFiles({ folder = "root", name = "notes", pageSize = 10 })
		end,
	}
]],
	functions = functions,
	writes = writes,
}
