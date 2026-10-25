-- Granola public API v1, read-only. Arguments and results keep Granola's native field names.
type Options = {[string]: any}
type Endpoint = {path: string, id: string?, list: string?, maximum: number?, query: {[string]: string}, help: string}

local API = "https://public-api.granola.ai/v1"
local PAGE = {cursor = "text", page_size = "size"}
local endpoints: {[string]: Endpoint} = {
	listNotes = {path = "/notes", list = "notes", maximum = 30,
		query = {created_after = "date", created_before = "date", updated_after = "date", folder_id = "fol", space_id = "spa", cursor = "text", page_size = "size"},
		help = "List note summaries `{id, object, title, owner = {name, email}, created_at, updated_at, deleted_at}` the key can read. Optional created_after, created_before and updated_after take `YYYY-MM-DD` or RFC 3339 date-times. folder_id (`fol_…`, includes child folders) and space_id (`spa_…`) filter by location. Only notes with a generated summary and transcript are listed."},
	getNote = {path = "/notes/{id}", id = "not", query = {include = "transcript"},
		help = "Read one note (`not_…`): title, owner, attendees, calendar_event (event_title, invitees, organiser, scheduled times), folder_membership, space_membership, summary_text, summary_markdown, attachments (photo URLs anyone with the link can open), web_url, and private_notes_* (only for the note owner's key). Pass include = \"transcript\" to inline the transcript; if Granola answers HTTP 413 TRANSCRIPT_TOO_LARGE, page it with getTranscript."},
	getTranscript = {path = "/notes/{id}/transcript", id = "not", list = "transcript", maximum = 100, query = PAGE,
		help = "Page a note's transcript: `{transcript = {{speaker = {source, attribution?, name?, diarization_label?}, text, start_time, end_time}}, hasMore, cursor}`. source is microphone (the note owner) or speaker (other participants)."},
	listFolders = {path = "/folders", list = "folders", maximum = 30, query = PAGE,
		help = "List folders alphabetically: `{id, object, name, parent_folder_id, space_id}`. Pass an id as listNotes folder_id."},
	listSpaces = {path = "/spaces", list = "spaces", maximum = 30, query = PAGE,
		help = "List spaces `{id, object, name}`. Pass an id as listNotes space_id."},
}

local function text(value: any, field: string): string
	assert(type(value) == "string" and value ~= "", field .. " must be a nonempty string")
	return value
end

local function identifier(value: any, field: string, prefix: string): string
	local id = text(value, field)
	assert(#id == 18 and string.lower(string.sub(id, 1, 4)) == prefix .. "_" and string.match(id, "^%a%a%a_%w+$"),
		field .. " must be a Granola " .. prefix .. "_ ID")
	return id
end

local function queryValue(value: any, field: string, kind: string, maximum: number?): string
	if kind == "size" then
		assert(type(value) == "number" and value % 1 == 0 and value >= 1 and value <= (maximum :: number), field .. " must be an integer from 1 to " .. tostring(maximum))
		return tostring(value)
	elseif kind == "date" then
		assert(string.match(text(value, field), "^%d%d%d%d%-%d%d%-%d%d"), field .. " must be YYYY-MM-DD or an RFC 3339 date-time")
	elseif kind == "transcript" then
		assert(value == "transcript", field .. " must be \"transcript\"")
	elseif kind ~= "text" then
		identifier(value, field, kind)
	end
	return url.encode(text(value, field))
end

local function failure(name: string, response: HttpResponse): never
	local status = response.statusCode
	local prefix = await(response.body:readPrefix(4096))
	local ok, body = pcall(json.decode, prefix)
	if not ok or type(body) ~= "table" then
		body = {code = string.match(prefix, '^%s*{%s*"code"%s*:%s*"([%w_]+)"')}
	end
	local message = "Granola HTTP " .. tostring(status)
	local code = body.code or body.error
	if type(code) == "string" then message ..= " " .. string.sub(code, 1, 64) end
	if type(body.message) == "string" then message ..= ": " .. string.sub(body.message, 1, 300) end
	if status == 401 then message ..= " (check the API key; personal keys can expire or be revoked)"
	elseif status == 404 then message ..= " (the note may not exist, lack a summary and transcript, or be outside the key's access scopes)"
	elseif status == 413 then message ..= " (use getTranscript to page the transcript)" end
	local retry = response.headers["retry-after"]
	if status == 429 and retry and retry[1] then message ..= "; retry after " .. string.sub(retry[1], 1, 32) .. "s" end
	return houston.fail({operation = name, layer = "upstream", upstream_status = status,
		retryable = status == 429 or status >= 500, message = message})
