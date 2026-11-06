-- Execute the rendered examples, including positional statFile and content headers.
-- Native response shapes and access enforcement are covered by the route fixtures.
return {
	scenario = {publisher = {client_id = "fixture-app-key", client_secret = "fixture-private-secret"}, auth_method = "oauth", auth_config = {}},
	config = {access = "read-write"},
	configure = function()
		requests = {}
		fs = fixture.files()
		local source = fs.open("report.pdf", "w"); source:write("PDF" .. string.char(0, 255)); await(source:close())
		http = {request = function(req)
			table.insert(requests, req)
			if type(req.body) == "userdata" then req.uploaded = await(req.body:readAll()) end
			return fixture.operation({statusCode = 200, headers = {["dropbox-api-result"] = {json.encode({id = "id:file", name = "report.pdf"})}}, body = fixture.reader(payload)})
		end}
	end,
	run = function(c)
		local routes = require("lib/example-routes.luau")
		local schemas = require("lib/schemas.luau")
		local count = 0
		for name in c do if name ~= "help" then count += 1 end end
		assert(count == 70)
		local checked = 0
		for name, route in routes do
			checked += 1
			for index, example in schemas[name].examples do
				payload = if route.style == "download" then "PDF" .. string.char(0, 255) else '{"futureField":true}'
				local before = #requests
				local result = fixture.example(name, index)
				assert(#requests == before + 1, name .. " unexpectedly paged or retried")
				local req = requests[#requests]
				local base = if route.style == "rpc" then "https://api.dropboxapi.com/2/" else "https://content.dropboxapi.com/2/"
				assert(req.method == "POST" and req.url == base .. route.route, name)
				if route.void then
					assert(req.body == nil and req.headers == nil)
				elseif route.style == "rpc" then
					assert(req.headers["Content-Type"][1] == "application/json")
					assert(json.encode(json.decode(req.body)) == json.encode(example), name .. " changed example fields")
				else
					local expected = table.clone(example); expected.session_path = nil
					assert(json.encode(json.decode(req.headers["Dropbox-API-Arg"][1])) == json.encode(expected), name .. " changed content arguments")
					if route.style == "upload" then assert(req.uploaded == "PDF" .. string.char(0, 255))
					else
						assert(req.body == nil and result.session_path == example.session_path and result.size == #payload and type(result.url) == "string")
						local file = fs.open(result.session_path, "r"); assert(await(file:readAll()) == payload); file:close()
						assert(result.result.id == "id:file")
					end
				end
				if route.style ~= "download" then assert(result.futureField == true) end
			end
		end
		assert(checked == 69)
		payload = '{".tag":"file","id":"id:file","name":"report.pdf","size":5}'
		local result = fixture.example("statFile")
		assert(result.id == "id:file" and result.name == "report.pdf" and result.size == 5 and not result.isFolder)
		assert(json.decode(requests[#requests].body).path == "/Reports/report.pdf")
	end,
}
