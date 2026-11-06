return {
	scenario = {config = {access = "read-write"}, auth_method = "token", auth_config = {token = "fixture-key"}},
	configure = function()
		requests = {}
		http = {request = function(req)
			table.insert(requests, req)
			return fixture.operation({statusCode = 200, headers = {}, body = fixture.reader('{"futureField":true}')})
		end}
	end,
	run = function(c)
		local routes, docs = require("lib/example-routes.luau"), require("lib/help.luau")
		local count = 0
		for name in c do if name ~= "help" then count += 1; assert(routes[name], name) end end
		assert(count == 128)
		for name, route in routes do
			for index, example in docs[name].inputSchema.examples do
				local expected = table.clone(example)
				local path = string.gsub(route.path, "{([%w_]+)}", function(field) expected[field] = nil; return tostring(example[field]) end)
				local query = {}
				for _, field in route.query do
					local value = example[field]
					if value ~= nil then
						local values = if type(value) == "table" then value else {value}
						local encoded = {}; for _, item in values do table.insert(encoded, url.encode(item)) end
						if field == "fundCartaIds" or field == "prospectPublicIds" then encoded = {table.concat(encoded, ",")} end
						for _, item in encoded do table.insert(query, field .. "=" .. item) end
					end
					expected[field] = nil
				end
				if #query > 0 then path ..= "?" .. table.concat(query, "&") end
				local before = #requests
				local result = fixture.example(name, index)
				assert(result.futureField and #requests == before + 1, name)
				local req = requests[#requests]
				assert(req.method == route.method and req.url == "https://crm-public-api.app.carta.com" .. path, name .. ": " .. req.url)
				assert(req.headers.Authorization == nil)
				if route.body then
					assert(json.encode(json.decode(req.body)) == json.encode(expected), name .. " changed native body fields")
					assert(req.headers["Content-Type"][1] == "application/json")
				else assert(req.body == nil) end
			end
		end
	end,
}
