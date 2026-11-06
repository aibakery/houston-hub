-- Every authored first example crosses the real connector/HTTP boundary. The
-- generated requests bind examples to the provider's advertised route contract.
local function same(a, b)
	if type(a) ~= "table" or type(b) ~= "table" then return a == b end
	for key, value in a do if not same(value, b[key]) then return false end end
	for key in b do if a[key] == nil then return false end end
	return true
end
return {
	scenario = {publisher = {}, config = {store_host = "shop.example.com", access = "read-write"}, auth_method = "keys", auth_config = {consumer_key = "ck_fixture", consumer_secret = "cs_fixture"}},
	configure = function()
		current, requestCount = nil, 0
		fs = fixture.files()
		http = {request = function(req)
			assert(current, "unexpected provider request")
			requestCount += 1
			assert(req.method == current.method and req.url == "https://shop.example.com/wp-json/wc/v3" .. current.path, req.method .. " " .. req.url)
			if current.file then
				assert(await(req.body:readAll()) == "fixture media bytes", "upload body changed")
				assert(req.headers["Content-Type"][1] == current.content_type)
				assert(req.headers["Content-Disposition"][1] == 'attachment; filename="' .. current.filename .. '"')
			elseif current.body then
				assert(req.headers["Content-Type"][1] == "application/json")
				assert(same(json.decode(req.body), current.body), req.body)
			else
				assert(req.body == nil, "read/delete sent a body")
			end
			return fixture.operation({statusCode = 200, headers = {["x-wp-total"] = {"1"}, ["x-wp-totalpages"] = {"1"}},
				body = fixture.reader(if current.list then '[{"id":42}]' else '{"id":42}')})
		end}
	end,
	run = function(connector)
		local cases = require("lib/example-requests.luau")
		local calls = 0
		for name in connector do
			assert(cases[name], "missing example fixture for " .. name)
			for index, expected in cases[name] do
				current = table.clone(expected)
				current.list = string.sub(name, 1, 4) == "list" and name ~= "listPostTypes" and name ~= "listPostStatuses" and name ~= "listTaxonomies"
				if current.file then
					local file = fs.open(current.file, "w")
					file:write("fixture media bytes")
					await(file:close())
				end
				local before = requestCount
				local result = fixture.example(name, index)
				assert(requestCount == before + 1, name .. " made an unexpected number of requests")
				if current.list then
					assert(result.items[1].id == 42 and result.total == 1 and result.total_pages == 1)
				else
					assert(result.id == 42)
				end
				calls += 1
			end
		end
		assert(calls == requestCount and calls > 0)
	end,
}
