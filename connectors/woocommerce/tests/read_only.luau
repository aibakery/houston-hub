return {
	scenario = {publisher = {}, config = {store_host = "shop.example.com"}, auth_method = "keys",
		auth_config = {consumer_key = "ck_fixture", consumer_secret = "cs_fixture"}},
	configure = function()
		requests = {}
		status = 200
		payload = "{}"
		responseHeaders = {}
		http = {request = function(req)
			table.insert(requests, req)
			return fixture.operation({statusCode = status, headers = responseHeaders, body = fixture.reader(payload)})
		end}
	end,
	run = function(woo)
		local API = "https://shop.example.com/wp-json/wc/v3"
		local function last() return requests[#requests] end

		local names = {}
		for name in woo do if name ~= "help" then table.insert(names, name) end end
		assert(#names == 57, "wrong read-only surface: " .. #names)
		for _, name in {"createOrder", "updateOrder", "deleteOrder", "batchProducts", "createOrderRefund",
			"updateSetting", "runSystemStatusTool", "deleteTaxClass", "sendOrderEmail", "previewOrderRefund",
			"duplicateProduct", "listSettings", "getSetting", "listSettingGroups", "listPaymentGateways", "getPaymentGateway", "listWebhooks", "getWebhook"} do
			assert(woo[name] == nil, "read-only leaked " .. name)
		end
		assert(#requests == 0, "initialization reached WooCommerce")

		payload = '[{"id":7,"status":"processing","date_paid":null,"line_items":[]}]'
		responseHeaders = {["x-wp-total"] = {"31"}, ["x-wp-totalpages"] = {"4"}}
		local opts = {status = {"processing", "on-hold"}, search = "Café & co/1", per_page = 10, include = {12, 3}, orderby = "include"}
		local page = woo.listOrders(opts)
		assert(last().method == "GET" and last().body == nil and last().headers.Accept[1] == "application/json")
		assert(last().url == API .. "/orders?include%5B%5D=12&include%5B%5D=3&orderby=include&per_page=10&search=Caf%C3%A9%20%26%20co%2F1&status%5B%5D=processing&status%5B%5D=on-hold", last().url)
		assert(opts.search == "Café & co/1", "caller options were modified")
		assert(page.total == 31 and page.total_pages == 4 and page.items[1].id == 7)
		assert(page.items[1].date_paid == json.decode("null") and json.encode(page.items[1].line_items) == "[]")

		payload = "[]"
		responseHeaders = {}
		local empty = woo.listProductVariations({product_id = 5})
		assert(last().url == API .. "/products/5/variations")
		assert(json.encode(empty.items) == "[]" and empty.total == nil and empty.total_pages == nil)
		woo.listShippingZoneMethods({zone_id = 0})
		assert(last().url == API .. "/shipping/zones/0/methods", "rest-of-world zone 0 rejected")

		payload = '{"id":123,"billing":{"email":"buyer@example.com"},"coupon_lines":[]}'
		local order = woo.getOrder({id = 123, _fields = "id,billing"})
		assert(last().url == API .. "/orders/123?_fields=id%2Cbilling")
		assert(order.id == 123 and order.billing.email == "buyer@example.com" and json.encode(order.coupon_lines) == "[]")
		woo.getOrderNote({order_id = 123, id = 9})
		assert(last().url == API .. "/orders/123/notes/9")

		payload = '{"code":"USD","name":"United States (US) dollar","symbol":"$"}'
		assert(woo.getCurrency({id = "current"}).code == "USD")
		assert(last().url == API .. "/data/currencies/current")
		payload = '[{"total_sales":"120.00","totals":{"2026-10-01":{"orders":2}}}]'
		local report = woo.getSalesReport({period = "month", date_min = "2026-10-01"})
		assert(last().url == API .. "/reports/sales?date_min=2026-10-01&period=month")
		assert(report.items[1].total_sales == "120.00")
		payload = '{"environment":{"version":"10.2.0"}}'
		assert(woo.getSystemStatus().environment.version == "10.2.0")
		assert(last().url == API .. "/system_status")
		woo.listProducts({featured = true, per_page = 5})
		assert(last().url == API .. "/products?featured=true&per_page=5")
		woo.listRefunds({after = "2026-10-01T00:00:00"})
		assert(last().url == API .. "/refunds?after=2026-10-01T00%3A00%3A00")
		assert(#requests == 10)
	end,
}
