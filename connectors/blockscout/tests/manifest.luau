return {
	contract = function(m)
		local blockscoutManifest = "../../connectors/blockscout/houston.json"
		local resolveBlockscout = function(config)
			local r, err = m.resolve(nil, config, nil, "")
			assert(not err, tostring(err))
			return r
		end
		local blockscoutSource = function()
			local source, err = m.modules["connector.luau"], nil
			assert(not err, tostring(err))
			return source
		end
		-- TestBlockscoutPublicExplorerRoutes
		do
			local address = "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045"
			local hash = "0x1ccc11eecc6d44bd0b03d278560a5257d4dc93ac8414a6d1982d96bd88a0ffbc"
			local r = resolveBlockscout(nil)
			local api = "https://eth.blockscout.com/api/v2"
			m.routes(r, "", true, {
				"GET " .. api .. "/addresses/" .. address,
				"GET " .. api .. "/addresses/" .. address .. "/transactions?filter=to&sort=value&order=desc",
				"GET " .. api .. "/addresses/" .. address .. "/tokens?type=ERC-20",
				"GET " .. api .. "/transactions/" .. hash .. "/logs",
				"GET " .. api .. "/blocks/26303681/transactions",
				"GET " .. api .. "/tokens?q=usd",
				"GET "
					.. api
					.. "/tokens/"
					.. address
					.. "/instances/115792089237316195423570985008687907853269984665640564039457584007913129639935",
				"GET " .. api .. "/smart-contracts/" .. address,
				"GET " .. api .. "/search?q=token%5Bname%5D",
				"GET " .. api .. "/stats",
			})
			m.routes(r, "", false, {
				"POST " .. api .. "/tokens/batch",
				"PATCH " .. api .. "/tokens/" .. address .. "/instances/1/refetch-metadata",
				"POST " .. api .. "/smart-contracts/" .. address .. "/verification/via/flattened-code",
				"GET " .. api .. "/addresses/" .. address .. "/token-balances",
				"GET " .. api .. "/addresses/" .. address .. "/transactions/csv",
				"GET " .. api .. "/tokens/" .. address .. "/holders/csv",
				"GET " .. api .. "/config/backend-version",
				"GET " .. api .. "/addresses/%2e%2e/stats",
				"GET https://eth.blockscout.com/api/account/v2/user/info",
				"GET https://eth.blockscout.com/api?module=account&action=balance",
				"GET https://eth.blockscout.com/api/eth-rpc",
				"GET https://eth.blockscout.com/graphiql",
				"GET https://base.blockscout.com/api/v2/stats",
				"GET https://gnosisscan.io/api/v2/stats",
				"GET https://api.blockscout.com/1/api/v2/stats",
				"GET https://gnosis.blockscout.com/api/v2/stats",
				"GET https://eth.blockscout.com.example.com/api/v2/stats",
				"GET http://eth.blockscout.com:8080/api/v2/stats",
				"GET https://blockscout.com/api/v2/stats",
				"GET https://evil.blockscout.com/api/v2/stats",
			})
			r = resolveBlockscout({ chain = "gnosisscan.io" })
			m.routes(r, "", true, { "GET https://gnosisscan.io/api/v2/stats" })
			m.routes(r, "", false, { "GET https://eth.blockscout.com/api/v2/stats" })
			do
				local _, err = m.resolve(nil, { chain = "evil.example.com" }, nil, "")
				if err == nil then
					m.fail("a host outside the chain list resolved")
				end
			end
		end
		-- TestBlockscoutAPIKeyRoutes
		do
			local address = "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913"
			local r = resolveBlockscout({
				chain = "base.blockscout.com",
				use_api_key = true,
				api_key = "proapi_synthetic",
			})
			local api = "https://api.blockscout.com/8453/api/v2"
			m.routes(r, "Bearer proapi_synthetic", true, {
				"GET " .. api .. "/tokens/" .. address .. "/holders",
				"GET " .. api .. "/addresses/" .. address .. "/transactions?block_number=1&index=4",
				"GET "
					.. api
					.. "/transactions/0x1ccc11eecc6d44bd0b03d278560a5257d4dc93ac8414a6d1982d96bd88a0ffbc/summary",
			})
			m.routes(r, "", false, {
				"POST " .. api .. "/tokens/batch",
				"GET " .. api .. "/addresses/" .. address .. "/token-balances",
				"GET https://api.blockscout.com/v2/api?chain_id=8453&module=account&action=balance",
				"GET https://api.blockscout.com/8453/api?module=account&action=balance",
				"GET https://api.blockscout.com/8453/json-rpc",
				"GET https://api.blockscout.com/8453/stats-service/api/v1/counters",
				"GET https://api.blockscout.com/services/metadata/api/v1/metadata",
				"GET https://api.blockscout.com/api/v2/stats",
				"GET https://base.blockscout.com/api/v2/stats",
				"GET https://eth.blockscout.com/api/v2/stats",
				"GET https://api.blockscout.com.example.com/8453/api/v2/stats",
			})
			local recipe, err = m.recipe(r, "GET", api .. "/stats", nil)
			assert(not err, tostring(err))
			do
				local prepared, err = m.prepareUrl(recipe, r.Context)
				if (err ~= nil) or (prepared ~= api .. "/stats") then
					m.fail("the key reached the URL: %s %s", prepared, err)
				end
			end
			m.rejectPreparedOverrides(recipe, r.Context, "GET " .. api .. "/stats")
			local dropped = { "Cookie" }
			local caller = { Accept = { "application/json" }, Authorization = { "Bearer forged" } }
			for _, name in dropped do
				caller[name] = { "caller-value" }
			end
			local headers, err = m.prepare(recipe, r.Context, caller)
			if
				((err ~= nil) or (m.header(headers, "Accept") ~= "application/json"))
				or (m.header(headers, "Authorization") ~= "Bearer proapi_synthetic")
			then
				m.fail("prepare: %s %s", headers, err)
			end
			for _, name in dropped do
				if m.header(headers, name) ~= "" then
					m.fail("%s reached Blockscout", name)
				end
			end
		end
		-- TestBlockscoutAPIKeyNeedsAValue
		do
			for _, config in { { use_api_key = true }, { use_api_key = true, api_key = "" } } do
				do
					local _, err = m.resolve(nil, config, nil, "")
					if err == nil then
						m.fail("%s resolved", config)
					end
				end
			end
		end
	end,
}
