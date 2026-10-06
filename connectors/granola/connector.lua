-- Granola connector: read notes through Houston's HTTP proxy.
-- Host primitives used: private http.request and json.
-- Those primitives are sufficient; the API key never appears in this module.

local BASE = "https://public-api.granola.ai/v1"

local function encode(s: any)
	s = tostring(s)
	return (string.gsub(s, "[^A-Za-z0-9%-_%.~]", function(c: any)
		return string.format("%%%02X", string.byte(c))
	end))
end

local function scalar(value: any)
	if type(value) == "boolean" then
		if value then
			return "true"
		end
		return "false"
	end
	return tostring(value)
end

local function add_query(parts: any,key: any,value: any)
	if value == nil then
		return
	end
	if type(value) == "table" then
		for _, item in value do
			add_query(parts, key, item)
		end
		return
	end
	parts[#parts + 1] = encode(key) .. "=" .. encode(scalar(value))
end

local function query_string(params: any)
	if type(params) ~= "table" then
		return ""
	end
	local parts = {}
	for key, value in params do
		add_query(parts, key, value)
	end
	if #parts == 0 then
		return ""
	end
	local s = parts[1]
	for i = 2, #parts do
		s = s .. "&" .. parts[i]
	end
	return s
end

local function request(method: any,path: any,params: any,operation: any)
	local url = BASE .. path
	local qs = query_string(params)
	if qs ~= "" then
		url = url .. "?" .. qs
	end
	local response = http.request({
		method = method,
		url = url,
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

local function date_only(value: any): string?
	if value == nil then
		return nil
	end
	local s = tostring(value)
	local y, m, d = string.match(s, "^(%d%d%d%d)%-(%d%d)%-(%d%d)")
	if y and m and d then
		return y .. "-" .. m .. "-" .. d
	end
	return s
end

local function list_notes_params(opts: any)
	opts = opts or {}
	return {
		created_after = date_only(opts.created_after),
		created_before = date_only(opts.created_before),
		updated_after = date_only(opts.updated_after),
		folder_id = opts.folder_id,
		cursor = opts.cursor,
		page_size = opts.page_size,
	}
end

local function get_note_params(opts: any)
	opts = opts or {}
	local include = opts.include
	if include == nil and opts.includeTranscript then
		include = "transcript"
	end
	return { include = include }
end

local function page_params(opts: any)
	opts = opts or {}
	return {
		cursor = opts.cursor,
		page_size = opts.page_size,
	}
end

local functions = {}

function functions.listNotes(opts: any)
	return request("GET", "/notes", list_notes_params(opts), "listNotes")
end

function functions.getNote(id: any,opts: any)
	if type(id) == "table" then
		opts = id
		id = id.id
	end
	if type(id) ~= "string" or id == "" then
		error("granola.getNote requires a note id")
	end
	return request("GET", "/notes/" .. encode(id), get_note_params(opts), "getNote")
end

function functions.listFolders(opts: any)
	return request("GET", "/folders", page_params(opts), "listFolders")
end

function functions.getTranscript(id: any,opts: any)
	if type(id) == "table" then
		opts = id
		id = id.id
	end
	if type(id) ~= "string" or id == "" then
		error("granola.getTranscript requires a note id")
	end
	return request("GET", "/notes/" .. encode(id) .. "/transcript", page_params(opts), "getTranscript")
end

return functions
