-- Google Calendar API v3. Arguments and results keep Google's native field names.
type Options = {[string]: any}
type Endpoint = {method: string, path: string, read: boolean, query: {string}?, body: boolean?, defaults: Options?, list: string?, help: string}
local API = "https://www.googleapis.com/calendar/v3"

-- Request layer shared verbatim by the Google connectors (tools/validate checks they match).
local function text(value: any, field: string): string
	assert(type(value) == "string" and value ~= "", field .. " must be a nonempty string")
	return value
end

local function options(value: any): Options
	if value == nil then return {} end
	assert(type(value) == "table", "opts must be an object")
	for key in value do assert(type(key) == "string", "opts must have named fields") end
	return table.clone(value)
end

-- Moves the named fields from args into a query string; arrays repeat the key.
local function query(args: Options, names: {string}): string
	local parts: {string} = {}
	for _, name in names do
		local value = args[name]
		args[name] = nil
		for _, item in (if type(value) == "table" then value else {value}) do
			assert(type(item) == "string" or type(item) == "number" or type(item) == "boolean", name .. " must be a string, number, boolean or an array of them")
			table.insert(parts, url.encode(name) .. "=" .. url.encode(item))
		end
	end
	return if #parts > 0 then "?" .. table.concat(parts, "&") else ""
end

local function fail(operation: string, response: HttpResponse): never
	local ok, decoded = pcall(json.decode, await(response.body:readPrefix(4096)))
	local problem = if ok and type(decoded) == "table" and type(decoded.error) == "table" then decoded.error else {}
	local reason = type(problem.errors) == "table" and type(problem.errors[1]) == "table" and problem.errors[1].reason
	local message = "Google HTTP " .. tostring(response.statusCode)
	if type(problem.status) == "string" then message ..= " (" .. problem.status .. ")" end
	if type(problem.message) == "string" then message ..= ": " .. string.sub(problem.message, 1, 600) end
	if type(reason) == "string" then message ..= " [" .. reason .. "]" end
	local retry = response.headers["retry-after"]
	if retry and retry[1] then message ..= "; Retry-After: " .. retry[1] end
	local limited = type(reason) == "string" and string.find(string.lower(reason), "ratelimitexceeded", 1, true) ~= nil
	return houston.fail({operation = operation, layer = "upstream", upstream_status = response.statusCode,
		retryable = response.statusCode == 429 or response.statusCode >= 500 or limited, message = message})
end

local function decode(operation: string, response: HttpResponse): any
	if response.statusCode < 200 or response.statusCode >= 300 then fail(operation, response) end
	local raw = await(response.body:readAll())
	if raw == "" then return {success = true} end
	local ok, value = pcall(json.decode, raw)
	if not ok or type(value) ~= "table" or not string.match(raw, "^%s*{") then
		houston.fail({operation = operation, layer = "upstream", upstream_status = response.statusCode,
			retryable = false, message = "Google returned an invalid JSON object"})
	end
	return value
end

local function call(operation: string, method: string, href: string, body: any?): any
	return decode(operation, await(http.request({method = method, url = href,
		headers = if body ~= nil then {["Content-Type"] = {"application/json"}} else nil,
		body = if body ~= nil then json.encode(body) else nil})))
end

-- Moves {placeholders} and declared query fields from args into the URL; remaining fields form the JSON body.
local function target(name: string, endpoint: Endpoint, args: Options): string
	local defaults: Options = endpoint.defaults or {}
	for key, value in defaults do
		if args[key] == nil then args[key] = value end
	end
	local path = string.gsub(endpoint.path, "{(%w+)}", function(field: string)
		local value = url.segment(text(args[field], field), field)
		args[field] = nil
		return value
	end)
	path ..= query(args, endpoint.query or {})
	if not endpoint.body then assert(next(args) == nil, name .. " received an unknown option") end
	return API .. path
end

local function invoke(name: string, endpoint: Endpoint, input: any): any
	local args = options(input)
	local result = call(name, endpoint.method, target(name, endpoint, args), if endpoint.body then args else nil)
	if endpoint.list and result[endpoint.list] == nil then result[endpoint.list] = json.decode("[]") end
	return result
end

local exports: {[string]: any} = {}
local help: {[string]: string} = {}

-- Exposes an operation when it only reads or the connection allows writes.
local function export(name: string, isRead: boolean, fn: (any) -> any, doc: string)
	if isRead or config.access == "read-write" then
		exports[name], help[name] = fn, doc
	end
end

local function exportEndpoints(endpoints: {[string]: Endpoint})
	for name, endpoint in endpoints do
		export(name, endpoint.read, function(args: Options?): any return invoke(name, endpoint, args) end, endpoint.help)
	end
end

-- help() introduces the API, then documents exactly the configured operations.
local function helpWith(overview: {string}): () -> string
	return function(): string
		local names: {string} = {}
		for name in help do table.insert(names, name) end
		table.sort(names)
		local lines = table.clone(overview)
		for _, name in names do table.insert(lines, help[name]) end
		return table.concat(lines, "\n")
	end
end
-- End of the shared request layer.

