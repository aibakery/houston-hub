return {
	scenario = {publisher = {}, config = {access = "read-write"}, auth_method = "token", auth_config = {token = "fixture-token"}},
	configure = function()
		requests = {}
		http = {request = function(req)
			table.insert(requests, req)
			return fixture.operation({statusCode = 200, headers = {}, body = fixture.reader('{"resource":{"id":"example"}}')})
		end}
	end,
	run = function(c)
		local cases = require("lib/example-requests.luau")
		local function equal(actual, expected)
			if type(expected) ~= "table" then assert(actual == expected, "request value differs"); return end
			assert(type(actual) == "table", "expected object or array")
			for key, value in expected do equal(actual[key], value) end
			for key in actual do assert(expected[key] ~= nil, "unexpected field " .. tostring(key)) end
		end
		local count = 0
		for name in c do
			if name ~= "help" then
				for index, expected in assert(cases[name], "missing request example " .. name) do
					local before = #requests
					local result = fixture.example(name, index)
					assert(#requests == before + 1, name .. " must make exactly one request")
					local actual = requests[#requests]
					assert(actual.method == expected.method and actual.url == expected.url, name .. ": " .. actual.url)
					if expected.body then equal(json.decode(actual.body), expected.body) else assert(actual.body == nil) end
					assert(result.resource.id == "example")
					count += 1
				end
			end
		end
		assert(count >= 63)
	end,
}
