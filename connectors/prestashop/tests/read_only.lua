return {
	scenario = {publisher = {}, config = {store_host = "Shop.Example.com"}, auth_method = "key",
		auth_config = {token = "0123456789ABCDEF0123456789ABCDEF"}},
	configure = function()
		requests = {}
		payload = "{}"
		http = {request = function(req)
			table.insert(requests, req)
			return fixture.operation({statusCode = 200, headers = {}, body = fixture.reader(payload)})
		end}
	end,
	run = function(shop)
		local API = "https://shop.example.com/api/"
		local function last() return requests[#requests] end

		local names = {}
		for name in shop do if name ~= "help" then table.insert(names, name) end end
		table.sort(names)
		assert(table.concat(names, ",") == "getAddress,getCarrier,getCart,getCartRule,getCategory,getCombination,getCountry,getCurrency,getCustomer,getLanguage,getManufacturer,getOrder,getOrderCarrier,getOrderDetail,getOrderHistory,getOrderInvoice,getOrderPayment,getOrderSlip,getOrderState,getProduct,getStockAvailable,getSupplier,"
			.. "listAddresses,listCarriers,listCartRules,listCarts,listCategories,listCombinations,listCountries,listCurrencies,listCustomers,listLanguages,listManufacturers,listOrderCarriers,listOrderDetails,listOrderHistories,listOrderInvoices,listOrderPayments,listOrderSlips,listOrderStates,listOrders,listProducts,listStockAvailables,listSuppliers",
			"wrong read-only surface: " .. table.concat(names, ","))
		assert(#requests == 0, "initialization reached PrestaShop")

		payload = '{"orders":[{"id":7,"reference":"XKBKNABJK","current_state":"2","secure_key":"b44a6d9efd7a0076a0fbce6b15eaf3b1","associations":{"order_rows":[{"id":"1","product_id":"9"}]}}]}'
		local page = shop.listOrders()
		assert(last().method == "GET" and last().body == nil)
		assert(last().url == API .. "orders?display=full&limit=0%2C50", last().url)
		assert(last().headers["Output-Format"][1] == "JSON" and last().headers.Accept[1] == "application/json")
		assert(last().headers.Authorization == nil, "connector set credentials")
		assert(page.orders[1].reference == "XKBKNABJK" and page.orders[1].associations.order_rows[1].product_id == "9")
		assert(page.orders[1].secure_key == nil, "secure_key was returned")

		local opts = {filter = {current_state = {2, 3}, date_upd = ">[2026-10-01 00:00:00]"}, sort = "date_add_DESC",
			limit = 20, offset = 40, language = 1, id_shop = "all"}
		shop.listOrders(opts)
		assert(last().url == API .. "orders?display=full&filter%5Bcurrent_state%5D=%5B2%7C3%5D&filter%5Bdate_upd%5D=%3E%5B2026-10-01%2000%3A00%3A00%5D&sort=%5Bdate_add_DESC%5D&limit=40%2C20&date=1&language=1&id_shop=all", last().url)
		assert(opts.filter.current_state[2] == 3 and opts.limit == 20, "caller options were modified")

		shop.listProducts({display = {"id", "reference", "price"}, filter = {reference = "%[MUG]%"}, sort = {"price_ASC", "id_DESC"}})
		assert(last().url == API .. "products?display=%5Bid%2Creference%2Cprice%5D&filter%5Breference%5D=%25%5BMUG%5D%25&sort=%5Bprice_ASC%2Cid_DESC%5D&limit=0%2C50", last().url)
		shop.listOrderSlips({filter = {id_order = 12}, limit = 100})
		assert(last().url == API .. "order_slip?display=full&filter%5Bid_order%5D=%5B12%5D&limit=0%2C100", last().url)

		payload = "[]"
		local empty = shop.listOrderHistories({filter = {id_order = 5}})
		assert(last().url == API .. "order_histories?display=full&filter%5Bid_order%5D=%5B5%5D&limit=0%2C50")
		assert(json.encode(empty.order_histories) == "[]", "empty list lost its wrapper")

		-- PrestaShop 8+ drops a lone record's "0", empty and false fields; display=full keeps them in a one-item list.
		payload = '{"customers":[{"id":5,"email":"ann@example.com","newsletter":"0","note":"","passwd":"$2y$10$abcdefghijklmnopqrstuv","secure_key":"0f3b","reset_password_token":"tok","reset_password_validity":"0000-00-00 00:00:00","last_passwd_gen":"2026-01-01 00:00:00","associations":{"groups":[{"id":"3"}]}}]}'
		local customer = shop.getCustomer(5)
		assert(last().url == API .. "customers/5?display=full", last().url)
		local record = customer.customer
		assert(record.email == "ann@example.com" and record.newsletter == "0" and record.note == "" and record.associations.groups[1].id == "3")
		for _, secret in {"passwd", "secure_key", "reset_password_token", "reset_password_validity", "last_passwd_gen"} do
			assert(record[secret] == nil, secret .. " was returned")
		end

		payload = '{"products":[{"id":9,"name":[{"id":"1","value":"Mug"},{"id":"2","value":"Tasse"}]}]}'
		local product = shop.getProduct(9, {language = 1, id_shop = 2})
		assert(last().url == API .. "products/9?display=full&language=1&id_shop=2", last().url)
		assert(product.product.name[2].value == "Tasse")
		payload = '{"stock_availables":[{"id":31,"id_product":"9","quantity":"0","out_of_stock":"0"}]}'
		assert(shop.getStockAvailable(31).stock_available.quantity == "0", "an empty stock lost its quantity")
		assert(last().url == API .. "stock_availables/31?display=full")
		assert(#requests == 8)
	end,
}
