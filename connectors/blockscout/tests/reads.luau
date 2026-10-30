-- Without a key, each export reads one exact URL from the Ethereum explorer and returns Blockscout's JSON unchanged.
return {
	scenario = {publisher = {}, config = {}, auth_method = "", auth_config = {}},
	configure = function()
		requests, responses = {}, {}
		http = {request = function(req)
			table.insert(requests, req)
			assert(req.method == "GET" and req.body == nil, "every request is a GET without a body")
			assert(req.headers.Accept[1] == "application/json" and req.headers.Authorization == nil, "the public explorer takes no credential")
			assert(req.timeoutMs == 20000, "headers get the call's time less the body's share")
			assert(#responses > 0, "unexpected request: " .. req.url)
			return fixture.operation({statusCode = 200, headers = {}, body = fixture.reader(table.remove(responses, 1))})
		end}
		function respond(body) table.insert(responses, body) end
	end,
	run = function(blockscout)
		local API = "https://eth.blockscout.com/api/v2"
		local VITALIK = "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045"
		local USDT = "0xdAC17F958D2ee523a2206206994597C13D831ec7"
		local TX = "0x" .. string.rep("ab", 32)
		local NULL = json.decode("null")
		local function got(path)
			local req = requests[#requests]
			assert(req.url == API .. path, req.url)
		end
		local EMPTY = '{"items":[],"next_page_params":null}'

		local names = {}
		for name, fn in blockscout do
			assert(type(fn) == "function")
			table.insert(names, name)
		end
		table.sort(names)
		assert(table.concat(names, ",") == "getAddress,getAddressCounters,getBlock,getSmartContract,getStats,getToken,getTokenCounters,"
			.. "getTokenInstance,getTransaction,getTransactionSummary,listAddressCoinBalanceHistory,listAddressInternalTransactions,"
			.. "listAddressLogs,listAddressNFTs,listAddressTokenTransfers,listAddressTokens,listAddressTransactions,listBlockTransactions,"
			.. "listBlocks,listSmartContracts,listTokenHolders,listTokenInstances,listTokenTransfers,listTokens,listTransactionInternalTransactions,"
			.. "listTransactionLogs,listTransactionTokenTransfers,listTransactions,search", table.concat(names, ","))
		assert(#requests == 0, "initialization reached Blockscout")

		-- Single records come back unchanged, nulls included.
		respond('{"hash":"0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045","coin_balance":"32644057673209982495","ens_domain_name":"vitalik.eth",'
			.. '"is_contract":false,"token":null,"public_tags":[]}')
		local account = blockscout.getAddress(VITALIK)
		got("/addresses/" .. VITALIK)
		assert(account.coin_balance == "32644057673209982495" and account.ens_domain_name == "vitalik.eth" and account.token == NULL)
		assert(json.encode(account.public_tags) == "[]")
		respond('{"transactions_count":"6311","token_transfers_count":"141803","gas_usage_count":"0","validations_count":"0"}')
		assert(blockscout.getAddressCounters(string.lower(VITALIK)).transactions_count == "6311")
		got("/addresses/" .. string.lower(VITALIK) .. "/counters")

		-- A first page: options in name order, and the cursor returned as is.
		respond('{"items":[{"hash":"' .. TX .. '","method":"transfer","value":"0","status":"ok"}],'
			.. '"next_page_params":{"block_number":26134774,"index":237,"value":"371078167616008","hash":"' .. TX .. '",'
			.. '"inserted_at":"2026-10-06T17:18:09.835753Z","fee":"17124093105626","items_count":50}}')
		local opts = {filter = "from", sort = "value", order = "desc"}
		local page = blockscout.listAddressTransactions(VITALIK, opts)
		got("/addresses/" .. VITALIK .. "/transactions?filter=from&order=desc&sort=value")
		assert(#page.items == 1 and page.items[1].method == "transfer" and page.next_page_params.index == 237)
		-- The next page repeats the options and adds every cursor field, in name order.
		respond(EMPTY)
		opts.page = page.next_page_params
		local last = blockscout.listAddressTransactions(VITALIK, opts)
		got("/addresses/" .. VITALIK .. "/transactions?block_number=26134774&fee=17124093105626&filter=from&hash=" .. TX
			.. "&index=237&inserted_at=2026-10-06T17%3A18%3A09.835753Z&items_count=50&order=desc&sort=value&value=371078167616008")
		assert(json.encode(last.items) == "[]" and last.next_page_params == nil, "the last page has no cursor")
		assert(opts.filter == "from" and opts.page.index == 237, "caller options were modified")
		-- Cursor values may be null, booleans or bracketed keys, as search uses.
		respond(EMPTY)
		blockscout.search("usdc", {page = {next_page_params_type = "search", q = "usdc", ["token[fiat_value]"] = NULL,
			["token[is_verified_via_admin_panel]"] = false, ["token[name]"] = "ICHI Vault Liquidity", ["token[holder_count]"] = "2"}})
		got("/search?next_page_params_type=search&q=usdc&token%5Bfiat_value%5D=null&token%5Bholder_count%5D=2"
			.. "&token%5Bis_verified_via_admin_panel%5D=false&token%5Bname%5D=ICHI%20Vault%20Liquidity")
		respond('{"items":[{"type":"token","name":"USD Coin","address_hash":"0xA0b8"}],"next_page_params":null}')
		assert(blockscout.search("USD Coin").items[1].name == "USD Coin")
		got("/search?q=USD%20Coin")

		-- Every other address list, with and without options.
		respond(EMPTY)
		blockscout.listAddressTokenTransfers(VITALIK, {filter = "to", type = {"ERC-20", "ERC-721"}, token = USDT})
		got("/addresses/" .. VITALIK .. "/token-transfers?filter=to&token=" .. USDT .. "&type=ERC-20%2CERC-721")
		respond(EMPTY)
		blockscout.listAddressTokenTransfers(VITALIK)
		got("/addresses/" .. VITALIK .. "/token-transfers")
		respond(EMPTY)
		blockscout.listAddressInternalTransactions(VITALIK, {filter = "from"})
		got("/addresses/" .. VITALIK .. "/internal-transactions?filter=from")
		respond(EMPTY)
		blockscout.listAddressLogs(USDT, {topic = "0x" .. string.rep("dd", 32)})
		got("/addresses/" .. USDT .. "/logs?topic=0x" .. string.rep("dd", 32))
		respond('{"items":[{"token":{"symbol":"USDT","decimals":"6"},"value":"1500000","token_id":null}],"next_page_params":null}')
		local balances = blockscout.listAddressTokens(VITALIK, {type = "ERC-20"})
		got("/addresses/" .. VITALIK .. "/tokens?type=ERC-20")
		assert(balances.items[1].value == "1500000" and balances.items[1].token.symbol == "USDT")
		respond(EMPTY)
		blockscout.listAddressCoinBalanceHistory(VITALIK, {page = {block_number = 26111475, items_count = 50}})
		got("/addresses/" .. VITALIK .. "/coin-balance-history?block_number=26111475&items_count=50")
		respond(EMPTY)
		blockscout.listAddressNFTs(VITALIK, {type = "ERC-1155"})
		got("/addresses/" .. VITALIK .. "/nft?type=ERC-1155")

		-- Transactions.
		respond(EMPTY)
		blockscout.listTransactions({filter = "pending"})
		got("/transactions?filter=pending")
		respond(EMPTY)
		blockscout.listTransactions()
		got("/transactions")
		respond('{"hash":"' .. TX .. '","status":"error","revert_reason":null,"value":"1000000000000000000","token_transfers":[]}')
		local tx = blockscout.getTransaction(TX)
		got("/transactions/" .. TX)
		assert(tx.status == "error" and tx.value == "1000000000000000000" and json.encode(tx.token_transfers) == "[]")
		respond('{"items":[{"index":3,"topics":["0x' .. string.rep("dd", 32) .. '",null],"data":"0x"}],"next_page_params":null}')
		local logs = blockscout.listTransactionLogs("0x" .. string.rep("AB", 32))
		got("/transactions/0x" .. string.rep("AB", 32) .. "/logs")
		assert(logs.items[1].topics[2] == NULL)
		respond(EMPTY)
		blockscout.listTransactionTokenTransfers(TX, {type = "ERC-721"})
		got("/transactions/" .. TX .. "/token-transfers?type=ERC-721")
		respond(EMPTY)
		blockscout.listTransactionInternalTransactions(TX, {page = {index = 2, block_number = 1, transaction_index = 107}})
		got("/transactions/" .. TX .. "/internal-transactions?block_number=1&index=2&transaction_index=107")
		respond('{"data":{"summaries":[]},"success":true}')
		assert(json.encode(blockscout.getTransactionSummary(TX).data.summaries) == "[]")
		got("/transactions/" .. TX .. "/summary")

		-- Blocks by number, as a number or a string, or by hash.
		respond(EMPTY)
		blockscout.listBlocks({type = "reorg"})
		got("/blocks?type=reorg")
		respond('{"height":26303681,"hash":"' .. TX .. '","transactions_count":160}')
		assert(blockscout.getBlock(26303681).height == 26303681)
		got("/blocks/26303681")
		respond('{"height":0}')
		blockscout.getBlock("0")
		got("/blocks/0")
		respond('{"height":1}')
		blockscout.getBlock(TX)
		got("/blocks/" .. TX)
		respond(EMPTY)
		blockscout.listBlockTransactions(26303681, {type = "contract_call"})
		got("/blocks/26303681/transactions?type=contract_call")

		-- Tokens and NFTs; token IDs beyond 2^53 stay decimal strings.
		respond(EMPTY)
		blockscout.listTokens({q = "usd", type = "ERC-20", sort = "holders_count", order = "asc"})
		got("/tokens?order=asc&q=usd&sort=holders_count&type=ERC-20")
		respond('{"address_hash":"' .. USDT .. '","symbol":"USDT","decimals":"6","exchange_rate":"0.998"}')
		assert(blockscout.getToken(USDT).decimals == "6")
		got("/tokens/" .. USDT)
		respond('{"token_holders_count":"12000000","transfers_count":"300000000"}')
		blockscout.getTokenCounters(USDT)
		got("/tokens/" .. USDT .. "/counters")
		respond('{"items":[{"address":{"hash":"0x5754284f345afc66a98fbb0a0afe71e0f007b949"},"value":"165680228936471","token_id":null}],'
			.. '"next_page_params":{"value":"165680228936471","address_hash":"0x5754284f345afc66a98fbb0a0afe71e0f007b949","items_count":50}}')
		local holders = blockscout.listTokenHolders(USDT)
		got("/tokens/" .. USDT .. "/holders")
		respond(EMPTY)
		blockscout.listTokenHolders(USDT, {page = holders.next_page_params})
		got("/tokens/" .. USDT .. "/holders?address_hash=0x5754284f345afc66a98fbb0a0afe71e0f007b949&items_count=50&value=165680228936471")
		respond(EMPTY)
		blockscout.listTokenTransfers(USDT)
		got("/tokens/" .. USDT .. "/transfers")
		respond(EMPTY)
		blockscout.listTokenInstances(USDT, {holder_address_hash = VITALIK})
		got("/tokens/" .. USDT .. "/instances?holder_address_hash=" .. VITALIK)
		-- A collection cursor's unique_token is a bare integer beyond 2^53; it comes back as a decimal string.
		local UNIQUE = "115790456664004915351485478058966557979628998555645103315289660377220126223400"
		respond('{"items":[{"id":"1"}],"next_page_params":{"unique_token":' .. UNIQUE .. '}}')
		local instances = blockscout.listTokenInstances(USDT)
		assert(instances.next_page_params.unique_token == UNIQUE, tostring(instances.next_page_params.unique_token))
		respond(EMPTY)
		blockscout.listTokenInstances(USDT, {page = instances.next_page_params})
		got("/tokens/" .. USDT .. "/instances?unique_token=" .. UNIQUE)
		local BIG = "115792089237316195423570985008687907853269984665640564039457584007913129639935"
		respond('{"id":"' .. BIG .. '","metadata":{"name":"x"}}')
		assert(blockscout.getTokenInstance(USDT, BIG).id == BIG)
		got("/tokens/" .. USDT .. "/instances/" .. BIG)
		respond('{"id":"7"}')
		blockscout.getTokenInstance(USDT, 7)
		got("/tokens/" .. USDT .. "/instances/7")

		-- Verified contracts and chain statistics.
		respond(EMPTY)
		blockscout.listSmartContracts({q = "Uniswap", filter = "vyper"})
		got("/smart-contracts?filter=vyper&q=Uniswap")
		respond('{"name":"Uni","language":"solidity","abi":[{"type":"function","name":"transfer"}],"additional_sources":[]}')
		local contract = blockscout.getSmartContract(USDT)
		got("/smart-contracts/" .. USDT)
		assert(contract.abi[1].name == "transfer" and json.encode(contract.additional_sources) == "[]")
		respond('{"total_blocks":"26303431","gas_prices":{"slow":0.72,"average":1.14,"fast":6.37}}')
		assert(blockscout.getStats().gas_prices.fast == 6.37)
		got("/stats")
		assert(#responses == 0, "a queued response was not read")
	end,
}
