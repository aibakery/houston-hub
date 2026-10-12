return {
	scenario = {publisher = {client_id = "fixture-client", client_secret = "fixture-private-secret"}, config = {}, auth_method = "oauth", auth_config = {}},
	config = {access = "read-only"},
	run = function(c)
		for _, name in {"insertEvent", "patchEvent", "deleteEvent", "moveEvent", "quickAddEvent"} do
			assert(c[name] == nil, "read-only leaked " .. name)
		end
		for _, name in {"listCalendars", "getCalendar", "listEvents", "getEvent", "listEventInstances", "queryFreeBusy"} do
			assert(type(c[name]) == "function", "missing " .. name)
		end
	end,
}
