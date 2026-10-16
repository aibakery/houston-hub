return {
	scenario = {config = {access = "read-only"}, auth_method = "token", auth_config = {token = "fixture-wise-token"}},
	configure = function()
		requests = {}
		payload = "[]"
		http = {request = function(req)
			table.insert(requests, req)
			return fixture.operation({statusCode = 200, headers = {}, body = fixture.reader(payload)})
		end}
	end,
	run = function(c)
		local expected = {"getMe", "listProfiles", "getProfile", "listBalances", "getBalance", "getTotalFunds", "getBalanceStatement", "downloadBalanceStatement", "listAccountDetails", "listActivities", "getRates", "listCurrencies", "listTransfers", "getTransfer", "downloadTransferReceipt", "getQuote", "getAccountRequirements", "listRecipients", "getRecipient", "getBatchGroup"}
		local names = {}
		for name in c do if name ~= "help" then table.insert(names, name) end end
		table.sort(names); table.sort(expected)
		assert(table.concat(names, ",") == table.concat(expected, ","), "unexpected read-only exports: " .. table.concat(names, ","))
		local api = "https://api.wise.com"
		local function last() return requests[#requests] end
		local function get(url)
			local req = last()
			assert(req.method == "GET" and req.url == url, req.url)
			for name in req.headers do assert(name == "Accept" or (name == "Accept-Minor-Version" and string.find(url, "account-requirements", 1, true)), "unexpected header " .. name) end
			assert(req.headers.Authorization == nil and req.body == nil and req.headers.Accept[1] == "application/json")
		end

		assert(json.encode(c.listProfiles()) == "[]", "empty profile array lost")
		get(api .. "/v2/profiles")
		payload = '[{"id":101,"type":"PERSONAL","details":{"firstName":"Ada"}},{"id":202,"type":"BUSINESS","details":{"name":"Acme"}}]'
		local profiles = c.listProfiles()
		assert(#profiles == 2 and profiles[2].id == 202 and profiles[2].details.name == "Acme")
		payload = '{"id":7,"email":"ada@example.com","active":true}'
		assert(c.getMe().email == "ada@example.com")
		get(api .. "/v1/me")
		c.getProfile({profileId = 202})
		get(api .. "/v2/profiles/202")

		payload = '[{"id":1,"currency":"EUR","type":"STANDARD","amount":{"value":12.5,"currency":"EUR"},"name":null}]'
		local balances = c.listBalances({profileId = "202", types = {"STANDARD", "SAVINGS"}})
		assert(balances[1].amount.value == 12.5 and balances[1].name == json.decode("null"))
		get(api .. "/v4/profiles/202/balances?types=STANDARD,SAVINGS")
		c.listBalances({profileId = 202, types = "STANDARD,SAVINGS"})
		get(api .. "/v4/profiles/202/balances?types=STANDARD,SAVINGS")
		c.listBalances({profileId = 202, types = " STANDARD , SAVINGS"})
		get(api .. "/v4/profiles/202/balances?types=STANDARD,SAVINGS")
		payload = "[]"
		assert(json.encode(c.listBalances({profileId = 202, types = "STANDARD"})) == "[]", "empty balance array lost")
		get(api .. "/v4/profiles/202/balances?types=STANDARD")
		payload = "{}"
		c.getBalance({profileId = 202, balanceId = 1})
		get(api .. "/v4/profiles/202/balances/1")
		c.getTotalFunds({profileId = 202, currency = "GBP"})
		get(api .. "/v1/profiles/202/total-funds/GBP")
		c.getBalanceStatement({profileId = 202, balanceId = 1, currency = "EUR", intervalStart = "2026-01-01T00:00:00.000Z", intervalEnd = "2026-02-01T00:00:00.000Z", type = "COMPACT"})
		get(api .. "/v1/profiles/202/balance-statements/1/statement.json?currency=EUR&intervalEnd=2026-02-01T00%3A00%3A00.000Z&intervalStart=2026-01-01T00%3A00%3A00.000Z&type=COMPACT")
		payload = '[{"id":1,"currency":{"code":"EUR"},"receiveOptions":[]}]'
		local details = c.listAccountDetails({profileId = 202})
		assert(details[1].currency.code == "EUR" and json.encode(details[1].receiveOptions) == "[]")
		payload = "[]"
		assert(json.encode(c.listAccountDetails({profileId = 202})) == "[]")
		get(api .. "/v1/profiles/202/account-details")

		payload = '{"activities":[{"id":"TU9ORVRBUllfQUNUSVZJVFk6OjE=","title":"<strong>Shop</strong>","primaryAmount":"10 EUR"}],"cursor":"abc=="}'
		local page = c.listActivities({profileId = 202, size = 100, ["until"] = "2026-10-01T00:00:00Z", nextCursor = "prev+/="})
		assert(page.cursor == "abc==" and page.activities[1].title == "<strong>Shop</strong>")
		get(api .. "/v1/profiles/202/activities?nextCursor=prev%2B%2F%3D&size=100&until=2026-10-01T00%3A00%3A00Z")
		payload = '{"activities":[],"cursor":null}'
		local done = c.listActivities({profileId = 202})
		assert(json.encode(done.activities) == "[]" and done.cursor == json.decode("null"))

		payload = '[{"rate":1.16,"source":"EUR","target":"USD","time":"2026-10-16T10:00:00+0000"}]'
		assert(c.getRates({source = "EUR", target = "USD", from = "2026-10-01", to = "2026-10-16", group = "day"})[1].rate == 1.16)
		get(api .. "/v1/rates?from=2026-10-01&group=day&source=EUR&target=USD&to=2026-10-16")
		payload = "[]"
		assert(json.encode(c.getRates({source = "EUR", target = "XXX"})) == "[]", "empty rate array lost")
		payload = '[{"code":"EUR","symbol":"€","name":"Euro","countryKeywords":[]}]'
		local currencies = c.listCurrencies()
		assert(currencies[1].symbol == "€" and json.encode(currencies[1].countryKeywords) == "[]")
		get(api .. "/v1/currencies")
		payload = "[]"
		assert(json.encode(c.listCurrencies()) == "[]", "empty currency array lost")
		payload = '[{"id":9001,"status":"processing","targetValue":10.5}]'
		assert(c.listTransfers({profile = 202})[1].targetValue == 10.5)
		payload = "[]"
		assert(json.encode(c.listTransfers({profile = 202, status = {"incoming_payment_waiting", "processing"}, limit = 20, offset = 0})) == "[]")
		get(api .. "/v1/transfers?limit=20&offset=0&profile=202&status=incoming_payment_waiting,processing")
		payload = '{"id":2147483648,"status":"outgoing_payment_sent"}'
		assert(c.getTransfer({transferId = 2147483648}).id == 2147483648)
		get(api .. "/v1/transfers/2147483648")
		local quote = "2d0b3b6e-6f1c-4c43-9c6a-1b6a0f4f3a10"
		c.getQuote({profileId = 202, quoteId = quote})
		get(api .. "/v3/profiles/202/quotes/" .. quote)
		payload = '[{"type":"iban","fields":[{"name":"IBAN","group":[{"key":"IBAN","refreshRequirementsOnChange":false}]}]}]'
		assert(c.getAccountRequirements({quoteId = quote})[1].fields[1].group[1].key == "IBAN")
		payload = "[]"
		c.getAccountRequirements({quoteId = quote, originatorLegalEntityType = "BUSINESS", addressRequired = true})
		get(api .. "/v1/quotes/" .. quote .. "/account-requirements?addressRequired=true&originatorLegalEntityType=BUSINESS")
		assert(last().headers["Accept-Minor-Version"][1] == "1")
		payload = '{"content":[],"seekPositionForNext":null,"size":20}'
		local recipients = c.listRecipients({profileId = 202, currency = "EUR", active = true, size = 20, seekPosition = 123})
		assert(json.encode(recipients.content) == "[]" and recipients.seekPositionForNext == json.decode("null"))
		get(api .. "/v2/accounts?active=true&currency=EUR&profileId=202&seekPosition=123&size=20")
		payload = "{}"
		c.getRecipient({accountId = 55})
		get(api .. "/v2/accounts/55")
		c.getBatchGroup({profileId = 202, batchGroupId = quote})
		get(api .. "/v3/profiles/202/batch-groups/" .. quote)

		local before = #requests
		for _, call in {
			function() c.getProfile({profileId = "../me"}) end,
			function() c.getProfile({profileId = "202?x=y"}) end,
			function() c.getProfile({profileId = 0}) end,
			function() c.getProfile({profileId = 1.5}) end,
			function() c.getProfile({}) end,
			function() c.getProfile({profileId = 202, extra = true}) end,
			function() c.listBalances({profileId = 202}) end,
			function() c.listBalances({profileId = 202, types = {"CHECKING"}}) end,
			function() c.listBalances({profileId = 202, types = {}}) end,
			function() c.getTotalFunds({profileId = 202, currency = "gbp"}) end,
			function() c.getTotalFunds({profileId = 202, currency = "../x"}) end,
			function() c.getBalanceStatement({profileId = 202, balanceId = 1, currency = "EUR", intervalStart = "x"}) end,
			function() c.listActivities({profileId = 202, size = 101}) end,
			function() c.listActivities({profileId = 202, ["_method"] = "POST"}) end,
			function() c.listRecipients({profileId = 202, size = 21}) end,
			function() c.listRecipients({profileId = 202, active = "true"}) end,
			function() c.getQuote({profileId = 202, quoteId = "../../me"}) end,
			function() c.getRates({group = "week"}) end,
			function() c.getProfile({profileId = "12345678901234567"}) end,
			function() c.getProfile({profileId = 9007199254740992}) end,
			function() c.getBalanceStatement({profileId = 202, balanceId = 1, currency = "EUR", intervalStart = "a", intervalEnd = "b", type = "DETAILED"}) end,
			function() c.getAccountRequirements({quoteId = quote, originatorLegalEntityType = "COMPANY"}) end,
			function() c.listActivities({profileId = 202, status = "DONE"}) end,
			function() c.listTransfers({profile = 202, status = {[1] = "a", [3] = "b"}}) end,
			function() c.listTransfers({profile = 0}) end,
			function() c.listTransfers({status = "processing"}) end,
			function() c.listRecipients({currency = "EUR"}) end,
			function() c.listTransfers({profile = 202, status = {"a", nil, "c"}}) end,
			function() c.listRecipients({profileId = 0}) end,
			function() c.listBalances({profileId = 202, types = "STANDARD,"}) end,
			function() c.listBalances({profileId = 202, types = "STANDARD,CHECKING"}) end,
			function() c.getMe({idempotenceUuid = quote}) end,
			function() c.listTransfers({profile = 202, status = "a\nb"}) end,
			function() c.downloadTransferReceipt({transferId = 1}) end,
		} do assert(not pcall(call), "invalid request accepted") end
		assert(#requests == before, "invalid input reached the network")
	end,
}
