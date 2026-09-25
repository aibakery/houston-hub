-- Dropbox connector: read a connected account through Houston's HTTP proxy.
-- Public functions are the storage/drive contract; vendor RPC paths stay here.
-- Host primitives used: http.send (with this instance's connector id) and json.

local BASE = "https://api.dropboxapi.com/2"
local CONTENT = "https://content.dropboxapi.com/2"

local function request(ctx, path, payload, operation)
	if type(ctx) ~= "table" or type(ctx.id) ~= "string" or ctx.id == "" then
		error("dropbox connector id is required")
	end
	local body = "null"
	if payload ~= nil then
		body = json.encode(payload)
	end
	local cursor
	if type(payload) == "table" then
		cursor = payload.cursor
	end
	return connector_http.send({
		connector = "dropbox",
		operation = operation,
		method = "POST",
		path = path,
		url = BASE .. path,
		headers = { ["Content-Type"] = "application/json" },
		body = body,
		connector_id = ctx.id,
		affected_cursor = cursor,
	})
end

local function request_file(ctx, arg_path, dest, operation)
	if type(ctx) ~= "table" or type(ctx.id) ~= "string" or ctx.id == "" then
		error("dropbox connector id is required")
	end
	return connector_http.send({
		connector = "dropbox",
		operation = operation,
		method = "POST",
		path = dest,
		url = CONTENT .. "/files/download",
		headers = {
			["Content-Type"] = "application/octet-stream",
			["Dropbox-API-Arg"] = json.encode({ path = arg_path }),
		},
		dest = dest,
		connector_id = ctx.id,
		affected_cursor = arg_path,
	})
end

local function as_path(value)
	if value == nil then
		return ""
	end
	local s = tostring(value)
	if s == "" or s == "/" then
		return ""
	end
	if string.sub(s, 1, 1) == "/" then
		return s
	end
	if string.find(s, ":", 1, true) then
		return s
	end
	return "/" .. s
end

local function stamp(value)
	local s = tostring(value)
	local y, m, d = string.match(s, "^(%d%d%d%d)%D(%d%d)%D(%d%d)")
	if not y then
		return s
	end
	local h, min, sec = string.match(s, "T(%d%d):(%d%d):(%d%d)")
	if not h then
		h, min, sec = "00", "00", "00"
	end
	return y .. "-" .. m .. "-" .. d .. "T" .. h .. ":" .. min .. ":" .. sec
end

local function unwrap_meta(item)
	local cur = item
	for _ = 1, 4 do
		if type(cur) ~= "table" or type(cur.metadata) ~= "table" then
			return cur
		end
		local tag = cur[".tag"]
		if tag == "metadata" or cur.name == nil then
			cur = cur.metadata
		else
			return cur
		end
	end
	return cur
end

local FOLDER_MIME = "application/vnd.google-apps.folder"
local EXT_MIME = {
	txt = "text/plain",
	md = "text/markdown",
	pdf = "application/pdf",
	png = "image/png",
	jpg = "image/jpeg",
	jpeg = "image/jpeg",
}

local function file_ext(name)
	local ext = string.lower(string.match(tostring(name or ""), "%.([^%.]+)$") or "")
	if ext == "jpeg" then
		return "jpg"
	end
	return ext
end

local function mime_from_name(name)
	local ext = file_ext(name)
	if ext == "" then
		return "application/octet-stream"
	end
	return EXT_MIME[ext] or "application/octet-stream"
end

local function mime_ext(want)
	want = string.lower(tostring(want))
	if want == "folder" or want == FOLDER_MIME then
		return "folder"
	end
	for ext, mime in EXT_MIME do
		if ext ~= "jpeg" and (want == mime or want == ext) then
			return ext
		end
	end
	local sub = string.match(want, "/([^/]+)$") or want
	if sub == "jpeg" then
		return "jpg"
	end
	return sub
end

local function decorate_file(entry)
	entry = unwrap_meta(entry)
	if type(entry) ~= "table" then
		return entry
	end
	local tag = entry[".tag"]
	if entry.modified == nil then
		entry.modified = entry.server_modified or entry.client_modified
	end
	if entry.folder == nil then
		entry.folder = tag == "folder"
	end
	if entry.mime == nil then
		if entry.folder then
			entry.mime = FOLDER_MIME
		else
			entry.mime = mime_from_name(entry.name)
		end
	end
	return entry
end

local function mime_ok(entry, mime)
	if mime == nil or tostring(mime) == "" then
		return true
	end
	local want = string.lower(tostring(mime))
	if entry.folder then
		return want == "folder" or want == FOLDER_MIME
	end
	local got = string.lower(tostring(entry.mime or ""))
	if got ~= "" and (got == want or mime_ext(got) == mime_ext(want)) then
		return true
	end
	return mime_ext(want) == file_ext(entry.name)
end

local function in_window(entry, after, before)
	local t = entry.modified or entry.server_modified or entry.client_modified
	if t == nil then
		return true
	end
	t = stamp(t)
	if after ~= nil and tostring(after) ~= "" and t < stamp(after) then
		return false
	end
	if before ~= nil and tostring(before) ~= "" and t >= stamp(before) then
		return false
	end
	return true
end

local function filter_rows(rows, opts)
	opts = opts or {}
	local out = {}
	for _, row in rows do
		if mime_ok(row, opts.mime) and in_window(row, opts.after, opts.before) then
			out[#out + 1] = row
		end
	end
	return out
end

local function collect_rows(raw)
	local rows = {}
	if type(raw) ~= "table" then
		return rows
	end
	local src = raw.matches or raw.entries or raw.files
	if type(src) ~= "table" then
		return rows
	end
	for _, item in src do
		rows[#rows + 1] = decorate_file(item)
	end
	return rows
end

local function decorate_list(raw, opts)
	if type(raw) ~= "table" then
		return raw
	end
	raw.files = filter_rows(collect_rows(raw), opts)
	if raw.nextPageToken == nil and raw.has_more and type(raw.cursor) == "string" and raw.cursor ~= "" then
		raw.nextPageToken = raw.cursor
	end
	return raw
end

local function search_query(opts)
	local text, name = nil, nil
	if opts.text ~= nil and tostring(opts.text) ~= "" then
		text = tostring(opts.text)
	end
	if opts.name ~= nil and tostring(opts.name) ~= "" then
		name = tostring(opts.name)
	end
	if text then
		if name then
			return text .. " " .. name, false
		end
		return text, false
	end
	if name then
		return name, true
	end
	return nil, false
end

local function page_limit(opts)
	return opts.pageSize or opts.maxResults
end

local functions = {}

function functions.getCurrentAccount(ctx)
	return request(ctx, "/users/get_current_account", nil, "getCurrentAccount")
end

function functions.listFiles(ctx, opts)
	opts = opts or {}
	local token = opts.pageToken or opts.cursor
	local query, filename_only = search_query(opts)
	local raw
	if type(token) == "string" and token ~= "" then
		if query then
			raw = request(ctx, "/files/search/continue_v2", { cursor = token }, "listFiles")
		else
			raw = request(ctx, "/files/list_folder/continue", { cursor = token }, "listFiles")
		end
	elseif query then
		local options = {
			path = as_path(opts.folder),
			filename_only = filename_only,
		}
		local limit = page_limit(opts)
		if limit ~= nil then
			options.max_results = limit
		end
		raw = request(ctx, "/files/search_v2", { query = query, options = options }, "listFiles")
	else
		local payload = { path = as_path(opts.folder) }
		local limit = page_limit(opts)
		if limit ~= nil then
			payload.limit = limit
		end
		if opts.recursive ~= nil then
			payload.recursive = opts.recursive
		end
		raw = request(ctx, "/files/list_folder", payload, "listFiles")
	end
	return decorate_list(raw, opts)
end

function functions.getFile(ctx, id, opts)
	if type(id) == "table" then
		opts = id
		id = id.id or id.path
	end
	if type(id) ~= "string" or id == "" then
		error("dropbox.getFile requires a file id")
	end
	opts = opts or {}
	local payload = { path = as_path(id) }
	if opts.includeDeleted ~= nil then
		payload.include_deleted = opts.includeDeleted
	end
	if opts.includeMediaInfo ~= nil then
		payload.include_media_info = opts.includeMediaInfo
	end
	return decorate_file(request(ctx, "/files/get_metadata", payload, "getFile"))
end

function functions.downloadFile(ctx, id, path, opts)
	if type(id) == "table" then
		opts = id
		path = id.path
		id = id.id or id.path
	end
	opts = opts or {}
	if type(id) ~= "string" or id == "" then
		error("dropbox.downloadFile requires a file id")
	end
	if type(path) ~= "string" or path == "" then
		error("dropbox.downloadFile requires a session path")
	end
	local saved = request_file(ctx, as_path(id), path, "downloadFile")
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

return {
	name = "dropbox",
	description = "Read a connected Dropbox account.",
	signatures = {
		getCurrentAccount = "getCurrentAccount()",
		listFiles = "listFiles(opts?)",
		getFile = "getFile(id, opts?)",
		downloadFile = "downloadFile(id, path, opts?)",
	},
	help = [[
# Dropbox

Read files for one connected Dropbox account. Credentials stay on the
Houston server. This is the storage/drive contract: later file-drive
providers implement the same functions. Use the instance from
`houston.connectors()` — do not call provider URLs yourself.

List-connector signatures are enough to call. Return compact rows;
`truncate` defaults true. Loop pagination in one `run`.

## listFiles(opts?)

Search and list files. Rows already have `id`, `name`, `mime`, `size`,
`modified`, and `folder` (boolean) — do not `getFile` every row. `mime` is
best-effort from the name (folders match Drive's folder mime). Optional
filters on `opts`:

- `folder` (Dropbox path or `id:...`; default the connected root)
- `name`, `text` (search; `name` is filename-only)
- `mime`, `after`, `before` (best-effort local filter; YYYY-MM-DD)
- `pageSize` or `maxResults` (number)
- `pageToken` (string)

`folder` maps to a list-folder path. `name` / `text` use Dropbox search.
Do not call `/files/list_folder` yourself.

Returns `files` and `nextPageToken`. Loop pages in the same `run`.

## getFile(id, opts?)

One file. `id` may be a string or a table with `id` (Dropbox path or
`id:...`). Same shared fields as `listFiles`.

`getFile("id:abc")` and `getFile({ id = "id:abc" })` are the same call.
This does not download file bytes into Houston.

## downloadFile(id, path, opts?)

Downloads file bytes onto the session path (streams past the proxy buffer)
and returns `{ path, url, bytes }` where `url` is a Houston signed GET URL.
Do not return the file bytes from `run`; give the caller the signed URL.

## getCurrentAccount()

Dropbox account profile (`account_id`, `email`, `name`). Extra to this
provider; not part of the storage/drive contract.

## Example

	return {
		run = function()
			return c.listFiles({ folder = "/Reports", pageSize = 10 })
		end,
	}
]],
	functions = functions,
}
