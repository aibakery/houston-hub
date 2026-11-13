-- HubSpot CRM API 2026-09 (date-based version; HubSpot stops supporting it around March 2028).
-- Arguments and results keep HubSpot's native field names.
type Options = {[string]: any}

local API = "https://api.hubapi.com"
local OBJECT_TYPES = {"contacts", "companies", "deals", "tickets", "notes", "tasks", "calls", "meetings", "emails"}
local PIPELINE_TYPES = {"deals", "tickets"}
local CATEGORIES = {"HUBSPOT_DEFINED", "USER_DEFINED", "INTEGRATOR_DEFINED"}
-- Property names a query or body may list, and associations or association types one call may send.
local MAX_NAMES = 500
local MAX_LINKS = 100

local function options(input: any): Options
	if input == nil then return {} end
	assert(type(input) == "table", "options must be an object")
	for key in input do assert(type(key) == "string", "options must have named fields") end
	return table.clone(input)
end

local function take(args: Options, field: string): any
	local value = args[field]
	args[field] = nil
	return value
end

local function done(name: string, args: Options)
	local unknown = next(args)
	assert(unknown == nil, name .. " received an unknown option " .. tostring(unknown))
end

local function text(value: any, field: string): string
	assert(type(value) == "string" and value ~= "", field .. " must be a nonempty string")
	return value
end

local function integer(value: any, field: string, min: number, max: number): number
	assert(type(value) == "number" and value == math.floor(value) and value >= min and value <= max,
		field .. " must be an integer from " .. tostring(min) .. " to " .. tostring(max))
	return value
end

local function oneOf(value: any, field: string, allowed: {string}): string
	assert(type(value) == "string" and table.find(allowed, value) ~= nil, field .. " must be one of " .. table.concat(allowed, ", "))
	return value
end

-- Record IDs are strings of digits. With idProperty, an ID is that property's unique value instead,
-- such as a contact's email.
local function idValue(value: any, field: string, idProperty: boolean?): string
	if idProperty then return text(value, field) end
	assert(type(value) == "string" and string.match(value, "^%d+$") ~= nil, field .. " must be a string of digits")
	return value
end

-- A record ID in a path, as one encoded segment.
local function recordId(value: any, field: string, idProperty: boolean?): string
	return url.segment(idValue(value, field, idProperty), field)
end

