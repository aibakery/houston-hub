local connector_http = require("lib/http.lua")
-- Google Calendar connector: read calendars and events through Houston's HTTP proxy.
-- Host primitives used: private http.request and json.

local BASE = "https://www.googleapis.com/calendar/v3"

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

local function request(method: any,path: any,params: any,operation: any,cursor: any,body: any)
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

		affected_cursor = cursor,
	})
end

local function list_calendar_params(opts: any)
	opts = opts or {}
	return {
		maxResults = opts.maxResults,
		pageToken = opts.pageToken,
		minAccessRole = opts.minAccessRole,
		showDeleted = opts.showDeleted,
		showHidden = opts.showHidden,
	}
end

local function list_event_params(opts: any)
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

local function get_event_params(opts: any)
	opts = opts or {}
	return {
		timeZone = opts.timeZone,
	}
end

local functions = {}

function functions.listCalendars(opts: any)
	return request("GET", "/users/me/calendarList", list_calendar_params(opts), "listCalendars")
end

function functions.listEvents(calendarId: any,opts: any)
	if type(calendarId) == "table" then
		opts = calendarId
		calendarId = calendarId.calendarId
	end
	if type(calendarId) ~= "string" or calendarId == "" then
		error("gcalendar.listEvents requires a calendar id")
	end
	return request("GET", "/calendars/" .. encode(calendarId) .. "/events", list_event_params(opts), "listEvents")
end

function functions.getEvent(calendarId: any,eventId: any,opts: any)
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
		"GET",
		"/calendars/" .. encode(calendarId) .. "/events/" .. encode(eventId),
		get_event_params(opts),
		"getEvent",
		eventId
	)
end

local writes = {}

function writes.insertEvent(calendarId: any,event: any)
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
	return request("POST", "/calendars/" .. encode(calendarId) .. "/events", nil, "insertEvent", nil, event)
end

function writes.deleteEvent(calendarId: any,eventId: any)
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
		"DELETE",
		"/calendars/" .. encode(calendarId) .. "/events/" .. encode(eventId),
		nil,
		"deleteEvent",
		eventId
	)
end

if config.access == "read-write" then
    for name, fn in (writes :: {[string]: any}) do (functions :: {[string]: any})[name] = fn end
end

return functions
