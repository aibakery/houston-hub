-- Exercise every rendered example through the real options/header/body transport.
return {
	scenario = {publisher = {}, config = {access = "read-write"}, auth_method = "api_key", auth_config = {token = "re_fixture"}},
	configure = function()
		requests = {}
		fs = fixture.files()
		local file = fs.open("contacts.csv", "w"); file:write("Email,First Name\nana@example.com,Ana\n"); await(file:close())
		local multipart = http.multipart
		http = {multipart = multipart, request = function(req)
			if req.body ~= nil and type(req.body) ~= "string" then req.body = await(req.body:readAll()) end
			table.insert(requests, req)
			local body = if req.url == "https://cdn.resend.com/attachment.pdf" then "PDF" .. string.char(0, 255) else if download then '{"id":"attachment-1","download_url":"https://cdn.resend.com/attachment.pdf"}' else if req.url == "https://api.resend.com/emails/batch" then '{"data":[{"id":"resource-1"}],"futureField":true}' else '{"id":"resource-1","futureField":true}'
			return fixture.operation({statusCode = 200, headers = {}, body = fixture.reader(body)})
		end}
	end,
	run = function(c)
		local schemas = require("lib/schemas.luau")
		local cases = require("lib/example-routes.luau")
		local count = 0
		for name in c do if name ~= "help" then count += 1 end end
		assert(count == 133)
		local checked = 0
		for name, case in cases do
			checked += 1
			for index, example in schemas[name].examples do
				local expected = table.clone(example)
				local path = string.gsub(case.path, "{([%w_]+)}", function(field)
					local value = expected[field]; expected[field] = nil
					return url.segment(value)
				end)
				local query = {}
				for _, field in case.query do
					local value = expected[field]; expected[field] = nil
					if value == nil and field == "limit" then value = 100 end
					if value ~= nil then
						local values = if type(value) == "table" then value else {value}
						local encoded = {}; for _, item in values do table.insert(encoded, url.encode(item)) end
						table.insert(query, field .. "=" .. table.concat(encoded, ","))
					end
				end
				if #query > 0 then path ..= "?" .. table.concat(query, "&") end
				for _, field in case.extra do expected[field] = nil end
				download = example.path ~= nil and not case.upload
				local before = #requests
				local result = fixture.example(name, index)
				assert(#requests == before + (if download then 2 else 1), name .. " unexpectedly paged or retried")
				local req = requests[before + 1]
				assert(req.url == "https://api.resend.com" .. path and req.method == case.method, name)
				assert(req.headers.Authorization == nil)
				assert((if req.headers["Idempotency-Key"] then req.headers["Idempotency-Key"][1] else nil) == example.idempotency_key)
				if case.upload then
					assert(string.find(req.headers["Content-Type"][1], "multipart/form-data; boundary=", 1, true))
					assert(string.find(req.body, 'name="file"; filename="contacts.csv"', 1, true))
					assert(string.find(req.body, "Email,First Name\nana@example.com,Ana\n", 1, true))
					for field, value in expected do
						local serialized = if type(value) == "table" then json.encode(value) else tostring(value)
						assert(string.find(req.body, 'name="' .. field .. '"\r\n\r\n' .. serialized .. '\r\n', 1, true), "incorrect multipart field " .. field)
					end
				elseif case.body then
					assert(req.headers["Content-Type"][1] == "application/json")
					assert(json.encode(json.decode(req.body)) == json.encode(if case.wrap == "" then expected else expected[case.wrap]), name .. " changed body fields")
				else assert(req.body == nil) end
				if download then
					assert(result.path == example.path and result.size == 5 and type(result.url) == "string" and result.attachment.id == "attachment-1")
					local file = fs.open(result.path, "r"); assert(await(file:readAll()) == "PDF" .. string.char(0, 255)); file:close()
				elseif name == "sendBatchEmails" then assert(result.data[1].id == "resource-1" and result.futureField)
				else assert(result.id == "resource-1" and result.futureField) end
			end
		end
		assert(checked == 133)
	end,
}
