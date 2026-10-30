-- With an API key, which the proxy adds as a bearer token, every chain goes through the multichain Blockscout API.
return {
	scenario = {publisher = {}, config = {chain = "base.blockscout.com", use_api_key = true, api_key = "proapi_synthetic"}, auth_method = "",
		auth_config = {}},
	configure = function()
		requests = {}
		status, payload, responseHeaders = 200, '{"items":[],"next_page_params":null}', {}
		http = {request = function(req)
			table.insert(requests, req)
			assert(req.headers.Authorization == nil and not string.find(req.url, "apikey", 1, true), "the proxy adds the key")
			return fixture.operation({statusCode = status, headers = responseHeaders, body = fixture.reader(payload)})
		end}
	end,
	run = function(blockscout)
		local API = "https://api.blockscout.com/8453/api/v2"
		local USDC = "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913"
		local function got(url) assert(requests[#requests].url == url, requests[#requests].url) end
		assert(type(blockscout.getAddress) == "function" and type(blockscout.search) == "function")

		blockscout.listTokenHolders(USDC)
		got(API .. "/tokens/" .. USDC .. "/holders")
		blockscout.listAddressTransactions(USDC, {page = {block_number = 37000000, index = 4}})
		got(API .. "/addresses/" .. USDC .. "/transactions?block_number=37000000&index=4")
		payload = '{"total_blocks":"37000000"}'
		assert(blockscout.getStats().total_blocks == "37000000")
		got(API .. "/stats")

		-- The Blockscout API reports its own errors as {error, source}.
		local function upstream(code, body, expected, absent)
			status, payload = code, body
			local ok, err = pcall(function() blockscout.getToken(USDC) end)
			for _, text in expected do
				assert(not ok and string.find(tostring(err), text, 1, true), "missing " .. text .. " in " .. tostring(err))
			end
			if absent then assert(not string.find(tostring(err), absent, 1, true), "unexpected " .. absent .. " in " .. tostring(err)) end
		end
		upstream(401, '{"error":"Unauthorized"}',
			{"Blockscout HTTP 401: Unauthorized; the connection's Blockscout API key was refused or has no credits left", '"retryable":false'})
		upstream(402, '{"error":"Proceed with API key or make a X402 payment to continue"}',
			{"Blockscout HTTP 402: Proceed with API key", "API key was refused or has no credits left", '"retryable":false'})
		-- With a key, a challenge page is not answered with advice to add one.
		responseHeaders = {["cf-mitigated"] = {"challenge"}}
		upstream(403, "<html>Just a moment...</html>", {"Blockscout HTTP 403", '"retryable":false'}, "bot protection")
		upstream(404, '{"error":"Network not supported","source":"internal"}', {"Blockscout HTTP 404: Network not supported"})
		upstream(504, '{"error":"Gateway timeout","source":"upstream"}', {"Blockscout HTTP 504: Gateway timeout", '"retryable":true'})
		upstream(501, '{"error":"Not implemented","source":"upstream"}', {"Blockscout HTTP 501: Not implemented", '"retryable":false'})
	end,
}
