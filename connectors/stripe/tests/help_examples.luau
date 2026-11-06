return {
	scenario = {config = {access = "read-write"}, auth_method = "token", auth_config = {token = "rk_test_fixture"}},
	configure = function()
		requests = {}
		fs = fixture.files()
		local multipart = http.multipart
		http = {multipart = multipart, request = function(req)
			if req.body ~= nil and type(req.body) ~= "string" then req.body = await(req.body:readAll()) end
			table.insert(requests, req)
			return fixture.operation({statusCode = 200, headers = {}, body = fixture.reader(if download then "%PDF\0data" else '{"futureField":true}')})
		end}
	end,
	run = function(c)
		local file = fs.open("evidence.pdf", "w"); file:write("%PDF\0evidence"); await(file:close())
		local schemas = require("lib/schemas.luau")
		local routes = require("lib/example-routes.luau")
		local count = 0
		for name in c do if name ~= "help" then count += 1; assert(routes[name], name) end end
		assert(count == 69)
		local bodies = {
			createCustomer = "address%5Bcountry%5D=US&address%5Bpostal_code%5D=94107&email=ana%40example.com&metadata%5Bproject%5D=demo&name=Ana%20Example",
			updateCustomer = "metadata%5Bold_key%5D=&metadata%5Bproject%5D=demo&shipping=",
			createSubscription = "customer=cus_example&items%5B0%5D%5Bprice%5D=price_example&items%5B0%5D%5Bquantity%5D=1&payment_behavior=default_incomplete",
			createPaymentIntent = "amount=1500&automatic_payment_methods%5Benabled%5D=true&currency=usd&customer=cus_example",
			updateDispute = "evidence%5Bcustomer_name%5D=Ana%20Example&evidence%5Breceipt%5D=file_example&evidence%5Buncategorized_text%5D=Service%20was%20delivered%20on%20the%20agreed%20date.&submit=false",
		}
		local queries = {
			listBalanceTransactions = "created%5Bgte%5D=1790812800&limit=20&type=charge",
			listCustomers = "email=ana%40example.com&expand%5B0%5D=data.default_source&limit=20",
			listEvents = "limit=20&types%5B0%5D=invoice.paid&types%5B1%5D=invoice.payment_failed",
			cancelSubscription = "invoice_now=false&prorate=false",
		}
		for name, route in routes do
			for index, example in schemas[name].examples do
				download = route.download
				local before = #requests
				local result = fixture.example(name, index)
				assert(#requests == before + 1, name .. " unexpectedly paged or retried")
				local req = requests[#requests]
				local path = string.gsub(route.path, "{([%w_]+)}", function(key) return example[key] end)
				local base = "https://" .. (if route.upload or download then "files.stripe.com" else "api.stripe.com") .. path
				assert(req.method == route.method and string.split(req.url, "?")[1] == base, name .. ": " .. req.url)
				assert(req.headers.Authorization == nil and req.headers["Stripe-Version"][1] == "2026-09-30.endive")
				if example.idempotency_key then assert(req.headers["Idempotency-Key"][1] == example.idempotency_key) end
				if bodies[name] then assert(req.body == bodies[name], name .. ": " .. tostring(req.body)) end
				if queries[name] then assert(req.url == base .. "?" .. queries[name], name .. ": " .. req.url) end
				if route.upload then
					for _, fragment in {'name="file"; filename="evidence.pdf"', 'Content-Type: application/pdf', '%PDF\0evidence', 'name="purpose"\r\n\r\ndispute_evidence', 'name="file_link_data[create]"\r\n\r\nfalse'} do assert(string.find(req.body, fragment, 1, true), fragment) end
				elseif route.method == "POST" then assert(req.headers["Content-Type"][1] == "application/x-www-form-urlencoded")
				else assert(req.body == nil) end
				if download then
					assert(result.path == example.path and result.size == 9 and type(result.url) == "string")
					file = fs.open(result.path, "r"); assert(await(file:readAll()) == "%PDF\0data"); file:close()
				else assert(result.futureField) end
			end
		end
	end,
}
