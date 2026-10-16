-- Wise Platform API with legacy per-endpoint versions (v1–v4). Arguments and results keep Wise's native field names.
type Options = {[string]: any}
type Query = {type: "string" | "integer" | "boolean" | "list", minimum: number?, maximum: number?, enum: {string}?}
type Endpoint = {
	method: string, path: string, query: {[string]: Query}?, required: {string}?, oneOf: {string}?, kind: "download"?,
	idempotence: boolean?, merge: boolean?, minor: boolean?, safe: boolean?, about: string,
}

local STATEMENT_QUERY: {[string]: Query} = {currency = {type = "string"}, intervalStart = {type = "string"}, intervalEnd = {type = "string"},
	type = {type = "string", enum = {"COMPACT", "FLAT"}}, statementLocale = {type = "string"}}
local LEGAL_ENTITY: Query = {type = "string", enum = {"PRIVATE", "BUSINESS"}}
local endpoints: {[string]: Endpoint} = {
	getMe = {method = "GET", path = "/v1/me", about = "The token's user: id, name, email and active state."},
	listProfiles = {method = "GET", path = "/v2/profiles", about = "Array of PERSONAL and BUSINESS profiles; most calls need a profile id from here."},
	getProfile = {method = "GET", path = "/v2/profiles/{profileId}", about = "One profile."},
	listBalances = {method = "GET", path = "/v4/profiles/{profileId}/balances", required = {"types"},
		query = {types = {type = "list", enum = {"STANDARD", "SAVINGS"}}},
		about = "Array of balances with amount, reservedAmount, cashAmount and totalWorth per currency; types required, e.g. {'STANDARD','SAVINGS'}. Unpaginated."},
	getBalance = {method = "GET", path = "/v4/profiles/{profileId}/balances/{balanceId}", about = "One balance."},
	getTotalFunds = {method = "GET", path = "/v1/profiles/{profileId}/total-funds/{currency}", about = "Total worth and available funds across balances, valued in currency."},
	getBalanceStatement = {method = "GET", path = "/v1/profiles/{profileId}/balance-statements/{balanceId}/statement.json", required = {"currency", "intervalStart", "intervalEnd"},
		query = STATEMENT_QUERY,
		about = "Statement JSON with transactions, start/end balances and query. ISO-8601 UTC interval of at most 469 days. Needs strong customer authentication outside the US, CA, AU, NZ, SG and MY."},
	downloadBalanceStatement = {method = "GET", path = "/v1/profiles/{profileId}/balance-statements/{balanceId}/statement.{format}", kind = "download", required = {"currency", "intervalStart", "intervalEnd"},
		query = STATEMENT_QUERY,
		about = "Save a statement file to path; format pdf, csv, xlsx, xml (CAMT.053), mt940 or qif. Same interval and authentication limits as getBalanceStatement."},
	listAccountDetails = {method = "GET", path = "/v1/profiles/{profileId}/account-details", about = "Array of receiving bank details (account numbers, IBANs, routing codes) per currency."},
	listActivities = {method = "GET", path = "/v1/profiles/{profileId}/activities",
		query = {monetaryResourceType = {type = "string"}, status = {type = "string", enum = {"REQUIRES_ATTENTION", "IN_PROGRESS", "UPCOMING", "COMPLETED", "CANCELLED"}}, since = {type = "string"}, ["until"] = {type = "string"}, nextCursor = {type = "string"}, size = {type = "integer", minimum = 1, maximum = 100}},
		about = "Activity feed {activities, cursor}: card spend, transfers, conversions and more; monetaryResourceType filters by Wise resource type such as TRANSFER or CARD_TRANSACTION. title and description may contain HTML. size 1..100 (default 10); pass cursor as nextCursor until it is null."},
	getRates = {method = "GET", path = "/v1/rates",
		query = {source = {type = "string"}, target = {type = "string"}, time = {type = "string"}, from = {type = "string"}, to = {type = "string"}, group = {type = "string", enum = {"day", "hour", "minute"}}},
		about = "Array of mid-market rates {rate, source, target, time}; time for one historic rate, or from/to/group for history."},
	listCurrencies = {method = "GET", path = "/v1/currencies", about = "Array of currencies Wise supports, with codes, names and symbols."},
	listTransfers = {method = "GET", path = "/v1/transfers",
		query = {profile = {type = "integer", minimum = 1}, status = {type = "list"}, sourceCurrency = {type = "string"}, targetCurrency = {type = "string"}, createdDateStart = {type = "string"}, createdDateEnd = {type = "string"}, limit = {type = "integer", minimum = 1}, offset = {type = "integer", minimum = 0}},
		about = "Array of transfers. Pass profile: Wise defaults to the personal profile. Filter by status list, currencies and createdDateStart/End; page with limit and offset."},
	getTransfer = {method = "GET", path = "/v1/transfers/{transferId}", about = "One transfer with status, amounts, rate and reference."},
	downloadTransferReceipt = {method = "GET", path = "/v1/transfers/{transferId}/receipt.pdf", kind = "download", about = "Save the transfer receipt PDF to path."},
	getQuote = {method = "GET", path = "/v3/profiles/{profileId}/quotes/{quoteId}", about = "One quote with paymentOptions, fees, rate and expirationTime."},
	getAccountRequirements = {method = "GET", path = "/v1/quotes/{quoteId}/account-requirements", minor = true,
		query = {originatorLegalEntityType = LEGAL_ENTITY, addressRequired = {type = "boolean"}},
		about = "Array of recipient forms (type, fields with keys, validation and refreshRequirementsOnChange) for a quote's route."},
	listRecipients = {method = "GET", path = "/v2/accounts",
		query = {profileId = {type = "integer", minimum = 1}, currency = {type = "string"}, type = {type = "string"}, active = {type = "boolean"}, ownedByCustomer = {type = "boolean"}, size = {type = "integer", minimum = 1, maximum = 20}, seekPosition = {type = "integer"}, sort = {type = "string"}},
		about = "{content, size, seekPositionForNext, ...} of recipient accounts. Pass profileId: Wise defaults to the personal profile; size 1..20, pass seekPositionForNext as seekPosition for the next page."},
	getRecipient = {method = "GET", path = "/v2/accounts/{accountId}", about = "One recipient account."},
	getBatchGroup = {method = "GET", path = "/v3/profiles/{profileId}/batch-groups/{batchGroupId}", about = "One batch group with status, version and transferIds."},

	createQuote = {method = "POST", path = "/v3/profiles/{profileId}/quotes", required = {"sourceCurrency", "targetCurrency"}, oneOf = {"sourceAmount", "targetAmount"}, safe = true,
		about = "Price a transfer or conversion; exactly one of sourceAmount or targetAmount; optional targetAccount, payOut, preferredPayIn. Moves no money."},
	updateQuote = {method = "PATCH", path = "/v3/profiles/{profileId}/quotes/{quoteId}", merge = true,
		about = "Attach targetAccount (and payOut) to a quote, refreshing fees and paymentOptions."},
	refreshAccountRequirements = {method = "POST", path = "/v1/quotes/{quoteId}/account-requirements", minor = true, safe = true,
		query = {originatorLegalEntityType = LEGAL_ENTITY},
		about = "Send a partial recipient body to get updated forms when a field has refreshRequirementsOnChange. Creates nothing."},
	createRecipient = {method = "POST", path = "/v1/accounts", required = {"profile", "accountHolderName", "currency", "type", "details"},
		about = "Create a recipient account; type and details follow getAccountRequirements. ownedByCustomer marks your own account."},
	validateTransferRequirements = {method = "POST", path = "/v1/transfer-requirements", required = {"targetAccount", "quoteUuid"}, safe = true,
		about = "Array of extra transfer fields (reference, transferPurpose, sourceOfFunds) needed for this quote and recipient. Creates nothing."},
	createTransfer = {method = "POST", path = "/v1/transfers", required = {"targetAccount", "quoteUuid", "customerTransactionId"},
		about = "Create an unfunded transfer from a quote; customerTransactionId is your UUID idempotency key; details holds reference and requirements."},
	cancelTransfer = {method = "PUT", path = "/v1/transfers/{transferId}/cancel", about = "Cancel a transfer while its status is incoming_payment_waiting; later states fail with 409."},
	fundTransfer = {method = "POST", path = "/v3/profiles/{profileId}/transfers/{transferId}/payments", required = {"type"},
		about = "Pay a transfer from your balance: {type='BALANCE'}. Moves money. Needs strong customer authentication outside the US, CA, AU, NZ, SG and MY. Check the returned status: REJECTED carries errorCode."},
	createBalance = {method = "POST", path = "/v4/profiles/{profileId}/balances", required = {"currency", "type", "idempotenceUuid"}, idempotence = true,
		about = "Open a STANDARD balance or a SAVINGS jar (name required for jars)."},
	deleteBalance = {method = "DELETE", path = "/v4/profiles/{profileId}/balances/{balanceId}", about = "Close an empty balance; its receiving bank details are deactivated and may not be restorable."},
	createBalanceMovement = {method = "POST", path = "/v2/profiles/{profileId}/balance-movements", required = {"idempotenceUuid"}, idempotence = true,
		about = "Convert between your balances with {quoteId} (a quote with payOut BALANCE), or move between a balance and a jar with {amount={value,currency}, sourceBalanceId, targetBalanceId}. Moves money."},
	createBatchGroup = {method = "POST", path = "/v3/profiles/{profileId}/batch-groups", required = {"name", "sourceCurrency"},
		about = "Start a batch of up to 1,000 transfers in one source currency."},
	createBatchTransfer = {method = "POST", path = "/v3/profiles/{profileId}/batch-groups/{batchGroupId}/transfers", required = {"targetAccount", "quoteUuid", "customerTransactionId"},
		about = "Add a transfer to an open batch; same body as createTransfer."},
	updateBatchGroup = {method = "PATCH", path = "/v3/profiles/{profileId}/batch-groups/{batchGroupId}", required = {"status", "version"},
		about = "Set status COMPLETED (close for funding) or CANCELLED, with the group's current version."},
	fundBatchGroup = {method = "POST", path = "/v3/profiles/{profileId}/batch-payments/{batchGroupId}/payments", required = {"type"},
		about = "Pay a completed batch from your balance: {type='BALANCE'}. Moves money; same authentication limits as fundTransfer."},
}

