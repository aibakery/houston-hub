return {
	scenario = {config = {access = "read-write"}, auth_method = "token", auth_config = {token = "fixture-wise-token"}},
	configure = function()
		requests = {}
		status = 200
		payload = '{"id":1}'
		http = {request = function(req)
			table.insert(requests, req)
			return fixture.operation({statusCode = status, headers = {}, body = fixture.reader(payload)})
		end}
	end,
	run = function(c)
		local api = "https://api.wise.com"
		local quote = "2d0b3b6e-6f1c-4c43-9c6a-1b6a0f4f3a10"
		local group = "6f0e2f8a-1b2c-4d5e-8f90-a1b2c3d4e5f6"
		local tx = "8c3a1f7e-0d4b-4e2a-9b6c-5f1e2d3c4b5a"
		local expected = {"getMe", "listProfiles", "getProfile", "listBalances", "getBalance", "getTotalFunds", "getBalanceStatement", "downloadBalanceStatement", "listAccountDetails", "listActivities", "getRates", "listCurrencies", "listTransfers", "getTransfer", "downloadTransferReceipt", "getQuote", "getAccountRequirements", "listRecipients", "getRecipient", "getBatchGroup",
			"createQuote", "updateQuote", "refreshAccountRequirements", "createRecipient", "validateTransferRequirements", "createTransfer", "cancelTransfer", "fundTransfer", "createBalance", "deleteBalance", "createBalanceMovement", "createBatchGroup", "createBatchTransfer", "updateBatchGroup", "fundBatchGroup"}
		local names = {}
		for name in c do if name ~= "help" then table.insert(names, name) end end
		table.sort(names); table.sort(expected)
		assert(table.concat(names, ",") == table.concat(expected, ","), "unexpected read-write exports: " .. table.concat(names, ","))

		local function same(a, b)
			if type(a) ~= "table" or type(b) ~= "table" then return a == b end
			for key, value in a do if not same(value, b[key]) then return false end end
			for key in b do if a[key] == nil then return false end end
			return true
		end

		local function sent(method, url, body, contentType)
			local req = requests[#requests]
			assert(req.method == method and req.url == url, req.method .. " " .. req.url)
			local allowed = {Accept = true, ["Content-Type"] = body ~= nil, ["X-idempotence-uuid"] = string.find(url, "/balance", 1, true) ~= nil and method == "POST", ["Accept-Minor-Version"] = string.find(url, "account-requirements", 1, true) ~= nil}
			for name in req.headers do assert(allowed[name], "unexpected header " .. name .. " on " .. url) end
			assert(req.headers.Accept[1] == "application/json")
			if body == nil then
				assert(req.body == nil, "unexpected body")
			else
				assert(req.headers["Content-Type"][1] == (contentType or "application/json"))
				assert(same(json.decode(req.body), body), "body mismatch: " .. req.body)
			end
			return req
		end

		c.createQuote({profileId = 202, sourceCurrency = "EUR", targetCurrency = "GBP", sourceAmount = 100, payOut = "BALANCE"})
		sent("POST", api .. "/v3/profiles/202/quotes", {sourceCurrency = "EUR", targetCurrency = "GBP", sourceAmount = 100, payOut = "BALANCE"})
		c.createQuote({profileId = 202, sourceCurrency = "EUR", targetCurrency = "GBP", sourceAmount = json.decode("null"), targetAmount = 10})
		sent("POST", api .. "/v3/profiles/202/quotes", {sourceCurrency = "EUR", targetCurrency = "GBP", sourceAmount = json.decode("null"), targetAmount = 10})
		c.updateQuote({profileId = 202, quoteId = quote, targetAccount = 55, payOut = "BANK_TRANSFER"})
		sent("PATCH", api .. "/v3/profiles/202/quotes/" .. quote, {targetAccount = 55, payOut = "BANK_TRANSFER"}, "application/merge-patch+json")
		payload = "[]"
		assert(json.encode(c.refreshAccountRequirements({quoteId = quote, originatorLegalEntityType = "PRIVATE", type = "iban", details = {legalType = "PRIVATE"}})) == "[]")
		local req = sent("POST", api .. "/v1/quotes/" .. quote .. "/account-requirements?originatorLegalEntityType=PRIVATE", {type = "iban", details = {legalType = "PRIVATE"}})
		assert(req.headers["Accept-Minor-Version"][1] == "1")
		payload = '{"id":55}'
		local recipient = {profile = 202, accountHolderName = "Ada Lovelace", currency = "EUR", type = "iban", ownedByCustomer = false, details = {legalType = "PRIVATE", IBAN = "DE89370400440532013000", address = json.decode("null")}}
		assert(c.createRecipient(recipient).id == 55)
		sent("POST", api .. "/v1/accounts", recipient)
		assert(recipient.profile == 202 and recipient.details.IBAN == "DE89370400440532013000", "input mutated")
		payload = "[]"
		c.validateTransferRequirements({targetAccount = 55, quoteUuid = quote, details = {reference = "Invoice 7"}})
		sent("POST", api .. "/v1/transfer-requirements", {targetAccount = 55, quoteUuid = quote, details = {reference = "Invoice 7"}})
		payload = '{"id":9001,"status":"incoming_payment_waiting"}'
		local transfer = {targetAccount = 55, quoteUuid = quote, customerTransactionId = tx, details = {reference = "Invoice 7"}}
		assert(c.createTransfer(transfer).id == 9001)
		sent("POST", api .. "/v1/transfers", transfer)
		payload = '{"id":9001,"status":"cancelled"}'
		c.cancelTransfer({transferId = 9001})
		sent("PUT", api .. "/v1/transfers/9001/cancel", nil)
		payload = ""
		assert(c.cancelTransfer({transferId = 9001}).success == true, "empty write response reported as failure")
		payload = '{"type":"BALANCE","status":"REJECTED","errorCode":"transfer.insufficient_funds"}'
		local funded = c.fundTransfer({profileId = 202, transferId = 9001, type = "BALANCE"})
		assert(funded.status == "REJECTED" and funded.errorCode == "transfer.insufficient_funds", "funding result changed")
		sent("POST", api .. "/v3/profiles/202/transfers/9001/payments", {type = "BALANCE"})

		payload = '{"id":3,"currency":"USD"}'
		c.createBalance({profileId = 202, currency = "USD", type = "STANDARD", idempotenceUuid = tx})
		req = sent("POST", api .. "/v4/profiles/202/balances", {currency = "USD", type = "STANDARD"})
		assert(req.headers["X-idempotence-uuid"][1] == tx)
		status = 204
		payload = ""
		assert(c.deleteBalance({profileId = 202, balanceId = 3}).success == true)
		sent("DELETE", api .. "/v4/profiles/202/balances/3", nil)
		status = 200
		payload = '{"success":true}'
		assert(c.deleteBalance({profileId = 202, balanceId = 4}).success == true)
		sent("DELETE", api .. "/v4/profiles/202/balances/4", nil)
		status = 201
		payload = '{"id":4,"type":"CONVERSION"}'
		c.createBalanceMovement({profileId = 202, quoteId = quote, idempotenceUuid = tx})
		req = sent("POST", api .. "/v2/profiles/202/balance-movements", {quoteId = quote})
		assert(req.headers["X-idempotence-uuid"][1] == tx)
		c.createBalanceMovement({profileId = 202, amount = {value = 5, currency = "EUR"}, sourceBalanceId = 1, targetBalanceId = 2, idempotenceUuid = tx})
		sent("POST", api .. "/v2/profiles/202/balance-movements", {amount = {value = 5, currency = "EUR"}, sourceBalanceId = 1, targetBalanceId = 2})

		payload = '{"id":"' .. group .. '","version":0}'
		c.createBatchGroup({profileId = 202, name = "October payroll", sourceCurrency = "EUR"})
		sent("POST", api .. "/v3/profiles/202/batch-groups", {name = "October payroll", sourceCurrency = "EUR"})
		c.createBatchTransfer({profileId = 202, batchGroupId = group, targetAccount = 55, quoteUuid = quote, customerTransactionId = tx})
		sent("POST", api .. "/v3/profiles/202/batch-groups/" .. group .. "/transfers", {targetAccount = 55, quoteUuid = quote, customerTransactionId = tx})
		c.updateBatchGroup({profileId = 202, batchGroupId = group, status = "COMPLETED", version = 0})
		sent("PATCH", api .. "/v3/profiles/202/batch-groups/" .. group, {status = "COMPLETED", version = 0})
		c.fundBatchGroup({profileId = 202, batchGroupId = group, type = "BALANCE"})
		sent("POST", api .. "/v3/profiles/202/batch-payments/" .. group .. "/payments", {type = "BALANCE"})

		local before = #requests
		for _, call in {
			function() c.createQuote({profileId = 202, sourceCurrency = "EUR", targetCurrency = "GBP"}) end,
			function() c.createQuote({profileId = 202, sourceCurrency = "EUR", targetCurrency = "GBP", sourceAmount = 1, targetAmount = 1}) end,
			function() c.createQuote({sourceCurrency = "EUR", targetCurrency = "GBP", sourceAmount = 1}) end,
			function() c.createQuote({profileId = 202, sourceCurrency = "EUR", targetCurrency = "GBP", sourceAmount = json.decode("null")}) end,
			function() c.createTransfer({targetAccount = 55, quoteUuid = "quote-1", customerTransactionId = tx}) end,
			function() c.createBalanceMovement({profileId = 202, quoteId = "quote-1", idempotenceUuid = tx}) end,
			function() c.createTransfer({targetAccount = 55, quoteUuid = quote}) end,
			function() c.createTransfer({targetAccount = 55, quoteUuid = quote, customerTransactionId = "payment-1"}) end,
			function() c.createBatchTransfer({profileId = 202, batchGroupId = group, targetAccount = 55, quoteUuid = quote, customerTransactionId = json.decode("null")}) end,
			function() c.createBatchTransfer({profileId = 202, batchGroupId = group, targetAccount = 55, quoteUuid = quote, customerTransactionId = "batch-1"}) end,
			function() c.createTransfer({targetAccount = 55, quoteUuid = quote, customerTransactionId = tx, idempotenceUuid = tx}) end,
			function() c.createBalance({profileId = 202, currency = "USD", type = "STANDARD", idempotenceUuid = "1"}) end,
			function() c.fundBatchGroup({profileId = 202, batchGroupId = group}) end,
			function() c.refreshAccountRequirements({quoteId = quote, originatorLegalEntityType = "COMPANY"}) end,
			function() c.createRecipient({profile = 202, currency = "EUR", type = "iban", details = {}}) end,
			function() c.createBalance({profileId = 202, currency = "USD", type = "STANDARD"}) end,
			function() c.createBalanceMovement({profileId = 202, quoteId = quote, idempotenceUuid = "not-a-uuid"}) end,
			function() c.fundTransfer({profileId = 202, transferId = 9001}) end,
			function() c.cancelTransfer({transferId = 9001, reason = "x"}) end,
			function() c.deleteBalance({profileId = 202, balanceId = "../balances"}) end,
			function() c.updateBatchGroup({profileId = 202, batchGroupId = group, status = "COMPLETED"}) end,
			function() c.updateQuote({profileId = 202, quoteId = "q1", targetAccount = 55}) end,
		} do assert(not pcall(call), "invalid write accepted") end
		assert(#requests == before, "invalid write reached Wise")
	end,
}
