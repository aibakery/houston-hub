-- RevenueCat REST API v2. Arguments and results keep RevenueCat's native snake_case field names.
type Options = {[string]: any}
type Endpoint = {method: string, path: string, query: {string}?, extra: {string}?, required: {string}?, write: boolean?, body: (boolean | string)?,
	fields: {string}?, shape: string?, doc: string, about: string}

local PROVIDER = "RevenueCat"
local API = "https://api.revenuecat.com/v2"
local DOCS = "https://www.revenuecat.com/docs/api-v2/"
local PAGE = {"starting_after", "limit"}

-- Operations in RevenueCat's API v2 reference (https://www.revenuecat.com/docs/api-v2), checked on
-- 2026-10-30. Path {fields} are required; listed query fields are taken from the options and the
-- other fields form the JSON body. Lists answer with one page.
local endpoints: {[string]: Endpoint} = {
	listProjects = {method = "GET", path = "/projects", query = PAGE, shape = "list", doc = "project#operation/list-projects",
		about = "Projects the key reaches, {id, name, created_at, icon_url}; a secret key belongs to one project, so this gives the project_id the other functions take."},
	listApps = {method = "GET", path = "/projects/{project_id}/apps", query = PAGE, shape = "list", doc = "app#operation/list-apps",
		about = "Apps, {id, name, type, created_at} plus the store's details, such as app_store.bundle_id or play_store.package_name. type: app_store, mac_app_store, play_store, amazon, stripe, rc_billing, paddle, roku, test_store and others."},
	getApp = {method = "GET", path = "/projects/{project_id}/apps/{app_id}", doc = "app#operation/get-app", about = "An app by id."},

	listCustomers = {method = "GET", path = "/projects/{project_id}/customers", query = {"search", "starting_after", "limit"}, shape = "customers",
		doc = "customer#operation/list-customers",
		about = "Customers, each trimmed to {id, project_id, first_seen_at, last_seen_at, last_seen_app_version, last_seen_platform, last_seen_platform_version}. search finds a customer by exact $email attribute, app user id, store transaction id or Apple order id; only email searches page."},
	getCustomer = {method = "GET", path = "/projects/{project_id}/customers/{customer_id}", query = {"expand"}, doc = "customer#operation/get-customer",
		about = "A customer by app user id, with last_seen_country, experiment and active_entitlements {items: [{entitlement_id, expires_at}]}. expand='attributes' adds attributes {items: [{name, value, updated_at}]}, such as $email, $displayName and $phoneNumber: personal data, so request it only when needed."},
	listCustomerSubscriptions = {method = "GET", path = "/projects/{project_id}/customers/{customer_id}/subscriptions", query = {"environment", "starting_after", "limit", "expand"},
		shape = "list", doc = "customer/resources#operation/list-subscriptions",
		about = "A customer's subscriptions: {id, product_id, store, status, gives_access, auto_renewal_status, starts_at, current_period_starts_at, current_period_ends_at, ends_at, total_revenue_in_usd, entitlements, environment, store_subscription_identifier, presented_offering_id, management_url}. status: trialing, active, in_grace_period, in_billing_retry, paused, expired, incomplete or unknown. environment: production or sandbox (default both); expand='items.redemption' adds redeemed promo codes."},
	listCustomerPurchases = {method = "GET", path = "/projects/{project_id}/customers/{customer_id}/purchases", query = {"environment", "starting_after", "limit", "expand"},
		shape = "list", doc = "customer/resources#operation/list-purchases",
		about = "A customer's one-time purchases: {id, product_id, store, status, purchased_at, quantity, revenue_in_usd, entitlements, environment, store_purchase_identifier}. environment and expand as for subscriptions."},
	listCustomerActiveEntitlements = {method = "GET", path = "/projects/{project_id}/customers/{customer_id}/active_entitlements", query = PAGE, shape = "list",
		doc = "customer/resources#operation/list-customer-active-entitlements", about = "Entitlements the customer has now, [{entitlement_id, expires_at}]; expires_at is null for lifetime access."},
	getSubscription = {method = "GET", path = "/projects/{project_id}/subscriptions/{subscription_id}", query = {"expand"}, doc = "subscription#operation/get-subscription",
		about = "A subscription by id, as in listCustomerSubscriptions; expand='redemption' adds its promo code."},
	listSubscriptionEntitlements = {method = "GET", path = "/projects/{project_id}/subscriptions/{subscription_id}/entitlements", query = PAGE, shape = "list",
		doc = "subscription#operation/list-subscription-entitlements", about = "The entitlements a subscription unlocks, {id, lookup_key, display_name}."},
	getPurchase = {method = "GET", path = "/projects/{project_id}/purchases/{purchase_id}", query = {"expand"}, doc = "purchase#operation/get-purchase",
		about = "A one-time purchase by id, as in listCustomerPurchases; expand='redemption' adds its promo code."},

	listProducts = {method = "GET", path = "/projects/{project_id}/products", query = {"app_id", "starting_after", "limit", "expand"}, shape = "list",
		doc = "product#operation/list-products",
		about = "Products: {id, store_identifier, type (subscription, one_time, consumable, non_consumable or non_renewing_subscription), state (active, or inactive when archived), display_name, app_id, subscription={duration, trial_duration, grace_period_duration}, created_at}. app_id filters by app; expand: items.app or items.indicative_price."},
	getProduct = {method = "GET", path = "/projects/{project_id}/products/{product_id}", query = {"expand"}, doc = "product#operation/get-product",
		about = "A product by id; expand: app or indicative_price."},
	listEntitlements = {method = "GET", path = "/projects/{project_id}/entitlements", query = {"starting_after", "limit", "expand"}, shape = "list",
		doc = "entitlement#operation/list-entitlements", about = "Entitlements: {id, lookup_key, display_name, state, created_at}; expand='items.product' adds their products."},
	getEntitlement = {method = "GET", path = "/projects/{project_id}/entitlements/{entitlement_id}", query = {"expand"}, doc = "entitlement#operation/get-entitlement",
		about = "An entitlement by id; expand='product' adds its products."},
	listEntitlementProducts = {method = "GET", path = "/projects/{project_id}/entitlements/{entitlement_id}/products", query = PAGE, shape = "list",
		doc = "entitlement#operation/get-products-from-entitlement", about = "The products that unlock an entitlement."},
	listOfferings = {method = "GET", path = "/projects/{project_id}/offerings", query = {"starting_after", "limit", "expand"}, shape = "list",
		doc = "offering#operation/list-offerings",
		about = "Offerings: {id, lookup_key, display_name, is_current, state, metadata, paywall_id, created_at}. expand='items.package' adds their packages, and also 'items.package.product' their products."},
	getOffering = {method = "GET", path = "/projects/{project_id}/offerings/{offering_id}", query = {"expand"}, doc = "offering#operation/get-offering",
		about = "An offering by id; expand: package, or package and package.product."},
	listPackages = {method = "GET", path = "/projects/{project_id}/offerings/{offering_id}/packages", query = {"starting_after", "limit", "expand"}, shape = "list",
		doc = "package#operation/list-packages", about = "An offering's packages: {id, lookup_key, display_name, position, created_at}; expand='items.product' adds their products."},
	getPackage = {method = "GET", path = "/projects/{project_id}/packages/{package_id}", query = {"expand"}, doc = "package#operation/get-package",
		about = "A package by id; expand='product' adds its products."},
	listPackageProducts = {method = "GET", path = "/projects/{project_id}/packages/{package_id}/products", query = PAGE, shape = "list",
		doc = "package#operation/get-products-from-package", about = "A package's products, [{product, eligibility_criteria}]."},
	getOverviewMetrics = {method = "GET", path = "/projects/{project_id}/metrics/overview", query = {"currency"}, doc = "charts-and-metrics#operation/get-overview-metrics",
		about = "The dashboard overview, {currency, metrics: [{id, name, description, unit, period, value, last_updated_at}]}: the dashboard's cards, such as active trials and active subscriptions now (period P0D), and MRR, revenue, new customers and active customers over the last 28 days (P28D). Read each metric's id, name and period rather than assuming them; ids include active_trials, mrr and revenue. currency: USD (default), EUR, GBP, AUD, CAD, JPY, BRL, KRW, CNY, MXN, SEK, PLN, NZD or CHF."},

	grantEntitlement = {method = "POST", path = "/projects/{project_id}/customers/{customer_id}/actions/grant_entitlement", required = {"entitlement_id", "expires_at"},
		fields = {"entitlement_id", "expires_at"}, doc = "customer#operation/grant-customer-entitlement",
		about = "Grants a promotional entitlement until expires_at (ms since epoch, in the future) and returns the customer. RevenueCat ignores a grant expiring within two hours of an existing grant of that entitlement: to extend, grant again with a later expires_at; to shorten, revoke and grant again."},
	revokeGrantedEntitlement = {method = "POST", path = "/projects/{project_id}/customers/{customer_id}/actions/revoke_granted_entitlement", required = {"entitlement_id"},
		fields = {"entitlement_id"}, doc = "customer#operation/revoke-customer-granted-entitlement",
		about = "Ends every promotional grant of the entitlement now and returns the customer. Store purchases are not affected."},
	createOffering = {method = "POST", path = "/projects/{project_id}/offerings", required = {"lookup_key", "display_name"}, fields = {"lookup_key", "display_name", "metadata"},
		doc = "offering#operation/create-offering", about = "Creates an offering, {lookup_key, display_name, metadata?}, and returns it; metadata is a JSON object your app reads."},
	updateOffering = {method = "POST", path = "/projects/{project_id}/offerings/{offering_id}", fields = {"display_name", "is_current", "metadata"},
		doc = "offering#operation/update-offering",
		about = "Changes display_name or metadata, or makes the offering the one apps show by default with is_current=true, and returns it. Apps pick up changes on their next fetch."},
	createPackage = {method = "POST", path = "/projects/{project_id}/offerings/{offering_id}/packages", required = {"lookup_key", "display_name"},
		fields = {"lookup_key", "display_name", "position"}, doc = "package#operation/create-packages",
		about = "Adds a package to an offering, {lookup_key, display_name, position?}, and returns it. lookup_key: a package type such as '$rc_monthly', '$rc_annual' or '$rc_lifetime', or a custom key. Attach products next."},
	updatePackage = {method = "POST", path = "/projects/{project_id}/packages/{package_id}", fields = {"display_name", "position"}, doc = "package#operation/update-package",
		about = "Changes a package's display_name or position (1 or more) and returns it."},
	deletePackage = {method = "DELETE", path = "/projects/{project_id}/packages/{package_id}", doc = "package#operation/delete-package-from-offering",
		about = "Deletes a package from its offering, {object, id, deleted_at}. It can't be undone."},
	attachPackageProducts = {method = "POST", path = "/projects/{project_id}/packages/{package_id}/actions/attach_products", required = {"products"}, fields = {"products"},
		doc = "package#operation/attach-products-to-package",
		about = "Attaches up to 50 products, products=[{product_id, eligibility_criteria}], and returns the package; eligibility_criteria: all, or google_sdk_lt_6 or google_sdk_ge_6 for Play Store products."},
	detachPackageProducts = {method = "POST", path = "/projects/{project_id}/packages/{package_id}/actions/detach_products", required = {"product_ids"}, fields = {"product_ids"},
		doc = "package#operation/detach-products-from-package", about = "Detaches up to 50 products by id and returns the package."},
}

