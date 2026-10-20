return {
	scenario = {publisher = {client_id = "fixture-client", client_secret = "fixture-private-secret"}, config = {}, auth_method = "oauth", auth_config = {}},
	config = {access = "read-write"},
	configure = function()
		requests, responses = {}, {}
		http = {request = function(req)
			table.insert(requests, req)
			assert(#responses > 0, "unexpected request: " .. req.url)
			local response = table.remove(responses, 1)
			return fixture.operation({statusCode = response.status or 200, headers = {}, body = fixture.reader(response.body or "")})
		end}
	end,
	run = function(c)
		local API = "https://www.googleapis.com/calendar/v3/calendars/"
		local names = {}
		for name in c do table.insert(names, name) end
		table.sort(names)
		assert(table.concat(names, ",") == "deleteEvent,getCalendar,getColors,getEvent,insertEvent,listCalendars,listEventInstances,listEvents,moveEvent,patchEvent,queryFreeBusy,quickAddEvent", table.concat(names, ","))
		local function sent(method, href, body)
			local req = requests[#requests]
			assert(req.method == method and req.url == href, req.method .. " " .. req.url)
			assert(req.headers == nil or req.headers.Authorization == nil, "connector set credentials")
			if body then
				assert(req.headers["Content-Type"][1] == "application/json")
				assert(req.body == body, req.body)
			else
				assert(req.body == nil and req.headers == nil, "unexpected body")
			end
		end

		responses = {{body = '{"id":"new"}'}}
		local event = c.insertEvent({summary = "Planning", start = {dateTime = "2026-10-13T09:00:00Z"}, ["end"] = {dateTime = "2026-10-13T10:00:00Z"}, attendees = {{email = "ana@example.com"}}, sendUpdates = "all", conferenceDataVersion = 1})
		assert(event.id == "new")
		sent("POST", API .. "primary/events?sendUpdates=all&conferenceDataVersion=1",
			'{"attendees":[{"email":"ana@example.com"}],"end":{"dateTime":"2026-10-13T10:00:00Z"},"start":{"dateTime":"2026-10-13T09:00:00Z"},"summary":"Planning"}')

		-- A caller-chosen id makes a repeated insert fail with 409 rather than duplicate the event.
		responses = {{body = '{"id":"planning20261013"}'}}
		c.insertEvent({calendarId = "team@group.calendar.google.com", id = "planning20261013", summary = "Planning", start = {date = "2026-10-13"}, ["end"] = {date = "2026-10-14"}})
		sent("POST", API .. "team%40group.calendar.google.com/events", '{"end":{"date":"2026-10-14"},"id":"planning20261013","start":{"date":"2026-10-13"},"summary":"Planning"}')

		responses = {{body = '{"id":"new","summary":"Moved"}'}, {body = '{"id":"new"}'}, {body = '{"id":"q1"}'}, {status = 204}}
		assert(c.patchEvent({eventId = "new", summary = "Moved", sendUpdates = "none"}).summary == "Moved")
		sent("PATCH", API .. "primary/events/new?sendUpdates=none", '{"summary":"Moved"}')
		c.moveEvent({eventId = "new", destination = "team@group.calendar.google.com"})
		sent("POST", API .. "primary/events/new/move?destination=team%40group.calendar.google.com")
		c.quickAddEvent({text = "Lunch with Ana tomorrow 12pm", sendUpdates = "all"})
		sent("POST", API .. "primary/events/quickAdd?text=Lunch%20with%20Ana%20tomorrow%2012pm&sendUpdates=all")
		assert(c.deleteEvent({calendarId = "team@group.calendar.google.com", eventId = "new", sendUpdates = "all"}).success == true)
		sent("DELETE", API .. "team%40group.calendar.google.com/events/new?sendUpdates=all")

		local count = #requests
		assert(not pcall(c.patchEvent, {summary = "No ID"}), "patchEvent requires eventId")
		assert(not pcall(c.deleteEvent, {eventId = "e", summary = "x"}), "deleteEvent takes no body")
		assert(not pcall(c.moveEvent, {eventId = "e/../x", destination = "primary"}))
		assert(not pcall(c.quickAddEvent, {text = "Lunch", start = {}}), "quickAddEvent takes no body")
		assert(not pcall(c.insertEvent, {calendarId = "..", summary = "x"}))
		assert(not pcall(c.insertEvent, "Planning"))
		assert(#requests == count, "invalid input reached Google")
		assert(#responses == 0)
	end,
}
