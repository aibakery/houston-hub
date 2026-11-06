return {
	scenario = {publisher = {}, config = {store_host = "shop.example.com", access = "read-write"}, auth_method = "key",
		auth_config = {token = "0123456789ABCDEF0123456789ABCDEF"}},
	configure = function()
		requests = {}
		payload = "{}"
		http = {request = function(req)
			table.insert(requests, req)
			return fixture.operation({statusCode = if req.method == "POST" then 201 else 200, headers = {}, body = fixture.reader(payload)})
		end}
	end,
	run = function(shop)
		local API = "https://shop.example.com/api/"
		local XML = '<?xml version="1.0" encoding="UTF-8"?><prestashop>'
		local function last() return requests[#requests] end
		local function sentXML() return last().headers["Content-Type"][1] == "application/xml" end

		-- The reads are read_only.luau's exact 44; everything else must be these writes.
		local names, reads = {}, 0
		for name in shop do
			if string.match(name, "^get%u") or string.match(name, "^list%u") then reads += 1
			elseif name ~= "help" then table.insert(names, name) end
		end
		assert(reads == 44, "wrong read count: " .. reads)
		table.sort(names)
		assert(table.concat(names, ",") == "createCustomer,createOrderHistory,createProduct,deleteCustomer,deleteProduct,updateCustomer,updateOrderCarrier,updateProduct,updateStockAvailable",
			"wrong writes: " .. table.concat(names, ","))

		payload = '{"products":[{"id":"10","price":"9.500000","active":"1","name":[{"id":"1","value":"Mug & co"}]}]}'
		local product = fixture.example("createProduct")
		assert(last().method == "POST" and last().url == API .. "products?display=full" and sentXML())
		assert(last().headers.Authorization == nil, "connector set credentials")
		assert(last().body == XML .. '<product><active>1</active><associations><categories><item><id>2</id></item><item><id>5</id></item></categories></associations><description_short>&lt;b&gt;New&lt;/b&gt;</description_short><name><language id="1">Mug &amp; co</language></name><price>9.5</price></product></prestashop>', last().body)
		assert(product.product.id == "10")

		fixture.example("updateProduct")
		assert(last().method == "PATCH" and last().url == API .. "products/10?display=full&id_shop=2" and sentXML())
		assert(last().body == XML .. "<product><id>10</id><name>Mug</name><price>12.00</price></product></prestashop>", last().body)
		-- An empty association clears it; PrestaShop replaces the whole set.
		fixture.example("updateProduct", 2)
		assert(last().body == XML .. "<product><id>10</id><associations><categories></categories></associations></product></prestashop>", last().body)

		payload = '{"stock_availables":[{"id":31,"quantity":"12"}]}'
		assert(fixture.example("updateStockAvailable").stock_available.quantity == "12")
		assert(last().method == "PATCH" and last().url == API .. "stock_availables/31?display=full")
		assert(last().body == XML .. "<stock_available><id>31</id><quantity>12</quantity></stock_available></prestashop>", last().body)

		payload = '{"order_histories":[{"id":"88","id_order":"123","id_order_state":"4"}]}'
		local history = fixture.example("createOrderHistory")
		assert(last().method == "POST" and last().url == API .. "order_histories?display=full&sendemail=1", last().url)
		assert(last().body == XML .. "<order_history><id_order>123</id_order><id_order_state>4</id_order_state></order_history></prestashop>", last().body)
		assert(history.order_history.id_order_state == "4")

		payload = '{"order_carriers":[{"id":7,"tracking_number":"1Z999"}]}'
		assert(fixture.example("updateOrderCarrier").order_carrier.tracking_number == "1Z999")
		assert(last().method == "PATCH" and last().url == API .. "order_carriers/7?display=full", last().url)
		assert(last().body == XML .. "<order_carrier><id>7</id><tracking_number>1Z999</tracking_number></order_carrier></prestashop>")

		payload = '{"customers":[{"id":"6","email":"bo@example.com","passwd":"$2y$10$hash","secure_key":"abcd"}]}'
		local customer = fixture.example("createCustomer")
		assert(last().method == "POST" and last().url == API .. "customers?display=full")
		assert(last().body == XML .. "<customer><email>bo@example.com</email><firstname>Bo</firstname><lastname>Lee</lastname><newsletter>0</newsletter><passwd>replace-with-new-customer-password</passwd></customer></prestashop>", last().body)
		assert(customer.customer.email == "bo@example.com" and customer.customer.passwd == nil and customer.customer.secure_key == nil)

		payload = ""
		assert(fixture.example("deleteProduct") == true)
		assert(last().method == "DELETE" and last().url == API .. "products/10" and last().body == nil)
		assert(fixture.example("deleteCustomer") == true)
		assert(last().method == "DELETE" and last().url == API .. "customers/6?id_shop=1")

		payload = '{"products":[{"id":10}]}'
		assert(shop.listProducts({display = {"id"}}).products[1].id == 10)
		assert(last().method == "GET" and last().url == API .. "products?display=%5Bid%5D&limit=0%2C50")
		assert(#requests == 10)
	end,
}
