return {
	contract = function(m)
		do
			local api = "https://api.cal.com/v2"
			for _, access in { "read-only", "read-write" } do
				local r, err = m.resolve(nil, { access = access }, { token = "cal_live_fixture" }, "api_key")
				assert(not err, tostring(err))
				m.routes(r, "Bearer cal_live_fixture", true, {
					"GET " .. api .. "/me",
					"GET " .. api .. "/bookings?status=upcoming&limit=20",
					"GET " .. api .. "/bookings/2NtaeaVcKfpmSZ4CthFdfk",
					"GET " .. api .. "/slots?eventTypeId=1&start=2026-10-15&end=2026-10-16",
					"GET " .. api .. "/teams/3/bookings",
					"POST " .. api .. "/routing-forms/f1/calculate-slots?start=2026-10-15&end=2026-10-16",
				})
				m.routes(r, "Bearer cal_live_fixture", (access == "read-write"), {
					"GET " .. api .. "/webhooks",
					"GET " .. api .. "/event-types/1/webhooks/w1",
					"POST " .. api .. "/bookings",
					"POST " .. api .. "/bookings/b1/cancel",
					"PATCH " .. api .. "/event-types/1",
					"PUT " .. api .. "/event-types/1/booking-fields",
					"DELETE " .. api .. "/webhooks/w1",
					"POST " .. api .. "/conferencing/zoom/default",
				})
				m.routes(r, "Bearer cal_live_fixture", false, {
					"POST " .. api .. "/api-keys/refresh",
					"POST " .. api .. "/credits/charge",
					"POST " .. api .. "/calendars/apple/credentials",
					"GET " .. api .. "/organizations/1/users",
					"DELETE " .. api .. "/event-types/1/webhooks",
					"PATCH " .. api .. "/bookings/b1",
					"GET https://api.cal.com/v1/bookings",
					"GET https://api.cal.eu/v2/me",
					"GET https://app.cal.com/v2/me",
					"GET " .. api .. "/bookings/%2e%2e/me",
				})
			end
		end
	end,
}
