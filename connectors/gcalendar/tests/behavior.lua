return {
	scenario = {publisher = {client_id = "fixture-client", client_secret = "fixture-private-secret"}, config = {}, auth_method = "oauth", auth_config = {}},
	config = {access = "read-write"},
	configure = function()
		requests, responses = {}, {}
		http = {request = function(req)
			table.insert(requests, req)
			assert(#responses > 0, "unexpected request: " .. req.url)
			local response = table.remove(responses, 1)
			return fixture.operation({statusCode = response.status or 200, headers = response.headers or {}, body = fixture.reader(response.body or "")})
		end}
	end,
	run = function(c)
		local API = "https://www.googleapis.com/calendar/v3"
		responses = {{body = '{"items":[{"id":"e1"}],"nextPageToken":"next+1"}'}, {body = '{"kind":"calendar#events"}'}}
		local page = c.listEvents({timeMin = "2026-10-12T00:00:00Z", singleEvents = true, pageToken = "start+1", eventTypes = {"default", "focusTime"}})
		assert(page.nextPageToken == "next+1" and page.items[1].id == "e1")
		assert(requests[1].method == "GET" and requests[1].body == nil)
		assert(requests[1].url == API .. "/calendars/primary/events?timeMin=2026-10-12T00%3A00%3A00Z&pageToken=start%2B1&singleEvents=true&eventTypes=default&eventTypes=focusTime", requests[1].url)
		local empty = c.listEvents({calendarId = "team@group.calendar.google.com"})
		assert(json.encode(empty.items) == "[]", "absent lists must be empty arrays")
		assert(requests[2].url == API .. "/calendars/team%40group.calendar.google.com/events")

		responses = {{body = '{"id":"new"}'}, {body = '{"id":"new","summary":"Moved"}'}, {status = 204}}
		local event = c.insertEvent({summary = "Planning", start = {dateTime = "2026-10-13T09:00:00Z"}, ["end"] = {dateTime = "2026-10-13T10:00:00Z"}, attendees = {{email = "ana@example.com"}}, sendUpdates = "all"})
		assert(event.id == "new")
		assert(requests[3].method == "POST" and requests[3].url == API .. "/calendars/primary/events?sendUpdates=all")
		assert(requests[3].headers["Content-Type"][1] == "application/json")
		local body = json.decode(requests[3].body)
		assert(body.summary == "Planning" and body.attendees[1].email == "ana@example.com" and body.sendUpdates == nil)
		c.patchEvent({eventId = "new", summary = "Moved"})
		assert(requests[4].method == "PATCH" and requests[4].url == API .. "/calendars/primary/events/new")
		assert(c.deleteEvent({eventId = "new"}).success)
		assert(requests[5].method == "DELETE")

		local count = #requests
		for _, args in {{eventId = ""}, {eventId = 42}, {eventId = "e", unknown = true}, {"e"}} do
			assert(not pcall(c.getEvent, args))
		end
		assert(not pcall(c.getEvent, "e"))
		assert(not pcall(c.listEvents, {eventTypes = {{}}}))
		assert(#requests == count, "invalid input reached Google")

		for _, status in {400, 403, 404, 429, 500} do
			responses = {{status = status, headers = {["retry-after"] = {"7"}}, body = '{"error":{"code":403,"message":"Rate Limit Exceeded","status":"PERMISSION_DENIED","errors":[{"reason":"rateLimitExceeded"}]}}'}}
			local ok, err = pcall(c.listCalendars)
			local message = tostring(err)
			assert(not ok and string.find(message, "Rate Limit Exceeded", 1, true) and string.find(message, "rateLimitExceeded", 1, true) and string.find(message, "Retry-After: 7", 1, true), message)
		end
		responses = {{status = 401, body = "not json"}}
		assert(not pcall(c.listCalendars))
		for _, bad in {"not JSON", "[]", "null"} do
			responses = {{body = bad}}
			assert(not pcall(c.getCalendar), "accepted invalid response " .. bad)
		end
		assert(#responses == 0)
	end,
}
