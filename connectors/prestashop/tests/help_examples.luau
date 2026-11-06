return {
	scenario = {config = {store_host = "shop.example.com", access = "read-write"}, auth_method = "key", auth_config = {token = "0123456789ABCDEF0123456789ABCDEF"}},
	configure = function()
		requests = {}
		http = {request = function(req)
			table.insert(requests, req)
			return fixture.operation({statusCode = 200, headers = {}, body = fixture.reader(json.encode(payload))})
		end}
	end,
	run = function(c)
		local cases = {
			{"Address", "Addresses", "address", "addresses"}, {"Carrier", "Carriers", "carrier", "carriers"},
			{"Cart", "Carts", "cart", "carts"}, {"CartRule", "CartRules", "cart_rule", "cart_rules"},
			{"Category", "Categories", "category", "categories"}, {"Combination", "Combinations", "combination", "combinations"},
			{"Country", "Countries", "country", "countries"}, {"Currency", "Currencies", "currency", "currencies"},
			{"Customer", "Customers", "customer", "customers"}, {"Language", "Languages", "language", "languages"},
			{"Manufacturer", "Manufacturers", "manufacturer", "manufacturers"}, {"Order", "Orders", "order", "orders"},
			{"OrderCarrier", "OrderCarriers", "order_carrier", "order_carriers"}, {"OrderDetail", "OrderDetails", "order_detail", "order_details"},
			{"OrderHistory", "OrderHistories", "order_history", "order_histories"}, {"OrderInvoice", "OrderInvoices", "order_invoice", "order_invoices"},
			{"OrderPayment", "OrderPayments", "order_payment", "order_payments"}, {"OrderSlip", "OrderSlips", "order_slip", "order_slips", "order_slip"},
			{"OrderState", "OrderStates", "order_state", "order_states"}, {"Product", "Products", "product", "products"},
			{"StockAvailable", "StockAvailables", "stock_available", "stock_availables"}, {"Supplier", "Suppliers", "supplier", "suppliers"},
		}
		local API = "https://shop.example.com/api/"
		local function last() return requests[#requests] end
		for _, case in cases do
			local one, many, path = case[3], case[4], case[5] or case[4]
			payload = {[many] = {{id = 123, future_field = "native", secure_key = "withheld"}}}
			local page = fixture.example("list" .. case[2])
			assert(page[many][1].id == 123 and page[many][1].future_field == "native" and page[many][1].secure_key == nil)
			assert(last().method == "GET" and last().body == nil and last().url == API .. path .. "?display=full&sort=%5Bid_ASC%5D&limit=0%2C20", last().url)
			local record = fixture.example("get" .. case[1])
			assert(record[one].id == 123 and record[one].future_field == "native" and record[one].secure_key == nil)
			assert(last().method == "GET" and last().url == API .. path .. "/123?display=full&language=1", last().url)
			assert(last().headers.Authorization == nil and last().headers["Output-Format"][1] == "JSON")
		end
		payload = {customers = {{id = 6, newsletter = "0", company = "Example Studio", passwd = "withheld"}}}
		local customer = fixture.example("updateCustomer")
		assert(customer.customer.company == "Example Studio" and customer.customer.passwd == nil)
		assert(last().method == "PATCH" and last().url == API .. "customers/6?display=full")
		assert(last().body == '<?xml version="1.0" encoding="UTF-8"?><prestashop><customer><id>6</id><company>Example Studio</company><newsletter>0</newsletter></customer></prestashop>')
		assert(#requests == 45, "examples unexpectedly paged or retried")
	end,
}
