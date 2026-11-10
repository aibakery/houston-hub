return {
	scenario = {publisher = {client_id = "fixture-client", client_secret = "fixture-private-secret"}, config = {}, auth_method = "oauth", auth_config = {}},
	config = {access = "read-only"},
	configure = function()
		requests, responses = {}, {}
		http = {request = function(req)
			assert(req.headers == nil or req.headers.Authorization == nil, "the proxy injects Authorization")
			table.insert(requests, req)
			assert(#responses > 0, "unexpected request: " .. req.url)
			local response = table.remove(responses, 1)
			return fixture.operation({statusCode = response.status or 200, headers = response.headers or {}, body = fixture.reader(response.body or "")})
		end}
	end,
	run = function(c)
		local API = "https://graph.microsoft.com/v1.0/me"
		local LIST = "$select=id%2Csubject%2Cstart%2Cend%2CisAllDay%2Clocation%2Corganizer%2Cattendees%2CshowAs%2CresponseStatus%2CisOrganizer%2CisCancelled%2Ctype%2CseriesMasterId%2ConlineMeeting%2CwebLink%2CbodyPreview%2Ccategories%2Csensitivity"
		local function last() return requests[#requests] end
		local function fails(expected: {string}, fn: (...any) -> any, ...: any)
			local ok, err = pcall(fn, ...)
			assert(not ok, "call succeeded")
			for _, text in expected do assert(string.find(tostring(err), text, 1, true), "missing " .. text .. " in " .. tostring(err)) end
		end
		local names = {}
		for name in c do table.insert(names, name) end
		table.sort(names)
		assert(table.concat(names, ",") == "getCalendar,getEvent,getSchedule,listCalendars,listEventInstances,listEvents", "read-only got " .. table.concat(names, ","))

		-- Calendars: the default one, or one named by ID; lists always carry a value array.
		responses = {{body = '{"id":"C0","name":"Calendar","isDefaultCalendar":true}'}, {body = '{"id":"C1","name":"Team"}'}, {body = '{}'}, {body = '{"value":[{"id":"C1"}]}'}}
		assert(c.getCalendar().isDefaultCalendar and last().url == API .. "/calendar", last().url)
		assert(last().headers.Prefer == nil, "calendars take no Prefer header")
		assert(c.getCalendar({calendarId = "AAMk-_=", select = {"id", "name"}}).name == "Team")
		assert(last().url == API .. "/calendars/AAMk-_%3D?$select=id,name", last().url)
		assert(json.encode(c.listCalendars({top = 50}).value) == "[]" and last().url == API .. "/calendars?$top=50", last().url)
		local link = "https://graph.microsoft.com/v1.0/me/calendars?$top=50&$skip=50"
		assert(c.listCalendars({nextLink = link}).value[1].id == "C1" and last().url == link, last().url)

		-- Calendar views take a time range, summary fields and start order by default, with text bodies
		-- and times in the requested zone.
		local nextLink = "https://graph.microsoft.com/v1.0/me/calendarView?startDateTime=2026-11-09T00%3a00%3a00.0000000&endDateTime=2026-11-16T00%3a00%3a00.0000000&%24select=id&%24orderby=start%2fdateTime&%24top=1&%24skip=1"
		responses = {
			{body = '{"value":[{"id":"E1","subject":"Standup","type":"occurrence","seriesMasterId":"S1"}],"@odata.nextLink":"' .. nextLink .. '"}'},
			{body = '{"value":[]}'}, {body = '{}'},
		}
		local page = c.listEvents({startDateTime = "2026-11-09T00:00:00Z", endDateTime = "2026-11-16T00:00:00Z", timeZone = "Europe/Paris", top = 1})
		assert(page.value[1].seriesMasterId == "S1" and page["@odata.nextLink"] == nextLink)
		assert(last().url == API .. "/calendarView?startDateTime=2026-11-09T00%3A00%3A00Z&endDateTime=2026-11-16T00%3A00%3A00Z&" .. LIST .. "&$orderby=start%2FdateTime&$top=1", last().url)
		assert(table.concat(last().headers.Prefer, ";") == 'outlook.timezone="Europe/Paris";outlook.body-content-type="text"', table.concat(last().headers.Prefer, ";"))
		-- nextLink keeps the range; the Prefer options repeat on every page.
		assert(#c.listEvents({nextLink = nextLink, timeZone = "Europe/Paris"}).value == 0)
		assert(last().url == nextLink and last().headers.Prefer[1] == 'outlook.timezone="Europe/Paris"', last().url)
		-- Graph may name the calendar by OData key; the route takes its path form.
		responses = {{body = '{"value":[{"id":"E2"}]}'}, {body = '{"value":[]}'}, {body = '{}'}}
		assert(c.listEvents({nextLink = "https://graph.microsoft.com/v1.0/me/calendars('C1')/calendarView?startDateTime=2026-11-01&endDateTime=2026-12-01&%24skip=10"}).value[1].id == "E2")
		assert(last().url == API .. "/calendars/C1/calendarView?startDateTime=2026-11-01&endDateTime=2026-12-01&%24skip=10", last().url)
		assert(json.encode(c.listEvents({calendarId = "C1", startDateTime = "2026-11-01", endDateTime = "2026-12-01", filter = "isCancelled eq false",
			select = "id,subject,body", orderby = "subject", bodyFormat = "html"}).value) == "[]")
		assert(last().url == API .. "/calendars/C1/calendarView?startDateTime=2026-11-01&endDateTime=2026-12-01&$select=id%2Csubject%2Cbody&$filter=isCancelled%20eq%20false&$orderby=subject", last().url)
		assert(#last().headers.Prefer == 1 and last().headers.Prefer[1] == 'outlook.body-content-type="html"')

		responses = {{body = '{"id":"S1","type":"seriesMaster","recurrence":{"pattern":{"type":"weekly"}}}'}, {body = '{"value":[{"id":"E1"},{"id":"E2"}]}'}}
		assert(c.getEvent({id = "AAMk-_=", timeZone = "Pacific Standard Time"}).recurrence.pattern.type == "weekly")
		assert(last().url == API .. "/events/AAMk-_%3D" and last().headers.Prefer[1] == 'outlook.timezone="Pacific Standard Time"', last().url)
		assert(#c.listEventInstances({id = "S1", startDateTime = "2026-11-01T00:00:00Z", endDateTime = "2027-01-01T00:00:00Z", top = 2}).value == 2)
		assert(last().url == API .. "/events/S1/instances?startDateTime=2026-11-01T00%3A00%3A00Z&endDateTime=2027-01-01T00%3A00%3A00Z&" .. LIST .. "&$top=2", last().url)
		-- Events of a shared calendar are reached through that calendar.
		responses = {{body = '{"id":"E5"}'}, {body = '{"value":[]}'}}
		assert(c.getEvent({calendarId = "C-1=", id = "E5"}).id == "E5" and last().url == API .. "/calendars/C-1%3D/events/E5", last().url)
		c.listEventInstances({calendarId = "C1", id = "S1", startDateTime = "2026-11-01", endDateTime = "2026-12-01"})
		assert(last().url == API .. "/calendars/C1/events/S1/instances?startDateTime=2026-11-01&endDateTime=2026-12-01&" .. LIST, last().url)
		local instances = "https://graph.microsoft.com/v1.0/me/events('S1')/instances?startDateTime=2026-11-01T00%3a00%3a00Z&endDateTime=2027-01-01T00%3a00%3a00Z&%24top=2&%24skip=2"
		responses = {{body = '{"value":[]}'}}
		assert(json.encode(c.listEventInstances({nextLink = instances}).value) == "[]")
		assert(last().url == "https://graph.microsoft.com/v1.0/me/events/S1/instances?startDateTime=2026-11-01T00%3a00%3a00Z&endDateTime=2027-01-01T00%3a00%3a00Z&%24top=2&%24skip=2", last().url)

		responses = {{body = '{"value":[{"scheduleId":"ana@example.com","availabilityView":"0220","scheduleItems":[]}]}'}}
		local schedule = c.getSchedule({schedules = {"ana@example.com"}, startTime = {dateTime = "2026-11-12T08:00:00", timeZone = "Europe/Paris"},
			endTime = {dateTime = "2026-11-12T10:00:00", timeZone = "Europe/Paris"}, availabilityViewInterval = 30, timeZone = "Europe/Paris"})
		assert(schedule.value[1].availabilityView == "0220" and last().method == "POST" and last().url == API .. "/calendar/getSchedule", last().url)
		local body = json.decode(last().body)
		assert(body.schedules[1] == "ana@example.com" and body.availabilityViewInterval == 30 and body.timeZone == nil and body.startTime.timeZone == "Europe/Paris")
		assert(#last().headers.Prefer == 1 and last().headers.Prefer[1] == 'outlook.timezone="Europe/Paris"' and last().headers["Content-Type"][1] == "application/json")
		-- A schedule Graph cannot read reports its error in place; an empty reply still carries value.
		responses = {{body = '{"value":[{"scheduleId":"bo@other.test","error":{"message":"Cannot read","responseCode":"5009"}}]}'}, {body = '{}'}}
		local window = {schedules = {"bo@other.test"}, startTime = {dateTime = "2026-11-12T08:00:00", timeZone = "UTC"}, endTime = {dateTime = "2026-11-12T10:00:00", timeZone = "UTC"}}
		assert(c.getSchedule(window).value[1].error.responseCode == "5009" and last().headers.Prefer == nil)
		local empty = c.getSchedule(window)
		assert(json.encode(empty.value) == "[]", "getSchedule returned " .. json.encode(empty))

		-- Invalid input never reaches the network.
		local before = #requests
		fails({"startDateTime must be a nonempty string"}, c.listEvents, {endDateTime = "2026-11-16T00:00:00Z"})
		fails({"endDateTime must be a nonempty string"}, c.listEventInstances, {id = "S1", startDateTime = "2026-11-01T00:00:00Z"})
		fails({"id must be a nonempty string"}, c.listEventInstances, {startDateTime = "2026-11-01T00:00:00Z", endDateTime = "2027-01-01T00:00:00Z"})
		fails({"listEvents takes nextLink alone"}, c.listEvents, {nextLink = nextLink, top = 5})
		fails({"nextLink must come from the same list"}, c.listEvents, {nextLink = "https://graph.microsoft.com/v1.0/me/events?$top=1"})
		fails({"nextLink must come from the same list"}, c.listEventInstances, {nextLink = "https://graph.microsoft.com/v1.0/me/events/S1/attachments?$top=1"})
		fails({"nextLink may carry only paging options"}, c.listEvents, {nextLink = nextLink .. "&$expand=attachments"})
		fails({"nextLink must be an @odata.nextLink"}, c.listEvents, {nextLink = "https://graph.microsoft.com.evil.test/v1.0/me/calendarView?$skip=1"})
		fails({"timeZone must be a time zone name"}, c.getEvent, {id = "E1", timeZone = 'UTC"\r\nX-Evil: 1'})
		fails({"timeZone must be a time zone name"}, c.listEvents, {nextLink = nextLink, timeZone = "UTC\\"})
		fails({"bodyFormat must be text or html"}, c.getEvent, {id = "E1", bodyFormat = "rtf"})
		fails({"getEvent received an unknown option"}, c.getEvent, {id = "E1", expand = "attachments"})
		fails({"getSchedule requires schedules"}, c.getSchedule, {schedules = {}, startTime = {}, endTime = {}})
		fails({"getSchedule requires startTime and endTime"}, c.getSchedule, {schedules = {"ana@example.com"}})
		fails({"getCalendar received an unknown option"}, c.getCalendar, {top = 1})
		assert(#requests == before, "invalid input reached the network")

		-- Graph errors keep the status, code and message; throttling is retryable.
		responses = {
			{status = 404, body = '{"error":{"code":"ErrorItemNotFound","message":"The specified object was not found in the store."}}'},
			{status = 429, headers = {["retry-after"] = {"7"}}, body = '{"error":{"code":"ApplicationThrottled","message":"Too many requests"}}'},
			{status = 403, body = '{"error":{"code":"ErrorAccessDenied","message":"Access is denied."}}'},
			{status = 200, body = "[]"},
		}
		fails({"Microsoft Graph HTTP 404 (ErrorItemNotFound)", '"retryable":false'}, c.getEvent, {id = "missing"})
		fails({"HTTP 429 (ApplicationThrottled)", "Retry-After: 7", '"retryable":true'}, c.getCalendar)
		fails({"HTTP 403 (ErrorAccessDenied)", '"retryable":false'}, c.listCalendars)
		fails({"invalid JSON object"}, c.getCalendar)
	end,
}
