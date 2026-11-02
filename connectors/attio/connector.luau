-- Attio REST API v2, read-only. Arguments and results keep Attio's native field names.
type Kind = string | number | {string}
type Endpoint = {method: string, path: string, params: {string}, options: {[string]: Kind}, required: {string}?, defaults: {[string]: any}?, bare: boolean?, help: string}

local API = "https://api.attio.com/v2"
local NONE: {string} = table.freeze({})
local NO_DEFAULTS: {[string]: any} = table.freeze({})
local QUERY: {[string]: Kind} = {filter = "table", filter_view_id = "text", sorts = "array", limit = "count", offset = "offset"}
local QUERY_HELP = "Optional filter (Attio filter object) or filter_view_id (a saved view's UUID), sorts (array), limit (Attio defaults to 500) and offset. Page with offset and stop as soon as you have enough. Records are `{id = {workspace_id, object_id, record_id}, created_at, web_url, values}`; each attribute in values is an array of historic values, newest active first."
local endpoints: {[string]: Endpoint} = {
	identify = {method = "GET", path = "/self", params = {}, options = {}, bare = true,
		help = "Describe the API key: `{active, scope, client_id, token_type, token_level, exp, iat, workspace_id, workspace_name, workspace_slug, workspace_logo_url, authorized_by_workspace_member_id}`. A revoked key returns active = false."},
	listObjects = {method = "GET", path = "/objects", params = {}, options = {},
		help = "List every object: `{data = {{id = {object_id}, api_slug, singular_noun, plural_noun, created_at}}}`. Standard slugs include people, companies, deals, users and workspaces."},
	listAttributes = {method = "GET", path = "/{target}/{identifier}/attributes", params = {"target", "identifier"},
		options = {target = {"objects", "lists"}, limit = "count", offset = "offset", show_archived = "boolean"},
		help = "List the attributes of an object or list: target is \"objects\" or \"lists\" and identifier is its slug or UUID. Each attribute has api_slug, title, type (text, number, select, status, record-reference, …), is_multiselect and config. Read them before filtering or sorting queries."},
	queryRecords = {method = "POST", path = "/objects/{object}/records/query", params = {"object"}, options = QUERY,
		help = "Query an object's records (object is a slug or UUID). " .. QUERY_HELP},
	getRecord = {method = "GET", path = "/objects/{object}/records/{record_id}", params = {"object", "record_id"}, options = {},
		help = "Read one record with all its attribute values."},
	searchRecords = {method = "POST", path = "/objects/records/search", params = {"query"}, required = {"objects"},
		options = {query = "string", objects = "texts", limit = 25, request_as = "table"}, defaults = {request_as = {type = "workspace"}},
		help = "Fuzzy-search record names, domains, emails, phone numbers and social handles. objects (required) lists object slugs or UUIDs; request_as defaults to `{type = \"workspace\"}`, or pass `{type = \"workspace-member\", workspace_member_id = …}` to see only what that member can. Attio defaults limit to 25. Results are eventually consistent: use queryRecords for up-to-date or exhaustive results."},
	listNotes = {method = "GET", path = "/notes", params = {},
		options = {limit = 50, offset = "offset", parent_object = "text", parent_record_id = "text"},
		help = "List notes newest first: `{data = {{id = {note_id}, parent_object, parent_record_id, title, content_plaintext, content_markdown, tags, created_by_actor, created_at}}}`. Filter one record with parent_object and parent_record_id together. Attio defaults limit to 10 and allows 10 note requests per second; stop paging once created_at leaves the window you need. Notes synced from meeting tools often appear on both a company and its deal."},
	getNote = {method = "GET", path = "/notes/{note_id}", params = {"note_id"}, options = {},
		help = "Read one note, including content_plaintext and content_markdown."},
	listEmails = {method = "GET", path = "/emails", params = {},
		options = {limit = 50, cursor = "text", linked_object = "text", linked_record_ids = "texts", participants = "texts", domain = "text",
			sent_after = "text", sent_before = "text", exclude_automated_participants = "boolean"},
		help = "List email metadata, never message bodies: `{data = {{id, subject_line, participants, sent_at, direction, linked_records}}, pagination = {next_cursor}}`. Attio requires one filter: linked_object (people or companies) with linked_record_ids (up to 10), participants (up to 10 addresses) or domain. Arrays are sent comma-separated. sent_after and sent_before are exclusive ISO 8601 timestamps. Attio enables this alpha endpoint per workspace and requires the key's email scope; otherwise it answers HTTP 403. Attio defaults limit to 25."},
	listTasks = {method = "GET", path = "/tasks", params = {},
		options = {limit = "count", offset = "offset", sort = {"created_at:asc", "created_at:desc", "completed_at:asc", "completed_at:desc"},
			linked_object = "text", linked_record_id = "text", assignee = "string", is_completed = "boolean"},
		help = "List tasks: `{data = {{id = {task_id}, content_plaintext, deadline_at, is_completed, completed_at, linked_records, assignees, created_at}}}`. Filter a record with linked_object and linked_record_id together; assignee is a member's email or UUID, or \"null\" for unassigned tasks. Attio defaults limit to 500 and sort to created_at:asc."},
	getTask = {method = "GET", path = "/tasks/{task_id}", params = {"task_id"}, options = {},
		help = "Read one task."},
	listThreads = {method = "GET", path = "/threads", params = {},
		options = {record_id = "text", object = "text", entry_id = "text", list = "text", limit = 50, offset = "offset"},
		help = "List comment threads with their comments: `{data = {{id = {thread_id}, comments = {{id = {comment_id}, content_plaintext, author, created_at}}, created_at}}}`. Pass object with record_id for a record's threads, or list with entry_id for a list entry's. Attio defaults limit to 10. There is no endpoint listing every comment."},
	getThread = {method = "GET", path = "/threads/{thread_id}", params = {"thread_id"},
		options = {limit = 250, cursor = "text", created_after = "text"},
		help = "Read one thread and up to 250 of its comments, with pagination.next_cursor for the rest. created_after keeps only newer comments."},
	getComment = {method = "GET", path = "/comments/{comment_id}", params = {"comment_id"}, options = {},
		help = "Read one comment: thread_id, content_plaintext, author, entry or record, resolved state and created_at."},
	listMeetings = {method = "GET", path = "/meetings", params = {},
		options = {limit = 200, cursor = "text", linked_object = "text", linked_record_id = "text", participants = "texts",
			sort = {"start_asc", "start_desc"}, ends_from = "text", starts_before = "text", timezone = "text"},
		help = "List meetings: `{data = {{id = {meeting_id}, title, description, start, end, is_all_day, participants, linked_records, created_at}}, pagination = {next_cursor}}`. Filter a record with linked_object and linked_record_id together; participants (emails) and linked_record_id combine with OR. ends_from is inclusive and starts_before exclusive; timezone (default UTC) applies to all-day meetings. Attio defaults limit to 50 and sort to start_asc."},
	getMeeting = {method = "GET", path = "/meetings/{meeting_id}", params = {"meeting_id"}, options = {},
		help = "Read one meeting."},
	listCallRecordings = {method = "GET", path = "/meetings/{meeting_id}/call_recordings", params = {"meeting_id"},
		options = {limit = 200, cursor = "text"},
		help = "List a meeting's call recordings: `{data = {{id = {call_recording_id}, status, web_url, created_at}}, pagination = {next_cursor}}`. Attio defaults limit to 50."},
	getCallRecording = {method = "GET", path = "/meetings/{meeting_id}/call_recordings/{call_recording_id}", params = {"meeting_id", "call_recording_id"}, options = {},
		help = "Read one call recording, including its transcript when Attio has one. video_url expires after an hour."},
	listLists = {method = "GET", path = "/lists", params = {}, options = {},
		help = "List every list the key can read: `{data = {{id = {list_id}, api_slug, name, parent_object, workspace_access, created_at}}}`."},
	getList = {method = "GET", path = "/lists/{list}", params = {"list"}, options = {},
		help = "Read one list by slug or UUID."},
	queryListEntries = {method = "POST", path = "/lists/{list}/entries/query", params = {"list"}, options = QUERY,
		help = "Query a list's entries (list is a slug or UUID). Entries are `{id = {entry_id}, parent_record_id, parent_object, created_at, entry_values}`. " .. QUERY_HELP},
	listWorkspaceMembers = {method = "GET", path = "/workspace_members", params = {}, options = {},
		help = "List workspace members: `{data = {{id = {workspace_member_id}, first_name, last_name, email_address, access_level, created_at}}}`."},
	getWorkspaceMember = {method = "GET", path = "/workspace_members/{workspace_member_id}", params = {"workspace_member_id"}, options = {},
		help = "Read one workspace member."},
	listFiles = {method = "GET", path = "/files", params = {}, required = {"object", "record_id"},
		options = {object = "text", record_id = "text", storage_provider = {"attio", "dropbox", "box", "google-drive", "microsoft-onedrive"},
			parent_folder_id = "text", limit = 200, cursor = "text"},
		help = "List a record's files and folders (object and record_id are required): `{data = {{id = {file_id}, name, file_type, content_type, content_size, storage_provider, parent_folder_id, created_at}}, pagination = {next_cursor}}`. Without parent_folder_id every nesting level is returned. Attio defaults limit to 50. File contents cannot be downloaded through this connection."},
	getFile = {method = "GET", path = "/files/{file_id}", params = {"file_id"}, options = {},
		help = "Read one file's metadata."},
}

