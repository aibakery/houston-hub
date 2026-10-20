-- PrestaShop Webservice API (PrestaShop 1.7, 8 and 9). Arguments and results keep PrestaShop's native field names.
type Options = {[string]: any}

local STORE = string.lower(config.store_host)
local API = "https://" .. STORE .. "/api/"
local DOCS = "https://devdocs.prestashop-project.org/9/webservice/resources/"
local NONE: Options = table.freeze({})

-- Each resource's singular and plural JSON nodes; the plural is also its path,
-- except for order_slip.
local NODES = {
	{"address", "addresses"}, {"carrier", "carriers"}, {"cart", "carts"}, {"cart_rule", "cart_rules"},
	{"category", "categories"}, {"combination", "combinations"}, {"country", "countries"},
	{"currency", "currencies"}, {"customer", "customers"}, {"language", "languages"},
	{"manufacturer", "manufacturers"}, {"order", "orders"}, {"order_carrier", "order_carriers"},
	{"order_detail", "order_details"}, {"order_history", "order_histories"}, {"order_invoice", "order_invoices"},
	{"order_payment", "order_payments"}, {"order_slip", "order_slips", "order_slip"}, {"order_state", "order_states"},
	{"product", "products"}, {"stock_available", "stock_availables"}, {"supplier", "suppliers"},
}
local WRITES: {[string]: {string}} = {
	create = {"customer", "order_history", "product"},
	update = {"customer", "order_carrier", "product", "stock_available"},
	delete = {"customer", "product"},
}
-- Only these resources email customers, when sendemail is set.
local SENDS_EMAIL = {createOrderHistory = true, updateOrderCarrier = true}

-- Password hashes, reset tokens and the guest order-tracking key never leave the
-- connector, and cannot be filtered or sorted on, which would reveal them.
local SECRET = {passwd = true, secure_key = true, reset_password_token = true,
	reset_password_validity = true, last_passwd_gen = true}

local function camel(node: string): string
	return (string.gsub("_" .. node, "_(%a)", string.upper))
end

local function field(value: any, name: string): string
	assert(type(value) == "string" and string.match(value, "^[%a_][%w_]*$"), name .. " must be a PrestaShop field name")
	return value
end

local function readable(value: any, name: string): string
	assert(not SECRET[field(value, name)], value .. " is withheld by the connector")
	return value
end

local function id(value: any, name: string): string
	assert(type(value) == "number" and value >= 1 and value % 1 == 0 and value <= 9007199254740991, name .. " must be a positive integer ID")
	return string.format("%d", value)
end

local function integer(value: any, name: string, min: number, max: number): number
	assert(type(value) == "number" and value % 1 == 0 and value >= min and value <= max,
		name .. " must be an integer from " .. min .. " to " .. max)
	return value
end

-- PrestaShop reads ps_method (the HTTP method) and url (the resource) from any query
-- string, overriding the request and the proxy's path rules. Every query is built
-- from these closed option lists, so callers can never add a parameter.
local function options(input: any, allowed: {[string]: boolean}): Options
	if input == nil then return NONE end
	assert(type(input) == "table", "opts must be an object")
	for key in input do
		assert(type(key) == "string" and allowed[key], tostring(key) .. " is not a supported option")
	end
	return input
end

local function scalar(value: any, name: string): string
	local kind = type(value)
	if kind == "boolean" then return if value then "1" else "0" end
	if kind == "number" then
		return if value % 1 == 0 and math.abs(value) <= 9007199254740991 then string.format("%d", value) else tostring(value)
	end
	assert(kind == "string", name .. " must be a string, number or boolean")
	return value
end

