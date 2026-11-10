return {
	contract = function(m)
		local api = "https://graph.microsoft.com/v1.0/me"
		for access, scopes in {["read-only"] = {"Calendars.Read"}, ["read-write"] = {"Calendars.ReadWrite"}} do
			local r, err = m.resolve({client_id = "publisher-client", client_secret = "publisher-secret"}, {access = access}, nil, "oauth")
			assert(r and not err, tostring(err))
			assert(m.equal(r.Scopes, m.concat({"offline_access", "User.Read"}, scopes)), "requested OAuth scopes for " .. access)
			r.Context.Auth.oauth.access_token = "fixture-token"
			local reads = {
				"GET " .. api .. "/calendar", "GET " .. api .. "/calendars?$top=50", "GET " .. api .. "/calendars/AAMk-_%3D",
				"GET " .. api .. "/calendarView?startDateTime=2026-11-09T00%3A00%3A00Z&endDateTime=2026-11-16T00%3A00%3A00Z",
				"GET " .. api .. "/calendars/C1/calendarView?startDateTime=2026-11-09&endDateTime=2026-11-16&$skip=10",
				"GET " .. api .. "/events/AAMk-_%3D", "GET " .. api .. "/events/E1/instances?startDateTime=2026-11-09&endDateTime=2026-12-09",
				"GET " .. api .. "/calendars/C1/events/E1", "GET " .. api .. "/calendars/C1/events/E1/instances?startDateTime=2026-11-09&endDateTime=2026-12-09",
				"POST " .. api .. "/calendar/getSchedule",
			}
			m.routes(r, "Bearer fixture-token", true, reads)
			m.rejectOverrides(r, reads)
			local writes = {
				"POST " .. api .. "/events", "POST " .. api .. "/calendars/C1/events", "PATCH " .. api .. "/events/E1", "DELETE " .. api .. "/events/E1",
				"POST " .. api .. "/events/E1/accept", "POST " .. api .. "/events/E1/tentativelyAccept", "POST " .. api .. "/events/E1/decline",
				"POST " .. api .. "/events/E1/cancel", "PATCH " .. api .. "/calendars/C1/events/E1", "DELETE " .. api .. "/calendars/C1/events/E1",
				"POST " .. api .. "/calendars/C1/events/E1/accept", "POST " .. api .. "/calendars/C1/events/E1/tentativelyAccept",
				"POST " .. api .. "/calendars/C1/events/E1/decline", "POST " .. api .. "/calendars/C1/events/E1/cancel",
			}
			m.routes(r, "Bearer fixture-token", access == "read-write", writes)
			if access == "read-write" then m.rejectOverrides(r, writes) end
			-- The token stays off Microsoft's token endpoint, batches that could wrap writes, other users,
			-- APIs and mailboxes, lookalike hosts and calendar routes the connector never calls: event
			-- lists outside a time range, permanent deletes, calendar changes and sharing, forwards,
			-- attachments, reminders and meeting-time suggestions.
			m.routes(r, "Bearer fixture-token", false, {
				"POST https://login.microsoftonline.com/common/oauth2/v2.0/token", "POST https://graph.microsoft.com/v1.0/$batch",
				"GET https://graph.microsoft.com/v1.0/users/other@example.com/calendarView", "GET https://graph.microsoft.com/beta/me/calendarView",
				"GET " .. api .. "/messages", "GET " .. api .. "/drive", "GET " .. api, "GET https://graph.microsoft.com.evil.test/v1.0/me/calendar",
				"GET " .. api .. "/events/%2e%2e/x", "GET " .. api .. "/events", "GET " .. api .. "/calendarView/delta",
				"GET " .. api .. "/calendarGroups", "GET " .. api .. "/calendars/C1/calendarPermissions", "POST " .. api .. "/calendars",
				"PATCH " .. api .. "/calendars/C1", "DELETE " .. api .. "/calendars/C1", "POST " .. api .. "/events/E1/forward",
				"GET " .. api .. "/events/E1/attachments", "POST " .. api .. "/events/E1/attachments", "POST " .. api .. "/events/E1/snoozeReminder",
				"POST " .. api .. "/events/E1/dismissReminder", "POST " .. api .. "/findMeetingTimes", "PUT " .. api .. "/events/E1",
				"GET " .. api .. "/calendars/C1/events", "POST " .. api .. "/calendars/C1/events/E1/forward",
				"POST " .. api .. "/events/E1/permanentDelete", "POST " .. api .. "/calendars/C1/permanentDelete", "PATCH " .. api .. "/calendar",
				"GET " .. api .. "/calendar/events", "POST https://graph.microsoft.com/v1.0/users/other@example.com/calendar/getSchedule",
				"GET " .. api .. "/calendars/../calendarView", "GET " .. api .. "/events/E1/../../messages",
			})
		end
	end,
}
