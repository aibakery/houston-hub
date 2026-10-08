-- Attio connector: read CRM data through Houston's HTTP proxy.
-- Host primitives used: private http.request and json.
-- Those primitives are sufficient; the API key never appears in this module.

local BASE = "https://api.attio.com/v2"

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

local function get(path: any,params: any,operation: any)
	local url = BASE .. path
	local qs = query_string(params)
	if qs ~= "" then
		url = url .. "?" .. qs
	end
	local response = http.request({
		method = "GET",
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

local function post(path: any,payload: any,operation: any)
	local body = "{}"
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

local function object_slug(object: any)
	if type(object) == "table" then
		return object.object or object.api_slug or object.id
	end
	return object
end

local function record_id_of(value: any)
	if type(value) == "table" then
		if type(value.id) == "table" then
			return (value.id :: {[string]: any}).record_id or (value.id :: {[string]: any}).id
		end
		return value.record_id or value.id
	end
	return value
end

local function entity_id(value: any,field: any)
	if type(value) == "table" then
		if type(value.id) == "table" then
			return (value.id :: {[string]: any})[field] or (value.id :: {[string]: any}).id
		end
		return value[field] or value.id
	end
	return value
end

local function require_id(value: any,field: any,err: any)
	local id = entity_id(value, field)
	if type(id) ~= "string" or id == "" then
		error(err)
	end
	return id
end

local function pick(opts: any,keys: any)
	opts = opts or {}
	local out = {}
	for _, key in keys do
		if opts[key] ~= nil then
			out[key] = opts[key]
		end
	end
	return out
end

local function query_payload(opts: any): {[string]: any}?
	local payload = pick(opts, { "filter", "filter_view_id", "sorts", "limit", "offset" })
	local n = 0
	for _k, _v in payload do
		n = n + 1
	end
	if n == 0 then
		return nil
	end
	return payload
end

local functions = {}

function functions.identify()
	return get("/self", nil, "identify")
end

function functions.listObjects()
	return get("/objects", nil, "listObjects")
end

function functions.queryRecords(object: any,opts: any)
	if type(object) == "table" then
		opts = opts or object
		object = object_slug(object)
	end
	if type(object) ~= "string" or object == "" then
		error("attio.queryRecords requires an object slug or id")
	end
	return post("/objects/" .. encode(object) .. "/records/query", query_payload(opts), "queryRecords")
end

function functions.getRecord(object: any,recordId: any)
	if type(object) == "table" then
		recordId = record_id_of(object)
		object = object_slug(object)
	end
	if type(object) ~= "string" or object == "" then
		error("attio.getRecord requires an object slug or id")
	end
	if type(recordId) ~= "string" or recordId == "" then
		error("attio.getRecord requires a record id")
	end
	return get("/objects/" .. encode(object) .. "/records/" .. encode(recordId), nil, "getRecord")
end

function functions.searchRecords(query: any,opts: any)
	if type(query) == "table" then
		opts = query
		query = query.query
	end
	opts = opts or {}
	if type(query) ~= "string" then
		error("attio.searchRecords requires a query string")
	end
	local payload = {
		query = query,
		objects = opts.objects,
		limit = opts.limit,
		request_as = opts.request_as,
	}
	if payload.request_as == nil then
		payload.request_as = { type = "workspace" }
	end
	return post("/objects/records/search", payload, "searchRecords")
end

function functions.listNotes(opts: any)
	return get("/notes", pick(opts, { "limit", "offset", "parent_object", "parent_record_id" }), "listNotes")
end

function functions.getNote(noteId: any)
	noteId = require_id(noteId, "note_id", "attio.getNote requires a note id")
	return get("/notes/" .. encode(noteId), nil, "getNote")
end

function functions.listEmails(opts: any)
	return get(
		"/emails",
		pick(opts, {
			"limit",
			"cursor",
			"linked_object",
			"linked_record_ids",
			"participants",
			"domain",
			"sent_after",
			"sent_before",
		}),
		"listEmails"
	)
end

function functions.listTasks(opts: any)
	return get(
		"/tasks",
		pick(opts, {
			"limit",
			"offset",
			"sort",
			"linked_object",
			"linked_record_id",
			"assignee",
			"is_completed",
		}),
		"listTasks"
	)
end

function functions.getTask(taskId: any)
	taskId = require_id(taskId, "task_id", "attio.getTask requires a task id")
	return get("/tasks/" .. encode(taskId), nil, "getTask")
end

function functions.listThreads(opts: any)
	return get(
		"/threads",
		pick(opts, { "record_id", "object", "entry_id", "list", "limit", "offset" }),
		"listThreads"
	)
end

function functions.getThread(threadId: any)
	threadId = require_id(threadId, "thread_id", "attio.getThread requires a thread id")
	return get("/threads/" .. encode(threadId), nil, "getThread")
end

function functions.getComment(commentId: any)
	commentId = require_id(commentId, "comment_id", "attio.getComment requires a comment id")
	return get("/comments/" .. encode(commentId), nil, "getComment")
end

function functions.listMeetings(opts: any)
	return get(
		"/meetings",
		pick(opts, {
			"limit",
			"cursor",
			"linked_object",
			"linked_record_id",
			"participants",
			"sort",
			"ends_from",
			"starts_before",
			"timezone",
		}),
		"listMeetings"
	)
end

function functions.getMeeting(meetingId: any)
	meetingId = require_id(meetingId, "meeting_id", "attio.getMeeting requires a meeting id")
	return get("/meetings/" .. encode(meetingId), nil, "getMeeting")
end

function functions.listCallRecordings(meetingId: any,opts: any)
	if type(meetingId) == "table" then
		opts = opts or meetingId
		meetingId = entity_id(meetingId, "meeting_id")
	end
	if type(meetingId) ~= "string" or meetingId == "" then
		error("attio.listCallRecordings requires a meeting id")
	end
	return get(
		"/meetings/" .. encode(meetingId) .. "/call_recordings",
		pick(opts, { "limit", "offset", "cursor" }),
		"listCallRecordings"
	)
end

function functions.getCallRecording(meetingId: any,recordingId: any)
	if type(meetingId) == "table" then
		recordingId = recordingId or entity_id(meetingId, "call_recording_id")
		meetingId = entity_id(meetingId, "meeting_id")
	end
	if type(meetingId) ~= "string" or meetingId == "" then
		error("attio.getCallRecording requires a meeting id")
	end
	recordingId = require_id(recordingId, "call_recording_id", "attio.getCallRecording requires a call recording id")
	return get(
		"/meetings/" .. encode(meetingId) .. "/call_recordings/" .. encode(recordingId),
		nil,
		"getCallRecording"
	)
end

function functions.listLists()
	return get("/lists", nil, "listLists")
end

function functions.getList(list: any)
	if type(list) == "table" then
		list = entity_id(list, "list_id") or object_slug(list)
	end
	if type(list) ~= "string" or list == "" then
		error("attio.getList requires a list slug or id")
	end
	return get("/lists/" .. encode(list), nil, "getList")
end

function functions.queryListEntries(list: any,opts: any)
	if type(list) == "table" then
		opts = opts or list
		list = entity_id(list, "list_id") or object_slug(list)
	end
	if type(list) ~= "string" or list == "" then
		error("attio.queryListEntries requires a list slug or id")
	end
	return post("/lists/" .. encode(list) .. "/entries/query", query_payload(opts), "queryListEntries")
end

function functions.listWorkspaceMembers()
	return get("/workspace_members", nil, "listWorkspaceMembers")
end

function functions.getWorkspaceMember(memberId: any)
	memberId = require_id(
		memberId,
		"workspace_member_id",
		"attio.getWorkspaceMember requires a workspace member id"
	)
	return get("/workspace_members/" .. encode(memberId), nil, "getWorkspaceMember")
end

function functions.listFiles(opts: any)
	opts = opts or {}
	local object = object_slug(opts.object or opts)
	local recordId = record_id_of(opts.record_id or opts)
	if type(object) ~= "string" or object == "" then
		error("attio.listFiles requires an object slug or id")
	end
	if type(recordId) ~= "string" or recordId == "" then
		error("attio.listFiles requires a record id")
	end
	local params = pick(opts, { "storage_provider", "parent_folder_id", "limit", "cursor" })
	params.object = object
	params.record_id = recordId
	return get("/files", params, "listFiles")
end

function functions.getFile(fileId: any)
	fileId = require_id(fileId, "file_id", "attio.getFile requires a file id")
	return get("/files/" .. encode(fileId), nil, "getFile")
end

function functions.listAttributes(target: any,identifier: any,opts: any)
	if type(target) == "table" then
		opts = target
		identifier = target.identifier or object_slug(target)
		target = target.target or "objects"
	elseif type(identifier) == "table" then
		opts = identifier
		identifier = object_slug(identifier)
	end
	if type(target) ~= "string" or target == "" then
		error("attio.listAttributes requires target objects or lists")
	end
	if type(identifier) ~= "string" or identifier == "" then
		error("attio.listAttributes requires an object or list slug or id")
	end
	return get(
		"/" .. encode(target) .. "/" .. encode(identifier) .. "/attributes",
		pick(opts, { "limit", "offset", "show_archived" }),
		"listAttributes"
	)
end

local operationHelp: {[string]: string} = {
	getCallRecording = [==[## getCallRecording(meetingId, id)

Attio `GET /v2/meetings/{meeting_id}/call_recordings/{call_recording_id}`.
The response includes `transcript` (`segments`, `raw_transcript`) when
Attio has one.]==],
	getComment = [==[## getComment(id)

Attio `GET /v2/comments/{comment_id}`. `id` may be a string or a table
with `comment_id` / `id`.]==],
	getFile = [==[## getFile(id)

Attio `GET /v2/files/{file_id}`.]==],
	getList = [==[## getList(list)

Attio `GET /v2/lists/{list}`. `list` is a slug or id.]==],
	getMeeting = [==[## getMeeting(id)

Attio `GET /v2/meetings/{meeting_id}`.]==],
	getNote = [==[## getNote(id)

Attio `GET /v2/notes/{note_id}`. `id` may be a string or a table with
`note_id` / `id`. Use only for the few notes you brief; list rows do
not need full markdown.]==],
	getRecord = [==[## getRecord(object, recordId)

Attio `GET /v2/objects/{object}/records/{record_id}`. `object` and
`recordId` may be strings, or a table with `object` / `api_slug` and
`record_id` / `id`.]==],
	getTask = [==[## getTask(id)

Attio `GET /v2/tasks/{task_id}`. `id` may be a string or a table with
`task_id` / `id`.]==],
	getThread = [==[## getThread(id)

Attio `GET /v2/threads/{thread_id}`. Returns the thread and its comments.]==],
	getWorkspaceMember = [==[## getWorkspaceMember(id)

Attio `GET /v2/workspace_members/{workspace_member_id}`.]==],
	identify = [==[## identify()

Attio `GET /v2/self`. Returns the token and workspace (`active`,
`workspace_id`, `workspace_name`, `workspace_slug`, `scope`, …).]==],
	listAttributes = [==[## listAttributes(target, identifier, opts?)

Attio `GET /v2/{target}/{identifier}/attributes`. `target` is
`"objects"` or `"lists"`; `identifier` is a slug or id. Optional
`limit`, `offset`, `show_archived`. Loop with `offset` in one `run`.]==],
	listCallRecordings = [==[## listCallRecordings(meetingId, opts?)

Attio `GET /v2/meetings/{meeting_id}/call_recordings`. `meetingId` may
be a string or a table with `meeting_id` / `id`.]==],
	listEmails = [==[## listEmails(opts?)

Attio `GET /v2/emails`. Metadata only — email **content** is never
returned. Requires the token `email:read` scope; without it the call
403s — use meetings/tasks/threads for CRM activity instead. At least
one of `linked_object`+`linked_record_ids`,
`participants`, or `domain` is required by Attio. Optional fields:

- `limit` (number, default 25, max 50)
- `cursor` (string)
- `linked_object` (string, people or companies)
- `linked_record_ids` (comma-separated record ids)
- `participants` (comma-separated email addresses)
- `domain` (string)
- `sent_after` / `sent_before` (timestamps)

Returns `data` (`{ id, subject_line, participants, sent_at, direction,
linked_records, … }[]`) and `pagination.next_cursor`. Loop on
`next_cursor` in one `run`.]==],
	listFiles = [==[## listFiles(opts)

Attio `GET /v2/files`. Required on `opts`: `object` and `record_id`.
Optional: `storage_provider`, `parent_folder_id`, `limit`, `cursor`.
Loop on `pagination.next_cursor` in one `run`.]==],
	listLists = [==[## listLists()

Attio `GET /v2/lists`. Returns lists the token can access.]==],
	listMeetings = [==[## listMeetings(opts?)

Attio `GET /v2/meetings`. Optional fields on `opts`:

- `limit` (default 50, max 200) / `cursor`
- `linked_object` / `linked_record_id`
- `participants` (comma-separated emails)
- `sort` (`start_asc`, `start_desc`)
- `ends_from` / `starts_before` / `timezone`

`participants` and `linked_record_id` are combined with OR. Loop on
`pagination.next_cursor` in one `run`.]==],
	listNotes = [==[## listNotes(opts?)

Attio `GET /v2/notes`. Optional fields on `opts`:

- `limit` (number, default 10, max 50)
- `offset` (number, default 0)
- `parent_object` (string)
- `parent_record_id` (string)

Returns `data` (`{ id, title, created_at, parent_object,
parent_record_id, content_plaintext, … }[]`). Notes are **newest-first**:
stop paging when `created_at` leaves the window; do not walk the whole
workspace. Return compact rows (`id`, `title`, `created_at`, parent ids)
and `getNote` only for bodies. The same Granola-synced note often
appears on **company and deal** — dedup on title + `created_at`.
`limit` max is 50. Loop with `offset` in one `run`.]==],
	listObjects = [==[## listObjects()

Attio `GET /v2/objects`. Returns `data` (`{ id, api_slug, singular_noun,
plural_noun, … }[]`).]==],
	listTasks = [==[## listTasks(opts?)

Attio `GET /v2/tasks`. Optional fields on `opts`:

- `limit` / `offset`
- `sort` (`created_at:asc`, `created_at:desc`, `completed_at:asc`, `completed_at:desc`)
- `linked_object` / `linked_record_id`
- `assignee` (email, member id, or `"null"`)
- `is_completed` (boolean)

Loop with `offset` in one `run`.]==],
	listThreads = [==[## listThreads(opts?)

Attio `GET /v2/threads`. There is no list-comments endpoint; threads
carry their comments. Optional fields:

- `record_id` + `object` (threads on a record)
- `entry_id` + `list` (threads on a list entry)
- `limit` (default 10, max 50) / `offset`

Each thread includes `comments` (`content_plaintext`, …). Loop with
`offset` in one `run`.]==],
	listWorkspaceMembers = [==[## listWorkspaceMembers()

Attio `GET /v2/workspace_members`.]==],
	queryListEntries = [==[## queryListEntries(list, opts?)

Attio `POST /v2/lists/{list}/entries/query`. Same optional `filter`,
`filter_view_id`, `sorts`, `limit`, `offset` as `queryRecords`. Loop
with `offset` in one `run`.]==],
	queryRecords = [==[## queryRecords(object, opts?)

Attio `POST /v2/objects/{object}/records/query`. `object` is a slug or
id (`"people"`, `"companies"`, …), or a table with `object` / `api_slug`.
Optional fields on `opts`:

- `filter` (table)
- `filter_view_id` (string)
- `sorts` (table)
- `limit` (number, default 500)
- `offset` (number, default 0)

Returns `data` (records with `id.record_id` and `values`). Loop with
`offset` in one `run`.]==],
	searchRecords = [==[## searchRecords(query, opts?)

Attio `POST /v2/objects/records/search`. `query` is a string, or a table
with `query`. Optional fields on `opts` (or on the table):

- `objects` (string array of slugs or ids; required by Attio)
- `limit` (number, default 25, max 25)
- `request_as` (table; defaults to `{ type = "workspace" }`)

Results are eventually consistent. Use `queryRecords` for up-to-date
rows.]==],
}

function functions.help(): string
	local names: {string} = {}
	for name in (functions :: {[string]: any}) do
		if name ~= "help" then names[#names + 1] = name end
	end
	table.sort(names)
	local sections = {"attio: configured connection help. Credentials stay on Houston. Use only the functions listed below. Provider scopes are enforced by real calls; help makes no network requests."}
	for _, name in names do
		local text = operationHelp[name]
		assert(text, "missing help for configured function " .. name)
		sections[#sections + 1] = text
	end
	return table.concat(sections, "\n\n")
end

return functions
