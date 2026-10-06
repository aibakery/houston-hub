local connector_http = require("lib/http.lua")
-- Google Drive connector: metadata, vendor links, and session-file transfer.
-- Host primitives used: private http.request (via lib/http.lua) and fs.signedGetUrl.
-- Public functions are the storage/drive contract later providers reuse;
-- only the HTTP paths and filter compilation below are Drive-specific.
-- File bytes do not travel in the MCP RPC envelope.

local BASE = "https://www.googleapis.com/drive/v3"
local UPLOAD_BASE = "https://www.googleapis.com/upload/drive/v3"
local FOLDER_MIME = "application/vnd.google-apps.folder"
local FILE_FIELDS =
	"id,name,mimeType,size,md5Checksum,webViewLink,webContentLink,exportLinks,modifiedTime"
local LIST_FIELDS = "nextPageToken,files(" .. FILE_FIELDS .. ")"

local function encode(s: any)
	return connector_http.encode(s)
end

local function query_string(params: any)
	return connector_http.query_string(params)
end

local function request(method: any,path: any,params: any,operation: any,cursor: any,body: any)
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

		affected_cursor = cursor,
	})
end

local function drive_quote(value: any)
	local s = tostring(value)
	s = string.gsub(s, "\\", "\\\\")
	s = string.gsub(s, "'", "\\'")
	return "'" .. s .. "'"
end

local function rfc3339(value: any)
	local s = tostring(value)
	local y, m, d = string.match(s, "^(%d%d%d%d)%D(%d%d)%D(%d%d)")
	if not y or not m or not d then
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

local function each_value(value: any,fn: any)
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

local function compile_query(opts: any): string?
	local terms = {}
	each_value(opts.name, function(s: any)
		terms[#terms + 1] = "name contains " .. drive_quote(s)
	end)
	each_value(opts.mime, function(s: any)
		terms[#terms + 1] = "mimeType = " .. drive_quote(s)
	end)
	each_value(opts.folder, function(s: any)
		terms[#terms + 1] = drive_quote(s) .. " in parents"
	end)
	if opts.after ~= nil and tostring(opts.after) ~= "" then
		terms[#terms + 1] = "modifiedTime > " .. drive_quote(rfc3339(opts.after))
	end
	if opts.before ~= nil and tostring(opts.before) ~= "" then
		terms[#terms + 1] = "modifiedTime < " .. drive_quote(rfc3339(opts.before))
	end
	each_value(opts.text, function(s: any)
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

local function list_params(opts: any)
	opts = opts or {}
	return {
		pageSize = opts.pageSize or opts.maxResults,
		pageToken = opts.pageToken,
		q = compile_query(opts),
		orderBy = opts.orderBy,
		fields = opts.fields or LIST_FIELDS,
	}
end

local function get_params(opts: any)
	opts = opts or {}
	return {
		fields = opts.fields or FILE_FIELDS,
	}
end

local function vendor_links(meta: any)
	if type(meta) ~= "table" then
		return meta
	end
	-- Relayed Google links must never include an access token.
	local function scrub(url: any)
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

local function decorate_file(meta: any)
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

local function decorate_list(raw: any)
	if type(raw) == "table" and type(raw.files) == "table" then
		for _, file in raw.files do
			decorate_file(file)
		end
	end
	return raw
end

local function request_file(method: any,url: any,path: any,operation: any,cursor: any,headers: any)
	return connector_http.send({
		connector = "gdrive",
		operation = operation,
		method = method,
		path = path,
		url = url,
		headers = headers,
		dest = path,

		affected_cursor = cursor,
	})
end

local function upload_file_body(method: any,url: any,path: any,operation: any,headers: any)
	return connector_http.send({
		connector = "gdrive",
		operation = operation,
		method = method,
		path = path,
		url = url,
		headers = headers,
		src = path,

	})
end

local functions = {}

function functions.listFiles(opts: any)
	return decorate_list(request("GET", "/files", list_params(opts), "listFiles"))
end

function functions.getFile(id: any,opts: any)
	if type(id) == "table" then
		opts = id
		id = id.id
	end
	if type(id) ~= "string" or id == "" then
		error("gdrive.getFile requires a file id")
	end
	return decorate_file(request("GET", "/files/" .. encode(id), get_params(opts), "getFile", id))
end

function functions.downloadFile(id: any,path: any,opts: any)
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
	local saved = request_file("GET", url, path, "downloadFile", id)
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

function writes.createFile(meta: any)
	if meta ~= nil and type(meta) ~= "table" then
		error("gdrive.createFile requires a metadata table")
	end
	return request("POST", "/files", nil, "createFile", nil, meta or {})
end

function writes.deleteFile(id: any)
	if type(id) == "table" then
		id = id.id
	end
	if type(id) ~= "string" or id == "" then
		error("gdrive.deleteFile requires a file id")
	end
	return request("DELETE", "/files/" .. encode(id), nil, "deleteFile", id)
end

function writes.uploadFile(path: any,meta: any)
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
	return request("PATCH", "/files/" .. encode(created.id), nil, "uploadFile", created.id, patch)
end

if config.access == "read-write" then
    for name, fn in (writes :: {[string]: any}) do (functions :: {[string]: any})[name] = fn end
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
