return {
	scenario = {config = {access = "read-write"}, auth_method = "api_key", auth_config = {token = "cal_live_fixture"}},
	configure = function()
		requests = {}
		http = {request = function(req)
			table.insert(requests, req)
			return fixture.operation({statusCode = 200, headers = {}, body = fixture.reader('{"status":"success","data":{},"futureField":true}')})
		end}
	end,
	run = function(c)
		local routes, docs = require("lib/example-routes.luau"), require("lib/help.luau")
		local count = 0
		for name in c do if name ~= "help" then count += 1; assert(routes[name], name) end end
		assert(count == 94)
		for name, route in routes do
			for index, example in docs[name].inputSchema.examples do
				local expected = table.clone(example)
				local path = string.gsub(route.path, "{([%w_]+)}", function(field) expected[field] = nil; return tostring(example[field]) end)
				local query = {}
				for _, field in route.query do
					local value = example[field]
					if value ~= nil then
						local values = if type(value) == "table" then value else {value}
						for _, item in values do table.insert(query, field .. "=" .. url.encode(item)) end
					end
					expected[field] = nil
				end
				if #query > 0 then path ..= "?" .. table.concat(query, "&") end
				local before = #requests
				local result = fixture.example(name, index)
				assert(result.status == "success" and result.futureField and #requests == before + 1, name)
				local req = requests[#requests]
				assert(req.method == route.method and req.url == "https://api.cal.com" .. path, name .. ": " .. req.url)
				assert(req.headers.Authorization == nil)
				if route.version ~= "" then assert(req.headers["cal-api-version"][1] == route.version, name) end
				if route.body then
					if route.wrap ~= "" then expected = expected[route.wrap] end
					assert(json.encode(json.decode(req.body)) == json.encode(expected), name .. " changed native body fields")
					assert(req.headers["Content-Type"][1] == "application/json")
				else assert(req.body == nil) end
			end
		end
	end,
}
