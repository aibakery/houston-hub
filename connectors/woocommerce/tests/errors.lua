return {
	scenario = {publisher = {}, config = {store_host = "shop.example.com", access = "read-write"}, auth_method = "keys",
		auth_config = {consumer_key = "ck_fixture", consumer_secret = "cs_fixture"}},
	configure = function()
		calls = 0
		status = 200
		payload = "{}"
		responseHeaders = {}
		http = {request = function(req)
			calls += 1
			return fixture.operation({statusCode = status, headers = responseHeaders, body = fixture.reader(payload)})
		end}
	end,
	run = function(woo)
		local function rejected(fn, expected)
			local before = calls
			local ok, err = pcall(fn)
			assert(not ok and string.find(tostring(err), expected, 1, true), "wrong validation error: " .. tostring(err))
			assert(calls == before, "invalid input reached WooCommerce")
		end
		rejected(function() woo.getOrder() end, "id must be")
		rejected(function() woo.getOrder({id = "../customers"}) end, "id must be")
		rejected(function() woo.getOrder({id = -1}) end, "nonnegative integer")
		rejected(function() woo.getOrder({id = 1.5}) end, "nonnegative integer")
		rejected(function() woo.getOrder({id = ""}) end, "id must be")
		rejected(function() woo.listOrderNotes({}) end, "order_id must be")
		rejected(function() woo.listOrders("processing") end, "opts must be an object")
		rejected(function() woo.listOrders({"processing"}) end, "named fields")
		rejected(function() woo.listOrders({status = {processing = true}}) end, "array, not an object")
		rejected(function() woo.listOrders({after = json.decode("null")}) end, "after must be")
		-- WordPress would let these change the request's method or route.
		for _, key in {"_method", "rest_route", "rest.route", "rest route", "_envelope", "status[0]"} do
			rejected(function() woo.getOrder({id = 1, [key] = "DELETE"}) end, "not a WooCommerce query parameter")
		end
		rejected(function() woo.deleteOrder({id = 1, _method = "GET"}) end, "not a WooCommerce query parameter")

		local function upstream(code, body, headers, expected)
			status, payload, responseHeaders = code, body, headers
			local before = calls
			local ok, err = pcall(function() woo.updateOrder({id = 1, status = "completed"}) end)
			for _, text in expected do
				assert(not ok and string.find(tostring(err), text, 1, true), "missing " .. text .. " in " .. tostring(err))
			end
			assert(calls == before + 1, "failed write was retried")
		end
		upstream(401, '{"code":"woocommerce_rest_cannot_edit","message":"Sorry, you are not allowed to edit this resource.","data":{"status":401}}', {},
			{"HTTP 401", "woocommerce_rest_cannot_edit", "not allowed to edit"})
		upstream(400, '{"code":"rest_invalid_param","message":"Invalid parameter(s): status","data":{"status":400,"params":{"status":"status is not one of pending, processing."}}}', {},
			{"HTTP 400", "rest_invalid_param", "status is not one of", '"retryable":false'})
		upstream(400, json.encode({code = "rest_invalid_param", message = string.rep("x", 5000), data = {params = {status = "status is invalid"}}}), {},
			{"rest_invalid_param", "status is invalid"})
		upstream(429, "Too many requests", {["retry-after"] = {"30"}}, {"HTTP 429: Too many requests", "Retry-After: 30", '"retryable":true'})
		-- Host firewalls answer with an HTML page that names the blocking layer.
		upstream(429, "<!doctype html><html><head><title>429</title></head><body>\n<!-- HTTP_Code = 429 -->\n<h1>Too many\n requests</h1></body></html>",
			{server = {"host-firewall"}}, {"HTTP 429: 429 HTTP_Code = 429 Too many requests", "Server: host-firewall"})
		upstream(500, "<html>Fatal error</html>", {}, {"HTTP 500: Fatal error", '"retryable":true'})
		upstream(301, "", {location = {"https://www.shop.example.com/wp-json/wc/v3/orders/1"}},
			{"HTTP 301", "redirected to https://www.shop.example.com/", "store domain"})
		upstream(200, "<!doctype html><title>Maintenance</title>", {}, {"not JSON", "/wp-json"})
		upstream(200, '"ok"', {}, {"not JSON"})
	end,
}
