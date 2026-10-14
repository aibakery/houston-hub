return {
	scenario = {publisher = {}, config = {}, auth_method = "api_key", auth_config = {token = "cal_live_fixture"}},
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
		local function version() return last().headers["cal-api-version"] and last().headers["cal-api-version"][1] end
		local function rejected(fn, expected)
			local before = #requests
			local ok, err = pcall(fn)
			assert(not ok and string.find(tostring(err), expected, 1, true), "wrong validation error: " .. tostring(err))
			assert(#requests == before, "invalid input reached Cal.com")
		end

		local names = {}
		for name in cal do if name ~= "help" then table.insert(names, name) end end
		assert(#names == 44, "wrong read-only surface: " .. #names)
		for _, name in {"createBooking", "cancelBooking", "rescheduleBooking", "updateMe", "createWebhook", "deleteEventType",
			"reserveSlot", "replaceBookingFields", "createWorkflow", "requestPhoneVerificationCode", "setDefaultConferencingApp",
			"listWebhooks", "getWebhook", "listEventTypeWebhooks", "getEventTypeWebhook"} do
			assert(cal[name] == nil, "read-only leaked " .. name)
		end
		assert(cal.calculateRoutingFormSlots, "calculateRoutingFormSlots only reads")
		assert(#requests == 0, "initialization reached Cal.com")

		payload = '{"status":"success","data":{"id":7,"email":"ana@example.com","bio":null}}'
		local me = cal.getMe()
		assert(last().method == "GET" and last().url == API .. "/me" and last().body == nil and version() == nil)
		assert(last().headers.Accept[1] == "application/json")
		assert(me.data.id == 7 and me.data.bio == NULL)

		payload = '{"status":"success","data":[{"uid":"b1","attendees":[],"location":null}],"pagination":{"hasMore":true,"nextCursor":"c2"}}'
		local opts = {status = "upcoming", afterStart = "2026-10-14T00:00:00Z", eventTypeIds = "100,200", limit = 20, cursor = "c1"}
		local page = cal.listBookings(opts)
		assert(last().url == API .. "/bookings?status=upcoming&eventTypeIds=100%2C200&afterStart=2026-10-14T00%3A00%3A00Z&cursor=c1&limit=20", last().url)
		assert(version() == "2026-05-01" and opts.limit == 20, "wrong version or modified options")
		assert(page.pagination.nextCursor == "c2" and json.encode(page.data[1].attendees) == "[]" and page.data[1].location == NULL)

		payload = '{"status":"success","data":[]}'
		local empty = cal.listTeamBookings({teamId = 3, status = "upcoming,past", take = 50})
		assert(last().url == API .. "/teams/3/bookings?status=upcoming%2Cpast&take=50" and version() == nil, last().url)
		assert(json.encode(empty.data) == "[]")

		cal.getBooking({bookingUid = "2NtaeaVcKfpmSZ4CthFdfk"})
		assert(last().url == API .. "/bookings/2NtaeaVcKfpmSZ4CthFdfk" and version() == "2026-02-25")
		cal.listBookingAttendees({bookingUid = "b1"})
		assert(last().url == API .. "/bookings/b1/attendees" and version() == "2024-08-13")
		cal.getEventType({eventTypeId = 123})
		assert(last().url == API .. "/event-types/123" and version() == "2026-06-12")
		cal.listPrivateLinks({eventTypeId = 123})
		assert(version() == "2024-09-04")
		cal.getSchedule({scheduleId = 9})
		assert(last().url == API .. "/schedules/9" and version() == "2024-06-11")
		cal.listWorkflows({take = 10, skip = 10})
		assert(last().url == API .. "/workflows?take=10&skip=10" and version() == "2026-09-22")

		payload = '{"status":"success","data":{"2026-10-15":[{"start":"2026-10-15T09:00:00.000+02:00"}]}}'
		local slots = cal.getSlots({eventTypeId = 123, start = "2026-10-15", ["end"] = "2026-10-22", timeZone = "Europe/Paris"})
		assert(last().url == API .. "/slots?start=2026-10-15&end=2026-10-22&timeZone=Europe%2FParis&eventTypeId=123", last().url)
		assert(version() == "2024-09-04" and slots.data["2026-10-15"][1].start == "2026-10-15T09:00:00.000+02:00")

		cal.getBusyTimes({dateFrom = "2026-10-15", dateTo = "2026-10-16", calendar = {"135,alice@example.com", "200,bob@example.com"}})
		assert(last().url == API .. "/calendars/busy-times?dateFrom=2026-10-15&dateTo=2026-10-16&calendar=135%2Calice%40example.com&calendar=200%2Cbob%40example.com", last().url)

		cal.calculateRoutingFormSlots({routingFormId = "form-1", start = "2026-10-15", ["end"] = "2026-10-16", answers = {company = "Acme", duration = "30 minutes"}})
		assert(last().method == "POST" and last().url == API .. "/routing-forms/form-1/calculate-slots?start=2026-10-15&end=2026-10-16")
		local answers = json.decode(last().body)
		assert(answers.company == "Acme" and answers.duration == "30 minutes" and answers.start == nil and answers.answers == nil)

		rejected(function() cal.getBooking() end, "bookingUid must be an ID")
		rejected(function() cal.getBooking({bookingUid = "../me"}) end, "bookingUid must be an ID")
		rejected(function() cal.getBooking({bookingUid = ""}) end, "bookingUid must be an ID")
		rejected(function() cal.getEventType({eventTypeId = 1.5}) end, "nonnegative integer")
		rejected(function() cal.getEventType({eventTypeId = -1}) end, "nonnegative integer")
		rejected(function() cal.getSlots({eventTypeId = 123, start = "2026-10-15"}) end, "end is required")
		rejected(function() cal.getSlots({eventTypeId = 123, start = NULL, ["end"] = "x"}) end, "start is required")
		rejected(function() cal.listBookings({statuz = "upcoming"}) end, "listBookings has no option statuz")
		rejected(function() cal.getBusyTimes({dateFrom = "2026-10-15", dateTo = "2026-10-16"}) end, "calendar is required")
		rejected(function() cal.getBusyTimes({dateFrom = "a", dateTo = "b", calendar = json.decode("[]")}) end, "calendar must not be an empty array")
		rejected(function() cal.calculateRoutingFormSlots({routingFormId = "f", start = "a", ["end"] = "b"}) end, "answers must be an object")
		rejected(function() cal.calculateRoutingFormSlots({routingFormId = "f", start = "a", ["end"] = "b", answers = {}, company = "Acme"}) end, "has no option company")
		rejected(function() cal.listBookings({status = {upcoming = true}}) end, "array, not an object")
		rejected(function() cal.listBookings({status = {{"upcoming"}}}) end, "must be a string, boolean, number")
		rejected(function() cal.listBookings("upcoming") end, "opts must be an object")
		rejected(function() cal.listBookings({"upcoming"}) end, "named fields")
		assert(#requests == 12)
	end,
}
