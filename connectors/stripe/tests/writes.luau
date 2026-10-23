return {
	scenario = {config = {access = "read-write"}, auth_method = "token", auth_config = {token = "sk_test_fixture"}},
	configure = function()
		requests = {}
		payload = '{"id":"fixture","object":"customer","deleted":true}'
		http = {request = function(req)
			table.insert(requests, req)
			return fixture.operation({statusCode = 200, headers = {}, body = fixture.reader(payload)})
		end}
	end,
	run = function(c)
		local routes = {
			createCustomer={"POST","/v1/customers",{}}, updateCustomer={"POST","/v1/customers/cus_1",{customer_id="cus_1"}}, deleteCustomer={"DELETE","/v1/customers/cus_1",{customer_id="cus_1"}},
			createProduct={"POST","/v1/products",{name="Book"}}, updateProduct={"POST","/v1/products/prod_1",{product_id="prod_1"}},
			createPrice={"POST","/v1/prices",{currency="usd",product="prod_1",unit_amount=100}}, updatePrice={"POST","/v1/prices/price_1",{price_id="price_1"}},
			createPaymentIntent={"POST","/v1/payment_intents",{amount=100,currency="usd"}}, updatePaymentIntent={"POST","/v1/payment_intents/pi_1",{payment_intent_id="pi_1"}},
			confirmPaymentIntent={"POST","/v1/payment_intents/pi_1/confirm",{payment_intent_id="pi_1"}}, capturePaymentIntent={"POST","/v1/payment_intents/pi_1/capture",{payment_intent_id="pi_1"}}, cancelPaymentIntent={"POST","/v1/payment_intents/pi_1/cancel",{payment_intent_id="pi_1"}},
			createRefund={"POST","/v1/refunds",{charge="ch_1"}}, updateRefund={"POST","/v1/refunds/re_1",{refund_id="re_1"}},
			createSubscription={"POST","/v1/subscriptions",{customer="cus_1",items={{price="price_1"}}}}, updateSubscription={"POST","/v1/subscriptions/sub_1",{subscription_id="sub_1"}}, cancelSubscription={"DELETE","/v1/subscriptions/sub_1",{subscription_id="sub_1"}},
			createInvoice={"POST","/v1/invoices",{customer="cus_1"}}, updateInvoice={"POST","/v1/invoices/in_1",{invoice_id="in_1"}}, finalizeInvoice={"POST","/v1/invoices/in_1/finalize",{invoice_id="in_1"}}, payInvoice={"POST","/v1/invoices/in_1/pay",{invoice_id="in_1"}}, sendInvoice={"POST","/v1/invoices/in_1/send",{invoice_id="in_1"}}, voidInvoice={"POST","/v1/invoices/in_1/void",{invoice_id="in_1"}}, deleteInvoice={"DELETE","/v1/invoices/in_1",{invoice_id="in_1"}}, createInvoiceItem={"POST","/v1/invoiceitems",{customer="cus_1",amount=100,currency="usd"}},
			attachPaymentMethod={"POST","/v1/payment_methods/pm_1/attach",{payment_method_id="pm_1",customer="cus_1"}}, detachPaymentMethod={"POST","/v1/payment_methods/pm_1/detach",{payment_method_id="pm_1"}},
			createPayout={"POST","/v1/payouts",{amount=100,currency="usd"}}, cancelPayout={"POST","/v1/payouts/po_1/cancel",{payout_id="po_1"}}, updateDispute={"POST","/v1/disputes/dp_1",{dispute_id="dp_1"}},
			createCheckoutSession={"POST","/v1/checkout/sessions",{mode="payment"}}, expireCheckoutSession={"POST","/v1/checkout/sessions/cs_1/expire",{session_id="cs_1"}}, createPortalSession={"POST","/v1/billing_portal/sessions",{customer="cus_1"}},
		}
		for name, route in routes do
			assert(c[name](route[3]).deleted == true)
			local req = requests[#requests]
			assert(req.method == route[1] and req.url == "https://api.stripe.com" .. route[2], name .. ": " .. req.url)
			assert(req.headers.Authorization == nil and req.headers["Stripe-Version"][1] == "2026-09-30.endive")
		end
		local count = 0
		for name in c do if name ~= "help" then count += 1 end end
		assert(count == 69 and c.uploadFile and c.downloadFile, "unexpected write surface")
		payload = '{"id":"pi_1","client_secret":"pi_secret","metadata":{"secret":"native"}}'
		local native = c.getPaymentIntent({payment_intent_id="pi_1"})
		assert(native.client_secret == "pi_secret" and native.metadata.secret == "native", "write access changed native fields")
		c.createSubscription({customer="cus_1",items={{price="price_1",quantity=2},{price="price_2"}},metadata={note="a+b & c"},idempotency_key="sub/customer/1"})
		local req = requests[#requests]
		assert(req.headers["Content-Type"][1] == "application/x-www-form-urlencoded" and req.headers["Idempotency-Key"][1] == "sub/customer/1")
		assert(req.body == "customer=cus_1&items%5B0%5D%5Bprice%5D=price_1&items%5B0%5D%5Bquantity%5D=2&items%5B1%5D%5Bprice%5D=price_2&metadata%5Bnote%5D=a%2Bb%20%26%20c",req.body)
		c.updateCustomer({customer_id="cus_1",metadata={},description="",invoice_settings={default_payment_method="pm_1"}})
		assert(requests[#requests].body == "description=&invoice_settings%5Bdefault_payment_method%5D=pm_1&metadata=")
		c.cancelSubscription({subscription_id="sub_1",invoice_now=true,prorate=false})
		assert(requests[#requests].url == "https://api.stripe.com/v1/subscriptions/sub_1?invoice_now=true&prorate=false" and requests[#requests].body == nil)
		c.createSubscription({customer_account="acct_1",items={{price="price_1"}}})
		assert(requests[#requests].body == "customer_account=acct_1&items%5B0%5D%5Bprice%5D=price_1")
		c.attachPaymentMethod({payment_method_id="pm_1",customer_account="acct_1"})
		assert(requests[#requests].body == "customer_account=acct_1")
		c.createPortalSession({customer_account="acct_1"})
		assert(requests[#requests].body == "customer_account=acct_1")
		c.createInvoice({from_invoice={action="revision",invoice="in_1"}})
		assert(requests[#requests].body == "from_invoice%5Baction%5D=revision&from_invoice%5Binvoice%5D=in_1")
		c.createRefund({customer="cus_1",origin="customer_balance",amount=100})
		assert(requests[#requests].body == "amount=100&customer=cus_1&origin=customer_balance")
		local before = #requests
		for _, call in {
			function() c.createPaymentIntent({currency="usd"}) end,
			function() c.createPrice({currency="usd"}) end,
			function() c.createCustomer({idempotency_key=string.rep("a",256)}) end,
			function() c.createCustomer({idempotency_key="a\nb"}) end,
			function() c.createCustomer({metadata={nested=json.decode("null")}}) end,
			function() c.createCustomer({metadata={["bad[key]"]="x"}}) end,
		} do assert(not pcall(call), "invalid input accepted") end
		assert(#requests == before, "invalid input reached Stripe")
	end,
}
