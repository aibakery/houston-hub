-- WooCommerce REST API v3. Native fields, nulls and arrays pass through unchanged.
type Options = {[string]: any}
type Endpoint = {method: string, path: string, doc: string, sensitive: boolean?}

local STORE = string.lower(config.store_host)
local API = "https://" .. STORE .. "/wp-json/wc/v3"
local DOCS = "https://developer.woocommerce.com/docs/apis/rest-api/v3/"

-- WooCommerce resources share one CRUD shape; path placeholders are required parent
-- IDs. Sensitive resources can return payment-gateway credentials, webhook secrets or
-- password settings, so they need read-write access even to read.
local ALL = {"list", "get", "create", "update", "delete", "batch"}
local READ = {"list", "get"}
local RESOURCES = {
	{one = "Order", many = "Orders", path = "/orders", ops = ALL, doc = "orders"},
	{one = "OrderNote", many = "OrderNotes", path = "/orders/{order_id}/notes", ops = {"list", "get", "create", "delete"}, doc = "order-notes"},
	{one = "OrderRefund", many = "OrderRefunds", path = "/orders/{order_id}/refunds", ops = {"list", "get", "create", "delete"}, doc = "order-refunds"},
	{one = "Product", many = "Products", path = "/products", ops = ALL, doc = "products"},
	{one = "ProductVariation", many = "ProductVariations", path = "/products/{product_id}/variations", ops = ALL, doc = "product-variations"},
	{one = "ProductAttribute", many = "ProductAttributes", path = "/products/attributes", ops = ALL, doc = "product-attributes"},
	{one = "ProductAttributeTerm", many = "ProductAttributeTerms", path = "/products/attributes/{attribute_id}/terms", ops = ALL, doc = "product-attribute-terms"},
	{one = "ProductCategory", many = "ProductCategories", path = "/products/categories", ops = ALL, doc = "product-categories"},
	{one = "ProductTag", many = "ProductTags", path = "/products/tags", ops = ALL, doc = "product-tags"},
	{one = "ProductShippingClass", many = "ProductShippingClasses", path = "/products/shipping_classes", ops = ALL, doc = "product-shipping-classes"},
	{one = "ProductReview", many = "ProductReviews", path = "/products/reviews", ops = ALL, doc = "product-reviews"},
	{one = "Customer", many = "Customers", path = "/customers", ops = ALL, doc = "customers"},
	{one = "Coupon", many = "Coupons", path = "/coupons", ops = ALL, doc = "coupons"},
	{one = "TaxRate", many = "TaxRates", path = "/taxes", ops = ALL, doc = "taxes"},
	{one = "TaxClass", many = "TaxClasses", path = "/taxes/classes", ops = {"list", "create", "delete"}, doc = "tax-classes"},
	{one = "ShippingZone", many = "ShippingZones", path = "/shipping/zones", ops = {"list", "get", "create", "update", "delete"}, doc = "shipping-zones"},
	{one = "ShippingZoneMethod", many = "ShippingZoneMethods", path = "/shipping/zones/{zone_id}/methods", ops = {"list", "get", "create", "update", "delete"}, doc = "shipping-zone-methods"},
	{one = "ShippingMethod", many = "ShippingMethods", path = "/shipping_methods", ops = READ, doc = "shipping-methods"},
	{one = "SystemStatusTool", many = "SystemStatusTools", path = "/system_status/tools", ops = READ, doc = "system-status-tools"},
	{one = "Continent", many = "Continents", path = "/data/continents", ops = READ, doc = "data"},
	{one = "Country", many = "Countries", path = "/data/countries", ops = READ, doc = "data"},
	{one = "Currency", many = "Currencies", path = "/data/currencies", ops = READ, doc = "data"},
	{one = "Webhook", many = "Webhooks", path = "/webhooks", ops = ALL, doc = "webhooks", sensitive = true},
	{one = "SettingGroup", many = "SettingGroups", path = "/settings", ops = {"list"}, doc = "settings", sensitive = true},
	{one = "Setting", many = "Settings", path = "/settings/{group_id}", ops = {"list", "get", "update", "batch"}, doc = "setting-options", sensitive = true},
	{one = "PaymentGateway", many = "PaymentGateways", path = "/payment_gateways", ops = {"list", "get", "update"}, doc = "payment-gateways", sensitive = true},
}
local OPERATIONS = {
	list = {many = true, method = "GET", suffix = ""},
	get = {many = false, method = "GET", suffix = "/{id}"},
	create = {many = false, method = "POST", suffix = ""},
	update = {many = false, method = "PUT", suffix = "/{id}"},
	delete = {many = false, method = "DELETE", suffix = "/{id}"},
	batch = {many = true, method = "POST", suffix = "/batch"},
}
local endpoints: {[string]: Endpoint} = {
	listRefunds = {method = "GET", path = "/refunds", doc = "refunds"},
	previewOrderRefund = {method = "POST", path = "/orders/{order_id}/refunds/preview", doc = "order-refunds"},
	listOrderEmailTemplates = {method = "GET", path = "/orders/{order_id}/actions/email_templates", doc = "order-actions"},
	sendOrderEmail = {method = "POST", path = "/orders/{order_id}/actions/send_email", doc = "order-actions"},
	sendOrderDetails = {method = "POST", path = "/orders/{order_id}/actions/send_order_details", doc = "order-actions"},
	duplicateProduct = {method = "POST", path = "/products/{id}/duplicate", doc = "products"},
	listProductCustomFieldNames = {method = "GET", path = "/products/custom-fields/names", doc = "product-custom-fields"},
	listCustomerDownloads = {method = "GET", path = "/customers/{customer_id}/downloads", doc = "customers"},
	listShippingZoneLocations = {method = "GET", path = "/shipping/zones/{zone_id}/locations", doc = "shipping-zone-locations"},
	runSystemStatusTool = {method = "PUT", path = "/system_status/tools/{id}", doc = "system-status-tools"},
	getSystemStatus = {method = "GET", path = "/system_status", doc = "system-status"},
	listReports = {method = "GET", path = "/reports", doc = "reports"},
	getSalesReport = {method = "GET", path = "/reports/sales", doc = "reports"},
	getTopSellersReport = {method = "GET", path = "/reports/top_sellers", doc = "reports"},
	getCouponTotals = {method = "GET", path = "/reports/coupons/totals", doc = "reports"},
	getCustomerTotals = {method = "GET", path = "/reports/customers/totals", doc = "reports"},
	getOrderTotals = {method = "GET", path = "/reports/orders/totals", doc = "reports"},
	getProductTotals = {method = "GET", path = "/reports/products/totals", doc = "reports"},
	getReviewTotals = {method = "GET", path = "/reports/reviews/totals", doc = "reports"},
}
for _, resource in RESOURCES do
	for _, verb in resource.ops do
		local operation = OPERATIONS[verb]
		endpoints[verb .. (if operation.many then resource.many else resource.one)] = {method = operation.method,
			path = resource.path .. operation.suffix, doc = resource.doc, sensitive = resource.sensitive}
	end
