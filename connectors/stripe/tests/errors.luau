return {
	scenario = {config = {access = "read-write"}, auth_method = "token", auth_config = {token = "rk_test_fixture"}},
	configure = function()
		calls, status, payload, responseHeaders = 0, 200, "{}", {}
		http = {request = function(req)
			calls += 1
			return fixture.operation({statusCode=status,headers=responseHeaders,body=fixture.reader(payload)})
		end}
	end,
	run = function(c)
		local function fails(code, body, headers, expected)
			status, payload, responseHeaders = code, body, headers
			local before = calls
			local ok, err = pcall(c.createRefund,{charge="ch_1",idempotency_key="refund-1"})
			for _, part in expected do assert(not ok and string.find(tostring(err),part,1,true), tostring(err)) end
			assert(calls == before + 1, "a financial write was retried")
		end
		fails(402,'{"error":{"type":"card_error","code":"card_declined","param":"payment_method","message":"Your card was declined"}}', {["request-id"]={"req_1"}}, {"Stripe HTTP 402","card_declined","payment_method","req_1",'"retryable":false'})
		fails(403,'{"error":{"message":"Permission denied"}}', {}, {"HTTP 403","Permission denied",'"retryable":false'})
		fails(429,'{"error":{"type":"rate_limit_error","message":"Slow down"}}', {["retry-after"]={"3"},["stripe-rate-limited-reason"]={"endpoint-rate"}}, {"retry-after=3","endpoint-rate",'"retryable":true'})
		fails(500,string.rep("X",100000),{["stripe-should-retry"]={"false"}},{"HTTP 500","stripe-should-retry=false",'"retryable":false'})
		fails(409,'{"error":{"message":"Conflict"}}',{["stripe-should-retry"]={"true"}},{"HTTP 409",'"retryable":true'})
		fails(200,"not json",{},{"invalid JSON object"})
		fails(200,"[]",{},{"invalid JSON object"})
		fails(204,"",{},{"invalid JSON object"})
	end,
}
