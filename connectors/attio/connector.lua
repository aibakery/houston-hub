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

return functions
