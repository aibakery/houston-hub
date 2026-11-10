return {
	scenario = {publisher = {client_id = "fixture-client", client_secret = "fixture-private-secret"}, config = {}, auth_method = "oauth", auth_config = {}},
	config = {access = "read-write"},
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
		local function last() return requests[#requests] end
		local function fails(expected: {string}, fn: (...any) -> any, ...: any)
			local ok, err = pcall(fn, ...)
			assert(not ok, "call succeeded")
			for _, text in expected do assert(string.find(tostring(err), text, 1, true), "missing " .. text .. " in " .. tostring(err)) end
		end
		local names = {}
		for name in c do table.insert(names, name) end
		table.sort(names)
		assert(table.concat(names, ",") == "acceptEvent,cancelEvent,createEvent,declineEvent,deleteEvent,getCalendar,getEvent,getSchedule,listCalendars,listEventInstances,listEvents,tentativelyAcceptEvent,updateEvent", "read-write got " .. table.concat(names, ","))

		local start = {dateTime = "2026-11-12T10:00:00", timeZone = "Europe/Paris"}
		local finish = {dateTime = "2026-11-12T11:00:00", timeZone = "Europe/Paris"}
		responses = {{status = 201, body = '{"id":"E1","subject":"Design review"}'}, {status = 201, body = '{"id":"E2"}'}}
		assert(c.createEvent({subject = "Design review", start = start, ["end"] = finish, transactionId = "t-1",
			attendees = {{emailAddress = {address = "ana@example.com"}, type = "required"}}}).id == "E1")
		assert(last().method == "POST" and last().url == API .. "/events" and last().headers["Content-Type"][1] == "application/json", last().url)
		local body = json.decode(last().body)
		assert(body.subject == "Design review" and body["end"].dateTime == "2026-11-12T11:00:00" and body.transactionId == "t-1" and body.attendees[1].type == "required")
		c.createEvent({calendarId = "C-1=", subject = "Focus", start = start, ["end"] = finish, isAllDay = false})
		body = json.decode(last().body)
		assert(last().url == API .. "/calendars/C-1%3D/events" and body.calendarId == nil and body.isAllDay == false, last().url)

		responses = {{body = '{"id":"E1","location":{"displayName":"Room 7"}}'}, {status = 204}, {status = 202}, {status = 202}, {status = 202}, {status = 202}, {status = 202}}
		assert(c.updateEvent({id = "E1", location = {displayName = "Room 7"}}).location.displayName == "Room 7")
		body = json.decode(last().body)
		assert(last().method == "PATCH" and last().url == API .. "/events/E1" and body.id == nil and body.location.displayName == "Room 7", last().url)
		assert(c.deleteEvent({id = "E1"}).success and last().method == "DELETE" and last().url == API .. "/events/E1" and last().body == nil)
		assert(c.cancelEvent({id = "E1", comment = "Moving to next week."}).success and last().url == API .. "/events/E1/cancel")
		assert(json.decode(last().body).comment == "Moving to next week.")
		-- A reply without fields still posts a JSON object.
		assert(c.acceptEvent({id = "E3"}).success and last().url == API .. "/events/E3/accept" and last().body == "{}", tostring(last().body))
		c.tentativelyAcceptEvent({id = "E3", comment = "May be late", sendResponse = false})
		body = json.decode(last().body)
		assert(last().url == API .. "/events/E3/tentativelyAccept" and body.sendResponse == false and body.id == nil, last().url)
		c.declineEvent({id = "E3", proposedNewTime = {start = start, ["end"] = finish}})
		assert(last().url == API .. "/events/E3/decline" and json.decode(last().body).proposedNewTime.start.timeZone == "Europe/Paris", last().url)
		c.cancelEvent({id = "E4"})
		assert(last().url == API .. "/events/E4/cancel" and last().body == "{}", tostring(last().body))
		-- Events of a shared calendar are changed and answered through that calendar.
		responses = {{body = '{"id":"E5"}'}, {status = 204}, {status = 202}}
		c.updateEvent({calendarId = "C1", id = "E5", subject = "Moved"})
		body = json.decode(last().body)
		assert(last().url == API .. "/calendars/C1/events/E5" and body.subject == "Moved" and body.calendarId == nil and body.id == nil, last().url)
		assert(c.deleteEvent({calendarId = "C1", id = "E5"}).success and last().method == "DELETE" and last().url == API .. "/calendars/C1/events/E5", last().url)
		c.declineEvent({calendarId = "C1", id = "E6", sendResponse = false})
		assert(last().url == API .. "/calendars/C1/events/E6/decline" and last().body == '{"sendResponse":false}', tostring(last().body))

		-- Invalid input never reaches the network.
		local before = #requests
		fails({"createEvent requires start and end"}, c.createEvent, {subject = "No time"})
		fails({"calendarId must be a nonempty string"}, c.createEvent, {calendarId = "", start = start, ["end"] = finish})
		fails({"updateEvent requires fields to change"}, c.updateEvent, {id = "E1"})
		fails({"updateEvent requires fields to change"}, c.updateEvent, {id = "E1", calendarId = "C1"})
		fails({"id must be a nonempty string"}, c.updateEvent, {subject = "x"})
		fails({"id must be a nonempty string"}, c.acceptEvent, {comment = "ok"})
		fails({"deleteEvent received an unknown option"}, c.deleteEvent, {id = "E1", sendUpdates = "all"})
		assert(#requests == before, "invalid input reached the network")

		-- A refused write keeps Graph's reason and is not retried blindly.
		responses = {
			{status = 400, body = '{"error":{"code":"ErrorInvalidRequest","message":"Your request can\'t be completed. You need to be an organizer to cancel a meeting."}}'},
			{status = 503, headers = {["retry-after"] = {"30"}}, body = '{"error":{"code":"ServiceUnavailable","message":"Try later"}}'},
		}
		fails({"HTTP 400 (ErrorInvalidRequest)", "need to be an organizer", '"retryable":false'}, c.cancelEvent, {id = "E3"})
		fails({"HTTP 503 (ServiceUnavailable)", "Retry-After: 30", '"retryable":true'}, c.createEvent, {start = start, ["end"] = finish})
	end,
}
