return {
	scenario = {publisher = {}, config = {access = "read-write", client_id = "fixture-client", client_secret = "fixture-secret"},
		auth_method = "oauth", auth_config = {}},
	configure = function()
		requests = {}
		status = 201
		payload = "{}"
		http = {request = function(req)
			table.insert(requests, req)
			return fixture.operation({statusCode = status, headers = {}, body = fixture.reader(payload)})
		end}
	end,
	run = function(calendly)
		local API = "https://api.calendly.com"
		local NULL = json.decode("null")
		local function last() return requests[#requests] end
		local function sent() return json.decode(last().body) end

		local count = 0
		for name in calendly do if name ~= "help" then count += 1 end end
		assert(count == 63, "wrong read-write surface: " .. count)

		payload = '{"resource":{"uri":"https://api.calendly.com/scheduled_events/E9/invitees/I9","cancel_url":"https://calendly.com/cancellations/I9"}}'
		local booked = calendly.createInvitee({event_type = "https://api.calendly.com/event_types/T1", start_time = "2026-10-20T15:00:00Z",
			invitee = {email = "ana@example.com", timezone = "Europe/Paris", name = "Ana"}, event_guests = json.decode("[]"),
			location = {kind = "zoom_conference"}})
		assert(last().method == "POST" and last().url == API .. "/invitees")
		assert(last().headers["Content-Type"][1] == "application/json")
		local body = sent()
		assert(body.event_type == "https://api.calendly.com/event_types/T1" and body.invitee.timezone == "Europe/Paris")
		assert(json.encode(body.event_guests) == "[]" and body.location.kind == "zoom_conference")
		assert(booked.resource.cancel_url == "https://calendly.com/cancellations/I9")

		payload = '{"resource":{"canceled_by":"Host","reason":null}}'
		calendly.cancelScheduledEvent({event = "https://api.calendly.com/scheduled_events/E9", reason = "Conflict"})
		assert(last().method == "POST" and last().url == API .. "/scheduled_events/E9/cancellation")
		body = sent()
		assert(body.reason == "Conflict" and body.event == nil, "path field leaked into the body")
		calendly.cancelScheduledEvent({event = "E9"})
		assert(last().body == "{}", "an empty body must still be a JSON object")

		payload = '{"resource":{"booking_url":"https://calendly.com/d/abc","owner":"https://api.calendly.com/event_types/T1","owner_type":"EventType"}}'
		local link = calendly.createSchedulingLink({owner = "https://api.calendly.com/event_types/T1", owner_type = "EventType", max_event_count = 1})
		assert(last().url == API .. "/scheduling_links" and sent().max_event_count == 1 and link.resource.booking_url == "https://calendly.com/d/abc")

		status = 200
		payload = '{"resource":{"rules":[]}}'
		calendly.updateEventTypeAvailability({event_type = "https://api.calendly.com/event_types/T1",
			availability_rule = {timezone = "Europe/Paris", rules = {{type = "wday", wday = "monday", intervals = {{from = "09:00", to = "17:00"}}}}}})
		assert(last().method == "PATCH" and last().url == API .. "/event_type_availability_schedules?event_type=https%3A%2F%2Fapi.calendly.com%2Fevent_types%2FT1")
		body = sent()
		assert(body.event_type == nil and body.availability_rule.rules[1].intervals[1].from == "09:00")

		calendly.updateContact({contact = "C1", company = NULL})
		assert(last().method == "PATCH" and last().url == API .. "/contacts/C1" and sent().company == NULL)

		status = 204
		payload = ""
		local deleted = calendly.deleteWebhookSubscription({webhook = "https://api.calendly.com/webhook_subscriptions/W1"})
		assert(last().method == "DELETE" and last().url == API .. "/webhook_subscriptions/W1" and last().body == nil)
		assert(deleted.success == true)
		calendly.revokeOrganizationInvitation({organization = "O1", invitation = "INV1"})
		assert(last().method == "DELETE" and last().url == API .. "/organizations/O1/invitations/INV1")
		assert(#requests == 8)
	end,
}