local NULL = json.decode("null")
local NONE: {string} = table.freeze({})
local NO_QUERY: {[string]: Query} = table.freeze({})
local ORIGIN = "https://" .. config.api_host
local FORMATS = table.freeze({"pdf", "csv", "xlsx", "xml", "mt940", "qif"})
local UUID_FIELDS = table.freeze({"customerTransactionId", "quoteUuid", "quoteId"})
local UUID = "^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$"

local function text(value: any, field: string): string
	assert(type(value) == "string" and value ~= "" and not string.find(value, "%c"), field .. " must be a nonempty string without control characters")
	return value
end

local function integer(value: any, field: string, minimum: number?, maximum: number?): string
	if type(value) == "string" and string.match(value, "^%d+$") and #value <= 16 then value = tonumber(value) end
	assert(type(value) == "number" and value % 1 == 0 and value >= (minimum or 0) and value <= (maximum or 9007199254740991),
		field .. " must be an integer" .. (if minimum then " from " .. minimum else "") .. (if maximum then " to " .. maximum else ""))
	return string.format("%d", value)
end

local function uuid(value: any, field: string): string
	assert(type(value) == "string" and string.match(value, UUID), field .. " must be a UUID")
	return value
end

local function pathValue(value: any, field: string): string
	if field == "quoteId" or field == "batchGroupId" then return uuid(value, field) end
	if field == "currency" then
		assert(type(value) == "string" and string.match(value, "^%u%u%u$"), "currency must be a three-letter uppercase code")
		return value
	end
	if field == "format" then
		assert(table.find(FORMATS, value), "format must be one of " .. table.concat(FORMATS, ", "))
		return value
	end
	return integer(value, field, 1)
