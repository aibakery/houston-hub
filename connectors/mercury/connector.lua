-- Preserve Mercury's native field names, amounts, nulls and pagination.
type Options = {[string]: any}
type Query = {type: string, minimum: number?, maximum: number?, enum: {any}?}
type Endpoint = {
	method: string, path: string, write: boolean, body: boolean, query: {[string]: Query},
	required: {string}, kind: string, response: string, list: string, empty: boolean, vault: boolean, help: string,
}
local endpoints: {[string]: Endpoint} = require("lib/endpoints.lua")
local NULL = json.decode("null")

local function text(value: any, field: string): string
	assert(type(value) == "string" and value ~= "", field .. " must be a nonempty string")
	return value
end

local function options(input: Options?): Options
	if input == nil then return {} end
	assert(type(input) == "table", "opts must be an object")
	for key in input do assert(type(key) == "string", "opts must have named fields") end
	return table.clone(input)
end

local function encode(value: string): string
	return (string.gsub(value, "[^A-Za-z0-9%-_%.~]", function(c: string)
		return string.format("%%%02X", string.byte(c))
	end))
end

local function identifier(value: any, field: string): string
	local id = text(value, field)
	assert(string.match(id, "^[%w%-_]+$"), field .. " must be an ID, not a URL or path")
	return encode(id)
end

local function queryValue(value: any, field: string, spec: Query): string
	if spec.type == "integer" then
		assert(type(value) == "number" and value % 1 == 0 and math.abs(value) <= 9007199254740991, field .. " must be a safe integer")
		assert(spec.minimum == nil or value >= spec.minimum, field .. " is below the allowed minimum")
		assert(spec.maximum == nil or value <= spec.maximum, field .. " exceeds the allowed maximum")
	elseif spec.type == "boolean" then
		assert(type(value) == "boolean", field .. " must be a boolean")
	else
		text(value, field)
	end
	if spec.enum then assert(table.find(spec.enum, value), field .. " has an unsupported value") end
	return encode(tostring(value))
end

local function fail(name: string, response: HttpResponse): never
	local chunk = await(response.body:read(4096))
	response.body:close()
	local ok, value = pcall(json.decode, if chunk.done then "" else chunk.data)
	local message = "Mercury HTTP " .. tostring(response.statusCode)
	if ok and type(value) == "table" then
		local detail = value.message or value.error
		if type(detail) == "string" then message ..= ": " .. string.sub(detail, 1, 600) end
	end
	local retry = response.headers["retry-after"]
	if retry and retry[1] then message ..= "; Retry-After: " .. retry[1] end
	return houston.fail({operation = name, layer = "upstream", upstream_status = response.statusCode,
		retryable = response.statusCode == 429 or response.statusCode >= 500, message = message})
end

local function invalidResponse(name: string, status: number): never
	return houston.fail({operation = name, layer = "upstream", upstream_status = status,
		retryable = false, message = "Mercury returned an invalid response"})
end

local function responseJSON(name: string, endpoint: Endpoint, response: HttpResponse): any
	if response.statusCode < 200 or response.statusCode >= 300 then fail(name, response) end
	if response.statusCode == 204 then
		response.body:close()
		if not endpoint.empty then invalidResponse(name, response.statusCode) end
		return {success = true}
	end
	local raw = await(response.body:readAll())
	if endpoint.empty and string.match(raw, "^%s*$") then return {success = true} end
	local ok, value = pcall(json.decode, raw)
	if ok and endpoint.empty and value == NULL then return {success = true} end
	local array = string.match(raw, "^%s*%[") ~= nil
	if not ok or type(value) ~= "table" or (not endpoint.empty and (endpoint.response == "array") ~= array)
		or (not array and not string.match(raw, "^%s*{")) then
		invalidResponse(name, response.statusCode)
	end
	if value.error ~= nil or value.errors ~= nil then invalidResponse(name, response.statusCode) end
	if endpoint.list ~= "" then
		local items = value[endpoint.list]
		if type(items) ~= "table" or not string.match(json.encode(items), "^%[") then invalidResponse(name, response.statusCode) end
	end
	return value
