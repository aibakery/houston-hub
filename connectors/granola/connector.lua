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

local operationHelp: {[string]: string} = {
	getNote = [==[## getNote(id, opts?)

Granola `GET /v1/notes/{note_id}`. `id` may be a string or a table with
`id`. Optional fields on `opts` (or on the table):

- `include`: `"transcript"` to inline the transcript when it fits
- `includeTranscript` (boolean) — same as `include = "transcript"`

If the transcript is too large, Granola returns `TRANSCRIPT_TOO_LARGE`;
use `getTranscript` and loop pages in one `run`.]==],
	getTranscript = [==[## getTranscript(id, opts?)

Granola `GET /v1/notes/{note_id}/transcript`. `id` may be a string or a
table with `id`. Optional fields on `opts`:

- `cursor` (string)
- `page_size` (number, max 100)

Returns `transcript` (items with `speaker` and `text`), `hasMore`, and
`cursor`. Loop while `hasMore` in the same `run`.]==],
	listFolders = [==[## listFolders(opts?)

Granola `GET /v1/folders`. Optional fields on `opts`:

- `cursor` (string)
- `page_size` (number, max 30)

Returns `folders` (`{ id, name, parent_folder_id, … }[]`), `hasMore`,
and `cursor`.]==],
	listNotes = [==[## listNotes(opts?)

Granola `GET /v1/notes`. Date filters are **calendar dates**
(`YYYY-MM-DD`). RFC3339 datetimes (e.g. `2026-08-22T00:00:00-07:00`)
are coerced to `YYYY-MM-DD` before the request; a plain `YYYY-MM-DD`
is forwarded unchanged. Optional fields on `opts`:

- `created_after` (string, ISO 8601 date `YYYY-MM-DD`)
- `created_before` (string, ISO 8601 date `YYYY-MM-DD`)
- `updated_after` (string, ISO 8601 date `YYYY-MM-DD`)
- `folder_id` (string, `fol_…`)
- `cursor` (string)
- `page_size` (number, max 30)

Returns `notes` (`{ id, title, … }[]`), `hasMore`, and `cursor`.]==],
}

function functions.help(): string
	local names: {string} = {}
	for name in (functions :: {[string]: any}) do
		if name ~= "help" then names[#names + 1] = name end
	end
	table.sort(names)
	local sections = {"granola: configured connection help. Credentials stay on Houston. Use only the functions listed below. Provider scopes are enforced by real calls; help makes no network requests."}
	for _, name in names do
		local text = operationHelp[name]
		assert(text, "missing help for configured function " .. name)
		sections[#sections + 1] = text
	end
	return table.concat(sections, "\n\n")
end

return functions
