return {
	scenario = {publisher = {}, config = {host = "erp.example.com", install_path = "/dolibarr", access = "read-write"}, auth_method = "key",
		auth_config = {token = "Zx81Kq0PnB2vLm4TcR7wYs9dHf3jGa6E"}},
	configure = function()
		requests = {}
		payload = "{}"
		http = {request = function(req)
			table.insert(requests, req)
			return fixture.operation({statusCode = 200, headers = {}, body = fixture.reader(payload)})
		end}
	end,
	run = function(erp)
		local API = "https://erp.example.com/dolibarr/api/index.php"
		local function last() return requests[#requests] end
		local function same(a, b): boolean
			if type(a) ~= "table" or type(b) ~= "table" then return a == b end
			for key, value in a do if not same(value, b[key]) then return false end end
			for key in b do if a[key] == nil then return false end end
			return true
		end
		local function sent(method, path, expected)
			local req = last()
			assert(req.method == method and req.url == API .. path, req.method .. " " .. req.url)
			assert(req.headers.DOLAPIKEY == nil and req.headers.Authorization == nil, "connector set credentials")
			if expected == nil then
				assert(req.body == nil and req.headers["Content-Type"] == nil, "unexpected body")
				return
			end
			assert(req.headers["Content-Type"][1] == "application/json")
			assert(same(json.decode(req.body), expected), req.body)
		end

		-- The reads are read_only.lua's exact 32; everything else must be these writes.
		local names, reads = {}, 0
		for name in erp do
			if string.match(name, "^get%u") or string.match(name, "^list%u") then reads += 1
			elseif name ~= "help" then table.insert(names, name) end
		end
		assert(reads == 32, "wrong read count: " .. reads)
		table.sort(names)
		assert(table.concat(names, ",") == "addInvoiceLine,addInvoicePayment,addOrderLine,closeOrder,createContact,createInvoice,createInvoiceFromOrder,createOrder,createProduct,createStockMovement,createThirdparty,updateContact,updateProduct,updateThirdparty,validateInvoice,validateOrder",
			"wrong writes: " .. table.concat(names, ","))

		payload = "12"
		local thirdparty = {name = "Ann SARL", client = 1, email = "ann@example.com", country_code = "FR", array_options = {options_shop = "PS"}}
		assert(erp.createThirdparty(thirdparty) == 12)
		sent("POST", "/thirdparties", thirdparty)
		payload = '{"id":"12","email":"billing@example.com"}'
		assert(erp.updateThirdparty("12", {email = "billing@example.com"}).email == "billing@example.com")
		sent("PUT", "/thirdparties/12", {email = "billing@example.com"})
		payload = "30"
		assert(erp.createContact({lastname = "Martin", socid = 12}) == 30)
		sent("POST", "/contacts", {lastname = "Martin", socid = 12})
		erp.updateContact(30, {phone_pro = "+33 1 23 45 67 89"})
		sent("PUT", "/contacts/30", {phone_pro = "+33 1 23 45 67 89"})
		erp.createProduct({ref = "MUG-01", label = "Mug", price = "12.50", tva_tx = "20"})
		sent("POST", "/products", {ref = "MUG-01", label = "Mug", price = "12.50", tva_tx = "20"})
		erp.updateProduct(9, {price = "13.00"})
		sent("PUT", "/products/9", {price = "13.00"})
		erp.createStockMovement({product_id = 9, warehouse_id = 1, qty = -2, label = "Shop order PS-1042"})
		sent("POST", "/stockmovements", {product_id = 9, warehouse_id = 1, qty = -2, label = "Shop order PS-1042"})

		payload = "7"
		assert(erp.createOrder({socid = 12, date = 1792540800, ref_ext = "PS-1042"}) == 7)
		sent("POST", "/orders", {socid = 12, date = 1792540800, ref_ext = "PS-1042"})
		payload = "70"
		assert(erp.addOrderLine(7, {fk_product = 9, qty = 2, subprice = "12.50", tva_tx = "20"}) == 70)
		sent("POST", "/orders/7/lines", {fk_product = 9, qty = 2, subprice = "12.50", tva_tx = "20"})
		payload = '{"id":"7","ref":"CO2610-0007","statut":"1"}'
		assert(erp.validateOrder(7).ref == "CO2610-0007")
		sent("POST", "/orders/7/validate", {})
		erp.validateOrder(7, {idwarehouse = 1})
		sent("POST", "/orders/7/validate", {idwarehouse = 1})
		erp.closeOrder("7")
		sent("POST", "/orders/7/close", {})

		payload = '{"id":"42","ref":"(PROV42)","fk_statut":"0"}'
		assert(erp.createInvoiceFromOrder(7).ref == "(PROV42)")
		sent("POST", "/invoices/createfromorder/7", nil)
		payload = "43"
		assert(erp.createInvoice({socid = 12, type = 0}) == 43)
		sent("POST", "/invoices", {socid = 12, type = 0})
		erp.addInvoiceLine(43, {desc = "Shipping", qty = 1, subprice = "5", tva_tx = "20", product_type = 1})
		sent("POST", "/invoices/43/lines", {desc = "Shipping", qty = 1, subprice = "5", tva_tx = "20", product_type = 1})
		payload = '{"id":"42","ref":"FA2610-0042"}'
		erp.validateInvoice(42)
		sent("POST", "/invoices/42/validate", {})
		payload = "88"
		local payment = {datepaye = 1792540800, paymentid = 6, accountid = 1, closepaidinvoices = "yes", num_payment = "PS-1042"}
		assert(erp.addInvoicePayment(42, payment) == 88)
		sent("POST", "/invoices/42/payments", payment)

		payload = "[]"
		erp.listOrders({sqlfilters = "(t.ref_ext:=:'PS-1042')"})
		assert(last().method == "GET" and last().url == API .. "/orders?limit=100&page=0&sqlfilters=%28t.ref_ext%3A%3D%3A%27PS-1042%27%29", last().url)
		assert(#requests == 18, "wrong request count: " .. #requests)
	end,
}