end

local function uploadBody(name: string, args: Options): (Reader, string)
	local path = text(args.path, "path")
	local filename = text(args.filename or string.match(path, "[^/]+$"), "filename")
	assert(#filename <= 299 and not string.find(filename, "[\r\n]"), "filename must be at most 299 bytes without newlines")
	local contentType = text(args.contentType or "application/octet-stream", "contentType")
	assert(not string.find(contentType, "[\r\n]"), "contentType must not contain newlines")
	args.path, args.filename, args.contentType = nil, nil, nil
	local parts: {MultipartPart} = {}
	if name == "uploadTransactionAttachment" and args.attachmentType ~= nil then
		assert(table.find({"receipt", "bill", "other"}, args.attachmentType), "attachmentType must be receipt, bill or other")
		table.insert(parts, {name = "attachmentType", body = args.attachmentType})
		args.attachmentType = nil
	end
	assert(next(args) == nil, name .. " received an unknown option")
	assert(await(fs.stat(path)).size <= 32 * 1024 * 1024, "Mercury uploads must not exceed 32 MB")
	table.insert(parts, {name = "file", filename = filename, contentType = contentType, body = fs.open(path, "r")})
	return http.multipart(parts)
end

local function request(name: string, endpoint: Endpoint, input: Options?): any
	local args = options(input)
	local path = string.gsub(endpoint.path, "{([%w_]+)}", function(field: string)
		local value = identifier(args[field], field)
		args[field] = nil
		return value
	end)
	assert(not (args.start_after ~= nil and args.end_before ~= nil), "start_after and end_before cannot be combined")
	local query: {string} = {}
	for field, spec in endpoint.query do
		if args[field] ~= nil then
			table.insert(query, encode(field) .. "=" .. queryValue(args[field], field, spec))
			args[field] = nil
		end
	end
	table.sort(query)
	if #query > 0 then path ..= "?" .. table.concat(query, "&") end
	local headers: HttpHeaders = {Accept = {if endpoint.kind == "download" then "application/pdf" else "application/json"}}
	local body: any = nil
	local destination: string? = nil
	if endpoint.kind == "download" then
		destination = text(args.path, "path")
		args.path = nil
		assert(next(args) == nil, name .. " received an unknown option")
	elseif endpoint.kind == "upload" then
		local contentType: string
		body, contentType = uploadBody(name, args)
		headers["Content-Type"] = {contentType}
	elseif endpoint.body then
		for _, field in endpoint.required do
			assert(args[field] ~= nil and args[field] ~= NULL, field .. " is required")
		end
		if args.amount ~= nil then
			assert(type(args.amount) == "number" and args.amount > 0 and args.amount < math.huge, "amount must be a positive finite dollar amount")
		end
		if args.idempotencyKey ~= nil then text(args.idempotencyKey, "idempotencyKey") end
		if name == "createCard" then assert(args.type == "virtual", "Mercury only issues virtual cards through the API") end
		headers["Content-Type"] = {"application/json"}
		body = json.encode(args)
	else
		assert(next(args) == nil, name .. " received an unknown option")
	end
	local origin = if endpoint.vault then "https://vault-api.mercury.com" else "https://api.mercury.com"
	local response = await(http.request({method = endpoint.method, url = origin .. path, headers = headers, body = body}))
	if destination then
		if response.statusCode ~= 200 then fail(name, response) end
		local contentType = response.headers["content-type"]
		local mediaType = if contentType then string.lower(string.match(contentType[1] or "", "^%s*([^;]+)") or "") else ""
		mediaType = string.gsub(mediaType, "%s+$", "")
		if mediaType ~= "application/pdf" then
			response.body:close()
			invalidResponse(name, response.statusCode)
		end
		local file = fs.open(destination, "w")
		file:write(response.body)
		await(file:close())
		return {path = destination, size = await(fs.stat(destination)).size, url = await(fs.signedGetUrl(destination))}
	end
	return responseJSON(name, endpoint, response)
end

local exports: {[string]: any} = {}
for name, endpoint in endpoints do
	if (not endpoint.write or config.access == "read-write") and (not endpoint.vault or config.reveal_card_details == true) then
		exports[name] = function(args: Options?): any return request(name, endpoint, args) end
	end
end
exports.help = function(): string
	local names: {string} = {}
	for name in exports do if name ~= "help" then table.insert(names, name) end end
	table.sort(names)
	local lines = {
		"Mercury API v1. Each function takes one named options object with Mercury's native field names; ? marks optional fields. Path and query options are removed from the JSON body; remaining body fields, nested objects, nulls and arrays pass through unchanged. Responses preserve all native fields. Empty successful mutations return {success=true}.",
		"getAccounts() returns accounts with currentBalance and availableBalance in dollars; getTreasury() and listCredit() return separate account types. Do not sum accounts of different kinds without checking what their balances represent.",
		"getSafeRequests() returns an array, not an envelope. getSafeRequest({safeRequestId=...}) includes signedByInvestorAt, signedByOwnerAt, paidAt, canceledAt and expiresAt. Missing/null timestamps do not imply completion. There is no synthetic SAFE status and no documented SAFE creation, editing or signing endpoint. getSafeRequestDocument({safeRequestId=...,path='safe.pdf'}) downloads the PDF.",
		"Lists fetch one page only. For cursor lists pass response.page.nextPage as start_after until absent; end_before navigates backwards and cannot be combined with start_after. getTreasuryTransactions uses response.cursor as opts.cursor; listAccountTransactions uses offset/limit and total. getSafeRequests, getAccountCards, listCredit and listInvoiceAttachments are unpaginated. Limits and query enums follow the linked API reference; most limits are 1..1000.",
		"Pass json.decode('null') to clear nullable body fields and json.decode('[]') for empty arrays. updateTransaction({transactionId=...,note=json.decode('null'),categoryId=json.decode('null')}) clears metadata. Amounts are dollars, not cents. Never invent idempotencyKey: supply and retain one unique key per intended payment/transfer; reuse it only for the same intended request after checking its outcome.",
		"Writes are omitted on read-only connections. Mercury token scopes, account eligibility, IP allowlists and approval policies also apply. createTransaction and createInternalTransfer move money; requestSendMoney and requestTransferMoney create approval requests. There are no API approval/denial operations. verifyWebhook sends an external test event; recipient invites and invoices can send email according to their body options. No automatic retries, paging or polling; after an ambiguous write failure inspect Mercury before repeating it. 429/5xx errors include retryability and Retry-After when provided.",
		"PDF downloads stream to a session file and return {path,url,size}; url is Houston's signed download URL. Failed transfers can leave partial files. Uploads stream a session file as multipart, with optional filename/contentType; maximum 32 MB and filename 299 bytes. uploadTransactionAttachment accepts attachmentType receipt/bill/other. getAttachment and listInvoiceAttachments return expiring signed attachment URLs; fetch a fresh URL before using it. Arbitrary external downloads are not connector operations.",
		"Cards can be issued only as virtual cards for existing users; physical issuance and user creation use the Mercury dashboard. revealCardPan appears only when Allow revealing agent card numbers and CVCs is enabled; it uses Mercury's dedicated Vault host and only supports agent cards. Its response and webhook signing secrets are sensitive: do not log or save them in shared actions or memories.",
		"Connect using a Mercury API token; Houston injects it privately. OAuth client onboarding requires Mercury approval and is not part of this token connector. Complete nested request schemas, feature eligibility and response definitions are in each operation's reference link.",
	}
	for _, name in names do table.insert(lines, name .. "(opts): " .. endpoints[name].help) end
	return table.concat(lines, "\n")
end
return exports
