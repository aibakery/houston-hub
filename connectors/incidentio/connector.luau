-- incident.io REST API (v1, v2 and v3 routes). Arguments and results keep incident.io's native snake_case field names.
type Options = {[string]: any}
type Endpoint = {method: string, path: string, query: {string}?, extra: {string}?, required: {string}?, write: boolean?, body: (boolean | string)?,
	fields: {string}?, page_max: number?, doc: string, about: string}

local PROVIDER = "incident.io"
local API = "https://api.incident.io"
local DOCS = "https://docs.incident.io/api-reference/"
local PAGE = {"page_size", "after"}
local CHANGED = {"created_at", "updated_at"}

local function with(...: {string}): {string}
	local fields: {string} = {}
	for _, group in {...} do table.move(group, 1, #group, #fields + 1, fields) end
	return fields
end

-- Operations in incident.io's OpenAPI (https://api.incident.io/v1/openapiV3.json), checked on
-- 2026-10-30, at their newest version: severities, statuses, incident types, custom field
-- options and the key's identity exist only in v1. Path {fields} are required; listed query
-- fields are taken from the options and the other fields form the JSON body.
local endpoints: {[string]: Endpoint} = {
	getIdentity = {method = "GET", path = "/v1/identity", doc = "utilities-v1/show-identity",
		about = "The API key's {identity={name, roles, team_roles, teams, dashboard_url}}: roles lists the permissions it was created with, such as viewer, global_access, incident_creator, incident_editor, catalog_viewer or on_call_viewer."},

	listIncidents = {method = "GET", path = "/v2/incidents",
		query = with({"status", "status_category", "severity", "incident_type", "incident_role", "custom_field", "mode", "filter_mode", "sort_by"}, CHANGED, PAGE),
		doc = "incidents-v2/list",
		about = "Incidents, newest first unless sort_by='created_at_oldest_first': {incidents, pagination_meta={after, page_size, total_record_count}}. Each has id, reference (INC-123), name, summary, permalink, visibility, mode, incident_status {id, name, category}, severity {id, name, rank}, incident_type, created_at, updated_at, incident_role_assignments [{role {id, name, role_type}, assignee {id, name, email}}], incident_timestamp_values [{incident_timestamp {id, name}, value {value}}], duration_metrics, custom_field_entries, slack_channel_url and call_url. Filters are objects of operator to values, sent as status[one_of]=...: status={one_of={id}} or not_in; status_category={one_of={'live'}} with triage, live (shown as Active), learning (Post-incident), paused, closed, declined, canceled or merged; severity with one_of, not_in, gte or lte a severity id; incident_type with one_of or not_in; created_at and updated_at with gte, lte or date_range='2026-10-01~2026-10-31'; incident_role={[role_id]={one_of={user_id}}} or {[role_id]={is_blank={'true'}}}; custom_field={[field_id]={one_of={option_id}}}; mode={one_of={'test'}} (test and tutorial incidents are left out by default). filter_mode='any' ORs the filters. incident.io answers at most 60 incident lists a minute."},
	getIncident = {method = "GET", path = "/v2/incidents/{id}", doc = "incidents-v2/show",
		about = "One incident, {incident}, by id or by the number of its reference (123 for INC-123), with the fields of listIncidents."},
	listIncidentUpdates = {method = "GET", path = "/v2/incident_updates", query = with({"incident_id"}, PAGE), doc = "incident-updates-v2/list",
		about = "Updates shared on incidents: {incident_updates=[{id, incident_id, message, new_incident_status, new_severity, updater, created_at}], pagination_meta}. Without incident_id, updates across all incidents."},
	listIncidentTimelineItems = {method = "GET", path = "/v2/incident_timeline_items", query = with({"incident_id"}, PAGE), required = {"incident_id"},
		doc = "incident-timeline-items-v2/list", about = "An incident's timeline as the dashboard shows it, oldest first: {incident_timeline_items=[{id, title, description, timestamp, creator}], pagination_meta}."},
	listIncidentAlerts = {method = "GET", path = "/v2/incident_alerts", query = with({"incident_id", "alert_id"}, PAGE), page_max = 50, doc = "incident-alerts-v2/list",
		about = "Links between alerts and incidents, {incident_alerts=[{id, alert {id, title, status}, incident {id, reference, name}, alert_route_id}], pagination_meta}; page_size at most 50."},
	listFollowUps = {method = "GET", path = "/v3/follow_ups", query = with({"incident_id", "incident_mode", "assignee_team_id"}, CHANGED, PAGE), doc = "follow-ups-v3/list",
		about = "Follow-ups, {follow_ups=[{id, incident_id, title, description, status (outstanding, completed, not_doing or deleted), assignee, assignee_team, priority, category, labels, external_issue_reference, created_at, completed_at}], pagination_meta}. created_at and updated_at filter like listIncidents; incident_mode: standard, retrospective, test, tutorial or stream (default standard and retrospective)."},
	getFollowUp = {method = "GET", path = "/v3/follow_ups/{id}", doc = "follow-ups-v3/show", about = "One follow-up, {follow_up}."},

	listAlerts = {method = "GET", path = "/v2/alerts",
		query = with({"status", "alert_source", "alert_group_id", "deduplication_key", "attributes", "tags", "has_notes", "include_maintenance_window"}, CHANGED, PAGE),
		page_max = 50,
		doc = "alerts-v2/list",
		about = "Alerts from your alert sources: {alerts=[{id, title, description, status (firing or resolved), alert_source_id, deduplication_key, source_url, attributes, tags, created_at, resolved_at}], pagination_meta}; page_size at most 50. Filters work like listIncidents: status={one_of={'firing'}}, alert_source={one_of={source_id}}, deduplication_key={is={key}}, tags={one_of={'known issue'}}, attributes={[attribute_id]={one_of={value}}}, has_notes={is={'true'}}, include_maintenance_window={is={'true'}}, created_at={gte={'2026-10-01'}}."},
	getAlert = {method = "GET", path = "/v2/alerts/{id}", doc = "alerts-v2/show", about = "One alert, {alert}."},

	listSchedules = {method = "GET", path = "/v2/schedules", query = PAGE, doc = "schedules-v2/list",
		about = "On-call schedules, {schedules=[{id, name, timezone, team_ids, current_shifts, next_shifts, config {rotations}}], pagination_meta}; current_shifts lists who is on call now, [{user {id, name, email}, start_at, end_at, rotation_id}]. next_shifts is filled only when page_size is 25 or less."},
	getSchedule = {method = "GET", path = "/v2/schedules/{id}", doc = "schedules-v2/show", about = "One schedule, {schedule}, with its current_shifts, next_shifts and rotations."},
	listScheduleEntries = {method = "GET", path = "/v2/schedule_entries", query = {"schedule_id", "entry_window_start", "entry_window_end"}, required = {"schedule_id"},
		doc = "schedule-entries-v2/list",
		about = "Who is on call on a schedule over a window (ISO 8601 times; by default from now): {schedule_entries={final, scheduled, overrides}, pagination_meta?}. final is the effective rota after overrides, [{user, start_at, end_at, rotation_id}]. When pagination_meta.after is set, call again with entry_window_start=pagination_meta.after and the same entry_window_end."},

	listUsers = {method = "GET", path = "/v2/users", query = with({"email", "slack_user_id", "include_inactive"}, PAGE), doc = "users-v2/list",
		about = "Users, {users=[{id, name, email, role, slack_user_id}], pagination_meta}; email or slack_user_id finds one person."},
	getUser = {method = "GET", path = "/v2/users/{id}", doc = "users-v2/show", about = "One user, {user}."},
	listTeams = {method = "GET", path = "/v3/teams", query = PAGE, doc = "teams-v3/list", about = "Teams, {teams=[{id, name, members, catalog_entry}], pagination_meta}."},

	listSeverities = {method = "GET", path = "/v1/severities", doc = "severities-v1/list",
		about = "Severities, {severities=[{id, name, description, rank}]}; a higher rank is more severe."},
	listIncidentStatuses = {method = "GET", path = "/v1/incident_statuses", doc = "incident-statuses-v1/list",
		about = "Incident statuses, {incident_statuses=[{id, name, description, rank, category}]}; category is triage, live, learning, paused, closed, declined, canceled or merged."},
	listIncidentTypes = {method = "GET", path = "/v1/incident_types", doc = "incident-types-v1/list",
		about = "Incident types, {incident_types=[{id, name, description, is_default, private_incidents_only}]}."},
	listIncidentRoles = {method = "GET", path = "/v2/incident_roles", doc = "incident-roles-v2/list",
		about = "Incident roles, {incident_roles=[{id, name, shortform, description, instructions, role_type (lead, reporter or custom)}]}."},
	listIncidentTimestamps = {method = "GET", path = "/v2/incident_timestamps", doc = "incident-timestamps-v2/list",
		about = "Incident timestamps, such as when an incident was reported, accepted or resolved: {incident_timestamps=[{id, name, rank}]}."},
	listCustomFields = {method = "GET", path = "/v2/custom_fields", doc = "custom-fields-v2/list",
		about = "Incident custom fields, {custom_fields=[{id, name, description, field_type (single_select, multi_select, text, link or numeric), catalog_type_id}]}."},
	listCustomFieldOptions = {method = "GET", path = "/v1/custom_field_options", query = with({"custom_field_id"}, PAGE), required = {"custom_field_id"},
		doc = "custom-field-options-v1/list", about = "A select custom field's options, {custom_field_options=[{id, value, sort_key}], pagination_meta}."},

	listCatalogTypes = {method = "GET", path = "/v3/catalog_types", doc = "catalog-types-v3/list-types",
		about = "Catalog types, such as services, teams or features, {catalog_types=[{id, name, description, type_name, schema {attributes}, categories, is_editable}]}."},
	listCatalogEntries = {method = "GET", path = "/v3/catalog_entries", query = with({"catalog_type_id", "identifier"}, PAGE), required = {"catalog_type_id"},
		doc = "catalog-entries-v3/list-entries",
		about = "A catalog type's entries, {catalog_entries=[{id, name, external_id, aliases, rank, attribute_values {[attribute_id]={value or array_value}}}], catalog_type, pagination_meta}. identifier matches an entry's id, external id or alias."},
	getCatalogEntry = {method = "GET", path = "/v3/catalog_entries/{id}", query = {"expand"}, doc = "catalog-entries-v3/show-entry",
		about = "One catalog entry, {catalog_entry, catalog_type}; expand=true adds the entries that link to it."},

	createIncident = {method = "POST", path = "/v2/incidents", required = {"idempotency_key", "visibility"},
		fields = {"idempotency_key", "visibility", "name", "summary", "severity_id", "incident_type_id", "incident_status_id", "mode", "incident_role_assignments",
			"incident_timestamp_values", "custom_field_entries", "slack_team_id", "slack_channel_name_override", "retrospective_incident_options"},
		doc = "incidents-v2/create",
		about = "Declares an incident and returns {incident}; read PAGING above first. visibility: public or private. mode: standard (default), retrospective, test or tutorial. Most accounts require name and severity_id, and the incident type's required custom fields. incident_role_assignments=[{incident_role_id, assignee={id or email or slack_user_id}}], incident_timestamp_values=[{incident_timestamp_id, value}], custom_field_entries=[{custom_field_id, values=[{value_option_id or value_text or value_link or value_numeric or value_catalog_entry_id}]}]. incident.io de-duplicates requests by idempotency_key, so repeating one with the same key cannot declare a second incident; list incidents to see what the first call did."},
	editIncident = {method = "POST", path = "/v2/incidents/{id}/actions/edit", required = {"incident", "notify_incident_channel"}, fields = {"incident", "notify_incident_channel"},
		doc = "incidents-v2/edit",
		about = "Changes only the fields given in incident={name, summary, severity_id, incident_status_id, custom_field_entries, incident_role_assignments, incident_timestamp_values, call_url, slack_channel_name_override} and returns {incident}; notify_incident_channel=true posts the change in the incident's channel. Statuses move within their category, from triage or live to learning or closed (resolving), or from learning to closed; resolving to learning starts the post-incident flow, and closing directly needs the key's post-incident opt-out permission."},
	createIncidentUpdate = {method = "POST", path = "/v2/incident_updates", required = {"incident_id", "idempotency_key"},
		fields = {"incident_id", "idempotency_key", "message", "to_incident_status_id", "to_severity_id"}, doc = "incident-updates-v2/create",
		about = "Shares an update in the incident's channel and returns {incident_update}: a Markdown message, a new status, a new severity, or a combination (at least one). Retrying with the same idempotency_key returns the update already shared."},
	createFollowUp = {method = "POST", path = "/v3/follow_ups", required = {"incident_id", "title"},
		fields = {"incident_id", "title", "description", "assignee_id", "assignee_team_id", "follow_up_priority_option_id", "follow_up_category_id", "labels", "external_issue_reference_id"},
		doc = "follow-ups-v3/create",
		about = "Adds a follow-up to an incident and returns {follow_up}; description is Markdown, assignee_id a user id and assignee_team_id a team id. Each call creates another follow-up."},
}

-- Request layer shared verbatim by the endpoint-table connectors
-- (tools/validate checks they match). It uses each connector's PROVIDER, DOCS and Endpoint type.
local NULL = json.decode("null")
local NONE: {string} = table.freeze({})

local function options(input: Options?): Options
	if input == nil then return {} end
	assert(type(input) == "table", "opts must be an object")
	for key in input do assert(type(key) == "string", "opts must have named fields") end
	return table.clone(input)
end

local function scalar(value: any, field: string): string
	local kind = type(value)
	assert(kind == "string" or kind == "boolean" or kind == "number", field .. " must be a string, boolean, number or array of those")
	return url.encode(value)
end

-- A query value's encoded parts: one for a scalar, one per item of a nonempty array. Each
-- connector joins them as its provider expects, comma-separated or with the key repeated.
local function queryParts(value: any, field: string): {string}
	if type(value) ~= "table" then return {scalar(value, field)} end
	local parts: {string} = {}
	for index, item in value do
		assert(type(index) == "number" and index == #parts + 1, field .. " must be an array, not an object")
		table.insert(parts, scalar(item, field))
	end
	assert(#parts > 0, field .. " must not be an empty array")
	return parts
end

-- Only GET reads unless write says otherwise.
local function writes(endpoint: Endpoint): boolean
	if endpoint.write ~= nil then return endpoint.write end
	return endpoint.method ~= "GET"
end

-- POST, PATCH and PUT send the remaining options as the JSON body unless body is false
-- (no body) or names the one option to send.
local function hasBody(endpoint: Endpoint): boolean
	return endpoint.body ~= false and (endpoint.method == "POST" or endpoint.method == "PATCH" or endpoint.method == "PUT")
end

local function fail(name: string, response: HttpResponse, message: string): never
	return houston.fail({operation = name, layer = "upstream", upstream_status = response.statusCode,
		retryable = response.statusCode == 429 or response.statusCode >= 500, message = message})
end

-- A successful response's JSON object, or nil when a write answers without a body. With arrays,
-- a top-level JSON array is accepted too, and the second result tells which one came back.
local function object(name: string, endpoint: Endpoint, response: HttpResponse, arrays: boolean?): (any, boolean)
	local raw = await(response.body:readAll())
	if endpoint.method ~= "GET" and writes(endpoint) and string.match(raw, "^%s*$") then return nil, false end
	local ok, value = pcall(json.decode, raw)
	local list = arrays == true and string.match(raw, "^%s*%[") ~= nil
	if not ok or type(value) ~= "table" or not (list or string.match(raw, "^%s*{")) then
		fail(name, response, PROVIDER .. " returned an invalid JSON object")
	end
	return value, list
end

-- name({path fields, query fields?, extra fields?, required body fields, ...body}) built from the
-- endpoint itself.
-- Extra fields are options the connector's own request consumes, such as a request header.
local function signature(endpoint: Endpoint): string
	local fields: {string} = {}
	for field in string.gmatch(endpoint.path, "{([%w_]+)}") do table.insert(fields, field) end
	for _, group in {endpoint.query or NONE, endpoint.extra or NONE} do
		for _, field in group do
			table.insert(fields, if table.find(endpoint.required or NONE, field) then field else field .. "?")
		end
	end
	if type(endpoint.body) == "string" then
		table.insert(fields, endpoint.body)
	elseif hasBody(endpoint) then
		for _, field in endpoint.required or NONE do
			if not table.find(fields, field) then table.insert(fields, field) end
		end
		table.insert(fields, "...body")
	end
	return "({" .. table.concat(fields, ", ") .. "})"
end

-- A function for each endpoint the connection's access allows, and help listing them after intro.
local function operations(endpoints: {[string]: Endpoint}, request: (string, Endpoint, Options?) -> any, intro: {string}): {[string]: any}
	local exports: {[string]: any} = {}
	for name, endpoint in endpoints do
		if not writes(endpoint) or config.access == "read-write" then
			exports[name] = function(args: Options?): any return request(name, endpoint, args) end
		end
	end
	exports.help = function(): string
		local names: {string} = {}
		for name in exports do if name ~= "help" then table.insert(names, name) end end
		table.sort(names)
		local lines = table.clone(intro)
		table.insert(lines, "Each function below names its route and reference page, " .. DOCS .. "<page>.")
		for _, name in names do
			local endpoint = endpoints[name]
			table.insert(lines, name .. signature(endpoint) .. ": " .. endpoint.about .. " " .. endpoint.method .. " " .. endpoint.path .. " (" .. endpoint.doc .. ")")
		end
		return table.concat(lines, "\n")
	end
	return exports
end
-- End of the shared request layer.

-- A request waits this long for incident.io's headers, Houston's 429 retries included, and then
-- for the body, so a slow answer fails clearly within the 30-second call.
local WAIT_MS, BODY_MS = 15000, 10000
local TIMED_OUT = "did not answer within " .. (WAIT_MS + BODY_MS) // 1000 .. " s"
local MAX_PAGE = 250

-- incident.io's deep-object filters, sent as status[one_of]=a or custom_field[id][one_of]=b.
local FILTERS = {"status", "status_category", "severity", "incident_type", "incident_role", "custom_field", "mode", "created_at", "updated_at",
	"alert_source", "alert_group_id", "deduplication_key", "attributes", "tags", "has_notes", "include_maintenance_window"}

local function timedOut(err: any): boolean
	return type(err) == "table" and err.code == "timeout"
end

-- Reads, and the writes incident.io de-duplicates by idempotency_key, are safe to repeat.
local function repeatable(endpoint: Endpoint): boolean
	return not writes(endpoint) or table.find(endpoint.required or NONE, "idempotency_key") ~= nil
end

local function writeHint(endpoint: Endpoint): string
	if not writes(endpoint) then return "" end
	return if repeatable(endpoint) then "; it may still have applied the change: read it back, and repeat it only with the same idempotency_key"
		else "; it may still have applied the change, so read it back before repeating it"
end

-- A call left without a complete answer.
local function unanswered(name: string, endpoint: Endpoint, status: number?, problem: string): never
	local hint = writeHint(endpoint)
	if hint == "" then hint = if table.find(endpoint.query or NONE, "page_size") then "; request a smaller page_size" else "; try again" end
	return houston.fail({operation = name, layer = "upstream", upstream_status = status, retryable = repeatable(endpoint), message = PROVIDER .. " " .. problem .. hint})
end

-- A body that stalls, or a write's body that breaks off after its 2xx headers; cancellation passes through.
local function unreadable(name: string, endpoint: Endpoint, status: number?, err: any): never
	if timedOut(err) then unanswered(name, endpoint, status, TIMED_OUT) end
	if writes(endpoint) and not (type(err) == "table" and err.code == "cancelled") then unanswered(name, endpoint, status, "did not finish its answer") end
	return error(err, 0)
end

-- incident.io errors are {type, status, request_id, errors=[{code, message, source={field}}]}.
local function failStatus(name: string, endpoint: Endpoint, response: HttpResponse): never
	local status = response.statusCode
	local message = PROVIDER .. " HTTP " .. tostring(status)
	local read, raw = pcall(function(): any return await(response.body:readPrefix(16 * 1024), BODY_MS) end)
	if not read and type(raw) == "table" and raw.code == "cancelled" then error(raw, 0) end
	local ok, value = pcall(json.decode, if read then raw else "")
	if ok and type(value) == "table" then
		if type(value.type) == "string" then message ..= " (" .. string.sub(value.type, 1, 100) .. ")" end
		local details: {string} = {}
		if type(value.errors) == "table" then
			for _, problem in value.errors do
				if type(problem) == "table" and type(problem.message) == "string" and #details < 5 then
					local field = if type(problem.source) == "table" and type(problem.source.field) == "string" then " (" .. string.sub(problem.source.field, 1, 100) .. ")" else ""
					table.insert(details, string.sub(problem.message, 1, 300) .. field)
				end
			end
		end
		if #details > 0 then message ..= ": " .. table.concat(details, "; ") end
		if type(value.request_id) == "string" then message ..= "; request_id " .. string.sub(value.request_id, 1, 64) end
	end
	local retry = response.headers["retry-after"]
	if status == 429 and retry and string.match(retry[1] or "", "^%d+$") then message ..= "; retry after " .. string.sub(retry[1], 1, 10) .. " s" end
	if status >= 500 then message ..= writeHint(endpoint) end
	return houston.fail({operation = name, layer = "upstream", upstream_status = status,
		retryable = status == 429 or (status >= 500 and repeatable(endpoint)), message = message})
end

-- A query value's key and encoded parts; filters nest objects of ids and operators.
local function addQuery(query: {string}, key: string, value: any, field: string, nested: boolean)
	if not nested then
		for _, part in queryParts(value, field) do table.insert(query, url.encode(key) .. "=" .. part) end
		return
	end
	assert(type(value) == "table" and type((next(value))) == "string", field .. " must be an object such as {one_of={...}}")
	local keys: {string} = {}
	for item in value do
		assert(type(item) == "string" and string.match(item, "^[^%[%]]+$"), field .. " must be an object of operators or ids, without [ or ]")
		table.insert(keys, item)
	end
	table.sort(keys)
	for _, item in keys do
		local inner = value[item]
		addQuery(query, key .. "[" .. item .. "]", inner, field, type(inner) == "table" and type((next(inner))) == "string")
	end
end

local function request(name: string, endpoint: Endpoint, input: Options?): any
	local args = options(input)
	local path = string.gsub(endpoint.path, "{([%w_]+)}", function(field: string)
		local value = args[field]
		args[field] = nil
		assert(value ~= nil and value ~= NULL, field .. " is required")
		assert(type(value) == "string" or (type(value) == "number" and value == math.floor(value)), field .. " must be a string")
		local ok, segment = pcall(url.segment, tostring(value), field)
		assert(ok, field .. " must be an incident.io id")
		return segment
	end)
	for _, field in endpoint.required or NONE do
		assert(args[field] ~= nil and args[field] ~= NULL, field .. " is required")
	end
	local query: {string} = {}
	for _, field in endpoint.query or NONE do
		local value = args[field]
		if field == "page_size" then
			local most = endpoint.page_max or MAX_PAGE
			value = if value == nil then 25 else value
			assert(type(value) == "number" and value == math.floor(value) and value >= 1 and value <= most, "page_size must be a whole number from 1 to " .. most)
		end
		if value ~= nil then addQuery(query, field, value, field, table.find(FILTERS, field) ~= nil) end
		args[field] = nil
	end
	if #query > 0 then path ..= "?" .. table.concat(query, "&") end
	if endpoint.fields then
		for field in args do assert(table.find(endpoint.fields :: {string}, field), name .. " has no option " .. field) end
	end
	local headers: HttpHeaders = {Accept = {"application/json"}}
	local body: string? = nil
	if hasBody(endpoint) then
		headers["Content-Type"] = {"application/json"}
		body = json.encode(args)
		args = {}
	end
	local unknown = next(args)
	assert(unknown == nil, name .. " has no option " .. tostring(unknown))
	local sent, response = pcall(function(): any
		return await(http.request({url = API .. path, method = endpoint.method, headers = headers, body = body, timeoutMs = WAIT_MS}))
	end)
	if not sent then
		if not timedOut(response) then error(response, 0) end
		unanswered(name, endpoint, nil, TIMED_OUT)
	end
	if response.statusCode < 200 or response.statusCode >= 300 then failStatus(name, endpoint, response) end
	local read, raw = pcall(function(): any return await(response.body:readAll(), BODY_MS) end)
	if not read then
		unreadable(name, endpoint, response.statusCode, raw)
	end
	local ok, value = pcall(json.decode, raw)
	if not ok or type(value) ~= "table" or not string.match(raw, "^%s*{") then fail(name, response, PROVIDER .. " returned an invalid JSON object") end
	return value
end

local intro = {
	"incident.io API on " .. API .. ", with the connection's API key. Every function takes one named options object with incident.io's native names; ? marks optional fields and ...body the JSON body fields. Results are incident.io's JSON unchanged, wrapped as incident.io wraps them ({incidents}, {incident}...). Connector calls return completed values: use them directly, without await.",
	"Ids are ULIDs such as 01FDAG4SAP5TYPT98WGR2N7W91; getIncident also takes an incident's number (123 for INC-123). Times are ISO 8601. Send an empty list as json.decode('[]'), since an empty Lua table is sent as {}. Severities, statuses, incident types, roles, timestamps and custom fields are your account's own: list them to find their ids before filtering or writing.",
	"Lists return one page with pagination_meta.after: while it is a string, pass it as after for the next page, even after a short page. page_size is 1 to " .. MAX_PAGE .. " (default 25; at most 50 for alerts and incident alerts). Configuration lists (severities, statuses, types, roles, timestamps, custom fields, catalog types) return everything at once.",
	"Examples: local live = incidentio.listIncidents({status_category={one_of={'live'}}, page_size=10}); local inc = incidentio.getIncident({id=live.incidents[1].id}).incident; local ups = incidentio.listIncidentUpdates({incident_id=inc.id}).incident_updates; local s = incidentio.listSchedules({}).schedules[1]; local now = s.current_shifts; local rota = incidentio.listScheduleEntries({schedule_id=s.id, entry_window_start='2026-11-02T00:00:00Z', entry_window_end='2026-11-09T00:00:00Z'}).schedule_entries.final.",
	"The API key's permissions apply: an HTTP 403 means the key lacks a permission, and private incidents (and their follow-ups, alerts and updates) need View all incident data; getIdentity lists the key's roles. incident.io allows 1,200 requests a minute per key; Houston retries an HTTP 429 up to twice when incident.io asks to wait 5 seconds or less, and otherwise reports how long to wait. Errors report the HTTP status, incident.io's error type and messages, and its request_id. A call that gets no complete answer within " .. (WAIT_MS + BODY_MS) // 1000 .. " s fails.",
}

if config.access == "read-write" then
	table.insert(intro, "PAGING: createIncident declares an incident, and incident.io acts on it at once. A standard incident is announced in your announcement channels, gets its own Slack or Microsoft Teams channel, and runs your workflows, which can escalate to on-call responders and page them by phone, SMS or app notification at any hour. Declare one only when the person explicitly asks for it, with the name, severity and visibility they confirmed. mode='retrospective' records a past incident without announcing it; mode='test' runs a practice incident that is not announced, stays out of dashboards and runs only workflows set to include test incidents. incident.io lets a key declare 10 incidents an hour that open a channel and 300 that do not.")
	table.insert(intro, "Other side effects: editIncident with notify_incident_channel=true, and createIncidentUpdate, post in the incident channel, and a status or severity change can run workflows and escalations; createFollowUp may be exported to your issue tracker. Apart from Houston's 429 retries, writes are not retried. After a timeout or 5xx, read the incident, its updates or its follow-ups before repeating a write; incident.io de-duplicates createIncident and createIncidentUpdate by idempotency_key, so repeat those only with the same key: their timeouts and 5xx errors are marked retryable on that basis, while editIncident and createFollowUp failures are not.")
else
	table.insert(intro, "This read-only connection omits writes: declaring and editing incidents, sharing updates and creating follow-ups.")
end

return operations(endpoints, request, intro)
