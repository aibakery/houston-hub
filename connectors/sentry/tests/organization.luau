return {
	scenario = {publisher = {}, config = {organization = "acme/../other"}, auth_method = "token", auth_config = {token = "fixture-token"}},
	configure = function()
		calls = 0
		http = {request = function()
			calls += 1
			return fixture.operation({statusCode = 200, headers = {}, body = fixture.reader("[]")})
		end}
	end,
	run = function(sentry)
		-- An invalid organization still loads, so help works, but no call reaches Sentry.
		local ok, err = pcall(function() sentry.listProjects() end)
		assert(not ok and string.find(tostring(err), "organization must be its slug or id", 1, true), tostring(err))
		assert(calls == 0, "an invalid organization reached Sentry")
	end,
}
