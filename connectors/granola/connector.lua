-- Granola connector: read notes through Houston's HTTP proxy.
-- Host primitives used: http.send (with this instance's connector id) and json.
-- Those primitives are sufficient; the API key never appears in this module.

local BASE = "https://public-api.granola.ai/v1"

local function encode(s)
	s = tostring(s)
	return (string.gsub(s, "[^A-Za-z0-9%-_%.~]", function(c)
		return string.format("%%%02X", string.byte(c))
	end))
end

local function scalar(value)
	if type(value) == "boolean" then
		if value then
			return "true"
		end
		return "false"
	end
	return tostring(value)
end

local function add_query(parts, key, value)
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

local function query_string(params)
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

local function request(ctx, method, path, params, operation, cursor)
	if type(ctx) ~= "table" or type(ctx.id) ~= "string" or ctx.id == "" then
		error("granola connector id is required")
	end
	local url = BASE .. path
	local qs = query_string(params)
	if qs ~= "" then
		url = url .. "?" .. qs
	end
	if cursor == nil and type(params) == "table" then
		cursor = params.cursor
	end
	return connector_http.send({
		connector = "granola",
		operation = operation,
		method = method,
		path = path,
		url = url,
		connector_id = ctx.id,
		affected_cursor = cursor,
	})
end

local function date_only(value)
	if value == nil then
		return nil
	end
	local s = tostring(value)
	local y, m, d = string.match(s, "^(%d%d%d%d)%-(%d%d)%-(%d%d)")
	if y then
		return y .. "-" .. m .. "-" .. d
	end
	return s
end

local function list_notes_params(opts)
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

local function get_note_params(opts)
	opts = opts or {}
	local include = opts.include
	if include == nil and opts.includeTranscript then
		include = "transcript"
	end
	return { include = include }
end

local function page_params(opts)
	opts = opts or {}
	return {
		cursor = opts.cursor,
		page_size = opts.page_size,
	}
end

local functions = {}

function functions.listNotes(ctx, opts)
	return request(ctx, "GET", "/notes", list_notes_params(opts), "listNotes")
end

function functions.getNote(ctx, id, opts)
	if type(id) == "table" then
		opts = id
		id = id.id
	end
	if type(id) ~= "string" or id == "" then
		error("granola.getNote requires a note id")
	end
	return request(ctx, "GET", "/notes/" .. encode(id), get_note_params(opts), "getNote", id)
end

function functions.listFolders(ctx, opts)
	return request(ctx, "GET", "/folders", page_params(opts), "listFolders")
end

function functions.getTranscript(ctx, id, opts)
	if type(id) == "table" then
		opts = id
		id = id.id
	end
	if type(id) ~= "string" or id == "" then
		error("granola.getTranscript requires a note id")
	end
	return request(ctx, "GET", "/notes/" .. encode(id) .. "/transcript", page_params(opts), "getTranscript", id)
end

return {
	name = "granola",
	description = "Read a connected Granola workspace.",
	signatures = {
		listNotes = "listNotes(opts?)",
		getNote = "getNote(id, opts?)",
		listFolders = "listFolders(opts?)",
		getTranscript = "getTranscript(id, opts?)",
	},
	help = [[
# Granola

Read notes, folders, and transcripts for one connected Granola account.
Credentials stay on the Houston server; these functions only see JSON from
Granola.

Several Granola keys are several instances of this connector, each with
its own `id`. Use the instance returned by `houston.connectors()` — do not
call Granola URLs yourself.

List endpoints are paginated. When `hasMore` is true, pass the returned
`cursor` on the next call and loop in the same `run`.

## listNotes(opts?)

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

Returns `notes` (`{ id, title, … }[]`), `hasMore`, and `cursor`.

## getNote(id, opts?)

Granola `GET /v1/notes/{note_id}`. `id` may be a string or a table with
`id`. Optional fields on `opts` (or on the table):

- `include`: `"transcript"` to inline the transcript when it fits
- `includeTranscript` (boolean) — same as `include = "transcript"`

If the transcript is too large, Granola returns `TRANSCRIPT_TOO_LARGE`;
use `getTranscript` and loop pages in one `run`.

## listFolders(opts?)

Granola `GET /v1/folders`. Optional fields on `opts`:

- `cursor` (string)
- `page_size` (number, max 30)

Returns `folders` (`{ id, name, parent_folder_id, … }[]`), `hasMore`,
and `cursor`.

## getTranscript(id, opts?)

Granola `GET /v1/notes/{note_id}/transcript`. `id` may be a string or a
table with `id`. Optional fields on `opts`:

- `cursor` (string)
- `page_size` (number, max 100)

Returns `transcript` (items with `speaker` and `text`), `hasMore`, and
`cursor`. Loop while `hasMore` in the same `run`.

## Example

	return {
		run = function()
			return c.listNotes({ page_size = 10 })
		end,
	}
]],
	functions = functions,
}