local PRIMARY = {calendarId = "primary"}
local WRITE = {"sendUpdates", "conferenceDataVersion", "supportsAttachments", "maxAttendees"}
local endpoints: {[string]: Endpoint} = {
	listCalendars = {method = "GET", path = "/users/me/calendarList", read = true, list = "items",
		query = {"maxResults", "pageToken", "minAccessRole", "showDeleted", "showHidden", "syncToken"},
		help = "listCalendars(opts?) -> {items, nextPageToken?, nextSyncToken?}. Calendars in the user's list. opts: maxResults (≤250), pageToken, minAccessRole, showDeleted, showHidden, syncToken."},
	getCalendar = {method = "GET", path = "/calendars/{calendarId}", read = true, defaults = PRIMARY,
		help = "getCalendar({calendarId?}) -> calendar {id, summary, timeZone, ...}. calendarId defaults to primary."},
	listEvents = {method = "GET", path = "/calendars/{calendarId}/events", read = true, defaults = PRIMARY, list = "items",
		query = {"timeMin", "timeMax", "q", "maxResults", "pageToken", "singleEvents", "orderBy", "timeZone", "showDeleted", "updatedMin", "syncToken", "iCalUID", "eventTypes", "privateExtendedProperty", "sharedExtendedProperty"},
		help = "listEvents({calendarId?, timeMin?, timeMax?, q?, singleEvents?, orderBy?, maxResults?, pageToken?, ...}) -> {items, nextPageToken?, timeZone, ...}. Times are RFC 3339 (2026-10-12T09:00:00Z). singleEvents=true expands recurring events and allows orderBy='startTime'. maxResults ≤2500."},
	getEvent = {method = "GET", path = "/calendars/{calendarId}/events/{eventId}", read = true, defaults = PRIMARY,
		query = {"timeZone", "maxAttendees"},
		help = "getEvent({calendarId?, eventId, timeZone?}) -> event."},
	listEventInstances = {method = "GET", path = "/calendars/{calendarId}/events/{eventId}/instances", read = true, defaults = PRIMARY, list = "items",
		query = {"timeMin", "timeMax", "maxResults", "pageToken", "timeZone", "showDeleted", "originalStart"},
		help = "listEventInstances({calendarId?, eventId, timeMin?, timeMax?, maxResults?, pageToken?}) -> {items, nextPageToken?}. Occurrences of a recurring event."},
	queryFreeBusy = {method = "POST", path = "/freeBusy", read = true, body = true,
		help = "queryFreeBusy({timeMin, timeMax, items={{id='primary'}}, timeZone?}) -> {calendars={[id]={busy={{start,end}}}}}. Busy intervals only; event details stay private."},
	insertEvent = {method = "POST", path = "/calendars/{calendarId}/events", read = false, body = true, defaults = PRIMARY, query = WRITE,
		help = "insertEvent({calendarId?, summary, start={dateTime|date, timeZone?}, end={...}, attendees?, description?, location?, recurrence?, sendUpdates?, conferenceDataVersion?, ...}) -> event. sendUpdates: all, externalOnly or none (default none). Use conferenceDataVersion=1 with conferenceData.createRequest to add Google Meet."},
	patchEvent = {method = "PATCH", path = "/calendars/{calendarId}/events/{eventId}", read = false, body = true, defaults = PRIMARY, query = WRITE,
		help = "patchEvent({calendarId?, eventId, sendUpdates?, ...fields to change}) -> event. Only the given fields change; arrays such as attendees are replaced whole."},
	deleteEvent = {method = "DELETE", path = "/calendars/{calendarId}/events/{eventId}", read = false, defaults = PRIMARY, query = {"sendUpdates"},
		help = "deleteEvent({calendarId?, eventId, sendUpdates?}) -> {success=true}. Cancels the event for its attendees when sendUpdates is all."},
	moveEvent = {method = "POST", path = "/calendars/{calendarId}/events/{eventId}/move", read = false, defaults = PRIMARY, query = {"destination", "sendUpdates"},
		help = "moveEvent({calendarId?, eventId, destination, sendUpdates?}) -> event. Changes the event's organizer calendar."},
	quickAddEvent = {method = "POST", path = "/calendars/{calendarId}/events/quickAdd", read = false, defaults = PRIMARY, query = {"text", "sendUpdates"},
		help = "quickAddEvent({calendarId?, text, sendUpdates?}) -> event. Creates an event from text such as 'Lunch with Ana tomorrow 12pm'."},
}

exportEndpoints(endpoints)
exports.help = helpWith({
	"Google Calendar API v3. Every operation takes one named options object with Google's camelCase fields and returns Google's JSON unchanged; deletes return {success=true}.",
	"calendarId defaults to 'primary' (the connected account's calendar); other IDs come from listCalendars. Lists return one page: pass nextPageToken as pageToken until it is absent.",
	"No hidden paging or retries. Errors report the HTTP status, Google's message and reason. A failed or timed-out write may already have succeeded; check with getEvent or listEvents before repeating.",
	"Example: listEvents({timeMin='2026-10-12T00:00:00Z', timeMax='2026-10-19T00:00:00Z', singleEvents=true, orderBy='startTime'}).",
})
return exports
