-- Microsoft Graph v1.0 for the connected account's Outlook calendars. Arguments and results keep
-- Graph's native field names.

-- Request layer shared verbatim by the Microsoft Graph connectors; Hub runs each copy against
-- every consumer's fixtures.
type Options = {[string]: any}
type Spec = {query: {string}?, body: boolean?, list: string?, defaults: Options?, headers: HttpHeaders?}
local GRAPH = "https://graph.microsoft.com/v1.0"
local API = GRAPH .. "/me"
-- Preauthenticated OneDrive download links, under either annotation, work without credentials,
-- so results never carry them.
local SIGNED = {"@microsoft.graph.downloadUrl", "@content.downloadUrl"}

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

local function done(name: string, args: Options)
	local unknown = next(args)
	assert(unknown == nil, name .. " received an unknown option " .. tostring(unknown))
end

-- Moves the named fields from args into a query string. A $name is an OData option taken from
-- the field without $ (select, top, ...); arrays join with commas, as OData lists do.
local function query(args: Options, names: {string}): string
	local parts: {string} = {}
	for _, name in names do
		local field = if string.sub(name, 1, 1) == "$" then string.sub(name, 2) else name
		local value = args[field]
		args[field] = nil
		if value ~= nil then
			local items: {string} = {}
			for key, item in (if type(value) == "table" then value else {value}) do
				assert(type(key) == "number" and (type(item) == "string" or type(item) == "number" or type(item) == "boolean"), field .. " must be a string, number, boolean or an array of them")
				table.insert(items, url.encode(item))
			end
			assert(#items > 0, field .. " must not be an empty array")
			table.insert(parts, (if field == name then url.encode(name) else name) .. "=" .. table.concat(items, ","))
		end
	end
	return if #parts > 0 then "?" .. table.concat(parts, "&") else ""
end

-- Graph errors are {error = {code, message}}; throttling answers 429 or 503 with Retry-After.
-- Quota (507) and other server refusals are not transient.
local function fail(operation: string, response: HttpResponse): never
	local ok, decoded = pcall(json.decode, await(response.body:readPrefix(4096)))
	local problem = if ok and type(decoded) == "table" and type(decoded.error) == "table" then decoded.error else {}
	local status = response.statusCode
	local message = "Microsoft Graph HTTP " .. tostring(status)
	if type(problem.code) == "string" then message ..= " (" .. problem.code .. ")" end
	if type(problem.message) == "string" then message ..= ": " .. string.sub(problem.message, 1, 600) end
	local retry = response.headers["retry-after"]
	if retry and retry[1] then message ..= "; Retry-After: " .. retry[1] end
	return houston.fail({operation = operation, layer = "upstream", upstream_status = status, message = message,
		retryable = status == 429 or status == 500 or status == 502 or status == 503 or status == 504 or status == 509})
end

local function decode(operation: string, response: HttpResponse): any
	if response.statusCode < 200 or response.statusCode >= 300 then fail(operation, response) end
	local raw = await(response.body:readAll())
	if string.match(raw, "^%s*$") then return {success = true} end
	local ok, value = pcall(json.decode, raw)
	if not ok or type(value) ~= "table" or not string.match(raw, "^%s*{") then
		houston.fail({operation = operation, layer = "upstream", upstream_status = response.statusCode,
			retryable = false, message = "Microsoft Graph returned an invalid JSON object"})
	end
	for _, key in SIGNED do
		value[key] = nil
		for _, item in (if type(value.value) == "table" then value.value else {}) :: {any} do
			if type(item) == "table" then item[key] = nil end
		end
	end
	return value
end

local function call(operation: string, method: string, href: string, body: any?, headers: HttpHeaders?): any
	local sent: HttpHeaders = if headers then table.clone(headers) else {}
	if body ~= nil then sent["Content-Type"] = {"application/json"} end
	return decode(operation, await(http.request({method = method, url = href, headers = sent,
		body = if body ~= nil then json.encode(body) elseif method == "POST" then "" else nil})))
end

-- Streams fetch()'s response to a session file; the path changes only when the whole body arrived.
local function save(operation: string, path: string, fetch: () -> HttpResponse): Options
	local output = fs.open(path, "w")
	local ok, err = pcall(function()
		local response = fetch()
		if response.statusCode ~= 200 then fail(operation, response) end
		output:write(response.body)
		await(output:close())
	end)
	if not ok then
		output:cancel()
		pcall(function() await(output:close()) end)
		error(err, 0)
	end
	return {path = path, url = await(fs.signedGetUrl(path)), size = await(fs.stat(path)).size}
end

-- Follows an @odata.nextLink of the list whose path ends with the pattern ending. It may carry only
-- paging options and a calendar view's time range: an $expand, or another route such as
-- thumbnails, could return attachment bytes or signed links. Graph may name entities by OData
-- key, as in mailFolders('inbox'), which the routes accept in their path form, mailFolders/inbox.
local PAGING = {select = true, top = true, skip = true, skiptoken = true, orderby = true, filter = true, search = true, count = true,
	startdatetime = true, enddatetime = true}
local function pageLink(link: string, ending: string): string
	local raw, search = string.match(link, "^([^?#]*)(%??[^#]*)$")
	assert(raw and search and string.sub(raw, 1, #GRAPH + 1) == GRAPH .. "/", "nextLink must be an @odata.nextLink from Microsoft Graph")
	local path = string.gsub((string.gsub(raw, "%%27", "'")), "/(%w+)%('([^'/]+)'%)", "/%1/%2")
	assert(string.find(path, ending), "nextLink must come from the same list")
	for pair in string.gmatch(string.sub(search, 2), "[^&]+") do
		local name = string.lower((string.gsub(string.match(pair, "^[^=]*") or "", "%%(%x%x)", function(hex: string): string
			return string.char(tonumber(hex, 16) or 0)
		end)))
		assert(PAGING[(string.gsub(name, "^%$", ""))], "nextLink may carry only paging options")
	end
	return path .. search
end

-- A list's nextLink, the previous page's @odata.nextLink, replaces every other option.
local function nextLink(name: string, args: Options, ending: string): string?
	if args.nextLink == nil then return nil end
	local link = text(args.nextLink, "nextLink")
	args.nextLink = nil
	assert(next(args) == nil, name .. " takes nextLink alone, from a previous page of the same list")
	return pageLink(link, ending)
end

-- One Graph request built from args: {field} placeholders take URL-encoded path segments, query
-- names the query fields and, with body, the other fields form the JSON body. A list (the Lua
-- pattern its path ends with) also accepts nextLink and always returns a value array.
local function request(name: string, method: string, path: string, input: any, spec: Spec?): any
	local args = options(input)
	local s: Spec = spec or {}
	local href = if s.list then nextLink(name, args, s.list) else nil
	if not href then
		local defaults: Options = s.defaults or {}
		for key, value in defaults do
			if args[key] == nil then args[key] = value end
		end
		local route = string.gsub(path, "{(%w+)}", function(field: string)
			local value = url.segment(text(args[field], field), field)
			args[field] = nil
			return value
		end)
		href = API .. route .. query(args, s.query or {})
		if not s.body then done(name, args) end
	end
	local result = call(name, method, href :: string, if s.body then args else nil, s.headers)
	if s.list and result.value == nil then result.value = json.decode("[]") end
	return result
end
-- End of the shared request layer.

-- Summary fields for event lists; getEvent returns every field.
local LIST = "id,subject,start,end,isAllDay,location,organizer,attendees,showAs,responseStatus,isOrganizer,isCancelled,type,seriesMasterId,onlineMeeting,webLink,bodyPreview,categories,sensitivity"
local VIEW_QUERY = {"startDateTime", "endDateTime", "$select", "$filter", "$orderby", "$top", "$skip"}

local help = {
	text = [[Microsoft Graph v1.0 for the connected account's Outlook calendars. Operations take one named
options object with Graph's camelCase fields and return Graph's JSON unchanged; deletes and replies
return {success=true}. Connector calls return completed values: use them directly, without await.
calendarId defaults to the user's default calendar; other IDs come from listCalendars. Event IDs
work across calendars. Event times are {dateTime='2026-11-12T10:00:00', timeZone='Romance Standard
Time'}; reads return UTC unless timeZone names another zone. Use Windows time zone names, such as
'UTC', 'Romance Standard Time' (Paris) or 'Eastern Standard Time': Graph accepts only some IANA
names. Luau reserves end: write event['end'] and {['end']=...}.
Lists return one page: while ['@odata.nextLink'] is present, pass it back as nextLink (alone, with
timeZone or bodyFormat if used). Example: listEvents({startDateTime='2026-11-09T00:00:00Z',
endDateTime='2026-11-16T00:00:00Z', timeZone='Romance Standard Time', top=100}).
Houston itself retries only a short 429 wait. Errors report the HTTP status and Graph's code and
message, e.g. 'Microsoft Graph HTTP 404 (ErrorItemNotFound)'; 429, 503 and other transient server
errors are retryable. Graph serves at most 4 concurrent requests per mailbox.]] .. (if config.access == "read-write" then [[

Writes change only events, not calendars or their sharing. Outlook emails attendees when the
organizer creates, changes or cancels a meeting, and the organizer when an attendee replies with
sendResponse. A failed or timed-out write may already have succeeded: check with listEvents before
repeating it, or retry createEvent with the same transactionId, which avoids a duplicate event.]] else ""),
	functions = {} :: {[string]: any},
}
local exports: {[string]: any} = {help = help}

-- Schemas and hints shared by several operations.
local ID = {type = "string", minLength = 1}
local EVENT_ID = "AAMkAGI2TG93AAA="
local CALENDAR_ID = "AAMkAGI2TGuLAAA="
local SELECT = {type = {"string", "array"}, items = {type = "string"}, description = "Fields, comma-separated or as an array."}
local NEXT = {type = "string", description = "The previous page's @odata.nextLink; pass it alone, with timeZone or bodyFormat if used."}
local ZONE = {type = "string", minLength = 1, description = "Windows time zone name for returned times, such as 'Romance Standard Time'; defaults to UTC."}
local BODY_FORMAT = {type = "string", enum = {"text", "html"}, description = "Format of body; defaults to text."}
local INSTANT = {type = "string", minLength = 1, description = "ISO 8601 date and time, such as 2026-11-09T00:00:00Z; without an offset it is UTC."}
local TIME = {
	type = "object",
	properties = {dateTime = {type = "string", minLength = 1, description = "Local date and time without offset, such as 2026-11-12T10:00:00."},
		timeZone = {type = "string", minLength = 1, description = "Windows time zone name, such as 'Romance Standard Time' or 'UTC'."}},
	required = {"dateTime", "timeZone"},
}
local RECIPIENTS = {
	type = "array",
	items = {
		type = "object",
		properties = {
			emailAddress = {type = "object", properties = {address = ID, name = {type = "string"}}, required = {"address"}},
			type = {type = "string", enum = {"required", "optional", "resource"}},
		},
		required = {"emailAddress"},
	},
}
local EVENT = {
	subject = {type = "string"},
	body = {type = "object", properties = {contentType = {type = "string", enum = {"text", "html"}}, content = {type = "string"}}, required = {"content"}},
	start = TIME,
	["end"] = TIME,
	isAllDay = {type = "boolean", description = "Start and end are then midnights in the same time zone; end is exclusive."},
	location = {type = "object", properties = {displayName = {type = "string"}}},
	attendees = RECIPIENTS,
	recurrence = {
		type = "object",
		properties = {
			pattern = {
				type = "object",
				properties = {
					type = {type = "string", enum = {"daily", "weekly", "absoluteMonthly", "relativeMonthly", "absoluteYearly", "relativeYearly"}},
					interval = {type = "integer", minimum = 1},
					daysOfWeek = {type = "array", items = {type = "string", enum = {"sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"}}},
					dayOfMonth = {type = "integer", minimum = 1, maximum = 31},
					month = {type = "integer", minimum = 1, maximum = 12},
					index = {type = "string", enum = {"first", "second", "third", "fourth", "last"}},
				},
				required = {"type", "interval"},
			},
			range = {
				type = "object",
				properties = {
					type = {type = "string", enum = {"endDate", "noEnd", "numbered"}},
					startDate = {type = "string", description = "The first occurrence's date, such as 2026-11-16."},
					endDate = {type = "string"},
					numberOfOccurrences = {type = "integer", minimum = 1},
				},
				required = {"type", "startDate"},
			},
		},
		required = {"pattern", "range"},
	},
	showAs = {type = "string", enum = {"free", "tentative", "busy", "oof", "workingElsewhere"}},
	isReminderOn = {type = "boolean"},
	reminderMinutesBeforeStart = {type = "integer", minimum = 0},
	categories = {type = "array", items = {type = "string"}},
	sensitivity = {type = "string", enum = {"normal", "personal", "private", "confidential"}},
	isOnlineMeeting = {type = "boolean"},
	onlineMeetingProvider = {type = "string", enum = {"teamsForBusiness", "skypeForBusiness", "skypeForConsumer"}},
	allowNewTimeProposals = {type = "boolean"},
	responseRequested = {type = "boolean"},
}
local READ = {readOnlyHint = true, openWorldHint = true}
local WRITE = {readOnlyHint = false, destructiveHint = false, openWorldHint = true}
local DESTRUCTIVE = {readOnlyHint = false, destructiveHint = true, openWorldHint = true}

local function with(base: Options, extra: Options): Options
	local merged = table.clone(base)
	for key, value in extra do merged[key] = value end
	return merged
end

-- Prefer picks the time zone of returned times (Graph defaults to UTC) and, for events, the body
-- format (text unless bodyFormat is html).
local function prefer(args: Options, events: boolean): HttpHeaders
	local values: {string} = {}
	if args.timeZone ~= nil then
		local zone = text(args.timeZone, "timeZone")
		assert(string.match(zone, "^[%w %(%)%.%-+/_]+$"), "timeZone must be a time zone name")
		table.insert(values, "outlook.timezone=\"" .. zone .. "\"")
	end
	if events then
		local format = if args.bodyFormat == nil then "text" else args.bodyFormat
		assert(format == "text" or format == "html", "bodyFormat must be text or html")
		table.insert(values, "outlook.body-content-type=\"" .. format .. "\"")
	end
	args.timeZone, args.bodyFormat = nil, nil
	return if #values > 0 then {Prefer = values} else {}
end

-- A calendar view takes its time range on the first page; nextLink carries it afterwards.
local function range(args: Options)
	if args.nextLink ~= nil then return end
	text(args.startDateTime, "startDateTime")
	text(args.endDateTime, "endDateTime")
end

help.functions.listCalendars = {
	description = "One page of the user's calendars: {value={{id, name, color, isDefaultCalendar, canEdit, owner, allowedOnlineMeetingProviders, ...}}, ['@odata.nextLink']?}. Calendars others shared with the user are listed too: their events read like the user's own" .. (if config.access == "read-write" then ", and change where canEdit is true." else "."),
	inputSchema = {
		type = "object",
		properties = {select = SELECT, filter = {type = "string"}, top = {type = "integer", minimum = 1}, nextLink = NEXT},
		additionalProperties = false,
		examples = {{top = 50}},
	},
	annotations = READ,
}
function exports.listCalendars(args: Options?): Options
	return request("listCalendars", "GET", "/calendars", args, {list = "/calendars$", query = {"$select", "$filter", "$top"}})
end

help.functions.getCalendar = {
	description = "One calendar, the default one unless calendarId names another: {id, name, color, isDefaultCalendar, canEdit, owner, ...}.",
	inputSchema = {
		type = "object",
		properties = {calendarId = ID, select = SELECT},
		additionalProperties = false,
		examples = {{select = "id,name,owner"}, {calendarId = CALENDAR_ID}} :: {any},
	},
	annotations = READ,
}
function exports.getCalendar(input: any): Options
	local args = options(input)
	return request("getCalendar", "GET", if args.calendarId == nil then "/calendar" else "/calendars/{calendarId}", args, {query = {"$select"}})
end

help.functions.listEvents = {
	description = [[One page of the events overlapping [startDateTime, endDateTime), recurring ones expanded into
occurrences, ordered by start by default: {value={event}, ['@odata.nextLink']?}. Items already carry
id, subject, start, end, location, organizer, attendees and responseStatus: don't getEvent each one.
Default fields: ]] .. LIST .. [[; add body to select for full descriptions. type is singleInstance,
occurrence or exception; seriesMasterId names the recurring series. filter is OData, such as
"categories/any(c:c eq 'Travel')" or "isCancelled eq false". top is at most 1000; set it, as
default pages are small.]],
	inputSchema = {
		type = "object",
		properties = {
			calendarId = ID, startDateTime = INSTANT, endDateTime = INSTANT, filter = {type = "string"}, orderby = {type = "string"},
			select = SELECT, top = {type = "integer", minimum = 1, maximum = 1000}, skip = {type = "integer", minimum = 0},
			timeZone = ZONE, bodyFormat = BODY_FORMAT, nextLink = NEXT,
		},
		anyOf = {{required = {"startDateTime", "endDateTime"}}, {required = {"nextLink"}}} :: {any},
		additionalProperties = false,
		examples = {
			{startDateTime = "2026-11-09T00:00:00Z", endDateTime = "2026-11-16T00:00:00Z", timeZone = "Romance Standard Time", top = 50},
			{calendarId = CALENDAR_ID, startDateTime = "2026-11-01T00:00:00Z", endDateTime = "2026-12-01T00:00:00Z", filter = "isCancelled eq false"},
		} :: {any},
	},
	annotations = READ,
}
function exports.listEvents(input: any): Options
	local args = options(input)
	local headers = prefer(args, true)
	range(args)
	return request("listEvents", "GET", if args.calendarId == nil then "/calendarView" else "/calendars/{calendarId}/calendarView", args,
		{list = "/calendarView$", headers = headers, defaults = {select = LIST, orderby = "start/dateTime"}, query = VIEW_QUERY})
end

help.functions.getEvent = {
	description = [[One event with every field unless select narrows them: {id, subject, body={contentType,
content}, start, end, isAllDay, location, locations, organizer, attendees={{emailAddress, type,
status={response, time}}}, responseStatus, recurrence?, type, seriesMasterId?, onlineMeeting?,
webLink, ...}. A recurring series' master (type seriesMaster) carries recurrence.]],
	inputSchema = {
		type = "object",
		properties = {id = ID, select = SELECT, timeZone = ZONE, bodyFormat = BODY_FORMAT},
		required = {"id"},
		additionalProperties = false,
		examples = {{id = EVENT_ID, timeZone = "Romance Standard Time"}},
	},
	annotations = READ,
}
function exports.getEvent(input: any): Options
	local args = options(input)
	local headers = prefer(args, true)
	return request("getEvent", "GET", "/events/{id}", args, {headers = headers, query = {"$select"}})
end

help.functions.listEventInstances = {
	description = "One page of a recurring series' occurrences and exceptions in [startDateTime, endDateTime): {value={event}, ['@odata.nextLink']?}. id is the series master's id; each occurrence has its own id for getEvent, updateEvent or a reply.",
	inputSchema = {
		type = "object",
		properties = {
			id = ID, startDateTime = INSTANT, endDateTime = INSTANT, filter = {type = "string"}, orderby = {type = "string"}, select = SELECT,
			top = {type = "integer", minimum = 1, maximum = 1000}, skip = {type = "integer", minimum = 0}, timeZone = ZONE,
			bodyFormat = BODY_FORMAT, nextLink = NEXT,
		},
		anyOf = {{required = {"id", "startDateTime", "endDateTime"}}, {required = {"nextLink"}}} :: {any},
		additionalProperties = false,
		examples = {{id = EVENT_ID, startDateTime = "2026-11-01T00:00:00Z", endDateTime = "2027-01-01T00:00:00Z"}},
	},
	annotations = READ,
}
function exports.listEventInstances(input: any): Options
	local args = options(input)
	local headers = prefer(args, true)
	range(args)
	return request("listEventInstances", "GET", "/events/{id}/instances", args,
		{list = "/instances$", headers = headers, defaults = {select = LIST}, query = VIEW_QUERY})
end

help.functions.getSchedule = {
	description = [[Free/busy for people and rooms in the user's organization: {value={{scheduleId,
availabilityView, scheduleItems={{status, start, end, subject?, location?, isPrivate?}},
workingHours, error?}}}; subject and location appear only where the person shares them.
availabilityView has one digit per availabilityViewInterval minutes (default 30): 0 free (or
working elsewhere), 1 tentative, 2 busy, 3 out of office. Up to 20 people or rooms, counting
distribution list members, over less than 62 days. A schedule Graph cannot read reports error:
check it before treating anyone as free. Work or school accounts only.]],
	inputSchema = {
		type = "object",
		properties = {
			schedules = {type = "array", minItems = 1, maxItems = 20, items = {type = "string", minLength = 1}, description = "Email addresses of people, distribution lists or rooms."},
			startTime = TIME, endTime = TIME,
			availabilityViewInterval = {type = "integer", minimum = 5, maximum = 1440},
			timeZone = ZONE,
		},
		required = {"schedules", "startTime", "endTime"},
		additionalProperties = false,
		examples = {{schedules = {"ana@example.com", "bo@example.com"}, startTime = {dateTime = "2026-11-12T08:00:00", timeZone = "Romance Standard Time"},
			endTime = {dateTime = "2026-11-12T18:00:00", timeZone = "Romance Standard Time"}, availabilityViewInterval = 30}},
	},
	annotations = READ,
}
function exports.getSchedule(input: any): Options
	local args = options(input)
	local headers = prefer(args, false)
	assert(type(args.schedules) == "table" and args.schedules[1] ~= nil, "getSchedule requires schedules as a nonempty array of email addresses")
	assert(type(args.startTime) == "table" and type(args.endTime) == "table", "getSchedule requires startTime and endTime as {dateTime, timeZone}")
	local result = request("getSchedule", "POST", "/calendar/getSchedule", args, {body = true, headers = headers})
	if result.value == nil then result.value = json.decode("[]") end
	return result
end

if config.access == "read-write" then
	help.functions.createEvent = {
		description = [[Creates an event in the default calendar, or in calendarId, and returns it. With attendees it is
a meeting: Outlook emails each one an invitation. All-day events set isAllDay=true with midnight
start and end in one time zone; end is exclusive. isOnlineMeeting=true with onlineMeetingProvider
adds a meeting link, from the calendar's allowedOnlineMeetingProviders (teamsForBusiness needs a
work or school account). Retrying a create with the same transactionId (any unique string) avoids
a duplicate event.]],
		inputSchema = {
			type = "object",
			properties = with(EVENT, {calendarId = ID, transactionId = ID}),
			required = {"start", "end"},
			additionalProperties = true,
			examples = {
				{subject = "Design review", start = {dateTime = "2026-11-12T10:00:00", timeZone = "Romance Standard Time"},
					["end"] = {dateTime = "2026-11-12T11:00:00", timeZone = "Romance Standard Time"}, location = {displayName = "Room 4"},
					attendees = {{emailAddress = {address = "ana@example.com", name = "Ana"}, type = "required"}},
					transactionId = "design-review-2026-11-12"},
				{subject = "Focus time", start = {dateTime = "2026-11-16T09:00:00", timeZone = "Romance Standard Time"},
					["end"] = {dateTime = "2026-11-16T11:00:00", timeZone = "Romance Standard Time"}, showAs = "busy",
					recurrence = {pattern = {type = "weekly", interval = 1, daysOfWeek = {"monday"}}, range = {type = "numbered", startDate = "2026-11-16", numberOfOccurrences = 6}}},
			} :: {any},
		},
		annotations = WRITE,
	}
	function exports.createEvent(input: any): Options
		local args = options(input)
		assert(type(args.start) == "table" and type(args["end"]) == "table", "createEvent requires start and end as {dateTime, timeZone}")
		return request("createEvent", "POST", if args.calendarId == nil then "/events" else "/calendars/{calendarId}/events", args, {body = true})
	end

	help.functions.updateEvent = {
		description = [[Changes the given fields of an event and returns it; arrays such as attendees are replaced
whole, so read the event and send the full list, and location replaces locations. As organizer,
Outlook emails attendees the update; changing only attendees notifies just the added and removed
ones. On an online meeting, a new body must keep the join details from getEvent, or the online
meeting stops working. A series master's id changes the whole series; an occurrence's id, from
listEvents or listEventInstances, changes only that occurrence.]],
		inputSchema = {
			type = "object",
			properties = with(EVENT, {id = ID}),
			required = {"id"},
			minProperties = 2,
			additionalProperties = true,
			examples = {{id = EVENT_ID, location = {displayName = "Room 7"}}},
		},
		annotations = WRITE,
	}
	function exports.updateEvent(input: any): Options
		local args = options(input)
		local fields = 0
		for key in args do
			if key ~= "id" then fields += 1 end
		end
		assert(fields > 0, "updateEvent requires fields to change")
		return request("updateEvent", "PATCH", "/events/{id}", args, {body = true})
	end

	help.functions.deleteEvent = {
		description = "Deletes an event and returns {success=true}. As organizer of a meeting, Outlook sends attendees a cancellation without a message; cancelEvent adds one. To answer an invitation, use declineEvent instead.",
		inputSchema = {type = "object", properties = {id = ID}, required = {"id"}, additionalProperties = false, examples = {{id = EVENT_ID}}},
		annotations = DESTRUCTIVE,
	}
	function exports.deleteEvent(args: Options?): Options
		return request("deleteEvent", "DELETE", "/events/{id}", args)
	end

	help.functions.cancelEvent = {
		description = "Cancels a meeting the user organizes, emailing attendees the cancellation with comment, moves it to Deleted Items and returns {success=true}. An occurrence's id cancels only that occurrence.",
		inputSchema = {
			type = "object",
			properties = {id = ID, comment = {type = "string"}},
			required = {"id"},
			additionalProperties = false,
			examples = {{id = EVENT_ID, comment = "Moving this to next week."}},
		},
		annotations = DESTRUCTIVE,
	}
	function exports.cancelEvent(input: any): Options
		return request("cancelEvent", "POST", "/events/{id}/cancel", input, {body = true})
	end

	local REPLY = {
		id = ID,
		comment = {type = "string"},
		sendResponse = {type = "boolean", description = "Whether the organizer gets the reply by email; defaults to true."},
	}
	local PROPOSAL = {type = "object", properties = {start = TIME, ["end"] = TIME}, required = {"start", "end"}, description = "A new time to suggest, if the organizer allows proposals; requires sendResponse=true."}

	help.functions.acceptEvent = {
		description = "Accepts an invitation and returns {success=true}.",
		inputSchema = {type = "object", properties = REPLY, required = {"id"}, additionalProperties = false, examples = {{id = EVENT_ID, comment = "See you there."}}},
		annotations = WRITE,
	}
	function exports.acceptEvent(input: any): Options
		return request("acceptEvent", "POST", "/events/{id}/accept", input, {body = true})
	end

	help.functions.tentativelyAcceptEvent = {
		description = "Tentatively accepts an invitation, optionally proposing a new time, and returns {success=true}.",
		inputSchema = {
			type = "object",
			properties = with(REPLY, {proposedNewTime = PROPOSAL}),
			required = {"id"},
			additionalProperties = false,
			examples = {{id = EVENT_ID, comment = "I may be late."}},
		},
		annotations = WRITE,
	}
	function exports.tentativelyAcceptEvent(input: any): Options
		return request("tentativelyAcceptEvent", "POST", "/events/{id}/tentativelyAccept", input, {body = true})
	end

	help.functions.declineEvent = {
		description = "Declines an invitation, optionally proposing a new time, and returns {success=true}.",
		inputSchema = {
			type = "object",
			properties = with(REPLY, {proposedNewTime = PROPOSAL}),
			required = {"id"},
			additionalProperties = false,
			examples = {{id = EVENT_ID, comment = "I'm out that day.", proposedNewTime = {
				start = {dateTime = "2026-11-13T10:00:00", timeZone = "Romance Standard Time"}, ["end"] = {dateTime = "2026-11-13T11:00:00", timeZone = "Romance Standard Time"}}}},
		},
		annotations = WRITE,
	}
	function exports.declineEvent(input: any): Options
		return request("declineEvent", "POST", "/events/{id}/decline", input, {body = true})
	end
end

return exports
