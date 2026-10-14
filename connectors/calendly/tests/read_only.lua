return {
	scenario = {publisher = {}, config = {}, auth_method = "token", auth_config = {token = "fixture-token"}},
	configure = function()
		requests = {}
		payload = "{}"
		http = {request = function(req)
			table.insert(requests, req)
			return fixture.operation({statusCode = 200, headers = {}, body = fixture.reader(payload)})
		end}
	end,
	run = function(calendly)
		local API = "https://api.calendly.com"
		local NULL = json.decode("null")
		local function last() return requests[#requests] end
		local function rejected(fn, expected)
			local before = #requests
			local ok, err = pcall(fn)
			assert(not ok and string.find(tostring(err), expected, 1, true), "wrong validation error: " .. tostring(err))
			assert(#requests == before, "invalid input reached Calendly")
		end

		local names = {}
		for name in calendly do if name ~= "help" then table.insert(names, name) end end
		assert(#names == 43, "wrong read-only surface: " .. #names)
		for _, name in {"createInvitee", "cancelScheduledEvent", "createEventType", "updateEventTypeAvailability", "createSchedulingLink",
			"createShare", "createWebhookSubscription", "deleteWebhookSubscription", "inviteUserToOrganization", "deleteContact"} do
			assert(calendly[name] == nil, "read-only leaked " .. name)
		end
		assert(#requests == 0, "initialization reached Calendly")

		payload = '{"resource":{"uri":"https://api.calendly.com/users/U1","current_organization":"https://api.calendly.com/organizations/O1","avatar_url":null}}'
		local me = calendly.getCurrentUser().resource
		assert(last().method == "GET" and last().url == API .. "/users/me" and last().body == nil)
		assert(last().headers.Accept[1] == "application/json")
		assert(me.uri == "https://api.calendly.com/users/U1" and me.avatar_url == NULL)

		payload = '{"collection":[{"uri":"https://api.calendly.com/scheduled_events/E1","event_guests":[]}],"pagination":{"count":1,"next_page_token":"tok2","next_page":null}}'
		local opts = {user = me.uri, status = "active", min_start_time = "2026-10-14T00:00:00Z", count = 50, page_token = "tok1"}
		local page = calendly.listScheduledEvents(opts)
		assert(last().url == API .. "/scheduled_events?user=https%3A%2F%2Fapi.calendly.com%2Fusers%2FU1&status=active&min_start_time=2026-10-14T00%3A00%3A00Z&count=50&page_token=tok1", last().url)
		assert(opts.user == me.uri and opts.count == 50, "caller options were modified")
		assert(page.pagination.next_page_token == "tok2" and page.pagination.next_page == NULL)
		assert(json.encode(page.collection[1].event_guests) == "[]")

		payload = '{"collection":[],"pagination":{"count":0,"next_page_token":null}}'
		local empty = calendly.listInvitees({event = "https://api.calendly.com/scheduled_events/E1"})
		assert(last().url == API .. "/scheduled_events/E1/invitees")
		assert(json.encode(empty.collection) == "[]")

		payload = '{"resource":{"uri":"https://api.calendly.com/scheduled_events/E1/invitees/I1"}}'
		calendly.getInvitee({event = "E1", invitee = "https://api.calendly.com/scheduled_events/E1/invitees/I1"})
		assert(last().url == API .. "/scheduled_events/E1/invitees/I1")
		calendly.getOrganizationInvitation({organization = me.current_organization, invitation = "INV-1_a"})
		assert(last().url == API .. "/organizations/O1/invitations/INV-1_a")

		calendly.listActivityLogEntries({organization = me.current_organization, action = {"Add", "Remove"}, namespace = {"User"}})
		assert(last().url == API .. "/activity_log_entries?organization=https%3A%2F%2Fapi.calendly.com%2Forganizations%2FO1&namespace=User&action=Add,Remove", last().url)
		calendly.listEventTypes({user = me.uri, active = true})
		assert(last().url == API .. "/event_types?user=https%3A%2F%2Fapi.calendly.com%2Fusers%2FU1&active=true")
		calendly.listContactCustomFields()
		assert(last().url == API .. "/contacts/custom_field_definitions")
		payload = ""
		assert(calendly.getGroup({group = "G1"}).success == true, "an empty 200 response is a success")

		rejected(function() calendly.getScheduledEvent() end, "event must be a UUID or Calendly URI")
		rejected(function() calendly.getScheduledEvent({event = "../users/me"}) end, "UUID or Calendly URI")
		rejected(function() calendly.getScheduledEvent({event = "a/b"}) end, "UUID or Calendly URI")
		rejected(function() calendly.getScheduledEvent({event = "https://evil.example/scheduled_events/E1"}) end, "UUID or Calendly URI")
		rejected(function() calendly.getScheduledEvent({event = 7}) end, "UUID or Calendly URI")
		rejected(function() calendly.getScheduledEvent({event = me.uri}) end, "event must be a scheduled_events URI or UUID")
		rejected(function() calendly.getInvitee({event = "https://api.calendly.com/scheduled_events/E1/invitees/I1", invitee = "I1"}) end, "event must be a scheduled_events URI")
		rejected(function() calendly.listActivityLogEntries({organization = me.current_organization, action = json.decode("[]")}) end, "action must not be an empty array")
		rejected(function() calendly.listUserBusyTimes({user = me.uri, start_time = "2026-10-15T00:00:00Z"}) end, "end_time is required")
		rejected(function() calendly.listUserBusyTimes({user = NULL, start_time = "a", end_time = "b"}) end, "user is required")
		rejected(function() calendly.listScheduledEvents({usr = me.uri}) end, "listScheduledEvents has no option usr")
		rejected(function() calendly.listScheduledEvents({status = {active = true}}) end, "array, not an object")
		rejected(function() calendly.listScheduledEvents({status = {{"active"}}}) end, "must be a string, boolean, number")
		rejected(function() calendly.listScheduledEvents("active") end, "opts must be an object")
		rejected(function() calendly.listScheduledEvents({"active"}) end, "named fields")
		assert(#requests == 9)
	end,
}
