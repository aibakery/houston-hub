return {
	scenario = {publisher = {client_id = "fixture-client", client_secret = "fixture-private-secret"}, config = {}, auth_method = "oauth", auth_config = {}},
	config = {access = "read-only"},
	configure = function()
		requests, responses = {}, {}
		http = {request = function(req)
			table.insert(requests, req)
			assert(#responses > 0, "unexpected request: " .. req.url)
			return fixture.operation({statusCode = 200, headers = {}, body = fixture.reader(table.remove(responses, 1))})
		end}
	end,
	run = function(c)
		local API = "https://www.googleapis.com/calendar/v3"
		local names = {}
		for name in c do table.insert(names, name) end
		table.sort(names)
		assert(table.concat(names, ",") == "getCalendar,getColors,getEvent,listCalendars,listEventInstances,listEvents,queryFreeBusy", table.concat(names, ","))
		local function sent(method, href)
			local req = requests[#requests]
			assert(req.method == method and req.url == href, req.method .. " " .. req.url)
			assert(req.headers == nil or req.headers.Authorization == nil, "connector set credentials")
		end

		responses = {'{"items":[{"id":"primary@example.com","accessRole":"owner"}],"nextPageToken":"p+2"}', '{"kind":"calendar#calendarList"}'}
		local calendars = c.listCalendars({maxResults = 250, minAccessRole = "writer", pageToken = "p+1"})
		assert(calendars.items[1].accessRole == "owner" and calendars.nextPageToken == "p+2")
		sent("GET", API .. "/users/me/calendarList?maxResults=250&pageToken=p%2B1&minAccessRole=writer")
		assert(requests[1].body == nil)
		assert(json.encode(c.listCalendars().items) == "[]", "absent lists must be empty arrays")
		sent("GET", API .. "/users/me/calendarList")

		responses = {'{"id":"primary@example.com","timeZone":"Europe/Paris"}', '{"id":"en.usa#holiday@group.v.calendar.google.com"}'}
		assert(c.getCalendar().timeZone == "Europe/Paris")
		sent("GET", API .. "/calendars/primary")
		c.getCalendar({calendarId = "en.usa#holiday@group.v.calendar.google.com"})
		sent("GET", API .. "/calendars/en.usa%23holiday%40group.v.calendar.google.com")

		responses = {'{"calendar":{"1":{"background":"#ac725e","foreground":"#1d1d1d"}},"event":{"11":{"background":"#dc2127","foreground":"#1d1d1d"}}}'}
		assert(c.getColors().event["11"].background == "#dc2127")
		sent("GET", API .. "/colors")
		assert(not pcall(c.getColors, {calendarId = "primary"}), "getColors takes no options")

		responses = {'{"items":[{"id":"e1"}],"nextPageToken":"next+1"}', '{"kind":"calendar#events","nextSyncToken":"s1"}'}
		local page = c.listEvents({timeMin = "2026-10-12T00:00:00Z", singleEvents = true, orderBy = "startTime", pageToken = "start+1", eventTypes = {"default", "focusTime"}})
		assert(page.nextPageToken == "next+1" and page.items[1].id == "e1")
		sent("GET", API .. "/calendars/primary/events?timeMin=2026-10-12T00%3A00%3A00Z&pageToken=start%2B1&singleEvents=true&orderBy=startTime&eventTypes=default&eventTypes=focusTime")
		local empty = c.listEvents({calendarId = "team@group.calendar.google.com", q = "standup & review", maxResults = 2500})
		assert(json.encode(empty.items) == "[]" and empty.nextSyncToken == "s1")
		sent("GET", API .. "/calendars/team%40group.calendar.google.com/events?q=standup%20%26%20review&maxResults=2500")

		responses = {'{"id":"e1_20261013T090000Z","recurringEventId":"e1"}', '{"items":[{"id":"e1_20261013T090000Z"}]}'}
		assert(c.getEvent({eventId = "e1_20261013T090000Z", timeZone = "Europe/Paris"}).recurringEventId == "e1")
		sent("GET", API .. "/calendars/primary/events/e1_20261013T090000Z?timeZone=Europe%2FParis")
		assert(#c.listEventInstances({calendarId = "team@group.calendar.google.com", eventId = "e1", timeMax = "2026-11-01T00:00:00+02:00"}).items == 1)
		sent("GET", API .. "/calendars/team%40group.calendar.google.com/events/e1/instances?timeMax=2026-11-01T00%3A00%3A00%2B02%3A00")

		responses = {'{"calendars":{"primary":{"busy":[{"start":"2026-10-13T09:00:00Z","end":"2026-10-13T10:00:00Z"}]}}}'}
		local busy = c.queryFreeBusy({timeMin = "2026-10-13T00:00:00Z", timeMax = "2026-10-14T00:00:00Z", items = {{id = "primary"}}})
		assert(busy.calendars.primary.busy[1]["end"] == "2026-10-13T10:00:00Z")
		sent("POST", API .. "/freeBusy")
		assert(requests[#requests].headers["Content-Type"][1] == "application/json")
		assert(requests[#requests].body == '{"items":[{"id":"primary"}],"timeMax":"2026-10-14T00:00:00Z","timeMin":"2026-10-13T00:00:00Z"}', requests[#requests].body)

		local count = #requests
		for _, args in {{eventId = ""}, {eventId = 42}, {eventId = "e", unknown = true}, {"e"}, {eventId = ".."}, {eventId = "e/f"}, {eventId = "e%2Ff"}, {calendarId = "a\\b", eventId = "e"}, {eventId = "e\0"}, {calendarId = "", eventId = "e"}} do
			assert(not pcall(c.getEvent, args), "accepted " .. json.encode(args))
		end
		assert(not pcall(c.getEvent, "e"))
		assert(not pcall(c.getEvent, {}), "getEvent requires eventId")
		assert(not pcall(c.listEvents, {eventTypes = {{}}}))
		assert(not pcall(c.listEvents, {key = "api-key"}), "unknown query options must fail")
		assert(not pcall(c.listCalendars, {fields = "items"}))
		assert(not pcall(c.listEvents, {q = {a = "b"}}), "query lists must be arrays")
		assert(not pcall(c.listEvents, {eventTypes = {"default", extra = "focusTime"}}))
		local day = {timeMin = "2026-10-13T00:00:00Z", timeMax = "2026-10-14T00:00:00Z"}
		for _, args in {{}, day, {timeMin = day.timeMin, timeMax = "", items = {{id = "primary"}}}, {timeMin = day.timeMin, timeMax = day.timeMax, items = {}}} do
			assert(not pcall(c.queryFreeBusy, args), "queryFreeBusy requires timeMin, timeMax and items: " .. json.encode(args))
		end
		assert(#requests == count, "invalid input reached Google")
		assert(#responses == 0)
	end,
}
