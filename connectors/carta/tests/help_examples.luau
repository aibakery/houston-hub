return {
	scenario = {config = {access = "read-write", own_app = true, client_id = "fixture-client", client_secret = "fixture-secret"}, auth_method = "own_app", auth_config = {}},
	configure = function()
		requests = {}
		fs = fixture.files()
		http = {request = function(req)
			if req.body ~= nil and type(req.body) ~= "string" then req.body = await(req.body:readAll()) end
			table.insert(requests, req)
			return fixture.operation({statusCode = 200, headers = {}, body = fixture.reader('{"futureField":true}')})
		end}
	end,
	run = function(c)
		local file = fs.open("captable.zip", "w"); file:write("PK\3\4example"); await(file:close())
		local routes, docs = require("lib/example-routes.luau"), require("lib/help.luau")
		local count = 0
		for name in c do if name ~= "help" then count += 1; assert(routes[name], name) end end
		assert(count == 79)
		for name, route in routes do
			for index, example in docs[name].inputSchema.examples do
				local expected = table.clone(example)
				local path = string.gsub(route.path, "{([%w_]+)}", function(field) expected[field] = nil; return tostring(example[field]) end)
				local query = {}
				for _, field in route.query do
					local value = example[field]
					if value ~= nil then
						if type(value) == "table" then local values = {}; for _, item in value do table.insert(values, url.encode(item)) end; value = table.concat(values, ",") else value = url.encode(value) end
						table.insert(query, field .. "=" .. value)
					end
					expected[field] = nil
				end
				if #query > 0 then path ..= "?" .. table.concat(query, "&") end
				for _, field in route.extra do expected[field] = nil end
				local before = #requests
				local result = fixture.example(name, index)
				assert(result.futureField and #requests == before + 1, name)
				local req = requests[#requests]
				assert(req.method == route.method and req.url == "https://api.carta.com" .. path, name .. ": " .. req.url)
				assert(req.headers.Authorization == nil)
				if name == "uploadOpenCapTable" then assert(req.body == "PK\3\4example" and req.headers["Content-Type"][1] == "application/zip")
				elseif route.body then
					assert(json.encode(json.decode(req.body)) == json.encode(expected), name .. " changed native body fields")
					assert(req.headers["Content-Type"][1] == "application/json")
				else assert(req.body == nil) end
			end
		end
	end,
}