end

local function request(name: string, endpoint: Endpoint, id: any, input: any): any
	assert(input == nil or type(input) == "table", name .. " options must be a table")
	local args: Options = if input then table.clone(input) else {}
	local path = endpoint.path
	if endpoint.id then
		path = string.gsub(path, "{id}", identifier(id, "id", endpoint.id :: string))
	end
	local query: {string} = {}
	for field, value in args do
		local kind = endpoint.query[field]
		assert(type(field) == "string" and kind, name .. " received an unknown option " .. tostring(field))
		table.insert(query, field .. "=" .. queryValue(value, field, kind, endpoint.maximum))
	end
	table.sort(query)
	local target = API .. path .. (if #query > 0 then "?" .. table.concat(query, "&") else "")
	local response = await(http.request({method = "GET", url = target, headers = {Accept = {"application/json"}}}))
	if response.statusCode < 200 or response.statusCode >= 300 then failure(name, response) end
	local raw = await(response.body:readAll())
	local ok, value = pcall(json.decode, raw)
	if not ok or type(value) ~= "table" or not string.match(raw, "^%s*{")
		or (endpoint.list and type(value[endpoint.list]) ~= "table") then
		houston.fail({operation = name, layer = "upstream", upstream_status = response.statusCode, retryable = false,
			message = "Granola returned an unexpected response"})
	end
	return value
end

local functions: {[string]: any} = {}
for name, endpoint in endpoints do
	if endpoint.id then
		functions[name] = function(id: any, opts: Options?)
			if type(id) == "table" then
				assert(opts == nil, name .. " takes (id, opts?) or one table with id")
				local args = table.clone(id)
				args.id = nil
				return request(name, endpoint, id.id, args)
			end
			return request(name, endpoint, id, opts)
		end
	else
		functions[name] = function(opts: Options?) return request(name, endpoint, nil, opts) end
	end
end

function functions.help(): string
	local sections = {"Granola: read-only access to the meeting notes, transcripts, folders and spaces this API key can read. Credentials stay on Houston. Each call makes one request and returns Granola's JSON unchanged. Calls return completed values; do not wrap them in await(). IDs are a prefix plus 14 letters or digits (not_, fol_, spa_). Unknown options are rejected.",
		"Paged calls take cursor and page_size (Granola defaults to 10, or 50 for getTranscript) and return hasMore and cursor: while hasMore is true, pass the returned cursor to fetch the next page, and stop as soon as you have enough. Granola allows bursts of 25 requests and 5 per second; HTTP 429 errors are retryable. Notes cannot be created or edited through this API."}
	local names: {string} = {}
	for name in endpoints do table.insert(names, name) end
	table.sort(names)
	for _, name in names do
		local endpoint = endpoints[name]
		local signature = if endpoint.id then "(id, opts?)" else "(opts?)"
		local section = "## " .. name .. signature .. "\n\nGET /v1" .. endpoint.path .. ". " .. endpoint.help
		if endpoint.maximum then section ..= " page_size: 1–" .. tostring(endpoint.maximum) .. "." end
		table.insert(sections, section)
	end
	table.insert(sections, [[## Example

Here granola is the configured Granola connection.

```lua
local page = granola.listNotes({created_after = "2026-10-01T00:00:00Z", page_size = 30})
local summaries = {}
for _, row in page.notes do
	local note = granola.getNote(row.id)
	table.insert(summaries, {title = note.title, summary = note.summary_markdown})
end
-- While page.hasMore, repeat listNotes with the same filters and cursor = page.cursor.
local first = granola.getTranscript(page.notes[1].id, {page_size = 100})
-- first.transcript[i].speaker.source, .text; continue with cursor = first.cursor while first.hasMore.
```

Reference: https://docs.granola.ai/introduction]])
	return table.concat(sections, "\n\n")
end

return functions
