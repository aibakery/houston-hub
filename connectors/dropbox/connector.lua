-- Dropbox connector: read a connected account through Houston's HTTP proxy.
-- Public functions are the storage/drive contract; vendor RPC paths stay here.
-- Host primitives used: private http.request and json.

local BASE = "https://api.dropboxapi.com/2"
local CONTENT = "https://content.dropboxapi.com/2"

local function request(path: any,payload: any,operation: any)
	local body = "null"
	if payload ~= nil then
		body = json.encode(payload)
	end
	local response = http.request({
		method = "POST",
		url = BASE .. path,
		headers = { ["Content-Type"] = "application/json" },
		body = body,
	})
	if response.status < 200 or response.status >= 300 then
		houston.fail({operation = operation, layer = "upstream", upstream_status = response.status,
			retryable = response.status == 429 or response.status == 502 or response.status == 503 or response.status == 504,
			message = "upstream HTTP request failed"})
	end
	local decoded = nil
	if response.body ~= nil and response.body ~= "" then
		local ok, body = pcall(json.decode, response.body)
		assert(ok, "upstream returned invalid JSON")
		decoded = body
	end
	return decoded
end

local function request_file(arg_path: any,dest: any,operation: any)
	local response = http.request({
		method = "POST",
		url = CONTENT .. "/files/download",
		headers = {
			["Content-Type"] = "application/octet-stream",
			["Dropbox-API-Arg"] = json.encode({ path = arg_path }),
		},
		dest = dest,
	})
	if response.status < 200 or response.status >= 300 then
		houston.fail({operation = operation, layer = "upstream", upstream_status = response.status,
			retryable = response.status == 429 or response.status == 502 or response.status == 503 or response.status == 504,
			message = "upstream HTTP request failed"})
	end
	return response
end

local function as_path(value: any)
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

local function stamp(value: any)
	local s = tostring(value)
	local y, m, d = string.match(s, "^(%d%d%d%d)%D(%d%d)%D(%d%d)")
	if not y or not m or not d then
		return s
	end
	local h, min, sec = string.match(s, "T(%d%d):(%d%d):(%d%d)")
	if not h or not min or not sec then
		h, min, sec = "00", "00", "00"
	end
	return y .. "-" .. m .. "-" .. d .. "T" .. (h or "00") .. ":" .. (min or "00") .. ":" .. (sec or "00")
end

local function unwrap_meta(item: any)
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
local EXT_MIME: {[string]: string} = {
	txt = "text/plain",
	md = "text/markdown",
	pdf = "application/pdf",
	png = "image/png",
	jpg = "image/jpeg",
	jpeg = "image/jpeg",
}

local function file_ext(name: any)
	local ext = string.lower(string.match(tostring(name or ""), "%.([^%.]+)$") or "")
	if ext == "jpeg" then
		return "jpg"
	end
	return ext
end

local function mime_from_name(name: any)
	local ext = file_ext(name)
	if ext == "" then
		return "application/octet-stream"
	end
	return EXT_MIME[ext] or "application/octet-stream"
end

local function mime_ext(want: any): string?
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

local function decorate_file(entry: any)
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

local function mime_ok(entry: any,mime: any)
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

local function in_window(entry: any,after: any,before: any)
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

local function filter_rows(rows: any,opts: any)
	opts = opts or {}
	local out = {}
	for _, row in rows do
		if mime_ok(row, opts.mime) and in_window(row, opts.after, opts.before) then
			out[#out + 1] = row
		end
	end
	return out
end

local function collect_rows(raw: any)
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

local function decorate_list(raw: any,opts: any)
	if type(raw) ~= "table" then
		return raw
	end
	raw.files = filter_rows(collect_rows(raw), opts)
	if raw.nextPageToken == nil and raw.has_more and type(raw.cursor) == "string" and raw.cursor ~= "" then
		raw.nextPageToken = raw.cursor
	end
	return raw
end

local function search_query(opts: any): (string?, boolean)
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

local function page_limit(opts: any)
	return opts.pageSize or opts.maxResults
end

local functions = {}

function functions.getCurrentAccount()
	return request("/users/get_current_account", nil, "getCurrentAccount")
end

function functions.listFiles(opts: any)
	opts = opts or {}
	local token = opts.pageToken or opts.cursor
	local query, filename_only = search_query(opts)
	local raw
	if type(token) == "string" and token ~= "" then
		if query then
			raw = request("/files/search/continue_v2", { cursor = token }, "listFiles")
		else
			raw = request("/files/list_folder/continue", { cursor = token }, "listFiles")
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
		raw = request("/files/search_v2", { query = query, options = options }, "listFiles")
	else
		local payload = { path = as_path(opts.folder) }
		local limit = page_limit(opts)
		if limit ~= nil then
			payload.limit = limit
		end
		if opts.recursive ~= nil then
			payload.recursive = opts.recursive
		end
		raw = request("/files/list_folder", payload, "listFiles")
	end
	return decorate_list(raw, opts)
end

function functions.getFile(id: any,opts: any)
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
	return decorate_file(request("/files/get_metadata", payload, "getFile"))
end

function functions.downloadFile(id: any,path: any,opts: any)
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
	local saved = request_file(as_path(id), path, "downloadFile")
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

function functions.statFile(id: string): {id: string, name: string, isFolder: boolean, size: number?}
    if type(id) ~= "string" or id == "" then error("statFile requires a nonempty file ID") end
    local file = functions.getFile(id)
    if type(file) ~= "table" or type(file.id) ~= "string" or file.id == "" or type(file.name) ~= "string" then
        error("storage provider returned invalid file metadata")
    end
    local folder = file.folder == true or file.mimeType == "application/vnd.google-apps.folder"
    local result: {id: string, name: string, isFolder: boolean, size: number?} = {id = file.id, name = file.name, isFolder = folder}
    if not folder and file.size ~= nil then
        local size = tonumber(file.size)
        if not size or size < 0 or size % 1 ~= 0 then error("storage provider returned invalid size") end
        result.size = size
    end
    return result
end

return functions
