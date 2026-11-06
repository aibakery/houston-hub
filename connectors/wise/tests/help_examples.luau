return {
	scenario = {config = {access = "read-write"}, auth_method = "token", auth_config = {token = "fixture-wise-token"}},
	configure = function()
		requests = {}
		fs = fixture.files()
		http = {request = function(req)
			table.insert(requests, req)
			return fixture.operation({statusCode = 200, headers = {["content-type"] = {if download then "application/pdf" else "application/json"}}, body = fixture.reader(if download then "PDF" .. string.char(0, 255) else '{"futureField":true}')})
		end}
	end,
	run = function(c)
		local quote = "00000000-0000-4000-8000-000000000001"
		local statement = "?currency=GBP&intervalEnd=2026-10-31T23%3A59%3A59Z&intervalStart=2026-10-01T00%3A00%3A00Z&type=COMPACT"
		local cases = {
			getMe = {"GET", "/v1/me"}, listProfiles = {"GET", "/v2/profiles"}, getProfile = {"GET", "/v2/profiles/101", "profileId"},
			listBalances = {"GET", "/v4/profiles/101/balances?types=STANDARD,SAVINGS", "profileId types"}, getBalance = {"GET", "/v4/profiles/101/balances/101", "profileId balanceId"},
			getTotalFunds = {"GET", "/v1/profiles/101/total-funds/GBP", "profileId currency"},
			getBalanceStatement = {"GET", "/v1/profiles/101/balance-statements/101/statement.json" .. statement},
			downloadBalanceStatement = {"GET", "/v1/profiles/101/balance-statements/101/statement.pdf" .. statement},
			listAccountDetails = {"GET", "/v1/profiles/101/account-details"}, listActivities = {"GET", "/v1/profiles/101/activities?size=20&status=COMPLETED"},
			getRates = {"GET", "/v1/rates?source=GBP&target=EUR"}, listCurrencies = {"GET", "/v1/currencies"},
			listTransfers = {"GET", "/v1/transfers?limit=20&offset=0&profile=101"}, getTransfer = {"GET", "/v1/transfers/101"}, downloadTransferReceipt = {"GET", "/v1/transfers/101/receipt.pdf"},
			getQuote = {"GET", "/v3/profiles/101/quotes/" .. quote}, getAccountRequirements = {"GET", "/v1/quotes/" .. quote .. "/account-requirements?addressRequired=true&originatorLegalEntityType=PRIVATE"},
			listRecipients = {"GET", "/v2/accounts?active=true&profileId=101&size=20"}, getRecipient = {"GET", "/v2/accounts/101"}, getBatchGroup = {"GET", "/v3/profiles/101/batch-groups/" .. quote},
			createQuote = {"POST", "/v3/profiles/101/quotes", "profileId"}, updateQuote = {"PATCH", "/v3/profiles/101/quotes/" .. quote, "profileId quoteId"},
			refreshAccountRequirements = {"POST", "/v1/quotes/" .. quote .. "/account-requirements?originatorLegalEntityType=PRIVATE", "quoteId originatorLegalEntityType"},
			createRecipient = {"POST", "/v1/accounts"}, validateTransferRequirements = {"POST", "/v1/transfer-requirements"}, createTransfer = {"POST", "/v1/transfers"},
			cancelTransfer = {"PUT", "/v1/transfers/101/cancel"}, fundTransfer = {"POST", "/v3/profiles/101/transfers/101/payments", "profileId transferId"},
			createBalance = {"POST", "/v4/profiles/101/balances", "profileId idempotenceUuid"}, deleteBalance = {"DELETE", "/v4/profiles/101/balances/101"},
			createBalanceMovement = {"POST", "/v2/profiles/101/balance-movements", "profileId idempotenceUuid"},
			createBatchGroup = {"POST", "/v3/profiles/101/batch-groups", "profileId"}, createBatchTransfer = {"POST", "/v3/profiles/101/batch-groups/" .. quote .. "/transfers", "profileId batchGroupId"},
			updateBatchGroup = {"PATCH", "/v3/profiles/101/batch-groups/" .. quote, "profileId batchGroupId"}, fundBatchGroup = {"POST", "/v3/profiles/101/batch-payments/" .. quote .. "/payments", "profileId batchGroupId"},
		}
		local examples = require("lib/examples.luau")
		local count = 0
		for name in c do if name ~= "help" then count += 1; assert(cases[name], name) end end
		assert(count == 35)
		for name, case in cases do
			for index, example in examples[name] do
				download = string.sub(name, 1, 8) == "download"
				local before = #requests
				local result = fixture.example(name, index)
				assert(#requests == before + 1, name .. " unexpectedly paged or retried")
				local req = requests[#requests]
				assert(req.method == case[1] and req.url == "https://api.wise.com" .. case[2], name .. ": " .. req.url)
				assert(req.headers.Authorization == nil and req.headers.Accept[1] == (if download then "*/*" else "application/json"))
				if example.idempotenceUuid then assert(req.headers["X-idempotence-uuid"][1] == example.idempotenceUuid) end
				if string.find(name, "AccountRequirements", 1, true) then assert(req.headers["Accept-Minor-Version"][1] == "1") end
				if case[1] == "POST" or case[1] == "PATCH" then
					local expected = table.clone(example)
					for field in string.gmatch(case[3] or "", "%S+") do expected[field] = nil end
					if name == "createQuote" then for _, field in {"sourceAmount", "targetAmount"} do if expected[field] == json.decode("null") then expected[field] = nil end end end
					assert(json.encode(json.decode(req.body)) == json.encode(expected), name .. " changed native fields")
					assert(req.headers["Content-Type"][1] == (if name == "updateQuote" then "application/merge-patch+json" else "application/json"))
				else assert(req.body == nil) end
				if download then
					assert(result.path == example.path and result.size == 5 and type(result.url) == "string")
					local file = fs.open(result.path, "r"); assert(await(file:readAll()) == "PDF" .. string.char(0, 255)); file:close()
				else assert(result.futureField) end
			end
		end
	end,
}
