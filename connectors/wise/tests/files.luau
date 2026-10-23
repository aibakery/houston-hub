return {
	scenario = {config = {access = "read-only", api_host = "api.wise-sandbox.com"}, auth_method = "token", auth_config = {token = "fixture-sandbox-token"}},
	configure = function()
		requests = {}
		fs = fixture.files()
		status = 200
		responseHeaders = {}
		stream = nil
		http = {request = function(req)
			table.insert(requests, req)
			return fixture.operation({statusCode = status, headers = responseHeaders, body = stream or fixture.reader('[{"id":101,"type":"BUSINESS"}]')})
		end}
	end,
	run = function(c)
		assert(c.listProfiles()[1].id == 101)
		assert(requests[1].url == "https://api.wise-sandbox.com/v2/profiles", "sandbox origin not used")

		local size = 8 * 1024 * 1024 + 17
		stream = fixture.reader(string.rep("d", size))
		local saved = c.downloadTransferReceipt({transferId = 9001, path = "receipts/9001.pdf"})
		assert(saved.path == "receipts/9001.pdf" and saved.size == size and type(saved.url) == "string")
		local req = requests[#requests]
		assert(req.method == "GET" and req.url == "https://api.wise-sandbox.com/v1/transfers/9001/receipt.pdf" and req.headers.Authorization == nil)

		stream = fixture.reader("Date,Amount\n2026-01-02,10.00\n")
		saved = c.downloadBalanceStatement({profileId = 202, balanceId = 1, format = "csv", currency = "EUR", intervalStart = "2026-01-01T00:00:00Z", intervalEnd = "2026-01-31T23:59:59Z", path = "statement.csv"})
		assert(saved.size == 29, tostring(saved.size))
		assert(requests[#requests].url == "https://api.wise-sandbox.com/v1/profiles/202/balance-statements/1/statement.csv?currency=EUR&intervalEnd=2026-01-31T23%3A59%3A59Z&intervalStart=2026-01-01T00%3A00%3A00Z")
		local file = fs.open("statement.csv", "r")
		assert(await(file:read(64)).data == "Date,Amount\n2026-01-02,10.00\n")
		await(file:close())

		local existing = fs.open("denied.pdf", "w")
		existing:write("keep")
		await(existing:close())
		stream = nil
		status = 403
		local ok, err = pcall(c.downloadTransferReceipt, {transferId = 9001, path = "denied.pdf"})
		assert(not ok and string.find(tostring(err), "HTTP 403", 1, true), tostring(err))
		assert(await(fs.stat("denied.pdf")).size == 4, "failed download truncated an existing file")
		status = 200
		responseHeaders = {["content-type"] = {"application/json;charset=UTF-8"}}
		ok, err = pcall(c.downloadTransferReceipt, {transferId = 9001, path = "denied.pdf"})
		assert(not ok and string.find(tostring(err), "instead of a file", 1, true) and string.find(tostring(err), "BUSINESS", 1, true), tostring(err))
		assert(await(fs.stat("denied.pdf")).size == 4, "error page replaced an existing file")
		responseHeaders = {}

		local before = #requests
		for _, call in {
			function() c.downloadBalanceStatement({profileId = 202, balanceId = 1, format = "json", currency = "EUR", intervalStart = "a", intervalEnd = "b", path = "x"}) end,
			function() c.downloadBalanceStatement({profileId = 202, balanceId = 1, format = "../x", currency = "EUR", intervalStart = "a", intervalEnd = "b", path = "x"}) end,
			function() c.downloadBalanceStatement({profileId = 202, balanceId = 1, format = "pdf", currency = "EUR", intervalStart = "a", intervalEnd = "b"}) end,
			function() c.downloadTransferReceipt({transferId = 9001, path = ""}) end,
		} do assert(not pcall(call), "invalid download accepted") end
		assert(#requests == before, "invalid download reached Wise")
	end,
}
