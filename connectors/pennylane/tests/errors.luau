return {
	scenario = {publisher = {}, config = {access = "read-write"}, auth_method = "token", auth_config = {token = "pennylane-fixture-token"}},
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
	run = function(pennylane)
		local function upstream(call, code, body, headers, expected)
			status, payload, responseHeaders = code, body, headers
			local before = calls
			local ok, err = pcall(call)
			for _, text in expected do
				assert(not ok and string.find(tostring(err), text, 1, true), "missing " .. text .. " in " .. tostring(err))
			end
			assert(calls == before + 1, "failed request was retried")
		end
		local function send() pennylane.sendByEmailCustomerInvoice({id = 42}) end
		local function read() pennylane.getCustomerInvoices() end
		local function ledger() pennylane.getLedgerEntries() end
		local function export() pennylane.exportFec({period_start = "2025-01-01", period_end = "2025-12-31"}) end

		upstream(read, 401, '{"status":401,"error":"The access token is invalid"}', {},
			{"HTTP 401", "The access token is invalid", '"retryable":false'})
		upstream(read, 403, '{"status":403,"error":"Forbidden"}', {},
			{"HTTP 403: Forbidden", "needs the customer_invoices:readonly or customer_invoices:all scope", '"retryable":false'})
		upstream(send, 403, '{"status":403,"error":"Forbidden"}', {}, {"customer_invoices:all scope"})
		upstream(ledger, 403, '{"status":403,"error":"Forbidden"}', {}, {"ledger_entries:readonly or ledger_entries:all scope"})
		upstream(function() pennylane.getNumberings() end, 403, '{"status":403,"error":"Forbidden"}', {},
			{"needs the customer_invoices:readonly or customer_invoices:all or quotes:readonly or quotes:all or commercial_documents:readonly or commercial_documents:all scope"})
		upstream(function() pennylane.getWebhookSubscriptions() end, 403, '{"status":403,"error":"Forbidden"}', {}, {"needs the companies:webhook_subscriptions:all scope"})
		upstream(export, 403, '{"status":403,"error":"Forbidden"}', {}, {"exports:fec scope"})
		upstream(function() pennylane.getMe() end, 403, '{"status":403,"error":"Forbidden"}', {}, {"HTTP 403: Forbidden"})
		upstream(send, 409, '{"status":409,"error":"The invoice PDF is not generated yet"}', {},
			{"HTTP 409", "PDF is not generated yet", '"retryable":false'})
		upstream(send, 400, '{"message":"is not a valid email","field":"recipients","code":"InvalidEmailFormat"}', {},
			{"HTTP 400: is not a valid email (InvalidEmailFormat) field recipients"})
		upstream(send, 400, json.encode({message = string.rep("x", 5000), code = "NotExistRequiredKey", payload = {missing = "recipients"}}), {},
			{"(NotExistRequiredKey)", "missing", "recipients"})
		local accented = string.rep("x", 599) .. "\u{e9} trop long"
		upstream(read, 422, '{"status":422,"error":"' .. accented .. '"}', {}, {"HTTP 422: " .. string.rep("x", 599) .. '","operation"', '"retryable":false'})
		upstream(send, 422, '{"status":422,"error":"Entry lines are not balanced"}', {}, {"HTTP 422", "not balanced"})
		upstream(read, 429, "Rate limit exceeded. Please retry in 3 seconds.", {["retry-after"] = {"3"}},
			{"HTTP 429: Rate limit exceeded. Please retry in 3 seconds.", "Retry-After: 3", '"retryable":true'})
		upstream(send, 500, "<html>Internal error</html>", {}, {"HTTP 500", '"retryable":true'})
		upstream(read, 503, '{"status":503,"error":"Service unavailable"}', {}, {"HTTP 503: Service unavailable", '"retryable":true'})
		upstream(read, 200, "<html>Maintenance</html>", {}, {"invalid JSON"})
		upstream(send, 200, "<html>Done</html>", {}, {"accepted the request with HTTP 200 but returned invalid JSON", "read it back before repeating", '"retryable":false'})
	end,
}
