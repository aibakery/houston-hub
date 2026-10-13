return {
	scenario = {publisher = {}, config = {store_host = "shop.example.com", access = "read-write"}, auth_method = "keys",
		auth_config = {consumer_key = "ck_fixture", consumer_secret = "cs_fixture"}},
	configure = function()
		requests = {}
		payload = "{}"
		http = {request = function(req)
			table.insert(requests, req)
			return fixture.operation({statusCode = 200, headers = {}, body = fixture.reader(payload)})
		end}
	end,
	run = function(woo)
		local API = "https://shop.example.com/wp-json/wc/v3"
		local NULL = json.decode("null")
		local function last() return requests[#requests] end
		local function sent() return json.decode(last().body) end

		local count = 0
		for name in woo do if name ~= "help" then count += 1 end end
		assert(count == 136, "wrong read-write surface: " .. count)

		payload = '{"id":42,"status":"pending","customer_note":null}'
		local order = woo.createOrder({status = "pending", line_items = {{product_id = 9, quantity = 2}},
			coupon_lines = json.decode("[]"), customer_note = NULL})
		assert(last().method == "POST" and last().url == API .. "/orders")
		assert(last().headers["Content-Type"][1] == "application/json")
		local body = sent()
		assert(body.line_items[1].quantity == 2 and json.encode(body.coupon_lines) == "[]" and body.customer_note == NULL)
		assert(order.id == 42 and order.customer_note == NULL)

		woo.updateOrder({id = 42, status = "completed"})
		assert(last().method == "PUT" and last().url == API .. "/orders/42")
		body = sent()
		assert(body.status == "completed" and body.id == nil, "path ID leaked into the body")

		woo.createOrderNote({order_id = 42, note = "Shipped", customer_note = true})
		assert(last().url == API .. "/orders/42/notes")
		body = sent()
		assert(body.note == "Shipped" and body.customer_note == true and body.order_id == nil)

		woo.createOrderRefund({order_id = 42, amount = "5.00", api_refund = false})
		assert(last().url == API .. "/orders/42/refunds" and sent().api_refund == false)
		woo.previewOrderRefund({order_id = 42, line_items = {{id = 7, quantity = 1}}})
		assert(last().method == "POST" and last().url == API .. "/orders/42/refunds/preview" and sent().line_items[1].id == 7)
		woo.sendOrderEmail({order_id = 42, template_id = "customer_invoice"})
		assert(last().url == API .. "/orders/42/actions/send_email" and sent().template_id == "customer_invoice" and sent().order_id == nil)
		woo.duplicateProduct({id = 9})
		assert(last().method == "POST" and last().url == API .. "/products/9/duplicate" and last().body == "{}")

		woo.deleteProduct({id = 9})
		assert(last().method == "DELETE" and last().url == API .. "/products/9" and last().body == nil)
		woo.deleteCustomer({id = 3, force = true, reassign = 1})
		assert(last().url == API .. "/customers/3?force=true&reassign=1")
		woo.deleteTaxClass({id = "reduced-rate", force = true})
		assert(last().url == API .. "/taxes/classes/reduced-rate?force=true")

		payload = '{"create":[{"id":0,"error":{"code":"woocommerce_rest_invalid","message":"Invalid"}}],"update":[{"id":9}],"delete":[]}'
		local batch = woo.batchProducts({create = {{name = ""}}, update = {{id = 9, regular_price = "12.00"}}, delete = json.decode("[]")})
		assert(last().method == "POST" and last().url == API .. "/products/batch")
		body = sent()
		assert(body.update[1].regular_price == "12.00" and json.encode(body.delete) == "[]")
		assert(batch.create[1].error.code == "woocommerce_rest_invalid" and json.encode(batch.delete) == "[]")

		payload = '{"id":"woocommerce_currency","value":"USD"}'
		assert(woo.getSetting({group_id = "general", id = "woocommerce_currency"}).value == "USD")
		assert(last().method == "GET" and last().url == API .. "/settings/general/woocommerce_currency")
		woo.updateSetting({group_id = "general", id = "woocommerce_currency", value = "EUR"})
		assert(last().url == API .. "/settings/general/woocommerce_currency" and sent().value == "EUR")
		woo.runSystemStatusTool({id = "clear_transients", confirm = true})
		assert(last().method == "PUT" and last().url == API .. "/system_status/tools/clear_transients" and sent().confirm == true and sent().id == nil)
		woo.updateShippingZoneMethod({zone_id = 0, id = 4, enabled = false})
		assert(last().url == API .. "/shipping/zones/0/methods/4" and sent().enabled == false)

		payload = '[{"id":1,"name":"Mugs"}]'
		assert(woo.listProductCategories({hide_empty = true}).items[1].name == "Mugs")
		assert(last().method == "GET" and last().url == API .. "/products/categories?hide_empty=true")
		assert(#requests == 16)
	end,
}
