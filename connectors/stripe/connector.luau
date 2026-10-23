-- Stripe API v1, version 2026-09-30.endive. Arguments and results keep Stripe's native field names.
type Options = {[string]: any}
type Endpoint = {method: string, path: string, required: {string}?, about: string, kind: string?}
local endpoints: {[string]: Endpoint} = {
	getAccount = {method = "GET", path = "/v1/account", about = "The account owning the key; not an Atlas company record."},
	getBalance = {method = "GET", path = "/v1/balance", about = "Available and pending balances by currency."},
	listBalanceTransactions = {method = "GET", path = "/v1/balance_transactions", about = "Balance ledger; filters include type, payout, source and created."},
	getBalanceTransaction = {method = "GET", path = "/v1/balance_transactions/{balance_transaction_id}", about = "One balance ledger entry."},
	listCustomers = {method = "GET", path = "/v1/customers", about = "Customers; filters include email and created."},
	searchCustomers = {method = "GET", path = "/v1/customers/search", required = {"query"}, about = "Search customers with Stripe search syntax; query required."},
	getCustomer = {method = "GET", path = "/v1/customers/{customer_id}", about = "One customer."},
	createCustomer = {method = "POST", path = "/v1/customers", about = "Create a customer; email, name, metadata and address are optional."},
	updateCustomer = {method = "POST", path = "/v1/customers/{customer_id}", about = "Update supplied customer fields."},
	deleteCustomer = {method = "DELETE", path = "/v1/customers/{customer_id}", about = "Permanently delete a customer and cancel their subscriptions."},
	listProducts = {method = "GET", path = "/v1/products", about = "Products; filters include active and created."},
	getProduct = {method = "GET", path = "/v1/products/{product_id}", about = "One product."},
	createProduct = {method = "POST", path = "/v1/products", required = {"name"}, about = "Create a product; name required."},
	updateProduct = {method = "POST", path = "/v1/products/{product_id}", about = "Update a product; active=false archives it."},
	listPrices = {method = "GET", path = "/v1/prices", about = "Prices; filters include product, active, currency and type."},
	getPrice = {method = "GET", path = "/v1/prices/{price_id}", about = "One price."},
	createPrice = {method = "POST", path = "/v1/prices", required = {"currency"}, about = "Create a price; currency and product or product_data required; supply pricing and optional recurring fields."},
	updatePrice = {method = "POST", path = "/v1/prices/{price_id}", about = "Update supported price fields, such as active, metadata or nickname; amounts are immutable."},
	listPaymentIntents = {method = "GET", path = "/v1/payment_intents", about = "Payment intents; filters include customer and created."},
	getPaymentIntent = {method = "GET", path = "/v1/payment_intents/{payment_intent_id}", about = "One payment intent, including status and client_secret."},
	createPaymentIntent = {method = "POST", path = "/v1/payment_intents", required = {"amount", "currency"}, about = "Create an intent; amount and currency required. confirm=true can charge immediately."},
	updatePaymentIntent = {method = "POST", path = "/v1/payment_intents/{payment_intent_id}", about = "Update an intent; changes may require confirmation again."},
	confirmPaymentIntent = {method = "POST", path = "/v1/payment_intents/{payment_intent_id}/confirm", about = "Attempt payment with payment_method or the intent's existing method; may require customer action."},
	capturePaymentIntent = {method = "POST", path = "/v1/payment_intents/{payment_intent_id}/capture", about = "Capture an authorized payment; optional amount_to_capture."},
	cancelPaymentIntent = {method = "POST", path = "/v1/payment_intents/{payment_intent_id}/cancel", about = "Cancel an eligible payment intent; optional cancellation_reason."},
	listCharges = {method = "GET", path = "/v1/charges", about = "Charges; filters include customer, payment_intent and created."},
	getCharge = {method = "GET", path = "/v1/charges/{charge_id}", about = "One charge, including refund and dispute status."},
	listRefunds = {method = "GET", path = "/v1/refunds", about = "Refunds; filters include charge, payment_intent and created."},
	getRefund = {method = "GET", path = "/v1/refunds/{refund_id}", about = "One refund and its status."},
	createRefund = {method = "POST", path = "/v1/refunds", about = "Refund a charge/payment_intent, or customer with origin=customer_balance. Optional amount for partial refunds."},
	updateRefund = {method = "POST", path = "/v1/refunds/{refund_id}", about = "Update refund metadata."},
	listSubscriptions = {method = "GET", path = "/v1/subscriptions", about = "Subscriptions; customer, price, status and created filters. Use status=all to include canceled subscriptions."},
	getSubscription = {method = "GET", path = "/v1/subscriptions/{subscription_id}", about = "One subscription."},
	createSubscription = {method = "POST", path = "/v1/subscriptions", about = "Create a subscription with customer or customer_account and items={{price='price_...'}}; can charge immediately."},
	updateSubscription = {method = "POST", path = "/v1/subscriptions/{subscription_id}", about = "Update items or cancel_at_period_end; proration_behavior controls prorations and changes can charge."},
	cancelSubscription = {method = "DELETE", path = "/v1/subscriptions/{subscription_id}", about = "Cancel immediately; invoice_now and prorate are optional."},
	listInvoices = {method = "GET", path = "/v1/invoices", about = "Invoices; filters include customer, subscription, status and created."},
	getInvoice = {method = "GET", path = "/v1/invoices/{invoice_id}", about = "One invoice, including hosted_invoice_url and invoice_pdf when available."},
	listInvoiceLines = {method = "GET", path = "/v1/invoices/{invoice_id}/lines", about = "Paginated invoice line items."},
	createInvoice = {method = "POST", path = "/v1/invoices", about = "Create a draft with customer/customer_account, or revise an invoice with from_invoice."},
	updateInvoice = {method = "POST", path = "/v1/invoices/{invoice_id}", about = "Update permitted invoice fields; finalized invoices have restrictions."},
	finalizeInvoice = {method = "POST", path = "/v1/invoices/{invoice_id}/finalize", about = "Finalize a draft; auto_advance controls automatic collection."},
	payInvoice = {method = "POST", path = "/v1/invoices/{invoice_id}/pay", about = "Attempt invoice payment; can charge a payment method."},
	sendInvoice = {method = "POST", path = "/v1/invoices/{invoice_id}/send", about = "Email an invoice to its customer."},
	voidInvoice = {method = "POST", path = "/v1/invoices/{invoice_id}/void", about = "Void a finalized invoice; irreversible."},
	deleteInvoice = {method = "DELETE", path = "/v1/invoices/{invoice_id}", about = "Delete a draft invoice."},
	createInvoiceItem = {method = "POST", path = "/v1/invoiceitems", about = "Create an invoice item; customer or customer_account required; amount or pricing fields determine its value."},
	listPaymentMethods = {method = "GET", path = "/v1/payment_methods", about = "Payment methods; filter by customer and optional type."},
	getPaymentMethod = {method = "GET", path = "/v1/payment_methods/{payment_method_id}", about = "One payment method; raw card numbers are not returned."},
	attachPaymentMethod = {method = "POST", path = "/v1/payment_methods/{payment_method_id}/attach", about = "Attach an existing payment method to customer or customer_account; use a SetupIntent first when appropriate."},
	detachPaymentMethod = {method = "POST", path = "/v1/payment_methods/{payment_method_id}/detach", about = "Detach a payment method; it cannot be used or reattached afterwards."},
	listPayouts = {method = "GET", path = "/v1/payouts", about = "Payouts; filters include status, destination, arrival_date and created."},
	getPayout = {method = "GET", path = "/v1/payouts/{payout_id}", about = "One payout."},
	createPayout = {method = "POST", path = "/v1/payouts", required = {"amount", "currency"}, about = "Move balance to an external account; amount and currency required."},
	cancelPayout = {method = "POST", path = "/v1/payouts/{payout_id}/cancel", about = "Cancel a pending manual payout when eligible."},
	listDisputes = {method = "GET", path = "/v1/disputes", about = "Disputes; filters include charge, payment_intent and created."},
	getDispute = {method = "GET", path = "/v1/disputes/{dispute_id}", about = "One dispute with evidence and deadlines."},
	updateDispute = {method = "POST", path = "/v1/disputes/{dispute_id}", about = "Update evidence; submit=true submits it to the bank and can be irreversible."},
	listEvents = {method = "GET", path = "/v1/events", about = "Events from the last 30 days; type, types, created and delivery_success filters. Event payload versions remain as created."},
	getEvent = {method = "GET", path = "/v1/events/{event_id}", about = "One event from the last 30 days."},
	listCheckoutSessions = {method = "GET", path = "/v1/checkout/sessions", about = "Checkout sessions; filters include customer, payment_intent, subscription and status."},
	getCheckoutSession = {method = "GET", path = "/v1/checkout/sessions/{session_id}", about = "One Checkout session."},
	createCheckoutSession = {method = "POST", path = "/v1/checkout/sessions", required = {"mode"}, about = "Create hosted checkout; mode payment/subscription/setup, line_items and return URLs depend on mode and ui_mode."},
	expireCheckoutSession = {method = "POST", path = "/v1/checkout/sessions/{session_id}/expire", about = "Expire an open Checkout session."},
	createPortalSession = {method = "POST", path = "/v1/billing_portal/sessions", about = "Create a billing portal session for customer or customer_account; optional return_url. Returned URL is short-lived."},
	listFiles = {method = "GET", path = "/v1/files", about = "File metadata; filters include purpose and created."},
	getFile = {method = "GET", path = "/v1/files/{file_id}", about = "File metadata; url may be absent for files that cannot be downloaded."},
	uploadFile = {method = "POST", path = "/v1/files", required = {"purpose"}, kind = "upload", about = "Upload session path with purpose; optional filename/content_type and file_link_data. File size/type limits depend on purpose."},
	downloadFile = {method = "GET", path = "/v1/files/{file_id}/contents", kind = "download", about = "Download an available file to session path; returns {path,url,size}. Some purposes cannot be downloaded."},
}
local NULL = json.decode("null")
local NONE: {string} = table.freeze({})

