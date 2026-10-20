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

		local count = 0
		for name in shop do if name ~= "help" then count += 1 end end
		assert(count == 53, "wrong read-write surface: " .. count)
		for _, name in {"createOrder", "updateOrder", "deleteOrder", "createStockAvailable", "deleteStockAvailable",
			"deleteOrderHistory", "updateCategory"} do
			assert(shop[name] == nil, "unexpected write " .. name)
		end

		payload = '{"product":{"id":"10","price":"9.500000","name":[{"id":"1","value":"Mug & co"}]}}'
		local product = shop.createProduct({price = 9.5, active = true, name = {{id = 1, value = "Mug & co"}},
			description_short = "<b>New</b>", associations = {categories = {{id = 2}, {id = 5}}}})
		assert(last().method == "POST" and last().url == API .. "products" and sentXML())
		assert(last().headers.Authorization == nil, "connector set credentials")
		assert(last().body == XML .. '<product><active>1</active><associations><categories><item><id>2</id></item><item><id>5</id></item></categories></associations><description_short>&lt;b&gt;New&lt;/b&gt;</description_short><name><language id="1">Mug &amp; co</language></name><price>9.5</price></product></prestashop>', last().body)
		assert(product.product.id == "10")

		shop.updateProduct(10, {price = "12.00", name = "Mug"}, {id_shop = 2})
		assert(last().method == "PATCH" and last().url == API .. "products/10?id_shop=2" and sentXML())
		assert(last().body == XML .. "<product><id>10</id><name>Mug</name><price>12.00</price></product></prestashop>", last().body)

		shop.updateStockAvailable(31, {quantity = 12})
		assert(last().method == "PATCH" and last().url == API .. "stock_availables/31")
		assert(last().body == XML .. "<stock_available><id>31</id><quantity>12</quantity></stock_available></prestashop>", last().body)

		payload = '{"order_history":{"id":"88","id_order":"123","id_order_state":"4"}}'
		local history = shop.createOrderHistory({id_order = 123, id_order_state = 4}, {sendemail = true})
		assert(last().method == "POST" and last().url == API .. "order_histories?sendemail=1", last().url)
		assert(last().body == XML .. "<order_history><id_order>123</id_order><id_order_state>4</id_order_state></order_history></prestashop>", last().body)
		assert(history.order_history.id_order_state == "4")

		shop.updateOrderCarrier(7, {tracking_number = "1Z999"}, {sendemail = false})
		assert(last().method == "PATCH" and last().url == API .. "order_carriers/7", last().url)
		assert(last().body == XML .. "<order_carrier><id>7</id><tracking_number>1Z999</tracking_number></order_carrier></prestashop>")

		payload = '{"customer":{"id":"6","email":"bo@example.com","passwd":"$2y$10$hash","secure_key":"abcd"}}'
		local customer = shop.createCustomer({firstname = "Bo", lastname = "Lee", email = "bo@example.com", passwd = "correct horse", newsletter = false})
		assert(last().method == "POST" and last().url == API .. "customers")
		assert(last().body == XML .. "<customer><email>bo@example.com</email><firstname>Bo</firstname><lastname>Lee</lastname><newsletter>0</newsletter><passwd>correct horse</passwd></customer></prestashop>", last().body)
		assert(customer.customer.email == "bo@example.com" and customer.customer.passwd == nil and customer.customer.secure_key == nil)

		payload = ""
		assert(shop.deleteProduct(10) == true)
		assert(last().method == "DELETE" and last().url == API .. "products/10" and last().body == nil)
		assert(shop.deleteCustomer(6, {id_shop = 1}) == true)
		assert(last().method == "DELETE" and last().url == API .. "customers/6?id_shop=1")

		payload = '{"products":[{"id":10}]}'
		assert(shop.listProducts({display = {"id"}}).products[1].id == 10)
		assert(last().method == "GET" and last().url == API .. "products?display=%5Bid%5D&limit=0%2C50")
		assert(#requests == 9)
	end,
}