end

local function queryValue(value: any, field: string, spec: Query): string
	if spec.type == "integer" then return integer(value, field, spec.minimum, spec.maximum) end
	if spec.type == "boolean" then
		assert(type(value) == "boolean", field .. " must be a boolean")
		return tostring(value)
	end
	local items: any = {value}
	if spec.type == "list" then
		items = if type(value) == "string" then string.split(value, ",") else value
		assert(type(items) == "table" and #items > 0, field .. " must be a nonempty list")
		for index in items do
			assert(type(index) == "number" and index % 1 == 0 and index >= 1 and index <= #items, field .. " must be a dense array")
		end
	end
	local values: {string} = {}
	for _, item in items do table.insert(values, text(item, field)) end
	if spec.enum then
		for _, item in values do assert(table.find(spec.enum, item), field .. " must be one of " .. table.concat(spec.enum, ", ")) end
	end
	return url.encode(table.concat(values, ","))
end

local function header(response: HttpResponse, name: string): string?
	local values = response.headers[name]
	return if values and values[1] then string.sub(values[1], 1, 200) else nil
end

local function fail(name: string, endpoint: Endpoint, response: HttpResponse, detail: string?): never
	local message = "Wise HTTP " .. response.statusCode
	local sca = response.statusCode == 403 and header(response, "x-2fa-approval-result") == "REJECTED"
	if detail then
		message ..= ": " .. detail
	else
		local read, prefix = pcall(function() return await(response.body:readPrefix(8192)) end)
		local raw = if read then prefix else ""
		local ok, body = pcall(json.decode, raw)
		local parts: {string} = {}
		if ok and type(body) == "table" then
			if type(body.errors) == "table" then
				for _, item in body.errors do
					if type(item) == "table" then
						local entry: {string} = {}
						for _, key in {"code", "message", "path"} do
							if type(item[key]) == "string" then table.insert(entry, key .. "=" .. string.sub(item[key], 1, 200)) end
						end
						if #entry > 0 then table.insert(parts, table.concat(entry, " ")) end
					end
				end
			end
			for _, key in {"error", "error_description", "message"} do
				if type(body[key]) == "string" then table.insert(parts, string.sub(body[key], 1, 200)) end
			end
		end
		if #parts == 0 and raw ~= "" then table.insert(parts, string.sub(raw, 1, 200)) end
		if #parts > 0 then message ..= ": " .. string.sub(table.concat(parts, "; "), 1, 1000) end
	end
	if sca then
		message ..= "; strong customer authentication required (x-2fa-approval-result=REJECTED)."
			.. " This connector cannot complete it: finish this step in the Wise app or website"
	end
	for _, key in {"retry-after", "x-trace-id"} do
		local value = header(response, key)
		if value then message ..= "; " .. key .. "=" .. value end
	end
	return houston.fail({operation = name, layer = "upstream", upstream_status = response.statusCode,
		retryable = not sca and (response.statusCode == 429 or (response.statusCode >= 500 and (endpoint.method == "GET" or endpoint.safe == true))), message = message})
end

local function present(value: any): boolean
	return value ~= nil and value ~= NULL and value ~= ""
end

-- Cancelling (PUT) and closing a balance (DELETE) take no body.
local function sendsBody(endpoint: Endpoint): boolean
	return endpoint.method == "POST" or endpoint.method == "PATCH"
end

local function request(name: string, endpoint: Endpoint, input: Options?): any
	assert(input == nil or type(input) == "table", "opts must be an object")
	local args: Options = if input then table.clone(input) else {}
	for key in args do assert(type(key) == "string", "opts must have named fields") end
	local path = string.gsub(endpoint.path, "{(%w+)}", function(field: string)
		local value = pathValue(args[field], field)
		args[field] = nil
		return value
	end)
	for _, field in endpoint.required or NONE do assert(present(args[field]), field .. " is required") end
	local headers: HttpHeaders = {Accept = {"application/json"}}
	if endpoint.minor then headers["Accept-Minor-Version"] = {"1"} end
	assert(endpoint.idempotence or args.idempotenceUuid == nil, name .. " does not accept idempotenceUuid")
	if endpoint.idempotence then
		headers["X-idempotence-uuid"] = {uuid(args.idempotenceUuid, "idempotenceUuid")}
		args.idempotenceUuid = nil
	end
	local query: {string} = {}
	for field, spec in endpoint.query or NO_QUERY do
		if args[field] ~= nil then
			table.insert(query, url.encode(field) .. "=" .. queryValue(args[field], field, spec))
			args[field] = nil
		end
	end
	table.sort(query)
	if #query > 0 then path ..= "?" .. table.concat(query, "&") end
	local destination: string? = nil
	if endpoint.kind == "download" then
		destination = text(args.path, "path")
		args.path = nil
		headers.Accept = {"*/*"}
	end
	local body: string? = nil
	if not sendsBody(endpoint) then
		local extra = next(args)
		assert(extra == nil, name .. " does not accept option " .. tostring(extra))
	else
		if endpoint.oneOf then
			local count = 0
			for _, field in endpoint.oneOf do
				assert(args[field] ~= "", field .. " cannot be empty")
				if present(args[field]) then count += 1 end
			end
			assert(count == 1, name .. " needs exactly one of " .. table.concat(endpoint.oneOf, " or "))
		end
		for _, field in UUID_FIELDS do
			if args[field] ~= nil then uuid(args[field], field) end
		end
		headers["Content-Type"] = {if endpoint.merge then "application/merge-patch+json" else "application/json"}
		body = json.encode(args)
	end
	local response = await(http.request({method = endpoint.method, url = ORIGIN .. path, headers = headers, body = body}))
	if response.statusCode < 200 or response.statusCode >= 300 then fail(name, endpoint, response) end
	if destination then
		local media = string.lower(header(response, "content-type") or "")
		if string.find(media, "json", 1, true) or string.find(media, "html", 1, true) then
			local ok, snippet = pcall(function() return await(response.body:readPrefix(200)) end)
			fail(name, endpoint, response, "Wise returned " .. media .. " instead of a file: " .. (if ok then snippet else ""))
		end
		local output = fs.open(destination, "w")
		output:write(response.body)
		await(output:close())
		return {path = destination, size = await(fs.stat(destination)).size, url = await(fs.signedGetUrl(destination))}
	end
	local read, raw = pcall(function() return await(response.body:readAll()) end)
	if not read then
		if type(raw) == "table" and raw.code == "limit_exceeded" then
			fail(name, endpoint, response, if endpoint.method == "GET" then "the response exceeded 8 MiB; narrow the interval or page size"
				else "Wise accepted the request but its response exceeded 8 MiB; check the result before repeating it")
		end
		error(raw, 0)
	end
	if endpoint.method ~= "GET" and string.match(raw, "^%s*$") then return {success = true} end
	local decoded, value = pcall(json.decode, raw)
	if not decoded or type(value) ~= "table" or not string.match(raw, "^%s*[%[{]") then
		fail(name, endpoint, response, if endpoint.method == "GET" then "Wise returned an invalid JSON response"
			else "Wise accepted the request but returned an invalid JSON response; check the result before repeating it")
	end
	return value
end

local exports: {[string]: any} = {}
for name, endpoint in endpoints do
	if endpoint.method == "GET" or config.access == "read-write" then
		exports[name] = function(opts: Options?): any return request(name, endpoint, opts) end
	end
end

exports.help = function(): string
	local lines = {
		"Wise Platform API (legacy v1-v4 paths) on " .. config.api_host .. ". Call functions directly, e.g. wise.listProfiles(); do not await connector calls. Each takes one options object with Wise's native names: {placeholders} in the route are required, query options are listed per function, and remaining options of POST/PATCH calls form the JSON body unchanged. Results are Wise's JSON unchanged (some are arrays). Reference: https://docs.wise.com/api-reference .",
		"Start with listProfiles() and pick the PERSONAL or BUSINESS profile id. Ids for profiles, balances, transfers and recipients are integers; quote and batch group ids are UUID strings. Amounts are decimal major units (12.5 = 12.50), not cents. Dates are ISO-8601, e.g. '2026-10-01T00:00:00Z'.",
		"Paging: listActivities returns cursor, passed back as nextCursor until null (size 1..100); listTransfers uses limit and offset; listRecipients uses size 1..20 and seekPositionForNext -> seekPosition. Other lists are unpaginated. No automatic paging or retries.",
		"Downloads stream to a session file and return {path,url,size}; url is Houston's signed link. A download that fails while streaming can leave a partial file.",
		"Personal API tokens: Wise documents them for business accounts, and a token created as read only rejects writes. Balance statements (and, with write access, funding) need strong customer authentication (SCA) except for accounts based in the US, Canada, Australia, New Zealand, Singapore and Malaysia; elsewhere these calls fail with a 403 naming SCA, which this connector cannot complete, and the owner must finish the step in the Wise app or website. Do not retry them. Card details, webhooks, profile/KYC changes and recipient deletion are not available here.",
	}
	if config.access == "read-write" then
		table.insert(lines, "Sending money: createQuote({profileId,sourceCurrency,targetCurrency,sourceAmount}) -> getAccountRequirements({quoteId}) -> createRecipient or listRecipients -> updateQuote({profileId,quoteId,targetAccount}) -> validateTransferRequirements -> createTransfer({targetAccount,quoteUuid,customerTransactionId,details={reference=...}}) -> fundTransfer({profileId,transferId,type='BALANCE'}). Quotes expire (expirationTime). Funding moves money and can be irreversible; confirm amount, currency and recipient with the user first. cancelTransfer works only while the status is incoming_payment_waiting. Business accounts with payment approvals enabled in Wise settings cannot create transfers through the API (missing approval error).")
		table.insert(lines, "Write errors: a 5xx is retryable only for calls that move no money (createQuote, refreshAccountRequirements, validateTransferRequirements); otherwise inspect the transfer or balance before repeating. A write answered with an empty body returns {success=true}.")
		table.insert(lines, "Idempotency: createTransfer and createBatchTransfer require customerTransactionId, and createBalance and createBalanceMovement require idempotenceUuid (sent as X-idempotence-uuid). Each must be a new UUID kept with the intended action; reuse it only to retry that same action after a timeout, never for a different payment. Inspect listTransfers or getTransfer before retrying an ambiguous write.")
	end
	table.insert(lines, "Errors report HTTP status, Wise's errors (code, message, path), Retry-After and x-trace-id. A 429 means Wise did not process the request and is retryable after Retry-After, as is a 5xx on a read. Wise rate-limits each user to about 100 requests per second and 900 per minute.")
	local names: {string} = {}
	for name in exports do if name ~= "help" then table.insert(names, name) end end
	table.sort(names)
	for _, name in names do
		local endpoint = endpoints[name]
		local options: {string} = {}
		for field in string.gmatch(endpoint.path, "{(%w+)}") do table.insert(options, field) end
		for _, field in endpoint.required or NONE do table.insert(options, field) end
		if endpoint.oneOf then table.insert(options, table.concat(endpoint.oneOf, "|")) end
		if endpoint.kind == "download" then table.insert(options, "path") end
		local optional: {string} = {}
		for field in endpoint.query or NO_QUERY do
			if not table.find(options, field) then table.insert(optional, field .. "?") end
		end
		table.sort(optional)
		for _, field in optional do table.insert(options, field) end
		if sendsBody(endpoint) then table.insert(options, "...body") end
		local signature = if #options > 0 then "{" .. table.concat(options, ", ") .. "}" else ""
		table.insert(lines, name .. "(" .. signature .. "): " .. endpoint.method .. " " .. endpoint.path .. ". " .. endpoint.about)
	end
	return table.concat(lines, "\n")
end
return exports