local function text(value: any, field: string): string
	assert(type(value) == "string" and #value > 0, field .. " must be a nonempty string")
	return value
end

local function identifier(value: any, field: string): string
	local result = text(value, field)
	assert(string.match(result, "^[%w_%-]+$") ~= nil, field .. " must be a Stripe identifier")
	return result
end

-- Stripe v1 uses bracketed form fields, including zero-based array indices.
local function fields(args: Options): {{string}}
	local result: {{string}} = {}
	local function add(key: string, value: any, depth: number)
		assert(depth <= 10, "parameters are nested too deeply")
		assert(value ~= NULL, key .. " cannot be null; use an empty string to clear a field")
		if type(value) == "table" then
			if next(value) == nil then table.insert(result, {key, ""}); return end
			local array = #value > 0
			local count = 0
			for child, item in value do
				count += 1
				if array then
					assert(type(child) == "number" and child % 1 == 0 and child >= 1 and child <= #value, key .. " must be a dense array or object")
					add(key .. "[" .. tostring(child - 1) .. "]", item, depth + 1)
				else
					assert(type(child) == "string" and #child > 0 and not string.find(child, "[%[%]%c]"), key .. " has an invalid field name")
					add(key .. "[" .. child .. "]", item, depth + 1)
				end
			end
			if array then assert(count == #value, key .. " must be a dense array") end
		else
			local kind = type(value)
			assert(kind == "string" or kind == "boolean" or kind == "number", key .. " must be plain form data")
			if kind == "number" then assert(value == value and math.abs(value) < math.huge, key .. " must be finite") end
			table.insert(result, {key, tostring(value)})
		end
		assert(#result <= 1000, "too many form fields")
	end
	for key, value in args do
		assert(type(key) == "string" and string.match(key, "^[%a][%w_]*$") ~= nil, "options must have plain named fields")
		add(key, value, 0)
	end
	table.sort(result, function(a, b) return a[1] < b[1] end)
	return result
end

local function fail(name: string, response: HttpResponse, message: string): never
	local retry = response.headers["stripe-should-retry"]
	local retryable = response.statusCode == 429 or response.statusCode >= 500
	if retry and retry[1] == "false" then retryable = false end
	if retry and retry[1] == "true" then retryable = true end
	return houston.fail({operation = name, layer = "upstream", upstream_status = response.statusCode,
		retryable = retryable, message = message})
end

local function check(name: string, response: HttpResponse)
	if response.statusCode >= 200 and response.statusCode < 300 then return end
	local raw = await(response.body:readPrefix(8192))
	local message = string.sub(raw, 1, 1000)
	local ok, body = pcall(json.decode, raw)
	if ok and type(body) == "table" and type(body.error) == "table" then
		local detail = body.error
		message = string.sub(tostring(detail.message or "Request failed"), 1, 1000)
		for _, key in {"type", "code", "param"} do
			if type(detail[key]) == "string" then message ..= " " .. key .. "=" .. string.sub(detail[key], 1, 200) end
		end
	end
	for _, key in {"request-id", "retry-after", "stripe-should-retry", "stripe-rate-limited-reason"} do
		local values = response.headers[key]
		if values and values[1] then message ..= " " .. key .. "=" .. string.sub(values[1], 1, 200) end
	end
	fail(name, response, "Stripe HTTP " .. response.statusCode .. ": " .. message)
end

-- Expanded resources and event payloads can contain payment-capable credentials.
local function redactCredentials(value: any)
	if type(value) ~= "table" then return end
	for key, child in value do
		if key == "client_secret" or key == "confirmation_secret" or key == "client_token" or key == "secret" then
			value[key] = nil
		else
			redactCredentials(child)
		end
	end
end

local function request(name: string, endpoint: Endpoint, input: Options?): any
	assert(input == nil or type(input) == "table", "opts must be an object")
	local args: Options = if input then table.clone(input) else {}
	local path = string.gsub(endpoint.path, "{([%w_]+)}", function(key: string)
		local value = identifier(args[key], key)
		args[key] = nil
		return value
	end)
	local required = endpoint.required or NONE
	for _, key in required do assert(args[key] ~= nil and args[key] ~= NULL and args[key] ~= "", key .. " is required") end
	if name == "createPrice" then assert(args.product ~= nil or args.product_data ~= nil, "product or product_data is required") end
	if args.limit ~= nil then assert(type(args.limit) == "number" and args.limit % 1 == 0 and args.limit >= 1 and args.limit <= 100, "limit must be an integer from 1 to 100") end
	assert(not (args.starting_after ~= nil and args.ending_before ~= nil), "starting_after and ending_before cannot be combined")
	local headers: HttpHeaders = {Accept = {"application/json"}, ["Stripe-Version"] = {"2026-09-30.endive"}}
	if args.idempotency_key ~= nil then
		local key = text(args.idempotency_key, "idempotency_key")
		assert(endpoint.method == "POST" and #key <= 255 and not string.find(key, "%c"), "idempotency_key requires POST and at most 255 characters without controls")
		headers["Idempotency-Key"] = {key}
		args.idempotency_key = nil
	end
	local destination: string? = nil
	local body: any = nil
	local host = "api.stripe.com"
	if endpoint.kind == "download" then
		destination = text(args.path, "path")
		args.path = nil
		assert(next(args) == nil, "downloadFile accepts only file_id and path")
		headers.Accept = {"application/octet-stream"}
		host = "files.stripe.com"
	elseif endpoint.kind == "upload" then
		local source = text(args.path, "path")
		local filename = text(args.filename or string.match(source, "[^/]+$"), "filename")
		local contentType = text(args.content_type or "application/octet-stream", "content_type")
		assert(not string.find(filename, '[%c"/\\]'), "filename must be a plain filename")
		assert(not string.find(contentType, "%c"), "content_type cannot contain controls")
		args.path, args.filename, args.content_type = nil, nil, nil
		assert(args.file == nil, "use path for the upload file")
		local parts: {any} = {}
		for _, field in fields(args) do table.insert(parts, {name = field[1], body = field[2]}) end
		local file = fs.open(source, "r")
		local ok, multipart, multipartType = pcall(function()
			await(file)
			table.insert(parts, {name = "file", filename = filename, contentType = contentType, body = file})
			return http.multipart(parts)
		end)
		if not ok then
			pcall(function() await(file:close()) end)
			error(multipart)
		end
		body = multipart
		headers["Content-Type"] = {multipartType}
		host = "files.stripe.com"
	else
		local encoded: {string} = {}
		for _, field in fields(args) do table.insert(encoded, url.encode(field[1]) .. "=" .. url.encode(field[2])) end
		local form = table.concat(encoded, "&")
		if endpoint.method == "POST" then
			body = form
			headers["Content-Type"] = {"application/x-www-form-urlencoded"}
		elseif #form > 0 then path ..= "?" .. form end
	end
	local output = if destination then fs.open(destination, "w") else nil
	local ok, result = pcall(function()
		if output then await(output) end
		local response = await(http.request({method = endpoint.method, url = "https://" .. host .. path, headers = headers, body = body}))
		check(name, response)
		if output then
			output:write(response.body)
			await(output:close())
			return {path = destination, size = await(fs.stat(destination :: string)).size, url = await(fs.signedGetUrl(destination :: string))}
		end
		local raw = await(response.body:readAll())
		local decoded, value = pcall(json.decode, raw)
		if not decoded or type(value) ~= "table" or not string.match(raw, "^%s*{") then fail(name, response, "Stripe returned an invalid JSON object") end
		if config.access ~= "read-write" then redactCredentials(value) end
		return value
	end)
	if not ok then
		if endpoint.kind == "upload" then pcall(function() body:close() end) end
		if output then pcall(function() await(output:close()) end) end
		error(result)
	end
	return result
end

local exports: {[string]: any} = {}
for name, endpoint in endpoints do
	if endpoint.method == "GET" or config.access == "read-write" then
		exports[name] = function(args: Options?): any return request(name, endpoint, args) end
	end
end
exports.help = function(): string
	local lines = {
		"Stripe API v1 (2026-09-30.endive). Call functions directly, e.g. stripe.listCustomers({limit=25}); do not await connector calls. Each takes one named options object; {field} in the route is required and removed before sending. Remaining options use Stripe's native parameter names and nested tables; results preserve Stripe's JSON objects, arrays and nulls. Full schemas: https://docs.stripe.com/api .",
		"List functions fetch one page (limit 1..100, Stripe default 10). While has_more, pass the last data item's id as starting_after; ending_before pages backwards and cannot accompany starting_after. Search uses query and page=result.next_page instead, and is eventually consistent. No automatic paging or retries. Small pages and selective expand keep results within runtime memory/response budgets.",
		"Nested values use Stripe form encoding: {created={gte=1700000000},expand={'data.customer'}}. Empty string clears supported fields; empty tables encode as empty values. JSON null is rejected in requests. Stripe validates resource-specific parameter types and constraints. Amounts use the currency's smallest unit (usually cents); zero-decimal currencies differ.",
		"Writes appear only with read-write access. Read-only results remove fields named client_secret, confirmation_secret, client_token and secret at every depth, including events, expansions and metadata, because these can authorize payment or setup. Other fields and all read-write results retain native values. Hosted payment links and personal financial data remain sensitive. A restricted API key must also grant the relevant resource permission. Keys select sandbox/test versus live mode. This connector acts on the key's own account; no per-request Stripe-Account override or Connect account administration.",
		"For POSTs, supply idempotency_key (at most 255 characters) and keep it with the intended request. Reuse only for an identical retry; Stripe can prune keys after 24 hours. Payments, refunds, payouts, subscription changes and invoice actions can move money or send email. After timeouts or ambiguous writes inspect Stripe before retrying; errors report HTTP status, request-id, retry-after and Stripe retry hints when supplied.",
		"uploadFile({path='evidence.pdf',purpose='dispute_evidence',content_type='application/pdf'}) streams a session file as multipart. Stripe applies purpose-specific size and file-type limits. downloadFile({file_id='file_...',path='download.pdf'}) streams available contents and returns {path,url,size}, with a signed Houston URL; failures may leave partial files. getFile exposes availability. Invoice PDF links are returned unchanged, not fetched through arbitrary hosts.",
		"Atlas incorporation, equity, tax and company documents are not in this public Stripe API connector. No supported public Atlas API was found; partner-only integrations need separate access and documentation. Use the Atlas dashboard for these workflows.",
	}
	local names: {string} = {}
	for name in exports do if name ~= "help" then table.insert(names, name) end end
	table.sort(names)
	for _, name in names do
		local endpoint = endpoints[name]
		table.insert(lines, name .. "(opts): " .. endpoint.method .. " " .. endpoint.path .. ". " .. endpoint.about)
	end
	return table.concat(lines, "\n")
end
return exports
