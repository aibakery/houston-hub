return {
	scenario = {publisher = {}, config = {access = "read-write"}, auth_method = "api_key", auth_config = {token = "cal_live_fixture"}},
	configure = function()
		requests = {}
		payload = '{"status":"success","data":{}}'
		http = {request = function(req)
			table.insert(requests, req)
			return fixture.operation({statusCode = 200, headers = {}, body = fixture.reader(payload)})
		end}
	end,
	run = function(cal)
		local API = "https://api.cal.com/v2"
		local NULL = json.decode("null")
		local function last() return requests[#requests] end
		local function sent() return json.decode(last().body) end

		local count = 0
		for name in cal do if name ~= "help" then count += 1 end end
		assert(count == 94, "wrong read-write surface: " .. count)

		payload = '{"status":"success","data":{"uid":"b9","status":"accepted","guests":[],"location":null}}'
		local booking = cal.createBooking({eventTypeId = 123, start = "2026-10-15T07:00:00Z",
			attendee = {name = "Ana", email = "ana@example.com", timeZone = "Europe/Paris"}, guests = json.decode("[]"), metadata = {source = "agent"}})
		assert(last().method == "POST" and last().url == API .. "/bookings")
		assert(last().headers["cal-api-version"][1] == "2026-02-25" and last().headers["Content-Type"][1] == "application/json")
		local body = sent()
		assert(body.eventTypeId == 123 and body.attendee.timeZone == "Europe/Paris" and json.encode(body.guests) == "[]")
		assert(booking.data.uid == "b9" and booking.data.location == NULL)

		cal.cancelBooking({bookingUid = "b9", cancellationReason = "Conflict"})
		assert(last().url == API .. "/bookings/b9/cancel")
		body = sent()
		assert(body.cancellationReason == "Conflict" and body.bookingUid == nil, "path field leaked into the body")
		cal.confirmBooking({bookingUid = "b9"})
		assert(last().url == API .. "/bookings/b9/confirm" and last().body == nil and last().headers["Content-Type"] == nil)
		local ok, err = pcall(function() cal.confirmBooking({bookingUid = "b9", reason = "typo"}) end)
		assert(not ok and string.find(tostring(err), "confirmBooking has no option reason", 1, true))
		cal.reassignBooking({bookingUid = "b9"})
		assert(last().method == "POST" and last().url == API .. "/bookings/b9/reassign" and last().body == nil)
		cal.reassignBookingToUser({bookingUid = "b9", userId = 42, reason = "Coverage"})
		assert(last().url == API .. "/bookings/b9/reassign/42" and sent().reason == "Coverage" and sent().userId == nil)
		cal.updateBookingLocation({bookingUid = "b9", location = {type = "address", address = "1 Main St"}})
		assert(last().method == "PATCH" and last().headers["cal-api-version"][1] == "2024-08-13" and sent().location.type == "address")

		cal.replaceBookingFields({eventTypeId = 123, bookingFields = json.decode("[]")})
		assert(last().method == "PUT" and last().url == API .. "/event-types/123/booking-fields" and json.encode(sent().bookingFields) == "[]")
		cal.deleteBookingField({eventTypeId = 123, slug = "company-size"})
		assert(last().method == "DELETE" and last().url == API .. "/event-types/123/booking-fields/company-size" and last().body == nil)
		cal.updateMe({bio = NULL, timeZone = "Europe/Paris"})
		assert(last().method == "PATCH" and last().url == API .. "/me" and sent().bio == NULL and last().headers["cal-api-version"] == nil)
		cal.updateSchedule({scheduleId = 9, availability = {{days = {"Monday"}, startTime = "09:00", endTime = "17:00"}}})
		assert(last().url == API .. "/schedules/9" and sent().availability[1].days[1] == "Monday" and sent().scheduleId == nil)
		cal.setDefaultConferencingApp({app = "google-meet"})
		assert(last().method == "POST" and last().url == API .. "/conferencing/google-meet/default" and last().body == nil and last().headers["Content-Type"] == nil)
		cal.deleteSlotReservation({reservationUid = "e2a7bcf9-cc7b-40a0-80d3-657d391775a6"})
		assert(last().method == "DELETE" and last().url == API .. "/slots/reservations/e2a7bcf9-cc7b-40a0-80d3-657d391775a6")
		cal.listWebhooks({take = 10})
		assert(last().method == "GET" and last().url == API .. "/webhooks?take=10", "read-write connections read webhooks")
		payload = ""
		local deleted = cal.deleteWorkflow({workflowId = 5})
		assert(last().method == "DELETE" and last().url == API .. "/workflows/5" and deleted.status == "success")
		assert(#requests == 14)
	end,
}
