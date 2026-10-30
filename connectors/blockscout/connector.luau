-- Blockscout REST API v2 (https://docs.blockscout.com/devs/apis/rest) on one hosted chain, public and read-only. Arguments and results keep Blockscout's native field names.
type Options = {[string]: any}
type Chain = {host: string, name: string, id: number}
type Endpoint = {name: string, path: string, args: {string}, options: {[string]: string}, list: boolean, about: string}

-- The manifest's chain options, in its order: each chain's public explorer host, which is the option value, its name and chain ID.
local CHAINS: {Chain} = {
	{host = "eth.blockscout.com", name = "Ethereum", id = 1},
	{host = "base.blockscout.com", name = "Base", id = 8453},
	{host = "explorer.optimism.io", name = "OP Mainnet", id = 10},
	{host = "arbitrum.blockscout.com", name = "Arbitrum One", id = 42161},
	{host = "arbitrum-nova.blockscout.com", name = "Arbitrum Nova", id = 42170},
	{host = "gnosisscan.io", name = "Gnosis", id = 100},
	{host = "polygon.blockscout.com", name = "Polygon PoS", id = 137},
	{host = "zksync.blockscout.com", name = "ZKsync Era", id = 324},
	{host = "scrollscan.com", name = "Scroll", id = 534352},
	{host = "celo.blockscout.com", name = "Celo", id = 42220},
	{host = "unichain.blockscout.com", name = "Unichain", id = 130},
	{host = "soneium.blockscout.com", name = "Soneium", id = 1868},
	{host = "explorer.inkonchain.com", name = "Ink", id = 57073},
	{host = "explorer.mode.network", name = "Mode", id = 34443},
	{host = "blockscout.lisk.com", name = "Lisk", id = 1135},
	{host = "worldchain-mainnet.explorer.alchemy.com", name = "World Chain", id = 480},
	{host = "etc.blockscout.com", name = "Ethereum Classic", id = 61},
	{host = "rootstock.blockscout.com", name = "Rootstock", id = 30},
	{host = "filecoin.blockscout.com", name = "Filecoin", id = 314},
	{host = "eth-sepolia.blockscout.com", name = "Ethereum Sepolia (testnet)", id = 11155111},
	{host = "base-sepolia.blockscout.com", name = "Base Sepolia (testnet)", id = 84532},
	{host = "testnet-explorer.optimism.io", name = "OP Sepolia (testnet)", id = 11155420},
	{host = "arbitrum-sepolia.blockscout.com", name = "Arbitrum Sepolia (testnet)", id = 421614},
	{host = "gnosis-chiado.blockscout.com", name = "Gnosis Chiado (testnet)", id = 10200},
}
local chain: Chain? = nil
for _, entry in CHAINS do
	if entry.host == config.chain then chain = entry end
end
-- With a key, every chain goes through the multichain Blockscout API; without one, through the chain's own explorer.
local KEYED = config.use_api_key == true
local API = if chain == nil then ""
	elseif KEYED then "https://api.blockscout.com/" .. string.format("%d", chain.id) .. "/api/v2"
	else "https://" .. chain.host .. "/api/v2"

-- Each call makes one request. Houston ends a call after 30 s and the sandbox has no clock, so a fixed split of 27 s
-- gives the headers 20 s and the body, an error body included, 7 s. A page of 50 transactions is about 0.5 MB.
local CALL_TIME, BODY_TIME = 27000, 7000
local MAX_BYTES = 4 * 1024 * 1024
local MAX_TEXT, MAX_PAGE_KEYS, MAX_PAGE_VALUE = 256, 32, 512
local NULL = json.decode("null")
local TOKEN_TYPES = table.freeze({"ERC-20", "ERC-721", "ERC-1155", "ERC-404", "ERC-7984"})
local LANGUAGES = "solidity vyper yul geas stylus_rust"

-- Option kinds: a space-separated list of accepted values, or one of the formats below.
local FORMATS = table.freeze({
	["@address"] = "an address, 0x and 40 hex digits",
	["@topic"] = "a 32-byte topic, 0x and 64 hex digits",
	["@text"] = "a nonempty string of at most " .. tostring(MAX_TEXT) .. " bytes",
	["@tokens"] = "a token type or an array of them: " .. table.concat(TOKEN_TYPES, ", "),
})

-- Every export, in help order. args are positional: path placeholders, then required query parameters.
local ENDPOINTS: {Endpoint} = ({
	{name = "getAddress", path = "/addresses/{address}", args = {"address"},
		about = "An address: hash, coin_balance (in wei, as a string), exchange_rate (coin price in USD), is_contract, is_verified, name, ens_domain_name, token (when it is a token contract), proxy_type and implementations, creator_address_hash, creation_transaction_hash, public_tags, has_tokens and has_token_transfers. An address the chain has never seen still answers, with a null coin_balance."},
	{name = "getAddressCounters", path = "/addresses/{address}/counters", args = {"address"},
		about = "Activity counts as strings: transactions_count, token_transfers_count, gas_usage_count and validations_count."},
	{name = "listAddressTransactions", path = "/addresses/{address}/transactions", args = {"address"}, list = true,
		options = {filter = "to from", sort = "block_number value fee", order = "asc desc"},
		about = "Transactions sent or received by the address, newest first, as in getTransaction. filter = \"to\" keeps incoming, \"from\" outgoing; sort and order change the order. Contract calls made inside other transactions are in listAddressInternalTransactions, token movements in listAddressTokenTransfers."},
	{name = "listAddressTokenTransfers", path = "/addresses/{address}/token-transfers", args = {"address"}, list = true,
		options = {filter = "to from", type = "@tokens", token = "@address"},
		about = "Token transfers to or from the address, newest first: from, to, token, total ({value, decimals} for ERC-20; token_id for NFTs), type (token_transfer, token_minting, token_burning...), method, transaction_hash, log_index, block_number and timestamp. token keeps one token contract."},
	{name = "listAddressInternalTransactions", path = "/addresses/{address}/internal-transactions", args = {"address"}, list = true,
		options = {filter = "to from"},
		about = "Internal transactions (calls and value transfers made by contracts) to or from the address: from, to, value, type (call, create, selfdestruct...), success, error, transaction_hash, index and block_number."},
	{name = "listAddressLogs", path = "/addresses/{address}/logs", args = {"address"}, list = true,
		options = {topic = "@topic"},
		about = "Event logs the contract at the address emitted, newest first, as in listTransactionLogs. topic keeps the logs with that topic, such as an event signature hash."},
	{name = "listAddressTokens", path = "/addresses/{address}/tokens", args = {"address"}, list = true,
		options = {type = "@tokens"},
		about = "Token balances of the address, highest fiat value first: each item has token (address_hash, name, symbol, decimals, type, exchange_rate, holders_count), value (in the token's smallest unit, as a string: divide by 10^decimals) and token_id for NFTs. Known scam tokens are left out."},
	{name = "listAddressCoinBalanceHistory", path = "/addresses/{address}/coin-balance-history", args = {"address"}, list = true,
		about = "Changes of the address's native coin balance, newest first: block_number, block_timestamp, value (the balance after the change, in wei), delta and transaction_hash."},
	{name = "listAddressNFTs", path = "/addresses/{address}/nft", args = {"address"}, list = true,
		options = {type = "@tokens"},
		about = "NFT instances the address holds: id (the token ID), token, token_type, value (count held, for ERC-1155), metadata, image_url, animation_url and owner."},
	{name = "listTransactions", path = "/transactions", args = {}, list = true,
		options = {filter = "validated pending"},
		about = "The chain's latest transactions, newest first, as in getTransaction; filter = \"pending\" lists the mempool where the explorer indexes it."},
	{name = "getTransaction", path = "/transactions/{hash}", args = {"hash"},
		about = "A transaction: hash, status (ok or error), result, revert_reason, block_number, timestamp, confirmations, from and to (address objects with hash, name, is_contract), value and fee ({type, value}) in wei, gas_used, gas_limit, gas_price, nonce, position, method (the called function's name), decoded_input ({method_call, method_id, parameters}) when the contract is verified, raw_input, token_transfers (at most 50, with token_transfers_overflow true when there are more) and transaction_types."},
	{name = "listTransactionLogs", path = "/transactions/{hash}/logs", args = {"hash"}, list = true,
		about = "The transaction's event logs: address, topics, data, index, block_number, transaction_hash and decoded ({method_call, method_id, parameters}) when the emitting contract is verified."},
	{name = "listTransactionTokenTransfers", path = "/transactions/{hash}/token-transfers", args = {"hash"}, list = true,
		options = {type = "@tokens"},
		about = "Every token transfer of the transaction, as in listAddressTokenTransfers."},
	{name = "listTransactionInternalTransactions", path = "/transactions/{hash}/internal-transactions", args = {"hash"}, list = true,
		about = "The transaction's internal transactions, as in listAddressInternalTransactions."},
	{name = "getTransactionSummary", path = "/transactions/{hash}/summary", args = {"hash"},
		about = "Blockscout's human-readable summary of what the transaction did: `{success, data = {summaries}}`, where each summary has a summary_template such as \"{action_type} {amount} {token} to {to_address}\" and the summary_template_variables to fill it with. summaries is empty when Blockscout has no interpretation. It can fail as retryable while the explorer is busy."},
	{name = "listBlocks", path = "/blocks", args = {}, list = true,
		options = {type = "block uncle reorg"},
		about = "The latest blocks, newest first, as in getBlock. type = \"uncle\" or \"reorg\" lists blocks outside the canonical chain."},
	{name = "getBlock", path = "/blocks/{block}", args = {"block"},
		about = "A block by number or hash: height, hash, parent_hash, timestamp, miner, transactions_count, internal_transactions_count, gas_used, gas_limit, base_fee_per_gas, burnt_fees, priority_fee, transaction_fees, rewards, size and withdrawals_count."},
	{name = "listBlockTransactions", path = "/blocks/{block}/transactions", args = {"block"}, list = true,
		options = {type = "coin_transfer contract_call contract_creation token_transfer token_creation"},
		about = "The block's transactions in block order, as in getTransaction; type keeps one kind."},
	{name = "listTokens", path = "/tokens", args = {}, list = true,
		options = {q = "@text", type = "@tokens", sort = "fiat_value holders_count circulating_market_cap", order = "asc desc"},
		about = "Tokens on the chain, by default by market cap and then holders, largest first: address_hash, name, symbol, type, decimals, total_supply, holders_count, exchange_rate, circulating_market_cap and volume_24h. q matches names and symbols. A sort other than the default can take 15 to 25 s on a large chain such as Ethereum, close to the time limit."},
	{name = "getToken", path = "/tokens/{address}", args = {"address"},
		about = "A token contract, with the fields of listTokens plus icon_url and reputation."},
	{name = "getTokenCounters", path = "/tokens/{address}/counters", args = {"address"},
		about = "token_holders_count and transfers_count, as strings."},
	{name = "listTokenHolders", path = "/tokens/{address}/holders", args = {"address"}, list = true,
		about = "Holders of the token, largest first: address (an address object), value (in the token's smallest unit) and token_id for ERC-1155."},
	{name = "listTokenTransfers", path = "/tokens/{address}/transfers", args = {"address"}, list = true,
		about = "Transfers of the token, newest first, as in listAddressTokenTransfers."},
	{name = "listTokenInstances", path = "/tokens/{address}/instances", args = {"address"}, list = true,
		options = {holder_address_hash = "@address"},
		about = "Instances of an NFT collection, as in getTokenInstance without token. holder_address_hash keeps those one address holds."},
	{name = "getTokenInstance", path = "/tokens/{address}/instances/{token_id}", args = {"address", "token_id"},
		about = "One NFT: id, token, owner, metadata (the token URI's JSON, such as name, description and attributes), image_url, animation_url and external_app_url."},
	{name = "listSmartContracts", path = "/smart-contracts", args = {}, list = true,
		options = {q = "@text", filter = LANGUAGES},
		about = "Verified contracts, most recently verified first: address, compiler_version, language, license_type, optimization_enabled, verified_at, coin_balance and transactions_count. q matches contract names and addresses; filter keeps one source language. There is no sort: Blockscout times out sorting verified contracts by balance or transactions."},
	{name = "getSmartContract", path = "/smart-contracts/{address}", args = {"address"},
		about = "A verified contract's source and ABI: name, language, compiler_version, evm_version, optimization_enabled, optimization_runs, license_type, source_code, file_path, additional_sources ({file_path, source_code}), abi (an array), constructor_args, decoded_constructor_args, compiler_settings, verified_at, is_verified, is_fully_verified, proxy_type and implementations (the logic contracts of a proxy, whose own source getSmartContract returns). Bytecode is included too, so a large contract can be several hundred KB. A contract without verified source still answers, with is_verified false, its bytecode and proxy fields, and no source_code or abi; an address without code fails with HTTP 404."},
	{name = "search", path = "/search", args = {"q"}, list = true,
		about = "Searches addresses, tokens, contracts, blocks, transactions and ENS names. Each item has type (address, contract, token, block, transaction, ens_domain...) and its fields, such as address_hash, name, symbol and token_type, or block_number and transaction_hash. q is a name, symbol, address, hash or block number. A broad text search can take long on a large chain and then fails as retryable; prefer exact names or addresses."},
	{name = "getStats", path = "/stats", args = {},
		about = "Chain statistics: total_blocks, total_addresses, total_transactions, transactions_today, average_block_time (ms), coin_price (USD), market_cap, gas_prices ({slow, average, fast} in gwei) and network_utilization_percentage."},
} :: {Options}) :: any

local function finite(value: any): boolean
	return type(value) == "number" and value == value and math.abs(value) < 2 ^ 53
end

local function hex(value: any, digits: number): boolean
	return type(value) == "string" and #value == digits + 2 and string.match(value, "^0x%x+$") ~= nil
end

local function text(value: any, field: string): string
	assert(type(value) == "string" and string.find(value, "%S") and #value <= MAX_TEXT,
		field .. " must be " .. FORMATS["@text"] .. ", not only spaces")
	return value
end

-- A block is a number or a block hash; a token ID is a nonnegative integer up to 2^256, as a number or a string.
local function positional(name: string, value: any): string
	if name == "address" then
		assert(hex(value, 40), "address must be " .. FORMATS["@address"])
	elseif name == "hash" then
		assert(hex(value, 64), "hash must be a transaction hash, 0x and 64 hex digits")
	elseif name == "block" then
		if finite(value) and value % 1 == 0 and value >= 0 then return string.format("%d", value) end
		assert(hex(value, 64) or (type(value) == "string" and #value <= 16 and string.match(value, "^%d+$")),
			"block must be a block number or a block hash, 0x and 64 hex digits")
	elseif name == "token_id" then
		if finite(value) and value % 1 == 0 and value >= 0 then return string.format("%d", value) end
		assert(type(value) == "string" and #value <= 78 and string.match(value, "^%d+$"),
			"token_id must be a nonnegative integer, as a number or a decimal string")
	else
		return text(value, name)
	end
	return value
end

local function option(name: string, kind: string, value: any): string
	if kind == "@address" then
		assert(hex(value, 40), name .. " must be " .. FORMATS[kind])
	elseif kind == "@topic" then
		assert(hex(value, 64), name .. " must be " .. FORMATS[kind])
	elseif kind == "@text" then
		return text(value, name)
	elseif kind == "@tokens" then
		local items: {any} = if type(value) == "table" then value else {value}
		local types: {string} = {}
		for index, item in items do
			assert(index == #types + 1 and table.find(TOKEN_TYPES, item), name .. " must be " .. FORMATS[kind])
			table.insert(types, item)
		end
		assert(#types > 0, name .. " must be " .. FORMATS[kind])
		return table.concat(types, ",")
	else
		assert(type(value) == "string" and table.find(string.split(kind, " "), value),
			name .. " must be one of " .. string.gsub(kind, " ", ", "))
	end
	return value
end

-- next_page_params holds the keyset of the last item; its values are scalars, sent back as Blockscout's frontend does.
local function pageValue(key: string, value: any): string
	if value == NULL then return "null" end
	if type(value) == "boolean" then return tostring(value) end
	if finite(value) then return if value % 1 == 0 then string.format("%d", value) else tostring(value) end
	assert(type(value) == "string" and #value <= MAX_PAGE_VALUE, "page." .. key .. " must be a value from next_page_params")
	return value
end

local function options(value: any, operation: string): Options
	assert(value == nil or type(value) == "table", operation .. " options must be a table")
	return table.clone((value or {}) :: Options)
end

local function query(endpoint: Endpoint, args: Options, params: {[string]: string}): string
	for name, kind in endpoint.options do
		if args[name] ~= nil then params[name] = option(name, kind, args[name]) end
		args[name] = nil
	end
	if endpoint.list and args.page ~= nil then
		local page = args.page
		args.page = nil
		assert(type(page) == "table", "page must be the next_page_params table of the previous page")
		local count = 0
		for key, value in page do
			count += 1
			assert(count <= MAX_PAGE_KEYS and type(key) == "string" and #key <= 64
				and (string.match(key, "^%l[%l%d_]*$") or string.match(key, "^%l[%l%d_]*%[[%l%d_]+%]$"))
				and key ~= "apikey" and key ~= "key", "page must be the next_page_params table of the previous page")
			local kind = endpoint.options[key]
			local rendered = if kind then option(key, kind, value) else pageValue(key, value)
			assert(params[key] == nil or params[key] == rendered,
				"page." .. key .. " differs from the option " .. key .. "; pass the previous page's options with its next_page_params")
			params[key] = rendered
		end
	end
	local unknown = next(args)
	assert(unknown == nil, endpoint.name .. " received an unknown option " .. string.sub(tostring(unknown), 1, 64))
	local names: {string} = {}
	for name in params do table.insert(names, name) end
	table.sort(names)
	local parts: {string} = {}
	for _, name in names do table.insert(parts, url.encode(name) .. "=" .. url.encode(params[name])) end
	return if #parts > 0 then "?" .. table.concat(parts, "&") else ""
end

local function errorCode(err: any): any
	return if type(err) == "table" then err.code else nil
end

local function fail(operation: string, status: number?, retryable: boolean, message: string): never
	return houston.fail({operation = operation, layer = "upstream", upstream_status = status, retryable = retryable,
		message = message})
end

-- houston.fail repairs a character split by the cut.
local function tidy(message: string): string
	return string.sub(string.match(string.gsub(message, "%s+", " "), "^ ?(.-) ?$") :: string, 1, 300)
end

-- Blockscout answers {"message"}, OpenAPI validation {"errors": [{source = {pointer}, detail}]}, and the Blockscout API
-- {"error", "source"}; other bodies are never shown.
local function reason(body: string): string
	local ok, decoded = pcall(json.decode, body)
	if not ok or type(decoded) ~= "table" then return "" end
	local first = if type(decoded.errors) == "table" then decoded.errors[1] else nil
	if type(first) == "table" and type(first.detail) == "string" then
		local pointer = if type(first.source) == "table" and type(first.source.pointer) == "string" then first.source.pointer else nil
		return tidy((if pointer then string.gsub(pointer, "^/", "") .. ": " else "") .. first.detail)
	end
	local message = if type(decoded.message) == "string" then decoded.message elseif type(decoded.error) == "string" then decoded.error else nil
	return if message then tidy(message) else ""
end

local function failure(operation: string, response: HttpResponse): never
	local status = response.statusCode
	local detail, body = "", ""
	if status >= 300 and status < 400 then
		response.body:close()
		detail = "unexpected redirect"
	else
		-- An error body that stalls or breaks counts as empty.
		local read, prefix = pcall(function() return await(response.body:readPrefix(4096), BODY_TIME) end)
		if not read and errorCode(prefix) == "cancelled" then error(prefix, 0) end
		if read then body, detail = prefix, reason(prefix) end
	end
	local name = if chain then chain.name else "Blockscout"
	local mitigated = response.headers["cf-mitigated"]
	if status == 403 and not KEYED and ((mitigated and mitigated[1] == "challenge") or string.find(body, "Just a moment", 1, true)) then
		return fail(operation, status, false, "The " .. name .. " explorer's bot protection refused the request; "
			.. "a connection admin can add a free Blockscout API key to the connection to read this chain")
	end
	local message = "Blockscout HTTP " .. tostring(status) .. (if detail == "" then "" else ": " .. detail)
	if (status == 401 or status == 402) and KEYED then message ..= "; the connection's Blockscout API key was refused or has no credits left" end
	local retry, reset = response.headers["retry-after"], response.headers["x-ratelimit-reset"]
	if (status == 429 or status == 503) and retry and retry[1] then
		-- Retry-After is either delay seconds or an HTTP date.
		local value = string.sub(retry[1], 1, 32)
		message ..= "; retry after " .. value .. (if string.match(value, "^%d+$") then "s" else "")
	elseif status == 429 and reset and reset[1] and string.match(reset[1], "^%d+$") and #reset[1] <= 9 then
		-- Blockscout's own header counts milliseconds until the limit resets.
		message ..= "; retry after " .. tostring(math.ceil(tonumber(reset[1]) :: number / 1000)) .. "s"
	end
	-- Input is validated first, so a 4xx is final; 501 means this explorer lacks the feature, other 5xx are server faults.
	return fail(operation, status, status == 429 or (status >= 500 and status ~= 501), message)
end

local function fetch(operation: string, target: string): any
	local sent, response = pcall(function()
		return await(http.request({method = "GET", url = target, headers = {Accept = {"application/json"}},
			timeoutMs = CALL_TIME - BODY_TIME}))
	end)
	if not sent then
		if errorCode(response) ~= "timeout" then error(response, 0) end
		fail(operation, nil, true, "Blockscout did not answer within " .. tostring((CALL_TIME - BODY_TIME) // 1000) .. " s; retry, or narrow the request")
	end
	if response.statusCode ~= 200 then failure(operation, response) end
	local read, raw = pcall(function() return await(response.body:readAll(MAX_BYTES), BODY_TIME) end)
	if not read then
		local code = errorCode(raw)
		if code == "limit_exceeded" then
			fail(operation, 200, false, "Blockscout returned more data than one call can hold")
		elseif code == "timeout" then
			fail(operation, 200, true, "Blockscout did not finish sending its answer within " .. tostring(BODY_TIME // 1000) .. " s; retry")
		elseif code == "cancelled" then
			error(raw, 0)
		end
		local detail = if type(raw) == "table" and type(raw.message) == "string" then raw.message else tostring(raw)
		fail(operation, 200, true, "Blockscout response failed: " .. string.sub(detail, 1, 300))
	end
	-- A collection's instance cursor holds unique_token as a bare integer up to 2^256, which would decode as a float.
	raw = string.gsub(raw, '"unique_token":(%d+)', '"unique_token":"%1"')
	-- The anchored check is cheap, so a large page that is not JSON is never decoded.
	local ok, value = false, nil
	if string.match(raw, "^%s*{") then ok, value = pcall(json.decode, raw) end
	if not ok or type(value) ~= "table" then fail(operation, 200, false, "Blockscout returned an invalid JSON object") end
	return value
end

local exports: {[string]: any} = {}
local sections: {string} = {}

local function optionHelp(endpoint: Endpoint): string
	local names: {string} = {}
	for name in endpoint.options do table.insert(names, name) end
	table.sort(names)
	local parts: {string} = {}
	for _, name in names do
		local kind = endpoint.options[name]
		table.insert(parts, name .. ": " .. (FORMATS[kind] or string.gsub(kind, " ", ", ")))
	end
	return if #parts > 0 then " Options: " .. table.concat(parts, "; ") .. "." else ""
end

for _, endpoint in ENDPOINTS do
	endpoint.options = endpoint.options or {}
	endpoint.list = endpoint.list == true
	local takesOptions = endpoint.list or next(endpoint.options) ~= nil
	exports[endpoint.name] = function(...: any): any
		local values = table.pack(...)
		local target = endpoint.path
		local args = options(if takesOptions then values[#endpoint.args + 1] else nil, endpoint.name)
		local most = #endpoint.args + (if takesOptions then 1 else 0)
		assert(values.n <= most, endpoint.name .. " takes at most " .. tostring(most) .. " arguments")
		-- Arguments without a path placeholder, such as search's q, are required query parameters.
		local params: {[string]: string} = {}
		for index, name in endpoint.args do
			local value = positional(name, values[index])
			local placeholder = "{" .. name .. "}"
			if string.find(target, placeholder, 1, true) then
				target = string.gsub(target, placeholder, value)
			else
				params[name] = value
			end
		end
		assert(chain, "the connection's chain is not one Houston knows; edit the connection and choose a chain")
		local result = fetch(endpoint.name, API .. target .. query(endpoint, args, params))
		-- JSON null is truthy in Luau, so the last page leaves next_page_params out.
		if endpoint.list and result.next_page_params == NULL then result.next_page_params = nil end
		return result
	end
	local signature = table.concat(endpoint.args, ", ")
	if takesOptions then signature ..= (if signature == "" then "" else ", ") .. "opts?" end
	table.insert(sections, "## " .. endpoint.name .. "(" .. signature .. ")\n\nGET " .. endpoint.path
		.. (if endpoint.list then ", a page" else "") .. ". " .. endpoint.about .. optionHelp(endpoint))
end

local function help(): string
	local name = if chain then chain.name .. " (chain ID " .. string.format("%d", chain.id) .. ")" else "an unknown chain"
	local via = if KEYED then "through the multichain Blockscout API with the connection's API key, which allows 5 requests per second on the free plan and costs credits per call (20 for most, up to 50 for summaries and coin balance history)"
		else "through the chain's public Blockscout explorer, without a key; every Houston connection shares its rate limit, and some explorers refuse automated requests until a connection admin adds a free Blockscout API key"
	return [[Blockscout: read ]] .. name .. [[ from its Blockscout block explorer (REST API v2, https://docs.blockscout.com/devs/apis/rest): addresses with balances, tokens and transactions; transactions with logs, token transfers and internal transactions; blocks; tokens, holders and NFTs; verified contract sources and ABIs; search and chain statistics. Requests go ]] .. via .. [[. Read-only: nothing can sign or send a transaction. One connection reads one chain. Calls return completed values; do not wrap them in await(). Results are Blockscout's JSON unchanged. Amounts are integer strings in the smallest unit: wei for the native coin (divide by 10^18), and 10^decimals of the token for tokens; fiat values are current USD prices, never historical.

Addresses are 0x and 40 hex digits, in any letter case; transaction and block hashes 0x and 64 hex digits. Each call makes one request. Invalid input and unknown options fail before any request.

## Pages

A call marked "a page" returns `{items, next_page_params}`: up to 50 items, and next_page_params, the keyset of the last item, absent after the last page. For the next page, call again with the same arguments and options plus `page = result.next_page_params`; next_page_params does not always carry the options (such as sort, order, type or filter), so repeat every option. Collect only the pages you need: each call reads one.

]] .. table.concat(sections, "\n\n") .. [[


## Errors and limits

Blockscout errors come back as upstream errors with the HTTP status and Blockscout's message: 404 for an unknown transaction, block or token, or a contract address without code, 422 for a value Blockscout rejects (such as an NFT-only type), 429 when the rate limit is reached and 5xx for server faults. 429 and 5xx (except 501, a feature this explorer lacks) are retryable; Houston waits and retries a refused request briefly. Each call reads at most ]] .. tostring(MAX_BYTES // 1048576) .. [[ MiB and gives Blockscout ]] .. tostring(CALL_TIME // 1000) .. [[ s: ]] .. tostring((CALL_TIME - BODY_TIME) // 1000) .. [[ s to start answering and ]] .. tostring(BODY_TIME // 1000) .. [[ s to send the body; a call that runs out of time fails as retryable. Lists of very active addresses, such as their tokens, can take long on large chains.

## Example

Here blockscout is the configured Blockscout connection.

```lua
local vitalik = "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045"
local account = blockscout.getAddress(vitalik)
print(account.coin_balance, account.ens_domain_name)
local page = blockscout.listAddressTransactions(vitalik, {filter = "from"})
for _, tx in page.items do print(tx.hash, tx.method, tx.value, tx.status) end
if #page.items == 0 then return end
if page.next_page_params then
	local older = blockscout.listAddressTransactions(vitalik, {filter = "from", page = page.next_page_params})
end
local tx = blockscout.getTransaction(page.items[1].hash)
local transfers = blockscout.listTransactionTokenTransfers(tx.hash, {type = "ERC-20"})
local holders = blockscout.listTokenHolders("0xdAC17F958D2ee523a2206206994597C13D831ec7")
local contract = blockscout.getSmartContract("0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984")
if contract.is_verified then print(contract.name, contract.compiler_version, #contract.abi) end
```]]
end

exports.help = help
return exports
