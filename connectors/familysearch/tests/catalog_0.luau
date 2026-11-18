-- Execute every documented example once across four bounded scenarios.
-- The fixture inspector cannot import test helpers before inspecting scenario metadata.
return {
	scenario = {config = {environment = "beta"}, access = {data = "write"}, auth_method = "token", auth_config = {token = "fixture-token"}},
	configure = function()
		fs = fixture.files()
		http = {request = function(req) return handler(req) end}
	end,
	run = function()
	local bucket = 0
	local catalog = require("catalog.luau")
	local expected: any = nil
	local operationName = ""
	local requests: {any} = {}
	handler = function(req: any): any
		table.insert(requests, req)
		assert(expected, "no expected operation")
		assert(req.method == expected.method, operationName .. " used wrong method")
		assert(string.find(req.url, "https://apibeta.familysearch.org/platform/", 1, true) == 1)
		if req.body ~= nil and type(req.body) ~= "string" then req.body = await(req.body:readAll()) end
		local status = expected.success[1] or 200
		local body = if status == 200 and expected.method ~= "HEAD" then (if expected.accept == "text/html" then "<p>Story</p>" else '{"fixture":true}') else ""
		return fixture.operation({statusCode = status, headers = {location = {"https://apibeta.familysearch.org/platform/memories/memories/fixture"}}, body = fixture.reader(body)})
	end
	for _, path in {"uploads/memory.txt", "uploads/story.html"} do
		local file = fs.open(path, "w")
		file:write("Fixture story")
		await(file:close())
	end
	local names: {string} = {}
	for name in catalog do table.insert(names, name) end
	table.sort(names)
	local exercised = 0
	for index, name in names do
		if (index - 1) % 4 == bucket then
			expected, operationName = catalog[name], name
			local result = fixture.example(expected.export)
			assert(result.statusCode == expected.success[1], name .. " lost provider status")
			local sent = requests[#requests]
			local path = string.gsub(expected.path, "{([%w_]+)}", function(field: string): string return url.segment(expected.example[field], field) end)
			assert(string.find(sent.url, "https://apibeta.familysearch.org" .. path, 1, true) == 1, name .. " used wrong route")
			if expected.body and expected.example.body then
				assert(sent.headers["Content-Type"][1] == expected.body.contentType)
				assert(json.encode(json.decode(sent.body)) == json.encode(expected.example.body), name .. " changed document")
			end
			exercised += 1
		end
	end
	assert(exercised >= 50 and #requests == exercised)
	end,
}
