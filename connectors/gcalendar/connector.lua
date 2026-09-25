-- Google Calendar connector: read calendars and events through Houston's HTTP proxy.
-- Host primitives used: http.send (with this instance's connector id) and json.

local BASE = "https://www.googleapis.com/calendar/v3"

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

local function request(ctx, method, path, params, operation, cursor, body)
	if type(ctx) ~= "table" or type(ctx.id) ~= "string" or ctx.id == "" then
		error("gcalendar connector id is required")
	end
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
		connector = "gcalendar",
		operation = operation,
		method = method,
		path = path,
		url = url,
		headers = headers,
		body = payload,
		connector_id = ctx.id,
		affected_cursor = cursor,
	})
end

local function list_calendar_params(opts)
	opts = opts or {}
	return {
		maxResults = opts.maxResults,
		pageToken = opts.pageToken,
		minAccessRole = opts.minAccessRole,
		showDeleted = opts.showDeleted,
		showHidden = opts.showHidden,
	}
end

local function list_event_params(opts)
	opts = opts or {}
	return {
		timeMin = opts.timeMin,
		timeMax = opts.timeMax,
		maxResults = opts.maxResults,
		pageToken = opts.pageToken,
		q = opts.q,
		singleEvents = opts.singleEvents,
		orderBy = opts.orderBy,
		timeZone = opts.timeZone,
	}
end

local function get_event_params(opts)
	opts = opts or {}
	return {
		timeZone = opts.timeZone,
	}
end

local functions = {}

function functions.listCalendars(ctx, opts)
	return request(ctx, "GET", "/users/me/calendarList", list_calendar_params(opts), "listCalendars")
end

function functions.listEvents(ctx, calendarId, opts)
	if type(calendarId) == "table" then
		opts = calendarId
		calendarId = calendarId.calendarId
	end
	if type(calendarId) ~= "string" or calendarId == "" then
		error("gcalendar.listEvents requires a calendar id")
	end
	return request(ctx, "GET", "/calendars/" .. encode(calendarId) .. "/events", list_event_params(opts), "listEvents")
end

function functions.getEvent(ctx, calendarId, eventId, opts)
	if type(calendarId) == "table" then
		opts = calendarId
		eventId = calendarId.eventId
		calendarId = calendarId.calendarId
	end
	if type(calendarId) ~= "string" or calendarId == "" then
		error("gcalendar.getEvent requires a calendar id")
	end
	if type(eventId) ~= "string" or eventId == "" then
		error("gcalendar.getEvent requires an event id")
	end
	return request(
		ctx,
		"GET",
		"/calendars/" .. encode(calendarId) .. "/events/" .. encode(eventId),
		get_event_params(opts),
		"getEvent",
		eventId
	)
end

local writes = {}

function writes.insertEvent(ctx, calendarId, event)
	if type(calendarId) == "table" then
		event = calendarId.event or calendarId
		calendarId = calendarId.calendarId
	end
	if type(calendarId) ~= "string" or calendarId == "" then
		error("gcalendar.insertEvent requires a calendar id")
	end
	if type(event) ~= "table" then
		error("gcalendar.insertEvent requires an event body")
	end
	return request(ctx, "POST", "/calendars/" .. encode(calendarId) .. "/events", nil, "insertEvent", nil, event)
end

function writes.deleteEvent(ctx, calendarId, eventId)
	if type(calendarId) == "table" then
		eventId = calendarId.eventId
		calendarId = calendarId.calendarId
	end
	if type(calendarId) ~= "string" or calendarId == "" then
		error("gcalendar.deleteEvent requires a calendar id")
	end
	if type(eventId) ~= "string" or eventId == "" then
		error("gcalendar.deleteEvent requires an event id")
	end
	return request(
		ctx,
		"DELETE",
		"/calendars/" .. encode(calendarId) .. "/events/" .. encode(eventId),
		nil,
		"deleteEvent",
		eventId
	)
end

return {
	name = "gcalendar",
	description = "Read a connected Google Calendar account.",
	signatures = {
		listCalendars = "listCalendars(opts?)",
		listEvents = "listEvents(calendarId, opts?)",
		getEvent = "getEvent(calendarId, eventId, opts?)",
		insertEvent = "insertEvent(calendarId, event)",
		deleteEvent = "deleteEvent(calendarId, eventId)",
	},
	help = [[
# Google Calendar

Read calendars and events for one connected Google Calendar account.
Credentials stay on the Houston server; these functions only see JSON from
Calendar.

Several Calendar accounts are several instances of this connector, each
with its own `id`. Use the instance returned by `houston.connectors()` — do
not call Calendar URLs yourself.

## listCalendars(opts?)

Calendar `calendarList.list`. Optional fields on `opts`:

- `maxResults` (number)
- `pageToken` (string)
- `minAccessRole` (string)
- `showDeleted` (boolean)
- `showHidden` (boolean)

Returns `items` (`{ id, summary, ... }[]`) and `nextPageToken`.

## listEvents(calendarId, opts?)

Calendar `events.list`. `calendarId` may be a string (e.g. `"primary"`)
or a table with `calendarId`. Optional fields on `opts`:

- `timeMin` / `timeMax` (RFC3339 strings)
- `maxResults` (number)
- `pageToken` (string)
- `q` (string)
- `singleEvents` (boolean)
- `orderBy` (string)
- `timeZone` (string)

Returns `items` (`{ id, summary, start, end, ... }[]`) and
`nextPageToken`. `listEvents` already has `id`, `summary`, `start`,
and `end`. Do not `getEvent` every row unless you need extra fields
(attendees, description, conference data). Loop pagination in one
`run`.

## getEvent(calendarId, eventId, opts?)

Calendar `events.get`. `calendarId` and `eventId` may be strings, or a
table with those fields. Optional `timeZone` on `opts`.

Returns the Event resource. Use only when `listEvents` is missing a
field you need.

Write functions are bound only when this instance is read-write.

## insertEvent(calendarId, event)

Calendar `events.insert`. `calendarId` may be a string (e.g. `"primary"`)
or a table with `calendarId` and `event`. `event` is the Event resource.

## deleteEvent(calendarId, eventId)

Calendar `events.delete`. `calendarId` and `eventId` may be strings, or a
table with those fields.

## Example

	return {
		run = function()
			return c.listEvents("primary", { maxResults = 10 })
		end,
	}
]],
	functions = functions,
	writes = writes,
}
