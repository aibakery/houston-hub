return {
	scenario = {config = {access = "read-only"}, auth_method = "token", auth_config = {token = "rk_test_fixture"}},
	configure = function()
		requests = {}
		payload = '{"object":"list","data":[{"id":"cus_1","metadata":{"key":"value"}}],"has_more":true}'
		http = {request = function(req)
			table.insert(requests, req)
			return fixture.operation({statusCode = 200, headers = {}, body = fixture.reader(payload)})
		end}
	end,
	run = function(c)
		local expected = {"getAccount", "getBalance", "listBalanceTransactions", "getBalanceTransaction", "listCustomers", "searchCustomers", "getCustomer", "listProducts", "getProduct", "listPrices", "getPrice", "listPaymentIntents", "getPaymentIntent", "listCharges", "getCharge", "listRefunds", "getRefund", "listSubscriptions", "getSubscription", "listInvoices", "getInvoice", "listInvoiceLines", "listPaymentMethods", "getPaymentMethod", "listPayouts", "getPayout", "listDisputes", "getDispute", "listEvents", "getEvent", "listCheckoutSessions", "getCheckoutSession", "listFiles", "getFile", "downloadFile"}
		local names = {}
		for name in c do if name ~= "help" then table.insert(names, name) end end
		table.sort(names); table.sort(expected)
		assert(table.concat(names, ",") == table.concat(expected, ","), "unexpected read-only exports")
		local args = {limit=2, email="a+b@example.com", created={gte=1700000000}, expand={"data.customer"}}
		local page = c.listCustomers(args)
		assert(page.data[1].id == "cus_1" and page.data[1].metadata.key == "value" and page.has_more)
		local req = requests[1]
		assert(req.url == "https://api.stripe.com/v1/customers?created%5Bgte%5D=1700000000&email=a%2Bb%40example.com&expand%5B0%5D=data.customer&limit=2", req.url)
		assert(req.method == "GET" and req.body == nil and req.headers.Authorization == nil and req.headers["Stripe-Version"][1] == "2026-09-30.endive")
		assert(args.limit == 2 and args.expand[1] == "data.customer", "input mutated")
		payload = '{"object":"list","data":[],"has_more":false}'
		assert(#c.listCustomers({starting_after="cus_1"}).data == 0)
		assert(requests[2].url == "https://api.stripe.com/v1/customers?starting_after=cus_1")
		payload = '{"object":"search_result","data":[],"has_more":false}'
		c.searchCustomers({query="email:'a@example.com'",page="next_1"})
		assert(string.find(requests[3].url, "page=next_1&query=",1,true))
		payload = '{"id":"in_1","amount_due":1234,"customer":null}'
		assert(c.getInvoice({invoice_id="in_1"}).customer == json.decode("null"))
		assert(requests[4].url == "https://api.stripe.com/v1/invoices/in_1")
		payload = '{"object":"list","data":[{"object":"event","data":{"object":{"object":"invoice","confirmation_secret":{"client_secret":"payment-capable"},"payment_intent":{"client_secret":"pi_secret","status":"requires_payment_method"},"subscription":{"pending_setup_intent":{"client_secret":"seti_secret"}},"source":{"klarna":{"client_token":"klarna_secret"}},"metadata":{"note":"keep","secret":"redact"},"hosted_invoice_url":"https://invoice.stripe.com/i/fixture","discounts":[],"description":null}}}],"has_more":false}'
		local event = c.listEvents().data[1].data.object
		assert(event.confirmation_secret == nil and event.payment_intent.client_secret == nil and event.payment_intent.status == "requires_payment_method")
		assert(event.subscription.pending_setup_intent.client_secret == nil and event.source.klarna.client_token == nil)
		assert(event.metadata.note == "keep" and event.metadata.secret == nil and event.description == json.decode("null"))
		assert(json.encode(event.discounts) == "[]" and event.hosted_invoice_url == "https://invoice.stripe.com/i/fixture")
		local before = #requests
		for _, call in {
			function() c.getCustomer({customer_id="../balance"}) end,
			function() c.getCustomer({customer_id="cus_1?x=y"}) end,
			function() c.getCustomer({}) end,
			function() c.listCustomers({limit=101}) end,
			function() c.listCustomers({starting_after="x",ending_before="y"}) end,
			function() c.listCustomers({["_method"]="POST"}) end,
			function() c.listCustomers({expand={[1]="a",[3]="b"}}) end,
			function() c.listCustomers({metadata=json.decode("null")}) end,
			function() c.listCustomers({idempotency_key="x"}) end,
			function() c.searchCustomers({}) end,
		} do assert(not pcall(call), "invalid request accepted") end
		assert(#requests == before, "invalid input reached network")
	end,
}
