return {
	scenario = {publisher = {}, config = {}, auth_method = "token", auth_config = {token = "pennylane-fixture-token"}},
	configure = function()
		requests = {}
		status = 200
		payload = '{"items":[],"has_more":false,"next_cursor":null}'
		http = {request = function(req)
			table.insert(requests, req)
			return fixture.operation({statusCode = status, headers = {}, body = fixture.reader(payload)})
		end}
	end,
	run = function(pennylane)
		local API = "https://app.pennylane.com/api/external/v2"
		local NULL = json.decode("null")
		local function last() return requests[#requests] end
		local function rejected(fn, expected)
			local before = #requests
			local ok, err = pcall(fn)
			assert(not ok and string.find(tostring(err), expected, 1, true), "wrong validation error: " .. tostring(err))
			assert(#requests == before, "invalid input reached Pennylane")
		end

		local names = {}
		for name in pennylane do if name ~= "help" then table.insert(names, name) end end
		assert(#names == 101, "wrong read-only surface: " .. #names)
		for _, name in {"postCustomerInvoices", "deleteCustomerInvoices", "finalizeCustomerInvoice", "sendByEmailCustomerInvoice",
			"postFileAttachments", "importSupplierInvoice", "putCustomerCategories", "postLedgerEntries", "postWebhookSubscriptions",
			"deleteLedgerEntryLinesUnletter", "postGocardlessMandateMailRequests", "validateAccountingSupplierInvoice"} do
			assert(pennylane[name] == nil, "read-only leaked " .. name)
		end
		assert(#requests == 0, "initialization reached Pennylane")

		payload = '{"user":null,"company":{"id":172916,"name":"Acme","reg_no":"sandbox-172916"},"scopes":["customer_invoices:readonly"]}'
		local me = pennylane.getMe()
		assert(last().method == "GET" and last().url == API .. "/me" and last().body == nil)
		assert(last().headers.Accept[1] == "application/json" and last().headers.Authorization == nil and last().headers["Content-Type"] == nil)
		assert(me.company.id == 172916 and me.user == NULL and me.scopes[1] == "customer_invoices:readonly")

		payload = '{"items":[{"id":42,"invoice_number":"F-2026-1","amount":"120.00","public_file_url":null,"customer":{"id":12,"url":"https://app.pennylane.com/api/external/v2/customers/12"}}],"has_more":true,"next_cursor":"eyJpZCI6NDJ9"}'
		local filter = {{field = "date", operator = "gteq", value = "2026-01-01"}, {field = "customer_id", operator = "in", value = {12, 34}}}
		local opts = {filter = filter, sort = "-date", limit = 50, cursor = "eyJpZCI6NDJ9", include = "invoice_lines"}
		local page = pennylane.getCustomerInvoices(opts)
		local query = string.match(last().url, "^" .. string.gsub(API, "%p", "%%%0") .. "/customer_invoices%?(.*)$")
		assert(query, last().url)
		local sent: {[string]: string} = {}
		local order: {string} = {}
		for key, value in string.gmatch(query, "([^&=]+)=([^&]*)") do sent[key] = value; table.insert(order, key) end
		assert(table.concat(order, ",") == "cursor,limit,filter,sort,include", table.concat(order, ","))
		assert(sent.cursor == "eyJpZCI6NDJ9" and sent.limit == "50" and sent.sort == "-date" and sent.include == "invoice_lines")
		assert(not string.find(sent.filter, "[%[%]{}\":,]"), "filter is not URL-encoded: " .. sent.filter)
		local decoded = json.decode((string.gsub(sent.filter, "%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end)))
		assert(decoded[1].field == "date" and decoded[1].operator == "gteq" and decoded[1].value == "2026-01-01")
		assert(decoded[2].value[1] == 12 and decoded[2].value[2] == 34, "filter values must stay an array")
		assert(opts.limit == 50 and opts.filter == filter, "options were modified")
		assert(page.has_more == true and page.next_cursor == "eyJpZCI6NDJ9" and page.items[1].amount == "120.00" and page.items[1].public_file_url == NULL)

		pennylane.getSupplierInvoices({filter = '[{"field":"supplier_id","operator":"eq","value":"7"}]'})
		assert(last().url == API .. "/supplier_invoices?filter=%5B%7B%22field%22%3A%22supplier_id%22%2C%22operator%22%3A%22eq%22%2C%22value%22%3A%227%22%7D%5D", last().url)

		payload = '{"items":[],"has_more":false,"next_cursor":null}'
		local empty = pennylane.getCustomerInvoiceInvoiceLines({customer_invoice_id = 42, sort = "rank"})
		assert(last().url == API .. "/customer_invoices/42/invoice_lines?sort=rank", last().url)
		assert(json.encode(empty.items) == "[]" and empty.next_cursor == NULL)

		pennylane.getCustomerInvoice({id = "42"})
		assert(last().url == API .. "/customer_invoices/42")
		pennylane.getCustomerContact({customer_id = 12, id = 3})
		assert(last().url == API .. "/customers/12/contacts/3")
		pennylane.getFiscalYears({sort = "start"})
		assert(last().url == API .. "/fiscal_years?sort=start")
		pennylane.getTrialBalance({period_start = "2026-01-01", period_end = "2026-03-31", is_auxiliary = true, limit = 1000})
		assert(last().url == API .. "/trial_balance?period_start=2026-01-01&period_end=2026-03-31&is_auxiliary=true&limit=1000", last().url)
		pennylane.getCustomerInvoicesChanges({start_date = "2026-10-20T00:00:00Z"})
		assert(last().url == API .. "/changelogs/customer_invoices?start_date=2026-10-20T00%3A00%3A00Z", last().url)
		pennylane.getLedgerAccounts({filter = {{field = "number", operator = "start_with", value = "411"}}})
		assert(string.find(last().url, API .. "/ledger_accounts?filter=", 1, true) == 1)

		payload = '{"items":[{"id":1,"siret":"12345678900011","status":"activated"}],"has_more":false,"next_cursor":null,"emission_activated":true}'
		assert(pennylane.getPaRegistrations().items[1].status == "activated" and last().url == API .. "/pa_registrations")

		status, payload = 201, '{"id":9,"status":"pending","file_url":null}'
		local job = pennylane.exportFec({period_start = "2025-01-01", period_end = "2025-12-31"})
		assert(last().method == "POST" and last().url == API .. "/exports/fecs" and last().headers["Content-Type"][1] == "application/json")
		local body = json.decode(last().body)
		assert(body.period_start == "2025-01-01" and body.period_end == "2025-12-31" and job.status == "pending")
		status, payload = 200, '{"id":9,"status":"ready","file_url":"https://app.pennylane.com/exports/fec.txt"}'
		assert(pennylane.getFecExport({id = job.id}).status == "ready" and last().url == API .. "/exports/fecs/9")

		payload = ""
		local ok, err = pcall(function() pennylane.getMe() end)
		assert(not ok and string.find(tostring(err), "empty response", 1, true), "an empty GET response is not data")
		payload = '"text"'
		ok, err = pcall(function() pennylane.getMe() end)
		assert(not ok and string.find(tostring(err), "invalid JSON", 1, true), tostring(err))
		local count = #requests

		rejected(function() pennylane.getCustomerInvoice() end, "id must be a nonnegative integer ID")
		rejected(function() pennylane.getCustomerInvoice({id = "../me"}) end, "id must be a nonnegative integer ID")
		rejected(function() pennylane.getCustomerInvoice({id = "42?x=1"}) end, "id must be a nonnegative integer ID")
		rejected(function() pennylane.getCustomerInvoice({id = 4.2}) end, "id must be a nonnegative integer ID")
		rejected(function() pennylane.getCustomerInvoice({id = -1}) end, "id must be a nonnegative integer ID")
		rejected(function() pennylane.getCustomerInvoice({id = 42, include = "x"}) end, "getCustomerInvoice has no option include")
		rejected(function() pennylane.getTrialBalance({period_start = "2026-01-01"}) end, "period_end is required")
		rejected(function() pennylane.getTrialBalance({period_start = NULL, period_end = "2026-01-31"}) end, "period_start is required")
		rejected(function() pennylane.exportFec({period_start = "2025-01-01"}) end, "period_end is required")
		rejected(function() pennylane.getCustomerChanges({start_date = "2026-10-20T00:00:00Z", cursor = "c1"}) end, "pass start_date or cursor, not both")
		rejected(function() pennylane.getCustomers({filter = {}}) end, "filter must be a nonempty array")
		rejected(function() pennylane.getCustomers({filter = {field = "name", operator = "eq", value = "x"}}) end, "filter must be a nonempty array")
		rejected(function() pennylane.getCustomers({filter = {{field = "name", value = "x"}}}) end, "needs field, operator and value")
		rejected(function() pennylane.getCustomers({filter = "name=x"}) end, "filter must be an array")
		rejected(function() pennylane.getCustomers({limit = 0}) end, "limit must be an integer")
		rejected(function() pennylane.getCustomers({limit = 2.5}) end, "limit must be an integer")
		rejected(function() pennylane.getCustomers({sort = {"id"}}) end, "sort must be a string")
		rejected(function() pennylane.getCustomers("x") end, "opts must be an object")
		rejected(function() pennylane.getCustomers({"x"}) end, "named fields")
		rejected(function() pennylane.getCustomers({_method = "delete"}) end, "getCustomers has no option _method")
		assert(#requests == count)
	end,
}