local function text(value: any, field: string): string
	assert(type(value) == "string" and value ~= "", field .. " must be a nonempty string")
	return value
end

local function integer(value: any, field: string, minimum: number, maximum: number?): number
	assert(type(value) == "number" and value % 1 == 0 and value >= minimum and value <= (maximum or 2 ^ 53),
		field .. " must be an integer from " .. tostring(minimum) .. (if maximum then " to " .. tostring(maximum) else " or more"))
	return value
end

local function array(value: any, field: string): {any}
	local count = 0
	if type(value) == "table" then for _ in value do count += 1 end end
	assert(type(value) == "table" and count == #value, field .. " must be an array")
	return value
end

local function texts(value: any, field: string): {string}
	if type(value) == "string" then return {text(value, field)} end
	assert(type(value) == "table" and #value > 0, field .. " must be a nonempty string or array of strings")
	array(value, field)
	for index, item in value do text(item, field .. "[" .. tostring(index) .. "]") end
	return value
end

-- Returns the checked value; Attio expects string arrays in query strings comma-separated.
local function option(value: any, field: string, kind: Kind, query: boolean): any
	if type(kind) == "number" then
		return integer(value, field, 1, kind)
	elseif type(kind) == "table" then
		assert(table.find(kind, value), field .. " must be one of " .. table.concat(kind, ", "))
		return value
	elseif kind == "count" then
		return integer(value, field, 1)
	elseif kind == "offset" then
		return integer(value, field, 0)
	elseif kind == "boolean" then
		assert(type(value) == "boolean", field .. " must be a boolean")
		return value
	elseif kind == "string" then
		assert(type(value) == "string", field .. " must be a string")
		return value
	elseif kind == "texts" then
		local items = texts(value, field)
		return if query then table.concat(items, ",") else items
	elseif kind == "array" then
		return if #array(value, field) > 0 then value else json.decode("[]")
	elseif kind == "table" then
		assert(type(value) == "table", field .. " must be a table")
		return value
	end
	return text(value, field)
end

local function failure(name: string, response: HttpResponse): never
	local status = response.statusCode
	local prefix = await(response.body:readPrefix(4096))
	local ok, body = pcall(json.decode, prefix)
	if not ok or type(body) ~= "table" then body = {code = string.match(prefix, '^%s*{.-"code"%s*:%s*"([%w_]+)"')} end
	local message = "Attio HTTP " .. tostring(status)
	if type(body.code) == "string" then message ..= " " .. string.sub(body.code, 1, 64) end
	if type(body.message) == "string" then message ..= ": " .. string.sub(body.message, 1, 300) end
	if status == 401 then message ..= " (check the connection's API key)"
	elseif status == 403 then message ..= " (the API key lacks a scope this call needs; add it in Attio's developer settings)" end
	local retry = response.headers["retry-after"]
	if status == 429 and retry and retry[1] then message ..= "; retry after " .. string.sub(retry[1], 1, 40) end
	return houston.fail({operation = name, layer = "upstream", upstream_status = status,
		retryable = status == 429 or status >= 500, message = message})
end

local function request(name: string, endpoint: Endpoint, args: {any}, input: any): any
	assert(input == nil or type(input) == "table", name .. " options must be a table")
	local path = endpoint.path
	local body: {[string]: any} = {}
	local query: {string} = {}
	for index, param in endpoint.params do
		local value = args[index]
		if string.find(path, "{" .. param .. "}", 1, true) then
			if type(value) == "table" then
				local id = if type(value.id) == "table" then value.id else {}
				value = value[param] or id[param] or value.api_slug
			end
			local segment = url.segment(option(value, param, endpoint.options[param] or "text", false), param)
			path = string.gsub(path, "{" .. param .. "}", function() return segment end)
		else
			body[param] = option(value, param, endpoint.options[param], false)
		end
	end
	for field, value in (input or {}) :: {[string]: any} do
		local kind = endpoint.options[field]
		assert(type(field) == "string" and kind and body[field] == nil and not table.find(endpoint.params, field), name .. " received an unknown option " .. tostring(field))
		if endpoint.method == "POST" then
			body[field] = option(value, field, kind, false)
		else
			table.insert(query, field .. "=" .. url.encode(option(value, field, kind, true)))
		end
	end
	for _, field in endpoint.required or NONE do
		assert((input or {})[field] ~= nil, name .. " requires " .. field)
	end
	for field, value in endpoint.defaults or NO_DEFAULTS do
		if body[field] == nil then body[field] = value end
	end
	table.sort(query)
	local target = API .. path .. (if #query > 0 then "?" .. table.concat(query, "&") else "")
	local headers: HttpHeaders = {Accept = {"application/json"}}
	if endpoint.method == "POST" then headers["Content-Type"] = {"application/json"} end
	local response = await(http.request({method = endpoint.method, url = target, headers = headers,
		body = if endpoint.method == "POST" then json.encode(body) else nil}))
	if response.statusCode < 200 or response.statusCode >= 300 then failure(name, response) end
	local raw = await(response.body:readAll())
	local ok, value = pcall(json.decode, raw)
	if not ok or type(value) ~= "table" or not string.match(raw, "^%s*{") or (not endpoint.bare and type(value.data) ~= "table") then
		houston.fail({operation = name, layer = "upstream", upstream_status = response.statusCode, retryable = false,
			message = "Attio returned an unexpected response"})
	end
	return value
end

local functions: {[string]: any} = {}
for name, endpoint in endpoints do
	local count = #endpoint.params
	functions[name] = function(...: any)
		local args = table.pack(...)
		assert(args.n <= count + 1, name .. " takes at most " .. tostring(count + 1) .. " arguments")
		return request(name, endpoint, args, args[count + 1])
	end
end

local function signature(name: string, endpoint: Endpoint): string
	local params = table.clone(endpoint.params)
	if next(endpoint.options) then
		table.insert(params, if endpoint.required then "opts" else "opts?")
	end
	return name .. "(" .. table.concat(params, ", ") .. ")"
end

local function describe(field: string, kind: Kind): string
	if type(kind) == "number" then return field .. " (1–" .. tostring(kind) .. ")" end
	if type(kind) == "table" then return field .. " (" .. table.concat(kind, " | ") .. ")" end
	return field
end

function functions.help(): string
	local sections = {"Attio: read-only access to this workspace's CRM objects, records, lists, notes, tasks, comments, meetings, emails and files, limited by the API key's scopes. Credentials stay on Houston. Each call makes one request and returns Attio's JSON unchanged, with results under data. Calls return completed values; do not wrap them in await(). Unknown options are rejected.",
		"IDs are UUIDs; objects, lists and attributes also accept their api_slug. Attio returns composite ids such as `record.id.record_id`: pass the inner UUID, or the row or id table itself, as in `attio.getNote(row)` or `attio.getRecord(\"people\", row)`. Offset-paged calls take limit and offset; cursor-paged calls return pagination.next_cursor, which you pass back as cursor until it is null. Attio allows 100 reads per second and limits queries by complexity, so prefer filters to paging through everything. HTTP 429 and 5xx errors are retryable."}
	local names: {string} = {}
	for name in endpoints do table.insert(names, name) end
	table.sort(names)
	for _, name in names do
		local endpoint = endpoints[name]
		local section = "## " .. signature(name, endpoint) .. "\n\n" .. endpoint.method .. " /v2" .. endpoint.path .. ". " .. endpoint.help
		local fields: {string} = {}
		for field, kind in endpoint.options do
			if not table.find(endpoint.params, field) then table.insert(fields, describe(field, kind)) end
		end
		table.sort(fields)
		if #fields > 0 then section ..= " Options: " .. table.concat(fields, ", ") .. "." end
		table.insert(sections, section)
	end
	table.insert(sections, [[## Example

Here attio is the configured Attio connection.

```lua
local found = attio.searchRecords("Acme", {objects = {"companies"}, limit = 5})
local company = found.data[1]
if company then
	local id = company.id.record_id
	local notes = attio.listNotes({parent_object = "companies", parent_record_id = id, limit = 20})
	local tasks = attio.listTasks({linked_object = "companies", linked_record_id = id, is_completed = false})
	local deals = attio.queryRecords("deals", {filter = {associated_company = {target_object = "companies", target_record_id = id}}, limit = 50})
end
```

Reference: https://docs.attio.com/rest-api/overview]])
	return table.concat(sections, "\n\n")
end

return functions
