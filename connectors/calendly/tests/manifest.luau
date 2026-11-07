return {
	contract = function(m)
		do
			local readScopes = {
				"users:read",
				"organizations:read",
				"event_types:read",
				"availability:read",
				"scheduled_events:read",
				"locations:read",
				"routing_forms:read",
				"groups:read",
				"webhooks:read",
				"contacts:read",
				"meeting_recaps:read",
				"activity_log:read",
				"outgoing_communications:read",
			}
			local writeScopes = {
				"organizations:write",
				"event_types:write",
				"availability:write",
				"scheduled_events:write",
				"scheduling_links:write",
				"shares:write",
				"webhooks:write",
				"contacts:write",
				"meeting_recaps:write",
			}
			local api = "https://api.calendly.com"
			for _, method in { "token", "oauth" } do
				for _, access in { "read-only", "read-write" } do
					local config = { access = access }
					local input = { token = "calendly-pat" }
					if method == "oauth" then
						config["client_id"], config["client_secret"], input =
							"fixture-client", "fixture-secret", nil
					end
					local r, err = m.resolve(nil, config, input, method)
					assert(not err, tostring(err))
					local token = "calendly-pat"
					if method == "oauth" then
						local scopes = readScopes
						if access == "read-write" then
							scopes = m.concat(readScopes, writeScopes)
						end
						if not (m.equal(r.Scopes, scopes)) then
							m.fail("access=%s scopes %s", access, r.Scopes)
						end
						token = "calendly-oauth"
						r.Context.Auth["oauth"].access_token = token
					end
					m.routes(r, "Bearer " .. token, true, {
						"GET " .. api .. "/users/me",
						"GET " .. api .. "/scheduled_events?user=https%3A%2F%2Fapi.calendly.com%2Fusers%2FU1",
						"GET " .. api .. "/scheduled_events/E1/invitees/I1",
						"GET " .. api .. "/organizations/O1/invitations/INV1",
						"GET " .. api .. "/meeting_recaps/R1/transcript",
					})
					m.routes(r, "Bearer " .. token, (access == "read-write"), {
						"POST " .. api .. "/invitees",
						"POST " .. api .. "/scheduled_events/E1/cancellation",
						"PATCH " .. api .. "/event_type_availability_schedules?event_type=x",
						"DELETE " .. api .. "/webhook_subscriptions/W1",
						"DELETE " .. api .. "/organization_memberships/M1",
					})
					m.routes(r, "Bearer " .. token, false, {
						"POST " .. api .. "/users/me/deletion",
						"POST " .. api .. "/data_compliance/deletion/invitees",
						"DELETE " .. api .. "/event_types/T1",
						"PUT " .. api .. "/event_types/T1",
						"GET https://calendly.com/users/me",
						"GET https://auth.calendly.com/oauth/token",
						"GET " .. api .. "/scheduled_events/%2e%2e/users/me",
					})
				end
			end
		end
	end,
}