end

local function options(input: Options?): Options
	if input == nil then return {} end
	assert(type(input) == "table", "opts must be an object")
	for key in input do assert(type(key) == "string", "opts must have named fields") end
	return table.clone(input)
end

-- WooCommerce IDs are nonnegative integers (shipping zone 0 is "rest of the
-- world"); settings, gateways, tax classes, tools and data use slugs or codes.
local function identifier(value: any, field: string): string
	if type(value) == "number" then
		assert(value >= 0 and value % 1 == 0 and value <= 9007199254740991, field .. " must be a nonnegative integer ID")
		return string.format("%d", value)
	end
	assert(type(value) == "string" and string.match(value, "^[%w_%-]+$"), field .. " must be an ID, slug or code")
	return value
end

-- WordPress reads _method and rest_route from any query string, so they could change
-- a request's method or route, and PHP turns dots and spaces in names into
-- underscores. WooCommerce's own parameters are plain names, plus _fields.
local function queryKey(key: string): string
	assert(key == "_fields" or (string.match(key, "^%a[%w_]*$") and key ~= "rest_route"), key .. " is not a WooCommerce query parameter")
	return key
end

local function scalar(value: any, key: string): string
	local kind = type(value)
	assert(kind == "string" or kind == "boolean" or (kind == "number" and value == value and math.abs(value) < math.huge),
		key .. " must be a string, boolean, finite number or array of those")
	return url.encode(value)
end

-- Arrays use WordPress's key[]=value form; their order is preserved (orderby=include).
local function query(args: Options): string
	local keys: {string} = {}
	for key in args do table.insert(keys, queryKey(key)) end
	table.sort(keys)
	local parts: {string} = {}
	for _, key in keys do
		local value = args[key]
		if type(value) == "table" then
			local count = 0
			for index in value do
				assert(type(index) == "number", key .. " must be an array, not an object")
				count += 1
			end
			assert(count == #value, key .. " must be a dense array")
			for _, item in ipairs(value) do table.insert(parts, key .. "%5B%5D=" .. scalar(item, key)) end
		else
			table.insert(parts, key .. "=" .. scalar(value, key))
		end
	end
	return if #parts > 0 then "?" .. table.concat(parts, "&") else ""
end

local function fail(name: string, response: HttpResponse, message: string): never
	return houston.fail({operation = name, layer = "upstream", upstream_status = response.statusCode,
		retryable = response.statusCode == 429 or response.statusCode >= 500, message = message})
end

local function header(response: HttpResponse, name: string): string?
	local values = response.headers[name]
	return if values then values[1] else nil
end

-- Host firewalls answer with HTML pages; keep their visible text and comments, which
-- name the blocking layer.
local function excerpt(raw: string): string
	local text = string.gsub(string.gsub(raw, "<!%-%-(.-)%-%->", " %1 "), "<[^>]*>", " ")
	return string.sub((string.gsub(string.gsub(text, "%s+", " "), "^ ", "")), 1, 300)
end

local function failStatus(name: string, response: HttpResponse): never
	local message = "WooCommerce HTTP " .. tostring(response.statusCode)
	local raw = await(response.body:readPrefix(16 * 1024))
	local ok, value = pcall(json.decode, raw)
	if ok and type(value) == "table" then
		if type(value.code) == "string" then message ..= " (" .. value.code .. ")" end
		if type(value.message) == "string" then message ..= ": " .. string.sub(value.message, 1, 600) end
		if type(value.data) == "table" and type(value.data.params) == "table" then
			message ..= " " .. string.sub(json.encode(value.data.params), 1, 600)
		end
	elseif string.match(raw, "%S") then
		message ..= ": " .. excerpt(raw)
	end
	local server = header(response, "server")
	if server then message ..= "; Server: " .. string.sub(server, 1, 100) end
	local location = header(response, "location")
	if response.statusCode >= 300 and response.statusCode < 400 and location then
		message ..= "; redirected to " .. string.sub(location, 1, 200) .. ". Set the connection's store domain to the final host."
	end
	local retry = header(response, "retry-after")
	if retry then message ..= "; Retry-After: " .. retry end
	return fail(name, response, message)
end

-- JSON arrays become {items, total?, total_pages?}, keeping WordPress's paging headers.
local function decode(name: string, response: HttpResponse): any
	if response.statusCode < 200 or response.statusCode >= 300 then failStatus(name, response) end
	local raw = await(response.body:readAll())
	local ok, value = pcall(json.decode, raw)
	if not ok or type(value) ~= "table" then
		fail(name, response, "WooCommerce returned a response that is not JSON; check that the store domain serves the WordPress REST API at /wp-json")
	end
	if string.match(raw, "^%s*%[") then
		return {items = value, total = tonumber(header(response, "x-wp-total")), total_pages = tonumber(header(response, "x-wp-totalpages"))}
	end
	return value
end

local function request(name: string, endpoint: Endpoint, input: Options?): any
	local args = options(input)
	local path = string.gsub(endpoint.path, "{([%w_]+)}", function(field: string)
		local value = identifier(args[field], field)
		args[field] = nil
		return value
	end)
	local headers: HttpHeaders = {Accept = {"application/json"}}
	local body: string? = nil
	if endpoint.method == "GET" or endpoint.method == "DELETE" then
		path ..= query(args)
	else
		headers["Content-Type"] = {"application/json"}
		body = json.encode(args)
	end
	return decode(name, await(http.request({method = endpoint.method, url = API .. path, headers = headers, body = body})))
end

local function signature(endpoint: Endpoint): string
	local fields: {string} = {}
	for field in string.gmatch(endpoint.path, "{([%w_]+)}") do table.insert(fields, field) end
	if string.sub(endpoint.path, -6) == "/batch" then
		table.insert(fields, "create?, update?, delete?")
	elseif endpoint.method == "GET" or endpoint.method == "DELETE" then
		table.insert(fields, "...query?")
	else
		table.insert(fields, "...fields")
	end
	return "({" .. table.concat(fields, ", ") .. "})"
end

local exports: {[string]: any} = {}
for name, endpoint in endpoints do
	if (endpoint.method == "GET" and not endpoint.sensitive) or config.access == "read-write" then
		exports[name] = function(args: Options?): any return request(name, endpoint, args) end
	end
end
exports.help = function(): string
	local names: {string} = {}
	for name in exports do if name ~= "help" then table.insert(names, name) end end
	table.sort(names)
	local lines = {
		"WooCommerce REST API v3 for " .. STORE .. ". Every function takes one named options object with WooCommerce's snake_case names; ? marks optional fields. Path IDs (id, order_id, product_id, ...) are numbers, or slugs/codes for settings, gateways, tax classes, tools and data. Other options are query parameters on list/get/delete calls (arrays send key[]=value; names are plain WooCommerce parameters or _fields) and the unchanged JSON body on create/update/batch calls. Results keep WooCommerce's native fields and nulls. Connector calls return completed values: use them directly, without await.",
		"JSON array responses return {items, total?, total_pages?}, with totals from X-WP-Total/X-WP-TotalPages when WooCommerce sends them. Lists fetch one page: pass page (1-based) and per_page (1-100, default 10), and continue while page < total_pages. per_page=1 with total counts matches without fetching them. _fields='id,status,total' trims each item. Dates such as after, before and modified_after are ISO 8601 in the store's time zone.",
		"Examples: listOrders({status={'processing','on-hold'}, after='2026-10-01T00:00:00', per_page=50}); getOrder({id=123}); listProducts({search='mug', stock_status='instock', _fields='id,name,price,stock_quantity'}); getSalesReport({period='month'}); updateOrder({id=123, status='completed'}); createOrderNote({order_id=123, note='Shipped', customer_note=true}); runSystemStatusTool({id='clear_transients', confirm=true}).",
		"Read-only connections omit writes and the settings, payment gateway and webhook functions, whose responses can contain payment credentials and webhook secrets; treat those values as sensitive. The API key's own Read/Write permission and its WordPress user's role also apply. Orders, products and coupons move to the trash unless force=true; resources that cannot be trashed require force=true. Batch functions take create/update/delete arrays (100 objects in total by default; batchSettings accepts only update) and report failures per item: check each entry's error. Pass json.decode('[]') for empty arrays and json.decode('null') to clear nullable fields.",
		"Side effects: createOrderRefund refunds through the payment gateway unless api_refund=false, so money moves; previewOrderRefund calculates one without creating it (WooCommerce 11.1+). sendOrderEmail, sendOrderDetails, order status changes and customer notes can email customers. runSystemStatusTool runs maintenance tools, such as clearing caches or regenerating data. Houston retries HTTP 429 at most twice when Retry-After is 5 seconds or less; nothing else is retried: after a timeout or 5xx, read the resource again before repeating a write. A remaining 429 usually comes from the store's host firewall rather than WooCommerce: space calls out and prefer fewer, larger ones, such as one updateProduct with every tag or a batch function, over one call per item. Errors report the HTTP status, WooCommerce code, message, invalid parameters, Retry-After, the Server header and the start of non-JSON bodies; a 401 usually means the key lacks permission or the web server drops the Authorization header.",
		"Each function below names its route and its reference page, " .. DOCS .. "<page>/, which lists fields, filters and response shapes.",
	}
	for _, name in names do
		local endpoint = endpoints[name]
		table.insert(lines, name .. signature(endpoint) .. ": " .. endpoint.method .. " " .. endpoint.path .. " (" .. endpoint.doc .. ")")
	end
	return table.concat(lines, "\n")
end
return exports
