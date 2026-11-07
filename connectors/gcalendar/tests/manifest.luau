return {
	contract = function(m)
		local function google(access, scopes)
			local r, err = m.resolve(
				{ client_id = "publisher-client", client_secret = "publisher-secret" },
				{ access = access },
				nil,
				"oauth"
			)
			assert(r and not err, tostring(err))
			local want = { "https://www.googleapis.com/auth/userinfo.email" }
			for _, scope in scopes do
				table.insert(want, "https://www.googleapis.com/auth/" .. scope)
			end
			assert(m.equal(r.Scopes, want), "requested OAuth scopes")
			r.Context.Auth.oauth.access_token = "fixture-token"
			return r
		end
		do
			local api = "https://www.googleapis.com/calendar/v3"
			local team = api .. "/calendars/team%40group.calendar.google.com"
			for _, access in { "read-only", "read-write" } do
				local scopes = { "calendar.readonly" }
				if access == "read-write" then
					scopes = m.concat(scopes, { "calendar.events" })
				end
				local r = google(access, scopes)
				local reads = {
					"GET " .. api .. "/users/me/calendarList?maxResults=250",
					"GET " .. api .. "/colors",
					"GET " .. api .. "/calendars/primary",
					"GET "
						.. api
						.. "/calendars/en.usa%23holiday%40group.v.calendar.google.com/events?singleEvents=true",
					"GET " .. team .. "/events/e1",
					"GET " .. team .. "/events/e1/instances",
					"POST " .. api .. "/freeBusy",
				}
				m.routes(r, "Bearer fixture-token", true, reads)
				m.rejectOverrides(r, reads)
				local writes = {
					"POST " .. team .. "/events?sendUpdates=all",
					"POST " .. api .. "/calendars/primary/events/quickAdd?text=Lunch",
					"POST " .. team .. "/events/e1/move?destination=primary",
					"PATCH " .. team .. "/events/e1",
					"DELETE " .. team .. "/events/e1",
				}
				m.routes(r, "Bearer fixture-token", (access == "read-write"), writes)
				if access == "read-write" then
					m.rejectOverrides(r, writes)
				end
				m.routes(r, "Bearer fixture-token", false, {
					"POST https://oauth2.googleapis.com/token",
					"GET https://www.googleapis.com/drive/v3/files",
					"GET https://www.googleapis.com.evil.test/calendar/v3/calendars/primary",
					"GET https://calendar-json.googleapis.com/calendar/v3/calendars/primary",
					"GET https://content.googleapis.com/calendar/v3/calendars/primary",
					"POST https://www.googleapis.com/batch/calendar/v3",
					"GET " .. api .. "/calendars/primary/acl",
					"POST " .. api .. "/calendars/primary/acl",
					"POST " .. api .. "/calendars",
					"DELETE " .. api .. "/calendars/c1",
					"PUT " .. api .. "/calendars/primary",
					"PATCH " .. api .. "/calendars/primary",
					"POST " .. api .. "/calendars/primary/clear",
					"PUT " .. team .. "/events/e1",
					"POST " .. team .. "/events/import",
					"POST " .. team .. "/events/watch",
					"POST " .. api .. "/users/me/calendarList",
					"POST " .. api .. "/users/me/calendarList/watch",
					"DELETE " .. api .. "/users/me/calendarList/c1",
					"GET " .. api .. "/users/me/settings",
					"POST " .. api .. "/channels/stop",
					"GET " .. team .. "/events/%2e%2e/acl",
					"GET " .. api .. "/calendars/primary%2F..%2Facl/events",
				})
			end
		end
	end,
}