-- A dense array of 1 to max items, so that it encodes as a JSON array.
local function array(value: any, field: string, max: number): {any}
	local problem = field .. " must be an array of 1 to " .. tostring(max) .. " items"
	assert(type(value) == "table", problem)
	local count = 0
	for _ in value do count += 1 end
	assert(count >= 1 and count <= max and count == #value, problem)
	return value
end

-- Property names, or object types when allowed is given. HubSpot reads query lists comma-separated.
local function names(value: any, field: string, allowed: {string}?): {string}
	for index, name in array(value, field, MAX_NAMES) do
		local item = field .. "[" .. tostring(index) .. "]"
		if allowed then
			oneOf(name, item, allowed)
		else
			assert(type(name) == "string" and string.match(name, "^[^,]+$") ~= nil, item .. " must be a nonempty name without commas")
		end
	end
	return value
end

-- Moves the named options from args into a query string, in the order given. Lists go
-- comma-separated, and archived is sent only when true.
local function query(args: Options, fields: {string}, maxLimit: number?): string
	local parts: {string} = {}
	for _, field in fields do
		local value = take(args, field)
		if value == nil then continue end
		if field == "archived" then
			assert(type(value) == "boolean", "archived must be a boolean")
			if value then table.insert(parts, "archived=true") end
		elseif field == "limit" then
			table.insert(parts, "limit=" .. tostring(integer(value, field, 1, maxLimit :: number)))
		elseif field == "properties" or field == "propertiesWithHistory" or field == "associations" then
			local items: {string} = {}
			for _, name in names(value, field, if field == "associations" then OBJECT_TYPES else nil) do
				table.insert(items, url.encode(name))
			end
			table.insert(parts, field .. "=" .. table.concat(items, ","))
		else
			table.insert(parts, field .. "=" .. url.encode(text(value, field)))
		end
	end
	return if #parts > 0 then "?" .. table.concat(parts, "&") else ""
end

-- Property values to write: strings, numbers or booleans; an empty string clears a value.
local function properties(value: any): Options
	assert(type(value) == "table" and next(value) ~= nil, "properties must be a nonempty object of property names and values")
	local copy: Options = {}
	for name, item in value do
		assert(type(name) == "string" and name ~= "", "properties must have property names as keys")
		local field = "properties." .. name
		assert(type(item) == "string" or type(item) == "boolean" or type(item) == "number",
			field .. " must be a string, number or boolean")
		copy[name] = item
	end
	return copy
end

-- Association types to set: {{associationCategory, associationTypeId}}, as HubSpot sends them.
local function associationTypes(value: any, field: string): {Options}
	local types: {Options} = {}
	for index, item in array(value, field, MAX_LINKS) do
		local path = field .. "[" .. tostring(index) .. "]"
		assert(type(item) == "table", path .. " must be an object")
		for key in item do
			assert(key == "associationCategory" or key == "associationTypeId", path .. " received an unknown field " .. tostring(key))
		end
		table.insert(types, {
			associationCategory = oneOf(item.associationCategory, path .. ".associationCategory", CATEGORIES),
			associationTypeId = integer(item.associationTypeId, path .. ".associationTypeId", 1, 2147483647),
		})
	end
	return types
end

-- HubSpot errors are {status, message, correlationId, category, errors = {{message, code, context}}},
-- every field optional; rate limits answer {errorType, policyName}. 429 (except the daily limit),
-- 423 (a 2-second lock) and 477 (a data migration) are transient. A write that failed with a server
-- error may still have been applied, so only reads retry those.
local function fail(operation: string, response: HttpResponse, write: boolean): never
	local ok, decoded = pcall(json.decode, await(response.body:readPrefix(4096)))
	local problem: Options = if ok and type(decoded) == "table" then decoded else {}
	local status = response.statusCode
	local message = "HubSpot HTTP " .. tostring(status)
	local category = if type(problem.category) == "string" then problem.category else problem.errorType
	if type(category) == "string" then message ..= " (" .. string.sub(category, 1, 100) .. ")" end
	if type(problem.message) == "string" then message ..= ": " .. string.sub(problem.message, 1, 600) end
	local errors = if type(problem.errors) == "table" then problem.errors else {}
	local scopes: {string} = {}
	for index = 1, math.min(#errors, 10) do
		local item = errors[index]
		if type(item) ~= "table" then continue end
		if index <= 3 and type(item.message) == "string" then message ..= "; " .. string.sub(item.message, 1, 200) end
		local required = if type(item.context) == "table" then item.context.requiredGranularScopes else nil
		if status == 403 and type(required) == "table" then
			for _, scope in required do
				if type(scope) == "string" and #scopes < 10 then table.insert(scopes, string.sub(scope, 1, 100)) end
			end
		end
	end
	if #scopes > 0 then message ..= "; needs one of: " .. table.concat(scopes, ", ") end
	if status == 429 and type(problem.policyName) == "string" then message ..= "; policy " .. string.sub(problem.policyName, 1, 64) end
	local retry = response.headers["retry-after"]
	if retry and retry[1] then message ..= "; Retry-After: " .. string.sub(retry[1], 1, 40) end
	if type(problem.correlationId) == "string" then message ..= "; correlationId " .. string.sub(problem.correlationId, 1, 64) end
	if status == 401 then message ..= " (check the connection's access token, or reconnect)" end
	return houston.fail({operation = operation, layer = "upstream", upstream_status = status, message = message,
		retryable = (status == 429 and problem.policyName ~= "DAILY") or status == 423 or status == 477 or (not write and status >= 500)})
end

-- One request to HubSpot. A table body is sent as JSON and a string body as is. An empty reply,
-- such as a 204, gives {success = true}; any other reply must be a JSON object.
local function call(operation: string, method: string, path: string, body: any, write: boolean): Options
	local headers: HttpHeaders = {}
	local payload: string? = nil
	if type(body) == "table" then
		headers["Content-Type"] = {"application/json"}
		payload = json.encode(body)
	elseif body ~= nil then
		payload = body
	end
	local response = await(http.request({method = method, url = API .. path, headers = headers, body = payload}))
	if response.statusCode < 200 or response.statusCode >= 300 then fail(operation, response, write) end
	local raw = await(response.body:readAll())
	if string.match(raw, "^%s*$") then return {success = true} end
	local ok, value = pcall(json.decode, raw)
	if not ok or type(value) ~= "table" or not string.match(raw, "^%s*{") then
		houston.fail({operation = operation, layer = "upstream", upstream_status = response.statusCode,
			retryable = false, message = "HubSpot returned an invalid JSON object"})
	end
	return value
end

-- List replies keep results an array, even when HubSpot leaves it out.
local function results(value: Options): Options
	if value.results == nil then value.results = json.decode("[]") end
	return value
end

local function objects(kind: string): string
	return "/crm/objects/2026-09/" .. kind
end

local help = {
	text = [[HubSpot CRM API 2026-09 for one HubSpot account: contacts, companies, deals and tickets, their
activities (notes, tasks, calls, meetings and logged emails), the associations between records,
deal and ticket pipelines, owners and property definitions. Every operation takes one named
options object with HubSpot's field names and returns HubSpot's JSON unchanged. Connector calls
return completed values: use them directly, without await.

objectType is one of contacts, companies, deals, tickets, notes, tasks, calls, meetings or emails.
A record is {id, properties, createdAt, updatedAt, archived, associations?}. HubSpot returns only
a few default properties unless properties names more, so list every property needed; values are
strings (numbers and dates too) or null. listProperties gives an object type's property names,
types and allowed options. Record, owner, pipeline and stage IDs are strings.

Lists return one page: while paging.next.after is present, pass it back unchanged as after.
results is always an array. Example: local page = hubspot.listObjects({objectType = "contacts",
limit = 100, properties = {"email", "firstname"}}); for the next page, repeat the call with the
same options plus after = page.paging.next.after.

searchObjects filters and sorts records (see the search topic). New or changed records take a
moment to appear in search, archived records never do, a query stops at 10,000 results, and
search allows 5 requests per second per account.

Rate limits: signing in with HubSpot allows 110 requests per 10 seconds per HubSpot account,
shared by every Houston connection to it; an access token allows 100 to 190 per 10 seconds per
key or app, plus a daily quota. Prefer batchReadObjects, batchReadAssociations and searchObjects
to loops of single reads. Houston itself retries only a short 429 wait.

Errors read 'HubSpot HTTP <status> (<category>): <message>', for example
'HubSpot HTTP 400 (VALIDATION_ERROR): Property values were not valid'. 429 (except the daily
limit), 423 and 477 are retryable, and so are server errors on reads. A missing permission is a
403 (MISSING_SCOPES) naming the scopes needed ('needs one of: ...'): the account admin must add
the scope to the service key or app, or reconnect. A 401 means the token is invalid or revoked.]]
		.. (if config.access == "read-write" then [[


Writes: createObject is not idempotent, and a failed or timed-out call may still have created the
record, so search for it before repeating. updateObject changes only the named properties. A
deal moves between stages through updateObject with dealstage (plus pipeline when the pipeline
changes), a ticket with hs_pipeline_stage (plus hs_pipeline). Notes and tasks are records created
with createObject and need hs_timestamp (see the activities topic). deleteAssociation removes every
association between two records and deletes neither record. Server errors on writes are not
retryable: check the record before repeating the call.]] else ""),
	functions = {} :: {[string]: any},
	sections = {
		search = [[searchObjects body fields: query (text searched in the default text properties), filterGroups,
sorts, properties, limit (1 to 200) and after. filterGroups are ORed and the filters inside one
group are ANDed: at most 5 groups, 6 filters per group and 18 filters in all. A filter is
{propertyName, operator, value} where operator is EQ, NEQ, LT, LTE, GT, GTE, HAS_PROPERTY,
NOT_HAS_PROPERTY, CONTAINS_TOKEN or NOT_CONTAINS_TOKEN (value may use * as a wildcard, as in
"*@example.com"); BETWEEN takes value and highValue; IN and NOT_IN take values, an array, which
must be lowercase for string properties. Values are strings; dates may be epoch milliseconds or
ISO 8601. The pseudo-property associations.{type}, with a singular type such as
associations.contact or associations.company, finds records associated with that record ID.
sorts holds one rule, {propertyName, direction = "ASCENDING" | "DESCENDING"}; results default to
creation order. Example:
hubspot.searchObjects({objectType = "deals", filterGroups = {{filters = {
  {propertyName = "dealstage", operator = "EQ", value = "contractsent"},
  {propertyName = "amount", operator = "GTE", value = "10000"}}}},
  sorts = {{propertyName = "closedate", direction = "ASCENDING"}}, properties = {"dealname", "amount"}})]],
		associations = [[Associations link two records. Every pair has a default, unlabelled association; labels add
meaning, such as a primary company or a custom label like Decision maker. An association type is
{associationCategory, associationTypeId}: HUBSPOT_DEFINED for HubSpot's own types, USER_DEFINED
for an account's custom labels (listAssociationLabels gives each pair's typeId values and labels).
Type IDs depend on direction: contact to company is 279 (primary 1), company to contact 280.
HUBSPOT_DEFINED type IDs from HubSpot's documentation:
contact to company 279 (primary 1), deal 4, ticket 15, call 193, email 197, meeting 199, note 201, task 203;
company to contact 280 (primary contact 2), deal 342 (primary 6), ticket 340 (primary 25), call 181,
email 185, meeting 187, note 189, task 191;
deal to contact 3, company 341 (primary 5), ticket 27, call 205, email 209, meeting 211, note 213, task 215;
ticket to contact 16, company 339 (primary 26), deal 28, call 219, email 223, meeting 225, note 227, task 229;
call to contact 194, company 182, deal 206, ticket 220;
email to contact 198, company 186, deal 210, ticket 224;
meeting to contact 200, company 188, deal 212, ticket 226;
note to contact 202, company 190, deal 214, ticket 228;
task to contact 204, company 192, deal 216, ticket 230.
listAssociations reads one record's associations of one type; batchReadAssociations reads them
for up to 1,000 records; listObjects and getObject also return associated IDs with
associations = {"companies"}.]] .. (if config.access == "read-write" then [[

createDefaultAssociation links two records without a label. createAssociation sets labelled types
on a pair: the types sent replace the pair's existing labels, so include every label to keep.
createObject can link a new record at creation with associations = {{to = {id}, types}}.
deleteAssociation removes every association between the two records.]] else ""),
		activities = [[Notes, tasks, calls, meetings and emails (logged one-to-one emails) are object types like
contacts. Useful properties:
notes: hs_timestamp (required: its position on the timeline, ISO 8601 UTC or epoch milliseconds),
hs_note_body (at most 65,536 characters), hubspot_owner_id, hs_attachment_ids.
tasks: hs_timestamp (required: the due date), hs_task_subject, hs_task_body, hs_task_status
(NOT_STARTED or COMPLETED), hs_task_priority (LOW, MEDIUM or HIGH), hs_task_type (EMAIL, CALL or
TODO), hubspot_owner_id, hs_task_reminders (epoch milliseconds).
calls: hs_timestamp, hs_call_title, hs_call_body, hs_call_direction, hs_call_duration,
hs_call_status. meetings: hs_timestamp, hs_meeting_title, hs_meeting_body, hs_meeting_start_time,
hs_meeting_end_time, hs_meeting_outcome. emails: hs_timestamp, hs_email_subject, hs_email_text,
hs_email_direction, hs_email_status; reading email content needs HubSpot's sales-email-read
permission.
To read one record's activities, call listAssociations (for example from a contact to notes),
then batchReadObjects on the returned toObjectId values (as strings) with the properties above;
or searchObjects on the activity type with a filter on associations.contact.
hubspot_owner_id holds an owner id from listOwners.]] .. (if config.access == "read-write" then [[

Create an activity with createObject and associations to the records it concerns, for example a
note on contact 101: createObject({objectType = "notes", properties = {hs_timestamp =
"2026-11-13T10:00:00Z", hs_note_body = "Called about renewal."}, associations = {{to = {id = "101"},
types = {{associationCategory = "HUBSPOT_DEFINED", associationTypeId = 202}}}}}). Complete a task
with updateObject and hs_task_status = "COMPLETED".]] else ""),
	},
}
local exports: {[string]: any} = {help = help}

-- Schemas and hints shared by several operations.
local OBJECT_TYPE = {type = "string", enum = OBJECT_TYPES}
local RECORD_ID = {type = "string", pattern = "^[0-9]+$", description = "A record ID, as a string."}
local LOOKUP_ID = {type = "string", minLength = 1, description = "A record ID, as a string, or with idProperty that property's value."}
local ID_PROPERTY = {type = "string", minLength = 1, description = "A unique property, such as email for contacts, whose value objectId holds instead of the record ID."}
local AFTER = {type = "string", minLength = 1, description = "paging.next.after from the previous page."}
local function nameList(description: string): Options
	return {type = "array", items = {type = "string", pattern = "^[^,]+$"}, minItems = 1, maxItems = MAX_NAMES, description = description}
end
local PROPERTY_NAMES = nameList("Property internal names to return; without it HubSpot returns only a few defaults.")
local HISTORY_NAMES = nameList("Properties to return with their previous values, in propertiesWithHistory.")
local ASSOCIATED = {type = "array", items = OBJECT_TYPE, minItems = 1, maxItems = MAX_NAMES,
	description = "Object types whose associated record IDs to include in each record's associations."}
local ARCHIVED = {type = "boolean", description = "true returns only archived (deleted) items."}
local ASSOCIATION_TYPES = {type = "array", minItems = 1, maxItems = MAX_LINKS, items = {
	type = "object",
	properties = {associationCategory = {type = "string", enum = CATEGORIES}, associationTypeId = {type = "integer", minimum = 1, maximum = 2147483647}},
	required = {"associationCategory", "associationTypeId"},
	additionalProperties = false,
}}
local PROPERTIES = {type = "object", minProperties = 1, additionalProperties = {type = {"string", "number", "boolean"}},
	description = "Property internal names and values; an empty string clears a value."}
local READ = {readOnlyHint = true, openWorldHint = true}
local WRITE = {readOnlyHint = false, destructiveHint = false, openWorldHint = true}
local LINK = {readOnlyHint = false, destructiveHint = false, idempotentHint = true, openWorldHint = true}
local DESTRUCTIVE = {readOnlyHint = false, destructiveHint = true, idempotentHint = true, openWorldHint = true}

help.functions.listObjects = {
	description = [[One page of records of objectType, oldest first: {results = {record}, paging = {next = {after}}?}.
limit is 1 to 100 (HubSpot's default is 10). properties names the properties to return, beyond a
few defaults; associations adds each record's associated IDs of those types. archived = true
lists only archived records.]],
	inputSchema = {
		type = "object",
		properties = {objectType = OBJECT_TYPE, limit = {type = "integer", minimum = 1, maximum = 100}, after = AFTER,
			properties = PROPERTY_NAMES, propertiesWithHistory = HISTORY_NAMES, associations = ASSOCIATED, archived = ARCHIVED},
		required = {"objectType"},
		additionalProperties = false,
		examples = {
			{objectType = "contacts", limit = 50, properties = {"email", "firstname", "lastname"}},
			{objectType = "deals", after = "9876", associations = {"contacts", "companies"}},
		} :: {any},
	},
	annotations = READ,
}
function exports.listObjects(input: any): Options
	local args = options(input)
	local kind = oneOf(take(args, "objectType"), "objectType", OBJECT_TYPES)
	local q = query(args, {"limit", "after", "properties", "propertiesWithHistory", "associations", "archived"}, 100)
	done("listObjects", args)
	return results(call("listObjects", "GET", objects(kind) .. q, nil, false))
end

help.functions.getObject = {
	description = [[One record: {id, properties, createdAt, updatedAt, archived, associations?, propertiesWithHistory?}.
objectId is the record ID, or with idProperty the value of that unique property, such as a
contact's email with idProperty = "email". properties names the properties to return beyond a few
defaults; associations adds associated record IDs of those types.]],
	inputSchema = {
		type = "object",
		properties = {objectType = OBJECT_TYPE, objectId = LOOKUP_ID, idProperty = ID_PROPERTY, properties = PROPERTY_NAMES,
			propertiesWithHistory = HISTORY_NAMES, associations = ASSOCIATED, archived = ARCHIVED},
		required = {"objectType", "objectId"},
		additionalProperties = false,
		examples = {
			{objectType = "companies", objectId = "512", properties = {"name", "domain"}},
			{objectType = "contacts", objectId = "ana@example.com", idProperty = "email"},
		} :: {any},
	},
	annotations = READ,
}
function exports.getObject(input: any): Options
	local args = options(input)
	local kind = oneOf(take(args, "objectType"), "objectType", OBJECT_TYPES)
	local id = recordId(take(args, "objectId"), "objectId", args.idProperty ~= nil)
	local q = query(args, {"idProperty", "properties", "propertiesWithHistory", "associations", "archived"})
	done("getObject", args)
	return call("getObject", "GET", objects(kind) .. "/" .. id .. q, nil, false)
end

help.functions.searchObjects = {
	description = [[Searches records of objectType: {total, results = {record}, paging = {next = {after}}?}. Every
field except objectType goes to HubSpot unchanged; see the search topic for filters and operators.
filterGroups holds at most 5 groups ({filters = {...}}, at most 6 each and 18 in all), sorts one
rule, limit 1 to 200 (default 10). Search is eventually consistent, excludes archived records,
stops at 10,000 results and allows 5 requests per second per account.]],
	inputSchema = {
		type = "object",
		properties = {
			objectType = OBJECT_TYPE,
			query = {type = "string", minLength = 1, description = "Text searched in the default text properties."},
			filterGroups = {type = "array", minItems = 1, maxItems = 5, items = {
				type = "object",
				properties = {filters = {type = "array", minItems = 1, maxItems = 6, items = {
					type = "object",
					properties = {propertyName = {type = "string", minLength = 1}, operator = {type = "string", enum = {"EQ", "NEQ", "LT", "LTE", "GT", "GTE", "BETWEEN", "IN", "NOT_IN", "HAS_PROPERTY", "NOT_HAS_PROPERTY", "CONTAINS_TOKEN", "NOT_CONTAINS_TOKEN"}},
						value = {type = "string"}, highValue = {type = "string"}, values = {type = "array", items = {type = "string"}}},
					required = {"propertyName", "operator"},
				}}},
				required = {"filters"},
				additionalProperties = false,
			}},
			sorts = {type = "array", minItems = 1, maxItems = 1, items = {
				type = "object",
				properties = {propertyName = {type = "string", minLength = 1}, direction = {type = "string", enum = {"ASCENDING", "DESCENDING"}}},
				required = {"propertyName"},
			}},
			properties = PROPERTY_NAMES,
			limit = {type = "integer", minimum = 1, maximum = 200},
			after = AFTER,
		},
		required = {"objectType"},
		additionalProperties = false,
		examples = {
			{objectType = "contacts", filterGroups = {{filters = {{propertyName = "email", operator = "CONTAINS_TOKEN", value = "*@example.com"}}}}, limit = 20},
			{objectType = "deals", filterGroups = {{filters = {{propertyName = "dealstage", operator = "EQ", value = "contractsent"},
				{propertyName = "amount", operator = "GTE", value = "10000"}}}}, sorts = {{propertyName = "closedate", direction = "ASCENDING"}},
				properties = {"dealname", "amount", "closedate"}},
			{objectType = "notes", filterGroups = {{filters = {{propertyName = "associations.contact", operator = "EQ", value = "101"}}}},
				properties = {"hs_note_body", "hs_timestamp"}},
		} :: {any},
	},
	annotations = READ,
}
function exports.searchObjects(input: any): Options
	local args = options(input)
	local kind = oneOf(take(args, "objectType"), "objectType", OBJECT_TYPES)
	local body: Options = {}
	if args.query ~= nil then body.query = text(take(args, "query"), "query") end
	if args.filterGroups ~= nil then
		local groups = array(take(args, "filterGroups"), "filterGroups", 5)
		local total = 0
		for index, group in groups do
			local field = "filterGroups[" .. tostring(index) .. "]"
			assert(type(group) == "table", field .. " must be an object")
			for key in group do assert(key == "filters", field .. " received an unknown field " .. tostring(key)) end
			for position, filter in array(group.filters, field .. ".filters", 6) do
				assert(type(filter) == "table", field .. ".filters[" .. tostring(position) .. "] must be an object")
				total += 1
			end
		end
		assert(total <= 18, "filterGroups may hold at most 18 filters in all")
		body.filterGroups = groups
	end
	if args.sorts ~= nil then body.sorts = array(take(args, "sorts"), "sorts", 1) end
	if args.properties ~= nil then body.properties = names(take(args, "properties"), "properties") end
	if args.limit ~= nil then body.limit = integer(take(args, "limit"), "limit", 1, 200) end
	if args.after ~= nil then body.after = text(take(args, "after"), "after") end
	done("searchObjects", args)
	return results(call("searchObjects", "POST", objects(kind) .. "/search", body, false))
end

help.functions.batchReadObjects = {
	description = [[Reads up to 100 records of objectType at once: {status, results = {record}, numErrors?, errors?}.
inputs are {{id}}: record IDs, or with idProperty values of that unique property. IDs that do not
exist are reported in errors (HTTP 207) while the others are returned. properties names the
properties to return beyond a few defaults.]],
	inputSchema = {
		type = "object",
		properties = {
			objectType = OBJECT_TYPE,
			inputs = {type = "array", minItems = 1, maxItems = 100, items = {
				type = "object", properties = {id = LOOKUP_ID}, required = {"id"}, additionalProperties = false,
			}},
			idProperty = ID_PROPERTY, properties = PROPERTY_NAMES, propertiesWithHistory = HISTORY_NAMES, archived = ARCHIVED,
		},
		required = {"objectType", "inputs"},
		additionalProperties = false,
		examples = {{objectType = "contacts", inputs = {{id = "101"}, {id = "102"}}, properties = {"email"}}},
	},
	annotations = READ,
}
function exports.batchReadObjects(input: any): Options
	local args = options(input)
	local kind = oneOf(take(args, "objectType"), "objectType", OBJECT_TYPES)
	local idProperty = take(args, "idProperty")
	local body: Options = {inputs = {}}
	for index, item in array(take(args, "inputs"), "inputs", 100) do
		local field = "inputs[" .. tostring(index) .. "]"
		assert(type(item) == "table", field .. " must be an object")
		for key in item do assert(key == "id", field .. " received an unknown field " .. tostring(key)) end
		idValue(item.id, field .. ".id", idProperty ~= nil)
		table.insert(body.inputs, {id = item.id})
	end
	if idProperty ~= nil then body.idProperty = text(idProperty, "idProperty") end
	if args.properties ~= nil then body.properties = names(take(args, "properties"), "properties") end
	if args.propertiesWithHistory ~= nil then body.propertiesWithHistory = names(take(args, "propertiesWithHistory"), "propertiesWithHistory") end
	local q = query(args, {"archived"})
	done("batchReadObjects", args)
	return results(call("batchReadObjects", "POST", objects(kind) .. "/batch/read" .. q, body, false))
end

help.functions.listAssociations = {
	description = [[One page of the records of toObjectType associated with one record:
{results = {{toObjectId, associationTypes = {{category, typeId, label}}}}, paging?}. toObjectId is a
number; pass it as a string to other operations. limit is 1 to 500 (the default).]],
	inputSchema = {
		type = "object",
		properties = {objectType = OBJECT_TYPE, objectId = RECORD_ID, toObjectType = OBJECT_TYPE,
			limit = {type = "integer", minimum = 1, maximum = 500}, after = AFTER},
		required = {"objectType", "objectId", "toObjectType"},
		additionalProperties = false,
		examples = {{objectType = "deals", objectId = "9876", toObjectType = "contacts"}},
	},
	annotations = READ,
}
function exports.listAssociations(input: any): Options
	local args = options(input)
	local kind = oneOf(take(args, "objectType"), "objectType", OBJECT_TYPES)
	local id = recordId(take(args, "objectId"), "objectId")
	local to = oneOf(take(args, "toObjectType"), "toObjectType", OBJECT_TYPES)
	local q = query(args, {"limit", "after"}, 500)
	done("listAssociations", args)
	return results(call("listAssociations", "GET", objects(kind) .. "/" .. id .. "/associations/" .. to .. q, nil, false))
end

help.functions.batchReadAssociations = {
	description = [[Reads the toObjectType associations of up to 1,000 records of fromObjectType:
{status, results = {{from = {id}, to = {{toObjectId, associationTypes}}, paging?}}, errors?}.
inputs are {{id, after?}}; after continues one record's associations from its paging.next.after.]],
	inputSchema = {
		type = "object",
		properties = {
			fromObjectType = OBJECT_TYPE, toObjectType = OBJECT_TYPE,
			inputs = {type = "array", minItems = 1, maxItems = 1000, items = {
				type = "object", properties = {id = RECORD_ID, after = AFTER}, required = {"id"}, additionalProperties = false,
			}},
		},
		required = {"fromObjectType", "toObjectType", "inputs"},
		additionalProperties = false,
		examples = {{fromObjectType = "deals", toObjectType = "companies", inputs = {{id = "9876"}, {id = "9877"}}}},
	},
	annotations = READ,
}
function exports.batchReadAssociations(input: any): Options
	local args = options(input)
	local from = oneOf(take(args, "fromObjectType"), "fromObjectType", OBJECT_TYPES)
	local to = oneOf(take(args, "toObjectType"), "toObjectType", OBJECT_TYPES)
	local inputs: {Options} = {}
	for index, item in array(take(args, "inputs"), "inputs", 1000) do
		local field = "inputs[" .. tostring(index) .. "]"
		assert(type(item) == "table", field .. " must be an object")
		for key in item do assert(key == "id" or key == "after", field .. " received an unknown field " .. tostring(key)) end
		idValue(item.id, field .. ".id")
		table.insert(inputs, {id = item.id, after = if item.after ~= nil then text(item.after, field .. ".after") else nil})
	end
	done("batchReadAssociations", args)
	return results(call("batchReadAssociations", "POST", "/crm/associations/2026-09/" .. from .. "/" .. to .. "/batch/read", {inputs = inputs}, false))
end

help.functions.listAssociationLabels = {
	description = [[The association types from fromObjectType to toObjectType in this account, HubSpot's and
custom labels: {results = {{category, typeId, label}}}. label is null for the default type.]],
	inputSchema = {
		type = "object",
		properties = {fromObjectType = OBJECT_TYPE, toObjectType = OBJECT_TYPE},
		required = {"fromObjectType", "toObjectType"},
		additionalProperties = false,
		examples = {{fromObjectType = "contacts", toObjectType = "companies"}},
	},
	annotations = READ,
}
function exports.listAssociationLabels(input: any): Options
	local args = options(input)
	local from = oneOf(take(args, "fromObjectType"), "fromObjectType", OBJECT_TYPES)
	local to = oneOf(take(args, "toObjectType"), "toObjectType", OBJECT_TYPES)
	done("listAssociationLabels", args)
	return results(call("listAssociationLabels", "GET", "/crm/associations/2026-09/" .. from .. "/" .. to .. "/labels", nil, false))
end

help.functions.listPipelines = {
	description = [[Every deal or ticket pipeline with its stages: {results = {{id, label, displayOrder, archived,
stages = {{id, label, displayOrder, metadata}}}}}. Stage IDs are what a deal's dealstage and a
ticket's hs_pipeline_stage hold; pipeline IDs are what pipeline and hs_pipeline hold. For deals,
stage metadata.probability is the win probability; for tickets, metadata.ticketState is OPEN or
CLOSED.]],
	inputSchema = {
		type = "object",
		properties = {objectType = {type = "string", enum = PIPELINE_TYPES}},
		required = {"objectType"},
		additionalProperties = false,
		examples = {{objectType = "deals"}},
	},
	annotations = READ,
}
function exports.listPipelines(input: any): Options
	local args = options(input)
	local kind = oneOf(take(args, "objectType"), "objectType", PIPELINE_TYPES)
	done("listPipelines", args)
	return results(call("listPipelines", "GET", "/crm/pipelines/2026-09/" .. kind, nil, false))
end

help.functions.getPipeline = {
	description = [[One deal or ticket pipeline: {id, label, displayOrder, archived, stages = {{id, label,
displayOrder, metadata}}}. The default pipeline's ID is often "default" for deals and "0" for tickets.]],
	inputSchema = {
		type = "object",
		properties = {objectType = {type = "string", enum = PIPELINE_TYPES}, pipelineId = {type = "string", minLength = 1}},
		required = {"objectType", "pipelineId"},
		additionalProperties = false,
		examples = {{objectType = "tickets", pipelineId = "0"}},
	},
	annotations = READ,
}
function exports.getPipeline(input: any): Options
	local args = options(input)
	local kind = oneOf(take(args, "objectType"), "objectType", PIPELINE_TYPES)
	local id = url.segment(text(take(args, "pipelineId"), "pipelineId"), "pipelineId")
	done("getPipeline", args)
	return call("getPipeline", "GET", "/crm/pipelines/2026-09/" .. kind .. "/" .. id, nil, false)
end

help.functions.listOwners = {
	description = [[One page of the account's owners, the users and teams records can be assigned to:
{results = {{id, email, firstName, lastName, userId, type, teams}}, paging?}. An owner's id is what
hubspot_owner_id holds on records; userId is the HubSpot user's ID. email finds one owner. limit
is 1 to 500 (default 100).]],
	inputSchema = {
		type = "object",
		properties = {email = {type = "string", minLength = 1}, limit = {type = "integer", minimum = 1, maximum = 500}, after = AFTER, archived = ARCHIVED},
		additionalProperties = false,
		examples = {{}, {email = "ana@example.com"}} :: {any},
	},
	annotations = READ,
}
function exports.listOwners(input: any): Options
	local args = options(input)
	local q = query(args, {"email", "limit", "after", "archived"}, 500)
	done("listOwners", args)
	return results(call("listOwners", "GET", "/crm/owners/2026-09" .. q, nil, false))
end

help.functions.getOwner = {
	description = [[One owner: {id, email, firstName, lastName, userId, type ("PERSON" or "QUEUE"), teams, archived}.
ownerId is the owner's id, or its userId with idProperty = "userId".]],
	inputSchema = {
		type = "object",
		properties = {ownerId = {type = "string", pattern = "^[0-9]+$"}, idProperty = {type = "string", enum = {"id", "userId"}}, archived = ARCHIVED},
		required = {"ownerId"},
		additionalProperties = false,
		examples = {{ownerId = "41629779"}},
	},
	annotations = READ,
}
function exports.getOwner(input: any): Options
	local args = options(input)
	local id = recordId(take(args, "ownerId"), "ownerId")
	if args.idProperty ~= nil then oneOf(args.idProperty, "idProperty", {"id", "userId"}) end
	local q = query(args, {"idProperty", "archived"})
	done("getOwner", args)
	return call("getOwner", "GET", "/crm/owners/2026-09/" .. id .. q, nil, false)
end

help.functions.listProperties = {
	description = [[Every property definition of objectType: {results = {{name, label, type, fieldType,
groupName, description, options = {{label, value}}, calculated, hasUniqueValue, hidden, ...}}}.
name is the internal name that properties lists and writes use; for enumerations, options give
the values a property accepts (such as lifecyclestage or hs_task_status).]],
	inputSchema = {
		type = "object",
		properties = {objectType = OBJECT_TYPE, archived = ARCHIVED},
		required = {"objectType"},
		additionalProperties = false,
		examples = {{objectType = "deals"}},
	},
	annotations = READ,
}
function exports.listProperties(input: any): Options
	local args = options(input)
	local kind = oneOf(take(args, "objectType"), "objectType", OBJECT_TYPES)
	local q = query(args, {"archived"})
	done("listProperties", args)
	return results(call("listProperties", "GET", "/crm/properties/2026-09/" .. kind .. q, nil, false))
end

help.functions.getProperty = {
	description = [[One property definition: {name, label, type, fieldType, groupName, description, options, ...}.]],
	inputSchema = {
		type = "object",
		properties = {objectType = OBJECT_TYPE, propertyName = {type = "string", pattern = "^[A-Za-z0-9_]+$"}, archived = ARCHIVED},
		required = {"objectType", "propertyName"},
		additionalProperties = false,
		examples = {{objectType = "tasks", propertyName = "hs_task_status"}},
	},
	annotations = READ,
}
function exports.getProperty(input: any): Options
	local args = options(input)
	local kind = oneOf(take(args, "objectType"), "objectType", OBJECT_TYPES)
	local name = take(args, "propertyName")
	assert(type(name) == "string" and string.match(name, "^[%w_]+$") ~= nil, "propertyName must be a property's internal name")
	local q = query(args, {"archived"})
	done("getProperty", args)
	return call("getProperty", "GET", "/crm/properties/2026-09/" .. kind .. "/" .. name .. q, nil, false)
end

if config.access == "read-write" then
	help.functions.createObject = {
		description = [[Creates a record of objectType and returns it (HTTP 201). properties sets property values by
internal name; associations links the new record, each {to = {id}, types = {{associationCategory,
associationTypeId}}} (see the associations topic for type IDs). Notes and tasks need hs_timestamp.
HubSpot refuses a contact whose email already exists (409). Not idempotent: a failed or timed-out
call may still have created the record, so search for it before repeating.]],
		inputSchema = {
			type = "object",
			properties = {
				objectType = OBJECT_TYPE, properties = PROPERTIES,
				associations = {type = "array", minItems = 1, maxItems = MAX_LINKS, items = {
					type = "object",
					properties = {
						to = {type = "object", properties = {id = RECORD_ID}, required = {"id"}, additionalProperties = false},
						types = ASSOCIATION_TYPES,
					},
					required = {"to", "types"},
					additionalProperties = false,
				}},
			},
			required = {"objectType", "properties"},
			additionalProperties = false,
			examples = {
				{objectType = "contacts", properties = {email = "ana@example.com", firstname = "Ana", lastname = "Silva"}},
				{objectType = "notes", properties = {hs_timestamp = "2026-11-13T10:00:00Z", hs_note_body = "Called about renewal."},
					associations = {{to = {id = "101"}, types = {{associationCategory = "HUBSPOT_DEFINED", associationTypeId = 202}}}}},
				{objectType = "tasks", properties = {hs_timestamp = "2026-11-20T09:00:00Z", hs_task_subject = "Send contract",
					hs_task_status = "NOT_STARTED", hs_task_priority = "HIGH", hs_task_type = "TODO"},
					associations = {{to = {id = "9876"}, types = {{associationCategory = "HUBSPOT_DEFINED", associationTypeId = 216}}}}},
			} :: {any},
		},
		annotations = WRITE,
	}
	function exports.createObject(input: any): Options
		local args = options(input)
		local kind = oneOf(take(args, "objectType"), "objectType", OBJECT_TYPES)
		local body: Options = {properties = properties(take(args, "properties"))}
		if args.associations ~= nil then
			body.associations = {}
			for index, item in array(take(args, "associations"), "associations", MAX_LINKS) do
				local field = "associations[" .. tostring(index) .. "]"
				assert(type(item) == "table", field .. " must be an object")
				for key in item do assert(key == "to" or key == "types", field .. " received an unknown field " .. tostring(key)) end
				local to = item.to
				assert(type(to) == "table", field .. ".to must be {id}")
				for key in to do assert(key == "id", field .. ".to received an unknown field " .. tostring(key)) end
				idValue(to.id, field .. ".to.id")
				table.insert(body.associations, {to = {id = to.id}, types = associationTypes(item.types, field .. ".types")})
			end
		end
		done("createObject", args)
		return call("createObject", "POST", objects(kind), body, true)
	end

	help.functions.updateObject = {
		description = [[Changes the named properties of a record and returns it; other properties keep their values,
and an empty string clears one. objectId is the record ID, or with idProperty that unique
property's value. Move a deal with dealstage (a stage ID from listPipelines), adding pipeline when
the stage belongs to another pipeline; move a ticket with hs_pipeline_stage (and hs_pipeline).]],
		inputSchema = {
			type = "object",
			properties = {objectType = OBJECT_TYPE, objectId = LOOKUP_ID, properties = PROPERTIES, idProperty = ID_PROPERTY},
			required = {"objectType", "objectId", "properties"},
			additionalProperties = false,
			examples = {
				{objectType = "deals", objectId = "9876", properties = {dealstage = "closedwon"}},
				{objectType = "deals", objectId = "9876", properties = {pipeline = "renewals", dealstage = "1234567"}},
				{objectType = "contacts", objectId = "ana@example.com", idProperty = "email", properties = {jobtitle = "CTO"}},
			} :: {any},
		},
		annotations = WRITE,
	}
	function exports.updateObject(input: any): Options
		local args = options(input)
		local kind = oneOf(take(args, "objectType"), "objectType", OBJECT_TYPES)
		local id = recordId(take(args, "objectId"), "objectId", args.idProperty ~= nil)
		local body = {properties = properties(take(args, "properties"))}
		local q = query(args, {"idProperty"})
		done("updateObject", args)
		return call("updateObject", "PATCH", objects(kind) .. "/" .. id .. q, body, true)
	end

	help.functions.createDefaultAssociation = {
		description = [[Links two records with HubSpot's default, unlabelled association, in both directions:
{status, results = {{from, to, associationSpec}}}. Repeating it changes nothing.]],
		inputSchema = {
			type = "object",
			properties = {fromObjectType = OBJECT_TYPE, fromObjectId = RECORD_ID, toObjectType = OBJECT_TYPE, toObjectId = RECORD_ID},
			required = {"fromObjectType", "fromObjectId", "toObjectType", "toObjectId"},
			additionalProperties = false,
			examples = {{fromObjectType = "contacts", fromObjectId = "101", toObjectType = "companies", toObjectId = "512"}},
		},
		annotations = LINK,
	}
	function exports.createDefaultAssociation(input: any): Options
		local args = options(input)
		local from = oneOf(take(args, "fromObjectType"), "fromObjectType", OBJECT_TYPES)
		local fromId = recordId(take(args, "fromObjectId"), "fromObjectId")
		local to = oneOf(take(args, "toObjectType"), "toObjectType", OBJECT_TYPES)
		local toId = recordId(take(args, "toObjectId"), "toObjectId")
		done("createDefaultAssociation", args)
		return call("createDefaultAssociation", "PUT", objects(from) .. "/" .. fromId .. "/associations/default/" .. to .. "/" .. toId, "", true)
	end

	help.functions.createAssociation = {
		description = [[Sets labelled association types between two records: {fromObjectTypeId, fromObjectId,
toObjectTypeId, toObjectId, labels}. types replaces the labels the pair already has, so include
every label to keep. Type IDs depend on direction; see the associations topic and
listAssociationLabels.]],
		inputSchema = {
			type = "object",
			properties = {objectType = OBJECT_TYPE, objectId = RECORD_ID, toObjectType = OBJECT_TYPE, toObjectId = RECORD_ID, types = ASSOCIATION_TYPES},
			required = {"objectType", "objectId", "toObjectType", "toObjectId", "types"},
			additionalProperties = false,
			examples = {{objectType = "contacts", objectId = "101", toObjectType = "companies", toObjectId = "512",
				types = {{associationCategory = "HUBSPOT_DEFINED", associationTypeId = 1}}}},
		},
		annotations = LINK,
	}
	function exports.createAssociation(input: any): Options
		local args = options(input)
		local kind = oneOf(take(args, "objectType"), "objectType", OBJECT_TYPES)
		local id = recordId(take(args, "objectId"), "objectId")
		local to = oneOf(take(args, "toObjectType"), "toObjectType", OBJECT_TYPES)
		local toId = recordId(take(args, "toObjectId"), "toObjectId")
		local types = associationTypes(take(args, "types"), "types")
		done("createAssociation", args)
		return call("createAssociation", "PUT", objects(kind) .. "/" .. id .. "/associations/" .. to .. "/" .. toId, types, true)
	end

	help.functions.deleteAssociation = {
		description = [[Removes every association between two records, labelled or not, and returns {success = true}.
Neither record is deleted; createDefaultAssociation or createAssociation links them again.]],
		inputSchema = {
			type = "object",
			properties = {objectType = OBJECT_TYPE, objectId = RECORD_ID, toObjectType = OBJECT_TYPE, toObjectId = RECORD_ID},
			required = {"objectType", "objectId", "toObjectType", "toObjectId"},
			additionalProperties = false,
			examples = {{objectType = "contacts", objectId = "101", toObjectType = "companies", toObjectId = "512"}},
		},
		annotations = DESTRUCTIVE,
	}
	function exports.deleteAssociation(input: any): Options
		local args = options(input)
		local kind = oneOf(take(args, "objectType"), "objectType", OBJECT_TYPES)
		local id = recordId(take(args, "objectId"), "objectId")
		local to = oneOf(take(args, "toObjectType"), "toObjectType", OBJECT_TYPES)
		local toId = recordId(take(args, "toObjectId"), "toObjectId")
		done("deleteAssociation", args)
		return call("deleteAssociation", "DELETE", objects(kind) .. "/" .. id .. "/associations/" .. to .. "/" .. toId, nil, true)
	end
end

return exports
