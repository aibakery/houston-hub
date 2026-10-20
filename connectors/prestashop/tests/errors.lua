return {
	scenario = {publisher = {}, config = {store_host = "shop.example.com", access = "read-write"}, auth_method = "key",
		auth_config = {token = "0123456789ABCDEF0123456789ABCDEF"}},
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
	run = function(shop)
		local function rejected(fn, expected)
			local before = calls
			local ok, err = pcall(fn)
			assert(not ok and string.find(tostring(err), expected, 1, true), "wrong validation error: " .. tostring(err))
			assert(calls == before, "invalid input reached PrestaShop")
		end
		rejected(function() shop.getOrder() end, "id must be a positive integer ID")
		for _, value in {"1", 0, -1, 1.5, "../configurations"} do
			rejected(function() shop.getOrder(value) end, "id must be a positive integer ID")
		end
		rejected(function() shop.deleteProduct("9") end, "id must be a positive integer ID")
		rejected(function() shop.listOrders("processing") end, "opts must be an object")
		-- PrestaShop reads ps_method from the query string, which would turn a read into a delete.
		for _, key in {"ps_method", "ws_key", "url", "output_format", "io_format", "price", "date"} do
			rejected(function() shop.listOrders({[key] = "DELETE"}) end, key .. " is not a supported option")
			rejected(function() shop.getOrder(1, {[key] = "DELETE"}) end, key .. " is not a supported option")
		end
		rejected(function() shop.deleteProduct(1, {ps_method = "GET"}) end, "ps_method is not a supported option")
		rejected(function() shop.listOrders({filter = {["id]=1&ps_method=DELETE&filter[id"] = 1}}) end, "filter must be a PrestaShop field name")
		rejected(function() shop.listOrders({filter = {}}) end, "filter must name at least one field")
		rejected(function() shop.listOrders({filter = {reference = ""}}) end, "filter.reference must be nonempty")
		rejected(function() shop.listOrders({filter = {id = json.decode("[]")}}) end, "filter.id must be a nonempty array")
		rejected(function() shop.listOrders({filter = {id = {nested = 1}}}) end, "filter.id must be")
		-- Filtering on a withheld field would reveal it one character at a time.
		rejected(function() shop.listCustomers({filter = {passwd = "[$2y]%"}}) end, "passwd is withheld")
		rejected(function() shop.listOrders({filter = {secure_key = "[a]%"}}) end, "secure_key is withheld")
		rejected(function() shop.listCustomers({sort = "reset_password_token_ASC"}) end, "reset_password_token is withheld")
		rejected(function() shop.listCustomers({display = {"id", "passwd"}}) end, "passwd is withheld")
		rejected(function() shop.listOrders({sort = "date_add"}) end, "sort must be field_ASC or field_DESC")
		rejected(function() shop.listOrders({sort = "date add_ASC"}) end, "sort must be a PrestaShop field name")
		rejected(function() shop.listOrders({display = "id"}) end, "display must be a nonempty array")
		rejected(function() shop.listOrders({limit = 0}) end, "limit must be an integer from 1 to 100")
		rejected(function() shop.listOrders({limit = 101}) end, "limit must be an integer from 1 to 100")
		rejected(function() shop.listOrders({offset = -1}) end, "offset must be an integer")
		rejected(function() shop.listOrders({language = "fr"}) end, "language must be a positive integer ID")
		rejected(function() shop.getOrder(1, {id_shop = "default"}) end, "id_shop must be a positive integer ID")
		rejected(function() shop.listOrders({schema = "synopsis"}) end, "schema is not a supported option")

		rejected(function() shop.createProduct("mug") end, "fields must be an object")
		rejected(function() shop.createProduct({id = 3, price = 1}) end, "fields must not contain id")
		rejected(function() shop.updateProduct(3, {["price><id>1</id><price"] = 1}) end, "fields must be a PrestaShop field name")
		rejected(function() shop.updateProduct(3, {name = {{value = "Mug"}}}) end, "name.id must be a positive integer ID")
		rejected(function() shop.updateProduct(3, {name = {lang = "Mug"}}) end, "name must be a nonempty array")
		rejected(function() shop.updateProduct(3, {associations = {categories = {2}}}) end, "associations.categories must contain objects")
		rejected(function() shop.updateProduct(3, {associations = {["a></associations><price>0</price><x"] = {{id = 1}}}}) end, "associations must be a PrestaShop field name")
		rejected(function() shop.updateProduct(3, {associations = {categories = {{["id></id><price>0</price><x"] = 1}}}}) end, "associations.categories must be a PrestaShop field name")
		rejected(function() shop.updateProduct(3, {associations = "categories"}) end, "associations must be an object")
		rejected(function() shop.createCustomer({firstname = "Bo\0", passwd = "secret"}) end, "firstname must not contain control characters")
		rejected(function() shop.updateProduct(3, {name = {{id = 1, value = "Mug\27"}}}) end, "name must not contain control characters")
		rejected(function() shop.createProduct({price = 1}, {sendemail = true}) end, "sendemail is not a supported option")
		rejected(function() shop.createOrderHistory({id_order = 1, id_order_state = 4}, {sendemail = "yes"}) end, "sendemail must be a boolean")

		local function upstream(code, body, headers, expected)
			status, payload, responseHeaders = code, body, headers
			local before = calls
			local ok, err = pcall(function() shop.updateOrderCarrier(1, {tracking_number = "1Z"}) end)
			for _, text in expected do
				assert(not ok and string.find(tostring(err), text, 1, true), "missing " .. text .. " in " .. tostring(err))
			end
			assert(calls == before + 1, "failed write was retried")
		end
		upstream(401, '{"errors":[{"code":26,"message":"No permission for this key"}]}', {},
			{"PrestaShop HTTP 401 [26] No permission for this key", '"retryable":false'})
		upstream(401, "401 Unauthorized", {["www-authenticate"] = {"Basic realm=\"Welcome to PrestaShop Webservice\""}},
			{"HTTP 401: 401 Unauthorized", "may drop the Authorization header"})
		upstream(405, '{"errors":[{"code":25,"message":"Method PATCH is not allowed for this resource"}]}', {}, {"[25] Method PATCH"})
		upstream(400, json.encode({errors = {{code = 85, message = "Validation error: " .. string.rep("x", 5000)}, {code = 41, message = "parameter \"id_order\" required"}}}), {},
			{"[85] Validation error", "[41] parameter", "id_order"})
		upstream(500, "<br />\n<b>Fatal error</b>: Allowed memory size exhausted", {}, {"HTTP 500: Fatal error : Allowed memory", '"retryable":true'})
		upstream(503, '{"errors":[{"code":22,"message":"The PrestaShop webservice is disabled. Please activate it in the PrestaShop Back Office"}]}', {},
			{"[22] The PrestaShop webservice is disabled", '"retryable":false'})
		upstream(500, '{"errors":[{"code":46,"message":"Unable to save resource"}]}', {}, {"HTTP 500 [46] Unable to save resource", '"retryable":false'})
		upstream(500, '{"errors":[{"message":"Unknown failure"}]}', {}, {"HTTP 500 Unknown failure"})
		upstream(429, "Too many requests", {["retry-after"] = {"30"}}, {"HTTP 429: Too many requests", "Retry-After: 30", '"retryable":true'})
		upstream(301, "", {location = {"https://www.shop.example.com/api/order_carriers/1"}},
			{"HTTP 301", "redirected to https://www.shop.example.com/", "store domain"})
		upstream(200, '<?xml version="1.0" encoding="UTF-8"?><prestashop><order_carrier/></prestashop>', {}, {"not JSON", "https://shop.example.com/api"})
		upstream(200, "", {}, {"not JSON"})
		-- Without display=full's one-item list, PrestaShop 8+ may have dropped fields.
		upstream(200, '{"order_carrier":{"id":1}}', {}, {"PrestaShop returned no order_carrier record"})
		upstream(200, '{"order_carriers":[]}', {}, {"PrestaShop returned no order_carrier record"})
	end,
}
