-- Dolibarr REST API (Dolibarr 16 to 24). Arguments and results keep Dolibarr's native field names.
type Options = {[string]: any}
type Endpoint = {name: string, method: string?, path: string, list: {string}?, query: {string}?, required: {string}?,
	fields: string?, returns: string?}

local HOST = string.lower(config.host)
local DOCS = "https://wiki.dolibarr.org/index.php/Module_Web_Services_API_REST_(developer)"
local NONE: Options = table.freeze({})
local EMPTY: {string} = table.freeze({})
local MAX_ID = 9007199254740991

-- The install path is the part of the address before /index.php, such as /dolibarr;
-- the proxy allows at most two folders. An invalid path fails each call, not help().
local function base(raw: string?): string?
	local text = string.gsub(string.gsub(raw or "", "^%s+", ""), "%s+$", "")
	text = string.gsub(string.gsub(string.gsub(text, "/index%.php$", ""), "^/+", ""), "/+$", "")
	local segments: {string} = {}
	for segment in string.gmatch(text, "[^/]+") do
		if not string.match(segment, "^[%w%-_.~]+$") or string.match(segment, "^%.+$") then return nil end
		table.insert(segments, segment)
	end
	if #segments > 2 then return nil end
	return "https://" .. HOST .. (if #segments > 0 then "/" .. table.concat(segments, "/") else "") .. "/api/index.php"
end
local API = base(config.install_path)

-- Endpoints read on every connection; list endpoints page with PAGE plus their own options.
local PAGE = {"sortfield", "sortorder", "limit", "page", "sqlfilters", "properties"}
local READS: {Endpoint} = {
	{name = "getStatus", path = "/status", returns = "{success: {code, dolibarr_version, ...}}"},
	{name = "listThirdparties", path = "/thirdparties", list = {"mode", "category"}},
	{name = "getThirdparty", path = "/thirdparties/{id}"},
	{name = "listContacts", path = "/contacts", list = {"thirdparty_ids", "category"}},
	{name = "getContact", path = "/contacts/{id}"},
	{name = "listProducts", path = "/products", list = {"mode", "category", "includestockdata"}},
	{name = "getProduct", path = "/products/{id}", query = {"includestockdata"}},
	{name = "getProductStock", path = "/products/{id}/stock", query = {"selected_warehouse_id"},
		returns = "{stock_reel, stock_theorique, stock_warehouses: {[warehouseID]: {real, ...}}}"},
	{name = "listWarehouses", path = "/warehouses", list = {"category"}},
	{name = "getWarehouse", path = "/warehouses/{id}"},
	{name = "listStockMovements", path = "/stockmovements", list = {}},
	{name = "listCategories", path = "/categories", list = {"type"}},
	{name = "getCategory", path = "/categories/{id}"},
	{name = "listOrders", path = "/orders", list = {"thirdparty_ids", "sqlfilterlines"}},
	{name = "getOrder", path = "/orders/{id}"},
	{name = "listInvoices", path = "/invoices", list = {"thirdparty_ids", "status"}},
	{name = "getInvoice", path = "/invoices/{id}"},
	{name = "listInvoicePayments", path = "/invoices/{id}/payments", returns = "[{amount, date, num, ref, type, ...}]"},
	{name = "listProposals", path = "/proposals", list = {"thirdparty_ids"}},
	{name = "getProposal", path = "/proposals/{id}"},
	{name = "listShipments", path = "/shipments", list = {"thirdparty_ids"}},
	{name = "getShipment", path = "/shipments/{id}"},
	{name = "listSupplierOrders", path = "/supplierorders", list = {"thirdparty_ids", "status"}},
	{name = "getSupplierOrder", path = "/supplierorders/{id}"},
	{name = "listSupplierInvoices", path = "/supplierinvoices", list = {"thirdparty_ids", "status"}},
	{name = "getSupplierInvoice", path = "/supplierinvoices/{id}"},
	{name = "listSupplierInvoicePayments", path = "/supplierinvoices/{id}/payments", returns = "[{amount, date, num, ref, type, ...}]"},
	{name = "listBankAccounts", path = "/bankaccounts", list = {"category"}},
	{name = "getBankAccount", path = "/bankaccounts/{id}"},
	{name = "listBankAccountLines", path = "/bankaccounts/{id}/lines", query = {"sqlfilters"}, required = {"sqlfilters"},
		returns = "[line]"},
	{name = "getBankAccountBalance", path = "/bankaccounts/{id}/balance", returns = "number"},
	{name = "listPaymentTypes", path = "/setup/dictionary/payment_types", list = {}},
}
-- Endpoints read-write connections add. A POST create answers with the new record's ID.
local WRITES: {Endpoint} = {
	{name = "createThirdparty", method = "POST", path = "/thirdparties", fields = "required", required = {"name"}, returns = "id"},
	{name = "updateThirdparty", method = "PUT", path = "/thirdparties/{id}", fields = "required"},
	{name = "createContact", method = "POST", path = "/contacts", fields = "required", required = {"lastname"}, returns = "id"},
	{name = "updateContact", method = "PUT", path = "/contacts/{id}", fields = "required"},
	{name = "createProduct", method = "POST", path = "/products", fields = "required", required = {"ref", "label"}, returns = "id"},
	{name = "updateProduct", method = "PUT", path = "/products/{id}", fields = "required"},
	{name = "createStockMovement", method = "POST", path = "/stockmovements", fields = "required",
		required = {"product_id", "warehouse_id", "qty"}, returns = "id"},
	{name = "createOrder", method = "POST", path = "/orders", fields = "required", required = {"socid", "date"}, returns = "id"},
	{name = "addOrderLine", method = "POST", path = "/orders/{id}/lines", fields = "required", returns = "lineID"},
	{name = "validateOrder", method = "POST", path = "/orders/{id}/validate", fields = "optional"},
	{name = "closeOrder", method = "POST", path = "/orders/{id}/close", fields = "optional"},
	{name = "createInvoice", method = "POST", path = "/invoices", fields = "required", required = {"socid"}, returns = "id"},
	{name = "createInvoiceFromOrder", method = "POST", path = "/invoices/createfromorder/{id}"},
	{name = "addInvoiceLine", method = "POST", path = "/invoices/{id}/lines", fields = "required", returns = "lineID"},
	{name = "validateInvoice", method = "POST", path = "/invoices/{id}/validate", fields = "optional"},
	{name = "addInvoicePayment", method = "POST", path = "/invoices/{id}/payments", fields = "required",
		required = {"datepaye", "paymentid", "closepaidinvoices", "accountid"}, returns = "paymentID"},
}

-- Dolibarr strips these from user records; the connector also drops them anywhere else.
local SECRET = {api_key = true, pass = true, pass_crypted = true, pass_indatabase = true,
	pass_indatabase_crypted = true, pass_temp = true, clicktodial_password = true}

-- Dolibarr returns IDs as strings, so digit strings are accepted too.
local function id(value: any, name: string): string
	local valid = if type(value) == "number" then value >= 1 and value <= MAX_ID and value % 1 == 0
		else type(value) == "string" and #value <= 16 and string.match(value, "^[1-9]%d*$") ~= nil and (tonumber(value) or math.huge) <= MAX_ID
	assert(valid, name .. " must be a positive integer ID")
	return if type(value) == "number" then string.format("%d", value) else value
end

local function integer(value: any, name: string, min: number, max: number): string
	assert(type(value) == "number" and value % 1 == 0 and value >= min and value <= max,
		name .. " must be an integer from " .. min .. " to " .. max)
	return string.format("%d", value)
end

local function text(value: any, name: string, pattern: string): string
	assert(type(value) == "string" and #value <= 4000 and string.match(value, pattern), name .. " is not valid")
	return value
end

local function array(value: any, name: string): {any}
	assert(type(value) == "table" and #value > 0, name .. " must be a nonempty array")
	local count = 0
	for _ in value do count += 1 end
	assert(count == #value, name .. " must be an array")
	return value
end

local FIELD = "^[%a_][%w_]*$"
-- Each option's query value. Restler reads http_method, and Dolibarr DOLAPIKEY, from any
-- query string, so queries are only ever built from these closed option names.
local ENCODE: {[string]: (any, string) -> string} = {
	sortfield = function(value, name)
		assert(type(value) == "string" and (string.match(value, FIELD) or string.match(value, "^[%a_][%w_]*%.[%a_][%w_]*$")),
			name .. " must be a column such as t.rowid")
		return value
	end,
	sortorder = function(value, name)
		assert(value == "ASC" or value == "DESC", name .. " must be ASC or DESC")
		return value
	end,
	limit = function(value, name) return integer(value, name, 1, 200) end,
	page = function(value, name) return integer(value, name, 0, MAX_ID) end,
	sqlfilters = function(value, name) return text(value, name, "%S") end,
	sqlfilterlines = function(value, name) return text(value, name, "%S") end,
	properties = function(value, name)
		local names: {string} = {}
		for _, item in array(value, name) do table.insert(names, text(item, name, FIELD)) end
		return table.concat(names, ",")
	end,
	thirdparty_ids = function(value, name)
		local ids: {string} = {}
		local items: {any} = if type(value) == "table" then array(value, name) else {value}
		for _, item in items do table.insert(ids, id(item, name)) end
		return table.concat(ids, ",")
	end,
	mode = function(value, name) return integer(value, name, 0, 4) end,
	category = id,
	selected_warehouse_id = id,
	status = function(value, name) return text(value, name, "^[%w_,]+$") end,
	type = function(value, name) return text(value, name, FIELD) end,
	includestockdata = function(value, name)
		assert(type(value) == "boolean", name .. " must be a boolean")
		return if value then "1" else "0"
	end,
}

local function optionNames(endpoint: Endpoint): {string}
	local names: {string} = {}
	local groups: {{string}} = {if endpoint.list then PAGE else EMPTY, endpoint.list or EMPTY, endpoint.query or EMPTY}
	for _, group in groups do
		for _, name in group do table.insert(names, name) end
	end
	return names
end

local function query(endpoint: Endpoint, input: any): string
	if input ~= nil then assert(type(input) == "table", "opts must be an object") end
	local opts: Options = input or NONE
	local allowed: {[string]: boolean} = {}
	for _, name in optionNames(endpoint) do allowed[name] = true end
	local keys: {string} = {}
	for key in opts do
		assert(type(key) == "string" and allowed[key], tostring(key) .. " is not a supported option")
		table.insert(keys, key)
	end
	-- required names fields for writes and options for reads.
	if not endpoint.fields then
		for _, name in endpoint.required or EMPTY do assert(opts[name] ~= nil, name .. " is required") end
	end
	-- Dolibarr returns the whole table for limit=0, so lists always send a limit.
	if endpoint.list then
		if opts.limit == nil then table.insert(keys, "limit") end
		if opts.page == nil then table.insert(keys, "page") end
	end
	table.sort(keys)
	local parts: {string} = {}
	for _, key in keys do
		local value = opts[key]
		if value == nil then value = if key == "limit" then 100 else 0 end
		table.insert(parts, key .. "=" .. url.encode(ENCODE[key](value, key)))
	end
	return if #parts > 0 then "?" .. table.concat(parts, "&") else ""
end

-- Fields become the JSON body unchanged, so they must be a JSON object.
local function body(endpoint: Endpoint, input: any): string?
	if not endpoint.fields then return nil end
	if input == nil and endpoint.fields == "optional" then return "{}" end
	assert(type(input) == "table" and #input == 0, "fields must be an object")
	local count = 0
	for key in input do
		assert(type(key) == "string", "fields must be an object")
		count += 1
	end
	assert(count > 0 or endpoint.fields == "optional", "fields must name at least one field")
	assert(input.id == nil, "fields must not contain id")
	for _, name in endpoint.required or EMPTY do assert(input[name] ~= nil, "fields." .. name .. " is required") end
	return json.encode(input)
end

local function header(response: HttpResponse, name: string): string?
	local values = response.headers[name]
	return if values then values[1] else nil
end

-- Web servers and firewalls answer with HTML; keep their visible text.
local function excerpt(raw: string): string
	local value = string.gsub(raw, "<!%-%-(.-)%-%->", " %1 ")
	for _, tag in {"script", "style"} do value = string.gsub(value, "<" .. tag .. "[%s>].-</" .. tag .. ">", " ") end
	value = string.gsub(string.gsub(value, "<[^>]*>", " "), "%s+", " ")
	return string.sub((string.gsub(value, "^ ", "")), 1, 300)
end

-- A write that failed late or answered unreadably may still have been applied.
local SAVED = "; the change may have been saved: read the record before repeating it"

local function envelope(raw: string): any
	local ok, value = pcall(json.decode, raw)
	return if ok and type(value) == "table" and type(value.error) == "table" then value.error else nil
end

local function failure(name: string, response: HttpResponse, raw: string, write: boolean): never
	local status = response.statusCode
	local message = "Dolibarr HTTP " .. tostring(status)
	local err = envelope(raw)
	if err then
		-- Restler adds an exception's details as keys "0", "1"...; debug names source files and is dropped.
		message ..= ": " .. string.sub(tostring(err.message), 1, 600)
		for index = 0, 4 do
			local detail = err[tostring(index)]
			if type(detail) == "string" and detail ~= "" then message ..= "; " .. string.sub(detail, 1, 300) end
		end
	elseif string.match(raw, "%S") then
		message ..= ": " .. excerpt(raw)
	end
	if status == 304 then
		message ..= ". Dolibarr made no change: the record may already be in that state"
	elseif status == 401 then
		message ..= ". Check the API key and that its Dolibarr user is active"
	elseif status == 403 then
		message ..= ". The Dolibarr user of this API key lacks the permission"
	elseif status == 501 then
		message ..= ". The Dolibarr module behind this request may be disabled"
	elseif status == 404 and not err then
		message ..= ". Check the connection's domain and install path: the API must answer at " .. tostring(API)
	end
	local location = header(response, "location")
	if status >= 300 and status < 400 and status ~= 304 and location then
		message ..= "; redirected to " .. string.sub(location, 1, 200) .. ". Set the connection's domain and install path to the final address."
	end
	local retry = header(response, "retry-after")
	if retry then message ..= "; Retry-After: " .. string.sub(retry, 1, 40) end
	if write and status >= 500 then message ..= SAVED end
	return houston.fail({operation = name, layer = "upstream", upstream_status = status,
		retryable = status == 429 or (status >= 500 and status ~= 501 and not write), message = message})
end

local function withhold(value: any)
	if type(value) ~= "table" then return end
	for key, item in value do
		if SECRET[key] then value[key] = nil else withhold(item) end
	end
end

local function call(endpoint: Endpoint, recordID: any, input: any): any
	assert(API, "The connection's install path must be empty or one or two folders, such as /dolibarr or /dolibarr/htdocs")
	local name, method = endpoint.name, endpoint.method or "GET"
	local path = endpoint.path
	if string.find(path, "{id}", 1, true) then path = string.gsub(path, "{id}", id(recordID, "id")) end
	local target = API .. path .. query(endpoint, if endpoint.fields then nil else input)
	local payload = body(endpoint, input)
	local headers: HttpHeaders = {Accept = {"application/json"}}
	if payload then headers["Content-Type"] = {"application/json"} end
	local response = await(http.request({method = method, url = target, headers = headers, body = payload}))
	local write = method ~= "GET"
	if response.statusCode < 200 or response.statusCode >= 300 then
		local raw = await(response.body:readPrefix(16 * 1024))
		-- Before Dolibarr 19 (22 for third parties), an empty list answered 404 "No ... found".
		local err = envelope(raw)
		if response.statusCode == 404 and endpoint.list and err and err.code == 404 then return json.decode("[]") end
		failure(name, response, raw, write)
	end
	local raw = await(response.body:readAll())
	local ok, value = pcall(json.decode, raw)
	if not ok or value == nil then
		-- With the API module disabled, Dolibarr answers HTTP 200 with its login page.
		return houston.fail({operation = name, layer = "upstream", upstream_status = response.statusCode, retryable = false,
			message = "Dolibarr returned a response that is not JSON; check that the API REST module is enabled and answers at "
				.. API .. "/status" .. (if write then SAVED else "")})
	end
	withhold(value)
	return value
end

local exports: {[string]: any} = {}
local signatures: {[string]: string} = {}
local function add(endpoint: Endpoint)
	local names: {string} = {}
	for _, name in optionNames(endpoint) do
		table.insert(names, name .. (if table.find(endpoint.required or EMPTY, name) then "" else "?"))
	end
	local hasID = string.find(endpoint.path, "{id}", 1, true) ~= nil
	local args: {string} = {}
	if hasID then table.insert(args, "id") end
	if endpoint.fields then table.insert(args, if endpoint.fields == "required" then "fields" else "fields?") end
	if #names > 0 then table.insert(args, "{" .. table.concat(names, ", ") .. "}" .. (if endpoint.required then "" else "?")) end
	local returns = endpoint.returns or (if endpoint.list then "[record]" else "record")
	signatures[endpoint.name] = "(" .. table.concat(args, ", ") .. ") -> " .. returns
	-- After the optional ID, an endpoint takes either fields or options.
	exports[endpoint.name] = if hasID then function(recordID: any, input: any): any return call(endpoint, recordID, input) end
		else function(input: any): any return call(endpoint, nil, input) end
end
for _, endpoint in READS do add(endpoint) end
if config.access == "read-write" then
	for _, endpoint in WRITES do add(endpoint) end
end

exports.help = function(): string
	local names: {string} = {}
	for name in signatures do table.insert(names, name) end
	table.sort(names)
	local lines = {
		"Dolibarr REST API for " .. HOST .. ". Results keep Dolibarr's native JSON: records are objects whose IDs and amounts are usually strings (\"id\":\"12\", \"total_ttc\":\"120.00000000\"), dates are Unix timestamps (payment lists use 'YYYY-MM-DD HH:MM:SS'), and lists are arrays, an empty list included. IDs can be passed as numbers or digit strings. Extra fields sit in array_options as options_<code>. Connector calls return completed values: use them directly, without await.",
		"Lists fetch one page: limit (1-200, default 100) and page (from 0); fetch the next page while a page returns limit records. sortfield is a database column with its alias, such as t.rowid, t.ref, t.datec or t.tms, and sortorder ASC or DESC. properties={'id','ref','total_ttc'} returns only those fields (Dolibarr 19+). sqlfilters uses Dolibarr's syntax on database columns, not JSON names: \"(t.ref:like:'FA26%') and (t.fk_soc:=:12)\", with operators = != < > <= >= like notlike in notin is isnot, quoted strings and no parentheses inside values; for example (t.tms:>:'2026-10-01 00:00:00') finds records changed since a date. thirdparty_ids is an ID or an array of IDs. listThirdparties mode: 1 customers, 2 prospects, 3 neither, 4 suppliers; listProducts mode: 1 products, 2 services. listInvoices and listSupplierInvoices status: draft, unpaid, paid or cancelled; listSupplierOrders status: draft, validated, approved, running, received_start, received_end, cancelled or refused. listOrders sqlfilterlines filters by line columns, such as (tl.fk_product:=:9).",
		"Examples: listInvoices({status='unpaid', sortfield='t.datef', sortorder='DESC', limit=20}); getInvoice(42); listOrders({sqlfilters=\"(t.ref_ext:=:'PS-1042')\"}); listThirdparties({sqlfilters=\"(t.email:=:'ann@example.com')\"}); listProducts({sqlfilters=\"(t.ref:=:'MUG-01')\", properties={'id','ref','label','price'}}); getProductStock(9); listStockMovements({sqlfilters='(t.fk_product:=:9)', sortorder='DESC'}); listBankAccountLines(1, {sqlfilters=\"(t.dateo:>=:'2026-10-01')\"}).",
		"Customer orders, invoices and proposals link to a third party through socid (fk_soc in sqlfilters) and carry their lines. Statuses (status, statut or fk_statut) are numeric strings: an order is 0 draft, 1 validated, 2 shipping, 3 delivered, -1 cancelled; an invoice 0 draft, 1 unpaid, 2 paid, 3 abandoned. ref_ext holds an external reference such as a shop order ID. listBankAccountLines requires sqlfilters, as Dolibarr returns every matching line at once; getBankAccountBalance needs Dolibarr 21+. The API key's Dolibarr user permissions apply: a missing permission fails with HTTP 403 (401 before Dolibarr 20), a disabled module with HTTP 501, and a missing record with HTTP 404. Errors carry Dolibarr's message.",
	}
	if config.access == "read-write" then
		table.insert(lines, "Writes send fields as a JSON object of Dolibarr field names (see Dolibarr's API explorer for each object); a create returns the new record's ID, so read it back with the matching get, while updates and actions return the record. Updates change only the given fields. Dates are Unix timestamps. createOrder({socid=12, date=1792540800, ref_ext='PS-1042'}) creates a draft order; add lines with addOrderLine(orderID, {fk_product=9, qty=2, subprice='12.50', tva_tx='20'}) or {desc='Shipping', qty=1, subprice='5', tva_tx='20', product_type=1}, then validateOrder(orderID) gives it its reference (pass {idwarehouse=1} when validation moves stock). createInvoiceFromOrder(orderID) returns a draft invoice copied from the order; validateInvoice(id) numbers it, which cannot be undone, and addInvoicePayment(id, {datepaye=1792540800, paymentid=<listPaymentTypes id>, accountid=<bank account id>, closepaidinvoices='yes'}) records a payment of the whole remaining amount. createStockMovement({product_id=9, warehouse_id=1, qty=-2, label='Shop order PS-1042'}) moves stock (negative qty removes it). Validation and closing may run Dolibarr's workflows and notifications; they answer HTTP 304 when the record is already in that state. Only HTTP 429 is retried: after a timeout or 5xx, read the record before repeating a write.")
	end
	table.insert(lines, "Reference: " .. DOCS .. " and the API explorer at <your Dolibarr>/api/index.php/explorer.")
	for _, name in names do table.insert(lines, name .. signatures[name]) end
	return table.concat(lines, "\n")
end
return exports