-- Request layer shared verbatim by the endpoint-table connectors
-- (tools/validate checks they match). It uses each connector's PROVIDER, DOCS and Endpoint type.
local NULL = json.decode("null")
local NONE: {string} = table.freeze({})

local function options(input: Options?): Options
	if input == nil then return {} end
	assert(type(input) == "table", "opts must be an object")
	for key in input do assert(type(key) == "string", "opts must have named fields") end
	return table.clone(input)
end

local function scalar(value: any, field: string): string
	local kind = type(value)
	assert(kind == "string" or kind == "boolean" or kind == "number", field .. " must be a string, boolean, number or array of those")
	return url.encode(value)
end

-- A query value's encoded parts: one for a scalar, one per item of a nonempty array. Each
-- connector joins them as its provider expects, comma-separated or with the key repeated.
local function queryParts(value: any, field: string): {string}
	if type(value) ~= "table" then return {scalar(value, field)} end
	local parts: {string} = {}
	for index, item in value do
		assert(type(index) == "number" and index == #parts + 1, field .. " must be an array, not an object")
		table.insert(parts, scalar(item, field))
	end
	assert(#parts > 0, field .. " must not be an empty array")
	return parts
end

-- Only GET reads unless write says otherwise.
local function writes(endpoint: Endpoint): boolean
	if endpoint.write ~= nil then return endpoint.write end
	return endpoint.method ~= "GET"
end

-- POST, PATCH and PUT send the remaining options as the JSON body unless body is false
-- (no body) or names the one option to send.
local function hasBody(endpoint: Endpoint): boolean
	return endpoint.body ~= false and (endpoint.method == "POST" or endpoint.method == "PATCH" or endpoint.method == "PUT")
end

local function fail(name: string, response: HttpResponse, message: string): never
	return houston.fail({operation = name, layer = "upstream", upstream_status = response.statusCode,
		retryable = response.statusCode == 429 or response.statusCode >= 500, message = message})
end

-- A successful response's JSON object, or nil when a write answers without a body. With arrays,
-- a top-level JSON array is accepted too, and the second result tells which one came back.
local function object(name: string, endpoint: Endpoint, response: HttpResponse, arrays: boolean?): (any, boolean)
	local raw = await(response.body:readAll())
	if endpoint.method ~= "GET" and writes(endpoint) and string.match(raw, "^%s*$") then return nil, false end
	local ok, value = pcall(json.decode, raw)
	local list = arrays == true and string.match(raw, "^%s*%[") ~= nil
	if not ok or type(value) ~= "table" or not (list or string.match(raw, "^%s*{")) then
		fail(name, response, PROVIDER .. " returned an invalid JSON object")
	end
	return value, list
end

-- name({path fields, query fields?, extra fields?, required body fields, ...body}) built from the
-- endpoint itself.
-- Extra fields are options the connector's own request consumes, such as a request header.
local function signature(endpoint: Endpoint): string
	local fields: {string} = {}
	for field in string.gmatch(endpoint.path, "{([%w_]+)}") do table.insert(fields, field) end
	for _, group in {endpoint.query or NONE, endpoint.extra or NONE} do
		for _, field in group do
			table.insert(fields, if table.find(endpoint.required or NONE, field) then field else field .. "?")
		end
	end
	if type(endpoint.body) == "string" then
		table.insert(fields, endpoint.body)
	elseif hasBody(endpoint) then
		for _, field in endpoint.required or NONE do
			if not table.find(fields, field) then table.insert(fields, field) end
		end
		table.insert(fields, "...body")
	end
	return "({" .. table.concat(fields, ", ") .. "})"
end

-- A function for each endpoint the connection's access allows, and help listing them after intro.
local function operations(endpoints: {[string]: Endpoint}, request: (string, Endpoint, Options?) -> any, intro: {string}): {[string]: any}
	local exports: {[string]: any} = {}
	for name, endpoint in endpoints do
		if not writes(endpoint) or config.access == "read-write" then
			exports[name] = function(args: Options?): any return request(name, endpoint, args) end
		end
	end
	exports.help = function(): string
		local names: {string} = {}
		for name in exports do if name ~= "help" then table.insert(names, name) end end
		table.sort(names)
		local lines = table.clone(intro)
		table.insert(lines, "Each function below names its route and reference page, " .. DOCS .. "<page>.")
		for _, name in names do
			local endpoint = endpoints[name]
			table.insert(lines, name .. signature(endpoint) .. ": " .. endpoint.about .. " " .. endpoint.method .. " " .. endpoint.path .. " (" .. endpoint.doc .. ")")
		end
		return table.concat(lines, "\n")
	end
	return exports
end
-- End of the shared request layer.

-- Customer lists leave out each customer's last country and experiment enrollment; getCustomer
-- returns them, and its attributes, for one customer at a time.
local CUSTOMER_FIELDS = {"object", "id", "project_id", "first_seen_at", "last_seen_at", "last_seen_app_version", "last_seen_platform", "last_seen_platform_version"}

local function customer(value: any): any
	if type(value) ~= "table" then return value end
	local kept: Options = {}
	for _, field in CUSTOMER_FIELDS do kept[field] = value[field] end
	return kept
end

-- The starting_after cursor of next_page, such as https://api.revenuecat.com/v2/projects/p/customers?starting_after=c2.
local function nextCursor(page: any): any
	local link = page.next_page
	if type(link) ~= "string" then return NULL end
	local cursor = string.match(link, "[?&]starting_after=([^&#]+)")
	if cursor == nil then return NULL end
	return (string.gsub(cursor, "%%(%x%x)", function(hex: string): string return string.char(tonumber(hex, 16) :: number) end))
end

-- RevenueCat errors are {type, message, param?, retryable, doc_url, backoff_ms?,
-- referenced_object_ids?}; rate limits add Retry-After in seconds, and backoff_ms gives it in ms.
local function failStatus(name: string, endpoint: Endpoint, response: HttpResponse): never
	local status = response.statusCode
	local message = "RevenueCat HTTP " .. tostring(status)
	local ok, value = pcall(json.decode, await(response.body:readPrefix(16 * 1024)))
	local problem: any = if ok and type(value) == "table" then value else {}
	if type(problem.type) == "string" then message ..= " " .. string.sub(problem.type, 1, 100) end
	if type(problem.param) == "string" then message ..= " (" .. string.sub(problem.param, 1, 100) .. ")" end
	if type(problem.message) == "string" then message ..= ": " .. string.sub(problem.message, 1, 600) end
	-- Archived products or packages that block the change, for example.
	if type(problem.referenced_object_ids) == "table" then
		local ids: {string} = {}
		for _, id in problem.referenced_object_ids do
			if type(id) == "string" and #ids < 10 then table.insert(ids, string.sub(id, 1, 100)) end
		end
		if #ids > 0 then message ..= " [" .. table.concat(ids, ", ") .. "]" end
	end
	if not ok and status >= 300 and status < 400 then message ..= ": unexpected redirect" end
	if status == 401 then
		message ..= "; check that the connection's key is a v2 secret API key"
	elseif status == 403 then
		message ..= "; the key lacks the permission this request needs"
	end
	local wait = response.headers["retry-after"]
	if wait and wait[1] then
		message ..= "; retry after " .. string.sub(wait[1], 1, 40) .. "s"
	elseif type(problem.backoff_ms) == "number" then
		message ..= "; retry after " .. string.format("%d", math.floor(problem.backoff_ms)) .. " ms"
	end
	-- A 429 or 423 (another request on the same object is still running) was refused. After a 5xx a
	-- write may have been applied, and RevenueCat takes no idempotency key, so only reads retry it.
	return houston.fail({operation = name, layer = "upstream", upstream_status = status,
		retryable = status == 429 or status == 423 or (status >= 500 and not writes(endpoint)), message = message})
end

local function decode(name: string, endpoint: Endpoint, response: HttpResponse): any
	if response.statusCode < 200 or response.statusCode >= 300 then failStatus(name, endpoint, response) end
	local value = object(name, endpoint, response)
	if value == nil then return {success = true} end
	if endpoint.shape == "list" or endpoint.shape == "customers" then
		if type(value.items) ~= "table" then fail(name, response, "RevenueCat returned an invalid list") end
		if endpoint.shape == "customers" then
			for index, item in value.items do value.items[index] = customer(item) end
		end
		value.next = nextCursor(value)
	end
	return value
end

local function request(name: string, endpoint: Endpoint, input: Options?): any
	local args = options(input)
	local path = string.gsub(endpoint.path, "{([%w_]+)}", function(field: string)
		local value = args[field]
		args[field] = nil
		assert(value ~= nil and value ~= NULL, field .. " is required")
		assert(type(value) == "string", field .. " must be a string")
		local ok, segment = pcall(url.segment, value, field)
		assert(ok, field .. " must be a RevenueCat id without /, \\ or %")
		return segment
	end)
	for _, field in endpoint.required or NONE do
		assert(args[field] ~= nil and args[field] ~= NULL, field .. " is required")
	end
	-- An array repeats the key, as expand=items.package&expand=items.package.product.
	local query: {string} = {}
	for _, field in endpoint.query or NONE do
		if args[field] ~= nil then
			for _, part in queryParts(args[field], field) do table.insert(query, field .. "=" .. part) end
		end
		args[field] = nil
	end
	if #query > 0 then path ..= "?" .. table.concat(query, "&") end
	if endpoint.fields then
		for field in args do assert(table.find(endpoint.fields :: {string}, field), name .. " has no option " .. field) end
	end
	local headers: HttpHeaders = {Accept = {"application/json"}}
	local body: string? = nil
	if hasBody(endpoint) then
		headers["Content-Type"] = {"application/json"}
		body = if next(args) == nil then "{}" else json.encode(args)
		args = {}
	end
	local unknown = next(args)
	assert(unknown == nil, name .. " has no option " .. tostring(unknown))
	return decode(name, endpoint, await(http.request({url = API .. path, method = endpoint.method, headers = headers, body = body})))
end

local intro = {
	"RevenueCat REST API v2 on " .. API .. ". Every function takes one named options object with RevenueCat's native snake_case names; ? marks optional fields and ...body the JSON body fields. Results are RevenueCat's JSON unchanged, except as noted. Connector calls return completed values: use them directly, without await.",
	"Call listProjects first: every other function takes its project_id. IDs are opaque strings. customer_id is the app user id your app gives RevenueCat, or its $RCAnonymousID:...; ids with /, \\ or % can't be used. Times are milliseconds since the Unix epoch; revenue fields ending in _in_usd are in US dollars.",
	"Lists return one page, {object='list', items, next_page, url, next}: while next is not null, call again with the same options and starting_after=next for the next page. limit is 1 to 100 (default 20). expand takes one value or an array.",
	"Examples: local project = revenuecat.listProjects().items[1].id; revenuecat.getOverviewMetrics({project_id=project}).metrics; local found = revenuecat.listCustomers({project_id=project, search='ada@example.com'}).items[1]; revenuecat.listCustomerSubscriptions({project_id=project, customer_id=found.id}); revenuecat.listOfferings({project_id=project, expand={'items.package', 'items.package.product'}}).",
	"The key's permissions still apply: an HTTP 403 means it lacks the permission for that kind of data. RevenueCat limits each key per minute and per domain: 480 requests for customers, subscriptions and purchases, 60 for projects, apps, products, entitlements, offerings and packages, and 25 for metrics. Houston retries an HTTP 429 twice, waiting as Retry-After asks when that is 5 seconds or less (1 and then 2 seconds without it); a longer wait or a third 429 fails with the delay to wait. Errors report the HTTP status, RevenueCat's error type, param and message.",
}
if config.access == "read-write" then
	table.insert(intro, "Side effects: entitlement grants and revocations change what the customer can use in your apps right away; offering and package changes reach every app on its next offerings fetch, and is_current=true changes what new paywalls show. Failed writes are not retried, and a 5xx is not reported as retryable: after a timeout or 5xx, read the customer, offering or package before repeating a write.")
else
	table.insert(intro, "This read-only connection omits writes.")
end

return operations(endpoints, request, intro)
