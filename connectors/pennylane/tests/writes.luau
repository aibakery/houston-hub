return {
	scenario = {publisher = {}, config = {access = "read-write"}, auth_method = "token", auth_config = {token = "pennylane-fixture-token"}},
	configure = function()
		requests = {}
		status = 201
		payload = '{"id":1}'
		fs = fixture.files()
		local multipart = http.multipart
		http = {multipart = multipart, request = function(req)
			if req.body ~= nil and type(req.body) ~= "string" then req.body = await(req.body:readAll()) end
			table.insert(requests, req)
			return fixture.operation({statusCode = status, headers = {}, body = fixture.reader(payload)})
		end}
	end,
	run = function(pennylane)
		local API = "https://app.pennylane.com/api/external/v2"
		local function last() return requests[#requests] end
		local function rejected(fn, expected)
			local before = #requests
			local ok, err = pcall(fn)
			local text = if type(err) == "table" then json.encode(err) else tostring(err)
			assert(not ok and string.find(text, expected, 1, true), "wrong validation error: " .. text)
			assert(#requests == before, "invalid input reached Pennylane")
		end

		local names = {}
		for name in pennylane do if name ~= "help" then table.insert(names, name) end end
		assert(#names == 182, "wrong read-write surface: " .. #names)

		payload = '{"id":42,"draft":true,"invoice_lines":{"url":"https://app.pennylane.com/api/external/v2/customer_invoices/42/invoice_lines"}}'
		local lines = {{label = "Consulting", quantity = 2, raw_currency_unit_price = "100.00", unit = "hour", vat_rate = "FR_200"}}
		local invoice = pennylane.postCustomerInvoices({date = "2026-11-03", deadline = "2026-12-03", customer_id = 12, draft = true, invoice_lines = lines})
		assert(last().method == "POST" and last().url == API .. "/customer_invoices" and last().headers.Authorization == nil)
		assert(last().headers["Content-Type"][1] == "application/json" and last().headers.Accept[1] == "application/json")
		local body = json.decode(last().body)
		assert(body.customer_id == 12 and body.draft == true and body.invoice_lines[1].raw_currency_unit_price == "100.00" and invoice.id == 42)

		status, payload = 200, '{"id":42,"draft":false}'
		pennylane.finalizeCustomerInvoice({id = 42})
		assert(last().method == "PUT" and last().url == API .. "/customer_invoices/42/finalize" and last().body == nil and last().headers["Content-Type"] == nil)

		pennylane.putCustomer({id = 12, name = "Acme SAS", emails = json.decode("[]")})
		assert(last().method == "PUT" and last().url == API .. "/customers/12" and last().body ~= nil)
		body = json.decode(last().body)
		assert(body.name == "Acme SAS" and body.id == nil and string.find(last().body, '"emails":[]', 1, true))

		status, payload = 204, ""
		local sent = pennylane.sendByEmailCustomerInvoice({id = 42})
		assert(last().url == API .. "/customer_invoices/42/send_by_email" and last().body == "{}" and next(sent) == nil)
		sent = pennylane.deleteCustomerInvoices({id = 43})
		assert(last().method == "DELETE" and last().url == API .. "/customer_invoices/43" and last().body == nil and next(sent) == nil)
		pennylane.deleteLedgerEntryLinesUnletter({unbalanced_lettering_strategy = "none", ledger_entry_lines = {{id = 1}, {id = 2}}})
		assert(last().method == "DELETE" and last().url == API .. "/ledger_entry_lines/lettering")
		body = json.decode(last().body)
		assert(body.unbalanced_lettering_strategy == "none" and body.ledger_entry_lines[2].id == 2)

		status, payload = 200, '[{"id":7,"weight":"1","label":"Marketing"}]'
		local categories = pennylane.putCustomerCategories({customer_id = 12, categories = {{id = 7, weight = "1"}}})
		assert(last().method == "PUT" and last().url == API .. "/customers/12/categories" and last().body == '[{"id":7,"weight":"1"}]', last().body)
		assert(categories[1].label == "Marketing")
		payload = "[]"
		pennylane.putTransactionCategories({transaction_id = 8, categories = {}})
		assert(last().url == API .. "/transactions/8/categories" and last().body == "[]", "clearing categories must send an empty array")

		local file = fs.open("receipts/invoice.pdf", "w")
		file:write("%PDF-fixture\0binary")
		await(file:close())
		status, payload = 201, '{"id":77,"url":"https://app.pennylane.com/rails/active_storage/blobs/redirect/x/invoice.pdf","filename":"invoice.pdf"}'
		local attachment = pennylane.postFileAttachments({file = "receipts/invoice.pdf"})
		assert(attachment.id == 77 and last().method == "POST" and last().url == API .. "/file_attachments")
		assert(string.find(last().headers["Content-Type"][1], "multipart/form-data", 1, true) == 1)
		for _, part in {'name="file"; filename="invoice.pdf"', "Content-Type: application/pdf", "%PDF-fixture\0binary"} do
			assert(string.find(last().body, part, 1, true), "missing multipart part " .. part)
		end

		pennylane.createCustomerInvoiceEInvoiceImport({file = "receipts/invoice.pdf", filename = "F-2026-1.pdf", send_to_pa = true,
			invoice_options = {customer_id = 12}, override_invoice_lines = {{label = "Line"}}})
		assert(last().url == API .. "/customer_invoices/e_invoices/imports")
		for _, part in {'filename="F-2026-1.pdf"', 'name="send_to_pa"\r\n\r\ntrue', 'name="invoice_options"', '{"customer_id":12}',
			'name="override_invoice_lines"', '[{"label":"Line"}]', "Content-Type: application/json"} do
			assert(string.find(last().body, part, 1, true), "missing multipart part " .. part)
		end
		pennylane.postQuoteAppendices({quote_id = 5, file = "receipts/invoice.pdf", content_type = "image/png"})
		assert(last().url == API .. "/quotes/5/appendices" and string.find(last().body, "Content-Type: image/png", 1, true))

		status, payload = 201, '{"id":99,"invoice_number":"A-1"}'
		pennylane.importSupplierInvoice({file_attachment_id = attachment.id, supplier_id = 3, date = "2026-11-01", deadline = "2026-12-01",
			currency_amount_before_tax = "100.00", currency_amount = "120.00", currency_tax = "20.00", invoice_lines = json.decode("[]")})
		body = json.decode(last().body)
		assert(last().url == API .. "/supplier_invoices/import" and body.file_attachment_id == 77 and string.find(last().body, '"invoice_lines":[]', 1, true))

		status, payload = 200, "true"
		assert(pennylane.markAsPaidCustomerInvoice({id = 42}) == true, "a write returns any JSON unchanged")

		status, payload = 201, '{"id":5,"callback_url":"https://hooks.example.com/pennylane","secret":"whsec_fixture"}'
		local webhook = pennylane.postWebhookSubscriptions({callback_url = "https://hooks.example.com/pennylane", events = {"customer_invoice.created"}})
		assert(last().url == API .. "/webhook_subscriptions" and webhook.secret == "whsec_fixture")
		local count = #requests

		rejected(function() pennylane.postCustomerInvoices({date = "2026-11-03", deadline = "2026-12-03", customer_id = 12}) end, "invoice_lines is required")
		rejected(function() pennylane.putCustomerCategories({customer_id = 12, categories = {id = 7, weight = "1"}}) end, "categories must be an array")
		rejected(function() pennylane.putCustomerCategories({customer_id = 12, categories = {{id = 7, weight = "1"}}, weight = "1"}) end, "has no option weight")
		rejected(function() pennylane.finalizeCustomerInvoice({id = 42, draft = false}) end, "finalizeCustomerInvoice has no option draft")
		rejected(function() pennylane.postFileAttachments({}) end, "file must be a session file path")
		rejected(function() pennylane.postFileAttachments({file = "receipts/invoice.pdf", filename = "../x.pdf"}) end, "filename must be a plain file name")
		rejected(function() pennylane.postFileAttachments({file = "receipts/invoice.pdf", content_type = "text/html\r\nX: y"}) end, "content_type must be a media type")
		rejected(function() pennylane.postFileAttachments({file = "receipts/invoice.pdf", send_to_pa = true}) end, "postFileAttachments has no option send_to_pa")
		rejected(function() pennylane.createCustomerInvoiceEInvoiceImport({file = "receipts/invoice.pdf", send_to_pa = "yes"}) end, "send_to_pa must be a boolean or JSON object")
		rejected(function() pennylane.postFileAttachments({file = "missing.pdf"}) end, "not_found")
		assert(#requests == count)
	end,
}
