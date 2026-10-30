-- Invalid input never reaches Blockscout, and its errors, slow answers and bad bodies map to clear failures.
return {
	scenario = {publisher = {}, config = {chain = "arbitrum.blockscout.com"}, auth_method = "", auth_config = {}},
	configure = function()
		calls = 0
		status, payload, responseHeaders = 200, "{}", {}
		http = {request = function(req)
			calls += 1
			assert(string.sub(req.url, 1, 39) == "https://arbitrum.blockscout.com/api/v2/", req.url)
			-- A table stands for a failure while waiting for headers, such as a timeout or a refused origin.
			if requestError then error(requestError, 0) end
			-- A body whose read fails stands in for a dropped connection or a cancelled invocation.
			local body = if readError
				then {readAll = function() error(readError, 0) end, readPrefix = function() error(readError, 0) end, close = function() end}
				else fixture.reader(payload)
			return fixture.operation({statusCode = status, headers = responseHeaders, body = body})
		end}
	end,
	run = function(blockscout)
		local ADDRESS = "0x" .. string.rep("a", 40)
		local TX = "0x" .. string.rep("b", 64)
		local function rejected(fn, expected)
			local before = calls
			local ok, err = pcall(fn)
			assert(not ok and string.find(tostring(err), expected, 1, true), "wrong validation error: " .. tostring(err))
			assert(calls == before, "invalid input reached Blockscout")
		end

		for _, value in {"", "0x", "0x" .. string.rep("a", 39), "0x" .. string.rep("a", 41), "0x" .. string.rep("g", 40),
			string.rep("a", 42), "0x" .. string.rep("a", 38) .. "/.", 42, {ADDRESS}} do
			rejected(function() blockscout.getAddress(value) end, "address must be an address, 0x and 40 hex digits")
		end
		for _, value in {ADDRESS, "0x" .. string.rep("b", 63) .. "/", string.rep("b", 66)} do
			rejected(function() blockscout.getTransaction(value) end, "hash must be a transaction hash, 0x and 64 hex digits")
		end
		for _, value in {-1, 1.5, "1.5", "-1", "latest", "0x10", string.rep("1", 17), 2 ^ 53} do
			rejected(function() blockscout.getBlock(value) end, "block must be a block number or a block hash")
		end
		for _, value in {-1, 0.5, "1e3", "-7", "0x1", string.rep("9", 79)} do
			rejected(function() blockscout.getTokenInstance(ADDRESS, value) end, "token_id must be a nonnegative integer")
		end
		for _, value in {"", "   ", string.rep("q", 257), 5} do
			rejected(function() blockscout.search(value) end, "q must be a nonempty string of at most 256 bytes")
		end
		rejected(function() blockscout.getAddress() end, "address must be an address")
		rejected(function() blockscout.search() end, "q must be a nonempty string")
		rejected(function() blockscout.getStats(1) end, "getStats takes at most 0 arguments")
		rejected(function() blockscout.getAddress(ADDRESS, {}) end, "getAddress takes at most 1 arguments")
		rejected(function() blockscout.listTokens({}, "x") end, "listTokens takes at most 1 arguments")
		rejected(function() blockscout.listBlocks("reorg") end, "listBlocks options must be a table")
		rejected(function() blockscout.listAddressTransactions(ADDRESS, {limit = 10}) end,
			"listAddressTransactions received an unknown option limit")
		-- Search takes q only as its argument.
		rejected(function() blockscout.search("usdc", {q = "dai"}) end, "search received an unknown option q")
		rejected(function() blockscout.listAddressTransactions(ADDRESS, {filter = "both"}) end, "filter must be one of to, from")
		rejected(function() blockscout.listAddressTransactions(ADDRESS, {sort = "timestamp"}) end,
			"sort must be one of block_number, value, fee")
		rejected(function() blockscout.listTransactions({filter = "to"}) end, "filter must be one of validated, pending")
		rejected(function() blockscout.listSmartContracts({filter = "Solidity"}) end,
			"filter must be one of solidity, vyper, yul, geas, stylus_rust")
		rejected(function() blockscout.listSmartContracts({sort = "balance"}) end, "listSmartContracts received an unknown option sort")
		for _, value in {"ERC20", {}, {"ERC-20", "BEP-20"}, {[1] = "ERC-20", [3] = "ERC-721"}, {kind = "ERC-20"}, 20} do
			rejected(function() blockscout.listAddressTokens(ADDRESS, {type = value}) end, "type must be a token type or an array of them")
		end
		rejected(function() blockscout.listAddressTokenTransfers(ADDRESS, {token = "USDT"}) end, "token must be an address")
		rejected(function() blockscout.listAddressLogs(ADDRESS, {topic = "0x12"}) end, "topic must be a 32-byte topic")
		rejected(function() blockscout.listTokens({q = ""}) end, "q must be a nonempty string")
		-- A cursor holds scalars under Blockscout's own names; the credential's names never pass.
		for _, page in {"next", 5, {index = {1}}, {[1] = 5}, {["Index"] = 1}, {["a&b"] = 1}, {["token[a][b]"] = 1},
			{apikey = "x"}, {key = "x"}, {index = 2 ^ 53}, {hash = string.rep("h", 513)}} do
			rejected(function() blockscout.listTransactions({page = page}) end, "page")
		end
		local many = {}
		for i = 1, 33 do many["k" .. i] = i end
		rejected(function() blockscout.listTransactions({page = many}) end, "page must be the next_page_params table")
		rejected(function() blockscout.listAddressTransactions(ADDRESS, {filter = "to", page = {filter = "from"}}) end,
			"page.filter differs from the option filter")
		-- A cursor value under an option's name is checked as that option.
		rejected(function() blockscout.listAddressTransactions(ADDRESS, {page = {filter = "both"}}) end, "filter must be one of to, from")
		rejected(function() blockscout.search("usdc", {page = {q = "dai"}}) end, "page.q differs from the option q")
		rejected(function() blockscout.getTransaction(TX, {page = {index = 1}}) end, "getTransaction takes at most 1 arguments")

		local function upstream(code, body, headers, expected, absent)
			status, payload, responseHeaders = code, body, headers
			local before = calls
			local ok, err = pcall(function() blockscout.getTransaction(TX) end)
			for _, text in expected do
				assert(not ok and string.find(tostring(err), text, 1, true), "missing " .. text .. " in " .. tostring(err))
			end
			if absent then assert(not string.find(tostring(err), absent, 1, true), "unexpected " .. absent .. " in " .. tostring(err)) end
			assert(calls == before + 1, "a failed request was repeated")
		end
		upstream(404, '{"message":"Not found"}', {}, {"Blockscout HTTP 404: Not found", '"retryable":false', '"upstream_status":404'})
		upstream(422, '{"errors":[{"title":"Invalid value","source":{"pointer":"/type"},"detail":"Invalid value for enum"}]}', {},
			{"Blockscout HTTP 422: type: Invalid value for enum", '"retryable":false'})
		upstream(400, '{"message":"Unknown API v2 action"}', {}, {"Blockscout HTTP 400: Unknown API v2 action"})
		upstream(400, '{"message":"' .. string.rep("y", 1000) .. '"}', {}, {"Blockscout HTTP 400: " .. string.rep("y", 300)},
			string.rep("y", 301))
		upstream(403, '<!DOCTYPE html><html lang="en-US"><head><title>Just a moment...</title></head></html>', {},
			{"The Arbitrum One explorer's bot protection refused the request; a connection admin can add a free Blockscout API key",
				'"retryable":false', '"upstream_status":403'}, "DOCTYPE")
		upstream(403, "<html><body>challenge</body></html>", {["cf-mitigated"] = {"challenge"}},
			{"The Arbitrum One explorer's bot protection refused the request", '"retryable":false'}, "challenge<")
		upstream(403, "<html>Forbidden</html>", {}, {"Blockscout HTTP 403", '"retryable":false'}, "Forbidden")
		upstream(429, '{"message":"Too Many Requests"}', {["x-ratelimit-reset"] = {"43712"}},
			{"Blockscout HTTP 429: Too Many Requests; retry after 44s", '"retryable":true'})
		upstream(429, "", {["retry-after"] = {"Thu, 29 Oct 2026 20:00:00 GMT"}, ["x-ratelimit-reset"] = {"9"}},
			{"Blockscout HTTP 429; retry after Thu, 29 Oct 2026 20:00:00 GMT", '"retryable":true'}, "GMTs")
		upstream(429, "", {["x-ratelimit-reset"] = {"-1"}}, {"Blockscout HTTP 429", '"retryable":true'}, "retry after")
		upstream(503, '{"error":"Transaction data is temporarily unavailable"}', {["retry-after"] = {"3"}},
			{"Blockscout HTTP 503: Transaction data is temporarily unavailable; retry after 3s", '"retryable":true'})
		upstream(500, "<html>Internal</html>", {}, {"Blockscout HTTP 500", '"retryable":true'}, "Internal")
		upstream(301, "", {location = {"https://elsewhere.example.com/api/v2/stats"}},
			{"Blockscout HTTP 301: unexpected redirect", '"retryable":false'}, "elsewhere")
		upstream(200, "<html>maintenance</html>", {}, {"Blockscout returned an invalid JSON object", '"retryable":false'}, "maintenance")
		upstream(200, "[]", {}, {"Blockscout returned an invalid JSON object"})
		upstream(200, '{"x":"' .. string.rep("z", 4 * 1024 * 1024) .. '"}', {},
			{"Blockscout returned more data than one call can hold", '"retryable":false'}, "limit_exceeded")

		requestError = {code = "timeout", message = "request deadline"}
		upstream(200, "", {}, {"Blockscout did not answer within 20 s; retry, or narrow the request", '"retryable":true'})
		-- Other request failures pass through unchanged: the stand-in table loses its message across the export boundary, so
		-- only the absence of an upstream failure (no retryable flag) is checked.
		requestError = {code = "access_denied", message = "origin not allowed"}
		upstream(200, "", {}, {"error"}, "retryable")
		requestError = nil
		readError = {code = "timeout", message = "await timed out"}
		upstream(200, "", {}, {"Blockscout did not finish sending its answer within 7 s; retry", '"retryable":true'})
		readError = {code = "io_error", message = "connection reset by peer"}
		upstream(200, "", {}, {"Blockscout response failed: connection reset by peer", '"retryable":true'})
		-- An error body that stalls or breaks still gives the structured failure.
		upstream(502, "", {}, {"Blockscout HTTP 502", '"retryable":true', '"upstream_status":502'}, "reset")
		readError = {code = "cancelled", message = "invocation cancelled"}
		local before = calls
		local ok, err = pcall(function() blockscout.getStats() end)
		-- A stand-in error loses its native identity across the export boundary; it must still not become an upstream failure.
		assert(not ok and not string.find(tostring(err), "retryable", 1, true), "cancellation became an upstream error: " .. tostring(err))
		assert(calls == before + 1)
		readError = nil
	end,
}
