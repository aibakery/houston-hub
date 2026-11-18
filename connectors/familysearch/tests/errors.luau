return {
	scenario = {config = {environment = "beta"}, access = {data = "write"}, auth_method = "token", auth_config = {token = "fixture-token"}},
	configure = function()
		requests, responses = {}, {}
		http = {request = function(req)
			table.insert(requests, req)
			local response = table.remove(responses, 1)
			assert(response, "unexpected request")
			return fixture.operation({statusCode = response.status, headers = response.headers or {}, body = fixture.reader(response.body or "")})
		end}
	end,
	run = function(c)
		for _, case in {{401, "Reconnect", false}, {403, "permission", false}, {404, "Not found", false}, {429, "Retry-After: 60", true}, {500, "upstream", true}} do
			responses = {{status = case[1], headers = {["retry-after"] = {"60"}}, body = '{"errors":[{"message":"Not found upstream"}]}'}}
			local ok, err = pcall(c.tree.persons.readPerson, {pid = "P1"})
			local message = tostring(err)
			assert(not ok and string.find(message, '"upstream_status":' .. tostring(case[1]), 1, true) and string.find(message, '"retryable":' .. tostring(case[3]), 1, true), message)
			assert(string.find(message, case[2], 1, true), message)
		end
		responses = {{status = 500, body = '{"errors":[{"message":"Write failed"}]}'}}
		local ok, err = pcall(c.tree.persons.updatePerson, {pid = "P1", body = {persons = {{id = "P1"}}}})
		assert(not ok and string.find(tostring(err), '"retryable":false', 1, true) and string.find(tostring(err), "may already have applied", 1, true))
		responses = {{status = 304}}
		ok, err = pcall(c.tree.persons.deletePerson, {pid = "P1"})
		assert(not ok and string.find(tostring(err), '"upstream_status":304', 1, true))
		responses = {{status = 200, body = "<html>sign in</html>"}}
		ok, err = pcall(c.tree.persons.readPerson, {pid = "P1"})
		assert(not ok and string.find(tostring(err), "invalid JSON", 1, true))
		responses = {{status = 302, headers = {location = {"https://untrusted.invalid/"}}}}
		ok, err = pcall(c.tree.persons.readPerson, {pid = "P1"})
		assert(not ok and string.find(tostring(err), '"upstream_status":302', 1, true))
		assert(#requests == 9, "unexpected retries or redirects")
		for _, request in requests do assert(string.find(request.url, "https://apibeta.familysearch.org/platform/", 1, true) == 1) end
	end,
}
