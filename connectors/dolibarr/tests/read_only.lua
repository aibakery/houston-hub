return {
	scenario = {publisher = {}, config = {host = "ERP.Example.com"}, auth_method = "key",
		auth_config = {token = "Zx81Kq0PnB2vLm4TcR7wYs9dHf3jGa6E"}},
	configure = function()
		requests = {}
		status = 200
		payload = "{}"
		http = {request = function(req)
			table.insert(requests, req)
			return fixture.operation({statusCode = status, headers = {}, body = fixture.reader(payload)})
		end}
	end,
	run = function(erp)
		local API = "https://erp.example.com/api/index.php"
		local function last() return requests[#requests] end

		local names = {}
		for name in erp do if name ~= "help" then table.insert(names, name) end end
		table.sort(names)
		assert(table.concat(names, ",") == "getBankAccount,getBankAccountBalance,getCategory,getContact,getInvoice,getOrder,getProduct,getProductStock,getProposal,getShipment,getStatus,getSupplierInvoice,getSupplierOrder,getThirdparty,getWarehouse,"
			.. "listBankAccountLines,listBankAccounts,listCategories,listContacts,listInvoicePayments,listInvoices,listOrders,listPaymentTypes,listProducts,listProposals,listShipments,listStockMovements,listSupplierInvoicePayments,listSupplierInvoices,listSupplierOrders,listThirdparties,listWarehouses",
			"wrong read-only surface: " .. table.concat(names, ","))
		assert(#requests == 0, "initialization reached Dolibarr")

		payload = '[{"id":"42","ref":"FA2610-0042","socid":"12","total_ttc":"120.00000000","lines":[{"id":"7","qty":"2"}],"user":{"login":"ann","api_key":"dolcrypt:AES-256-CTR:x","pass_indatabase_crypted":"$2y$10$x"}}]'
		local page = erp.listInvoices()
		assert(last().method == "GET" and last().body == nil)
		assert(last().url == API .. "/invoices?limit=100&page=0", last().url)
		assert(last().headers.Accept[1] == "application/json" and last().headers["Content-Type"] == nil)
		assert(last().headers.DOLAPIKEY == nil and last().headers.Authorization == nil, "connector set credentials")
		assert(page[1].ref == "FA2610-0042" and page[1].lines[1].qty == "2" and page[1].user.login == "ann")
		assert(page[1].user.api_key == nil and page[1].user.pass_indatabase_crypted == nil, "a credential was returned")

		local opts = {status = "unpaid", sortfield = "t.datef", sortorder = "DESC", limit = 20, page = 2, thirdparty_ids = {12, "13"},
			properties = {"id", "ref"}, sqlfilters = "(t.ref:like:'FA26%') and (t.fk_soc:=:12)"}
		erp.listInvoices(opts)
		assert(last().url == API .. "/invoices?limit=20&page=2&properties=id%2Cref&sortfield=t.datef&sortorder=DESC&sqlfilters=%28t.ref%3Alike%3A%27FA26%25%27%29%20and%20%28t.fk_soc%3A%3D%3A12%29&status=unpaid&thirdparty_ids=12%2C13", last().url)
		assert(opts.thirdparty_ids[2] == "13" and opts.limit == 20, "caller options were modified")
		erp.listThirdparties({mode = 4, category = 3, sortfield = "nom"})
		assert(last().url == API .. "/thirdparties?category=3&limit=100&mode=4&page=0&sortfield=nom", last().url)
		erp.listProducts({includestockdata = true, limit = 200})
		assert(last().url == API .. "/products?includestockdata=1&limit=200&page=0", last().url)
		erp.listOrders({sqlfilterlines = "(tl.fk_product:=:9)"})
		assert(last().url == API .. "/orders?limit=100&page=0&sqlfilterlines=%28tl.fk_product%3A%3D%3A9%29", last().url)
		erp.listSupplierOrders({status = "received_end", thirdparty_ids = 4})
		assert(last().url == API .. "/supplierorders?limit=100&page=0&status=received_end&thirdparty_ids=4", last().url)
		erp.listCategories({type = "product"})
		assert(last().url == API .. "/categories?limit=100&page=0&type=product", last().url)
		erp.listPaymentTypes()
		assert(last().url == API .. "/setup/dictionary/payment_types?limit=100&page=0", last().url)

		payload = "[]"
		local empty = erp.listStockMovements({sqlfilters = "(t.fk_product:=:9)"})
		assert(last().url == API .. "/stockmovements?limit=100&page=0&sqlfilters=%28t.fk_product%3A%3D%3A9%29", last().url)
		assert(json.encode(empty) == "[]", "an empty list is not an array")
		assert(json.encode(erp.listInvoicePayments("42")) == "[]")
		assert(last().url == API .. "/invoices/42/payments", last().url)

		-- Before Dolibarr 19 (22 for third parties), an empty list answers 404.
		status, payload = 404, '{"error":{"code":404,"message":"Not Found: Thirdparties not found"},"debug":{"source":"api_thirdparties.class.php:263 at call stage"}}'
		assert(json.encode(erp.listThirdparties({sqlfilters = "(t.nom:like:'zz%')"})) == "[]", "an old empty list failed")
		status = 200

		payload = '{"id":"12","name":"Ann SARL","client":"1","array_options":{"options_shop":"PS"}}'
		local thirdparty = erp.getThirdparty(12)
		assert(last().url == API .. "/thirdparties/12", last().url)
		assert(thirdparty.name == "Ann SARL" and thirdparty.array_options.options_shop == "PS")
		erp.getInvoice("42")
		assert(last().url == API .. "/invoices/42")
		erp.getProduct(9, {includestockdata = false})
		assert(last().url == API .. "/products/9?includestockdata=0", last().url)
		payload = '{"stock_reel":"5","stock_warehouses":{"1":{"real":"5"}}}'
		assert(erp.getProductStock(9, {selected_warehouse_id = 1}).stock_warehouses["1"].real == "5")
		assert(last().url == API .. "/products/9/stock?selected_warehouse_id=1", last().url)
		erp.listBankAccountLines(1, {sqlfilters = "(t.dateo:>=:'2026-10-01')"})
		assert(last().url == API .. "/bankaccounts/1/lines?sqlfilters=%28t.dateo%3A%3E%3D%3A%272026-10-01%27%29", last().url)
		payload = "1250.5"
		assert(erp.getBankAccountBalance(1) == 1250.5)
		assert(last().url == API .. "/bankaccounts/1/balance")
		payload = '{"success":{"code":200,"dolibarr_version":"24.0.2","access_locked":"0"}}'
		assert(erp.getStatus().success.dolibarr_version == "24.0.2")
		assert(last().url == API .. "/status")
		for _, req in requests do assert(req.method == "GET" and req.body == nil, "a read sent " .. req.method) end
		assert(#requests == 18, "wrong request count: " .. #requests)
	end,
}