local function list(value: any, name: string): {any}
	assert(type(value) == "table" and #value > 0, name .. " must be a nonempty array")
	local count = 0
	for _ in value do count += 1 end
	assert(count == #value, name .. " must be an array")
	return value
end

-- Filters take PrestaShop's syntax as a string, such as ">[10]" or "%[mug]%";
-- a number or an array of numbers and strings matches those exact values.
local function filterValue(value: any, name: string): string
	if type(value) == "string" then
		assert(value ~= "", name .. " must be nonempty")
		return value
	end
	if type(value) == "table" then
		local values: {string} = {}
		for _, item in list(value, name) do table.insert(values, scalar(item, name)) end
		return "[" .. table.concat(values, "|") .. "]"
	end
	return "[" .. scalar(value, name) .. "]"
end

local function shop(opts: Options, parts: {string})
	if opts.language ~= nil then table.insert(parts, "language=" .. id(opts.language, "language")) end
	if opts.id_shop ~= nil then
		table.insert(parts, "id_shop=" .. (if opts.id_shop == "all" then "all" else id(opts.id_shop, "id_shop")))
	end
end

local LIST_OPTIONS = {display = true, filter = true, sort = true, limit = true, offset = true, language = true, id_shop = true, schema = true}
local function listQuery(input: any): string
	local opts = options(input, LIST_OPTIONS)
	local parts: {string} = {}
	if opts.schema ~= nil then
		assert(opts.schema == "blank" or opts.schema == "synopsis", "schema must be blank or synopsis")
		assert(opts.display == nil and opts.filter == nil and opts.sort == nil and opts.limit == nil and opts.offset == nil,
			"schema takes no display, filter, sort, limit or offset")
		table.insert(parts, "schema=" .. opts.schema)
		shop(opts, parts)
		return table.concat(parts, "&")
	end
	local display = opts.display or "full"
	if display ~= "full" then
		local fields: {string} = {}
		for _, name in list(display, "display") do table.insert(fields, readable(name, "display")) end
		display = url.encode("[" .. table.concat(fields, ",") .. "]")
	end
	table.insert(parts, "display=" .. display)
	local dates = false
	if opts.filter ~= nil then
		assert(type(opts.filter) == "table", "filter must be an object")
		local names: {string} = {}
		for name in opts.filter do table.insert(names, readable(name, "filter")) end
		assert(#names > 0, "filter must name at least one field")
		table.sort(names)
		for _, name in names do
			dates = dates or name == "date_add" or name == "date_upd"
			table.insert(parts, url.encode("filter[" .. name .. "]") .. "=" .. url.encode(filterValue(opts.filter[name], "filter." .. name)))
		end
	end
	if opts.sort ~= nil then
		local sorts: {string} = {}
		local given: {any} = if type(opts.sort) == "string" then {opts.sort} else list(opts.sort, "sort")
		for _, sort in given do
			local name = type(sort) == "string" and (string.match(sort, "^(.+)_ASC$") or string.match(sort, "^(.+)_DESC$"))
			assert(name, "sort must be field_ASC or field_DESC, or an array of those")
			readable(name, "sort")
			dates = dates or name == "date_add" or name == "date_upd"
			table.insert(sorts, sort)
		end
		table.insert(parts, "sort=" .. url.encode("[" .. table.concat(sorts, ",") .. "]"))
	end
	local offset = integer(if opts.offset == nil then 0 else opts.offset, "offset", 0, 9007199254740991)
	local limit = integer(if opts.limit == nil then 50 else opts.limit, "limit", 1, 1000)
	table.insert(parts, "limit=" .. string.format("%d", offset) .. "%2C" .. string.format("%d", limit))
	if dates then table.insert(parts, "date=1") end
	shop(opts, parts)
	return table.concat(parts, "&")
end

local function escape(value: string): string
	return (string.gsub(value, "[&<>\"]", {["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;", ['"'] = "&quot;"}))
end

-- A field is a scalar, or a translated value as [{id = languageID, value}];
-- associations map names to arrays of objects, such as {categories = {{id = 2}}}.
local function element(name: string, value: any): string
	if type(value) ~= "table" then return "<" .. name .. ">" .. escape(scalar(value, name)) .. "</" .. name .. ">" end
	local languages: {string} = {}
	for _, item in list(value, name) do
		assert(type(item) == "table" and item.value ~= nil, name .. " must be a scalar or an array of {id, value}")
		table.insert(languages, '<language id="' .. id(item.id, name .. ".id") .. '">' .. escape(scalar(item.value, name)) .. "</language>")
	end
	return "<" .. name .. ">" .. table.concat(languages) .. "</" .. name .. ">"
end

local function sortedKeys(value: Options, name: string): {string}
	local keys: {string} = {}
	for key in value do table.insert(keys, field(key, name)) end
	table.sort(keys)
	return keys
end

local function xml(node: string, recordID: string?, fields: any): string
	assert(type(fields) == "table", "fields must be an object")
	assert(fields.id == nil, "fields must not contain id; pass the ID as the first argument")
	local parts = {"<?xml version=\"1.0\" encoding=\"UTF-8\"?><prestashop><" .. node .. ">"}
	if recordID then table.insert(parts, "<id>" .. recordID .. "</id>") end
	for _, name in sortedKeys(fields, "fields") do
		local value = fields[name]
		if name == "associations" then
			assert(type(value) == "table", "associations must be an object")
			table.insert(parts, "<associations>")
			for _, association in sortedKeys(value, "associations") do
				table.insert(parts, "<" .. association .. ">")
				for _, item in list(value[association], "associations." .. association) do
					assert(type(item) == "table", "associations." .. association .. " must contain objects")
					table.insert(parts, "<item>")
					for _, key in sortedKeys(item, "associations." .. association) do table.insert(parts, element(key, item[key])) end
					table.insert(parts, "</item>")
				end
				table.insert(parts, "</" .. association .. ">")
			end
			table.insert(parts, "</associations>")
		else
			table.insert(parts, element(name, value))
		end
	end
	table.insert(parts, "</" .. node .. "></prestashop>")
	return table.concat(parts)
end

local function header(response: HttpResponse, name: string): string?
	local values = response.headers[name]
	return if values then values[1] else nil
end

local function failStatus(name: string, response: HttpResponse): never
	local message = "PrestaShop HTTP " .. tostring(response.statusCode)
	local raw = await(response.body:readPrefix(16 * 1024))
	local ok, value = pcall(json.decode, raw)
	if ok and type(value) == "table" and type(value.errors) == "table" then
		for index, item in value.errors do
			if index > 5 then break end
			if type(item) == "table" then
				message ..= " [" .. tostring(item.code) .. "] " .. string.sub(tostring(item.message), 1, 600)
			end
		end
	elseif string.match(raw, "%S") then
		local text = string.gsub(string.gsub(string.gsub(raw, "<!%-%-(.-)%-%->", " %1 "), "<[^>]*>", " "), "%s+", " ")
		message ..= ": " .. string.sub((string.gsub(text, "^ ", "")), 1, 300)
	end
	if response.statusCode == 401 and string.match(raw, "^%s*401 Unauthorized%s*$") then
		message ..= ". PrestaShop received no key: the web server may drop the Authorization header"
	end
	local location = header(response, "location")
	if response.statusCode >= 300 and response.statusCode < 400 and location then
		message ..= "; redirected to " .. string.sub(location, 1, 200) .. ". Set the connection's store domain to the final host."
	end
	local retry = header(response, "retry-after")
	if retry then message ..= "; Retry-After: " .. string.sub(retry, 1, 40) end
	return houston.fail({operation = name, layer = "upstream", upstream_status = response.statusCode,
		retryable = response.statusCode == 429 or response.statusCode >= 500, message = message})
end

local function withhold(value: any)
	if type(value) ~= "table" then return end
	for key, item in value do
		if SECRET[key] then value[key] = nil else withhold(item) end
	end
end

local function request(name: string, method: string, path: string, query: string, body: string?): any
	local headers: HttpHeaders = {Accept = {"application/json"}, ["Output-Format"] = {"JSON"}}
	if body then headers["Content-Type"] = {"application/xml"} end
	local target = API .. path .. (if query ~= "" then "?" .. query else "")
	local response = await(http.request({method = method, url = target, headers = headers, body = body}))
	if response.statusCode < 200 or response.statusCode >= 300 then failStatus(name, response) end
	local raw = await(response.body:readAll())
	if method == "DELETE" and not string.match(raw, "%S") then return true end
	local ok, value = pcall(json.decode, raw)
	if not ok or type(value) ~= "table" then
		return houston.fail({operation = name, layer = "upstream", upstream_status = response.statusCode, retryable = false,
			message = "PrestaShop returned a response that is not JSON; check that the webservice is enabled and served at https://" .. STORE .. "/api"})
	end
	withhold(value)
	return value
end

local GET_OPTIONS = {language = true, id_shop = true}
local exports: {[string]: any} = {}
local signatures: {[string]: string} = {}
local resources: {[string]: {string}} = {}
for _, nodes in NODES do
	local one, many, path = nodes[1], nodes[2], nodes[3] or nodes[2]
	resources[one] = {one, many, path}
	local listName, getName = "list" .. camel(many), "get" .. camel(one)
	exports[listName] = function(opts: Options?): any
		local value = request(listName, "GET", path, listQuery(opts), nil)
		-- PrestaShop answers an empty list with [] instead of its usual wrapper.
		if next(value) == nil then return {[many] = json.decode("[]")} end
		return value
	end
	exports[getName] = function(recordID: number, opts: Options?): any
		local segment = id(recordID, "id")
		local parts: {string} = {}
		shop(options(opts, GET_OPTIONS), parts)
		return request(getName, "GET", path .. "/" .. segment, table.concat(parts, "&"), nil)
	end
	signatures[listName] = "({display?, filter?, sort?, limit?, offset?, language?, id_shop?, schema?}?) -> {" .. many .. ": [...]}"
	signatures[getName] = "(id, {language?, id_shop?}?) -> {" .. one .. ": {...}}"
end

if config.access == "read-write" then
	for verb, nodes in WRITES do
		for _, node in nodes do
			local one, path = resources[node][1], resources[node][3]
			local name = verb .. camel(one)
			local allowed = {id_shop = true, sendemail = SENDS_EMAIL[name]}
			local function query(input: Options?): string
				local opts = options(input, allowed)
				local parts: {string} = {}
				shop(opts, parts)
				if opts.sendemail ~= nil then
					assert(type(opts.sendemail) == "boolean", "sendemail must be a boolean")
					if opts.sendemail then table.insert(parts, "sendemail=1") end
				end
				return table.concat(parts, "&")
			end
			local email = if SENDS_EMAIL[name] then ", sendemail?" else ""
			if verb == "create" then
				exports[name] = function(fields: Options, opts: Options?): any
					local q = query(opts)
					return request(name, "POST", path, q, xml(one, nil, fields))
				end
				signatures[name] = "(fields, {id_shop?" .. email .. "}?) -> {" .. one .. ": {...}}"
			elseif verb == "update" then
				exports[name] = function(recordID: number, fields: Options, opts: Options?): any
					local segment, q = id(recordID, "id"), query(opts)
					return request(name, "PATCH", path .. "/" .. segment, q, xml(one, segment, fields))
				end
				signatures[name] = "(id, fields, {id_shop?" .. email .. "}?) -> {" .. one .. ": {...}}"
			else
				exports[name] = function(recordID: number, opts: Options?): any
					local segment, q = id(recordID, "id"), query(opts)
					return request(name, "DELETE", path .. "/" .. segment, q, nil)
				end
				signatures[name] = "(id, {id_shop?}?) -> true"
			end
		end
	end
end

exports.help = function(): string
	local names: {string} = {}
	for name in signatures do table.insert(names, name) end
	table.sort(names)
	local lines = {
		"PrestaShop Webservice API for " .. STORE .. ". Results keep PrestaShop's native snake_case fields and wrappers: lists return {<plural>: [...]}, an empty list included, and get returns {<singular>: {...}}. PrestaShop sends every value as a string, translated fields as [{id, value}] per language unless language=<id> is passed, and links under associations. Password hashes, reset tokens and secure_key are removed from results and cannot be filtered on. Connector calls return completed values: use them directly, without await.",
		"Lists fetch one page with every field (display='full'): pass limit (1-1000, default 50) and offset (default 0), and fetch the next offset while a page returns limit records; PrestaShop gives no total. display={'id','reference'} returns only those fields. filter maps a field to a value: a number or array matches exactly ({current_state={2,3}}), and a string uses PrestaShop's syntax: '[v]' equal, '[a|b]' either, '[1,10]' between, '>[v]', '<[v]', '![v]' not, '[mug]%' starts with, '%[mug]%' contains. Dates are 'YYYY-MM-DD HH:MM:SS' in the store's time zone, for example filter={date_upd='>[2026-10-01 00:00:00]'}. sort is 'field_ASC', 'field_DESC' or an array of those. language and id_shop (an ID, or 'all') pick a language and a multistore shop; the default shop is used otherwise. schema='synopsis' returns a resource's fields, formats and required flags instead of records, and schema='blank' an empty record.",
		"Examples: listOrders({filter={current_state=2}, sort='date_add_DESC', limit=20}); getOrder(123); listOrderDetails({filter={id_order=123}}); listOrderHistories({filter={id_order=123}, sort='date_add_DESC'}); listOrderStates({language=1, display={'id','name'}}); listCustomers({filter={email='[ann@example.com]'}}); listProducts({filter={reference='%[MUG]%'}, display={'id','reference','price','name'}, language=1}); listStockAvailables({filter={id_product=9}}).",
		"Orders link to customers, addresses, carts, carriers and currencies through id_* fields; an order's current status is current_state, an order_states ID. The webservice key's own resource and method permissions apply: a resource it does not allow fails with HTTP 401 [26], a method with HTTP 405 [25]. Errors report the HTTP status and PrestaShop's [code] messages; a plain 401 Unauthorized means the key did not reach PrestaShop.",
	}
	if config.access == "read-write" then
		table.insert(lines, "Writes take fields as an object of PrestaShop field names (see schema='synopsis'), sent as PrestaShop's XML; the result is the saved record. Translated fields take [{id=languageID, value='...'}] or one string for every language, associations take arrays of objects such as associations={categories={{id=2}}}, and booleans become 1 or 0. Updates use PATCH and change only the given fields, which needs PrestaShop 8 or later; on PrestaShop 1.7 only creates and deletes work. createProduct needs at least price; createCustomer needs firstname, lastname, email and passwd (the plain password, which PrestaShop hashes). createOrderHistory({id_order=123, id_order_state=4}, {sendemail=true}) changes an order's status, and updateOrderCarrier(id, {tracking_number='1Z...'}, {sendemail=true}) sets its tracking number: sendemail emails the customer. updateStockAvailable(id, {quantity=12}) sets a quantity; find its ID with listStockAvailables({filter={id_product=9, id_product_attribute=0}}). Deleting a product or customer is permanent. Nothing is retried: after a timeout or 5xx, read the record again before repeating a write.")
	end
	table.insert(lines, "Field reference per resource: " .. DOCS .. "<plural>/.")
	for _, name in names do table.insert(lines, name .. signatures[name]) end
	return table.concat(lines, "\n")
end
return exports
