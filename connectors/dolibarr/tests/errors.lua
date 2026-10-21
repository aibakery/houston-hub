return {
	scenario = {publisher = {}, config = {host = "erp.example.com", access = "read-write"}, auth_method = "key",
		auth_config = {token = "Zx81Kq0PnB2vLm4TcR7wYs9dHf3jGa6E"}},
	configure = function()
		calls = 0
		status = 200
		payload = "{}"
		responseHeaders = {}
		http = {request = function(req)
			calls += 1
			return fixture.operation({statusCode = status, headers = responseHeaders, body = fixture.reader(payload)})
		end}
	end,
	run = function(erp)
		local function rejected(fn, expected)
			local before = calls
			local ok, err = pcall(fn)
			assert(not ok and string.find(tostring(err), expected, 1, true), "wrong validation error: " .. tostring(err))
			assert(calls == before, "invalid input reached Dolibarr")
		end
		rejected(function() erp.getInvoice() end, "id must be a positive integer ID")
		for _, value in {0, -1, 1.5, "0", "07", "1e3", " 1", "../setup/conf", "9007199254740993", 2 ^ 60} do
			rejected(function() erp.getInvoice(value) end, "id must be a positive integer ID")
		end
		rejected(function() erp.updateProduct("x", {price = 1}) end, "id must be a positive integer ID")
		rejected(function() erp.listInvoices("unpaid") end, "opts must be an object")
		-- Restler and Dolibarr read a method override, a key and error suppression from any query string.
		for _, key in {"http_method", "DOLAPIKEY", "api_key", "suppress_response_codes", "pagination_data", "loadlinkedobjects", "withLines"} do
			rejected(function() erp.listInvoices({[key] = "DELETE"}) end, key .. " is not a supported option")
			rejected(function() erp.getInvoice(1, {[key] = "DELETE"}) end, key .. " is not a supported option")
		end
		rejected(function() erp.getStatus({limit = 1}) end, "limit is not a supported option")
		rejected(function() erp.getProduct(1, {limit = 1}) end, "limit is not a supported option")
		rejected(function() erp.listInvoices({limit = 0}) end, "limit must be an integer from 1 to 200")
		rejected(function() erp.listInvoices({limit = 201}) end, "limit must be an integer from 1 to 200")
		rejected(function() erp.listInvoices({page = -1}) end, "page must be an integer")
		rejected(function() erp.listInvoices({sortorder = "asc"}) end, "sortorder must be ASC or DESC")
		for _, value in {"t.rowid;", "t.rowid desc", "a.b.c", "t.", ".rowid", ""} do
			rejected(function() erp.listInvoices({sortfield = value}) end, "sortfield must be a column")
		end
		rejected(function() erp.listInvoices({sqlfilters = " "}) end, "sqlfilters is not valid")
		rejected(function() erp.listInvoices({sqlfilters = string.rep("x", 4001)}) end, "sqlfilters is not valid")
		rejected(function() erp.listInvoices({properties = "id,ref"}) end, "properties must be a nonempty array")
		rejected(function() erp.listInvoices({properties = {"id", "ref&http_method=DELETE"}}) end, "properties is not valid")
		rejected(function() erp.listInvoices({thirdparty_ids = {12, "x"}}) end, "thirdparty_ids must be a positive integer ID")
		rejected(function() erp.listInvoices({status = "unpaid&http_method=DELETE"}) end, "status is not valid")
		rejected(function() erp.listThirdparties({mode = 5}) end, "mode must be an integer from 0 to 4")
		rejected(function() erp.listProducts({includestockdata = 1}) end, "includestockdata must be a boolean")
		rejected(function() erp.listBankAccountLines(1) end, "sqlfilters is required")
		-- Filtering or sorting on a withheld field would reveal it one character at a time.
		rejected(function() erp.listThirdparties({sqlfilters = "(t.WebServices_Key:like:'a%')"}) end, "sqlfilters cannot use webservices_key")
		rejected(function() erp.listOrders({sqlfilterlines = "(tl.pass:=:'x')"}) end, "sqlfilterlines cannot use pass")
		rejected(function() erp.listThirdparties({sortfield = "t.webservices_key"}) end, "sortfield cannot use webservices_key")
		erp.listThirdparties({sqlfilters = "(t.note_private:like:'%passage%') and (t.webservices_url:!=:'')"})

		rejected(function() erp.createThirdparty("Ann") end, "fields must be an object")
		rejected(function() erp.createThirdparty({"Ann"}) end, "fields must be an object")
		rejected(function() erp.createThirdparty({email = "ann@example.com"}) end, "fields.name is required")
		rejected(function() erp.createProduct({ref = "MUG"}) end, "fields.label is required")
		rejected(function() erp.createOrder({socid = 12}) end, "fields.date is required")
		rejected(function() erp.addInvoicePayment(42, {datepaye = 1, paymentid = 6, accountid = 1}) end, "fields.closepaidinvoices is required")
		rejected(function() erp.createInvoice({id = 5, socid = 12}) end, "fields must not contain id")
		rejected(function() erp.updateProduct(9, {}) end, "fields must name at least one field")
		rejected(function() erp.validateOrder(7, "now") end, "fields must be an object")

		local function upstream(code, body, headers, expected, absent)
			status, payload, responseHeaders = code, body, headers
			local before = calls
			local ok, err = pcall(function() erp.validateInvoice(42) end)
			for _, text in expected do
				assert(not ok and string.find(tostring(err), text, 1, true), "missing " .. text .. " in " .. tostring(err))
			end
			for _, text in absent or {} do
				assert(not string.find(tostring(err), text, 1, true), "unexpected " .. text .. " in " .. tostring(err))
			end
			assert(calls == before + 1, "failed write was retried")
		end
		local debug = ',"debug":{"source":"api_access.class.php:339 at authenticate stage","stages":{"success":["get"]}}'
		upstream(401, '{"error":{"code":401,"message":"Unauthorized: Error user not valid (not found or bad password or bad api key)"}' .. debug .. "}", {},
			{"Dolibarr HTTP 401: Unauthorized: Error user not valid", "Check the API key", '"retryable":false'}, {"api_access.class.php"})
		upstream(403, '{"error":{"code":403,"message":"Forbidden"}}', {}, {"HTTP 403: Forbidden. The Dolibarr user of this API key lacks the permission, or the module behind this request is disabled"})
		upstream(304, "", {}, {"HTTP 304. Dolibarr made no change", '"retryable":false'})
		upstream(404, '{"error":{"code":404,"message":"Not Found: Invoice not found"}}', {}, {"HTTP 404: Not Found: Invoice not found"}, {"install path"})
		-- RestException details arrive as numbered keys beside the message.
		upstream(500, json.encode({error = {code = 500, message = "Internal Server Error: Error when validating Invoice: " .. string.rep("x", 5000), ["0"] = "ErrorBadValue", ["1"] = "ErrorRefAlreadyExists"}}), {},
			{"Error when validating Invoice", "; ErrorBadValue; ErrorRefAlreadyExists", "may have been saved", '"retryable":false'})
		upstream(501, "API not found (failed to include API file)", {}, {"HTTP 501: API not found", "does not offer this endpoint", '"retryable":false'})
		upstream(503, "<html><head><style>\nbody { color: red }</style><script>var x = 1</script></head><body><!-- WAF --><h1>Blocked</h1></body></html>",
			{}, {"HTTP 503: WAF Blocked", "may have been saved"}, {"color: red", "var x"})
		upstream(429, "Too many requests", {["retry-after"] = {"30"}}, {"HTTP 429: Too many requests", "Retry-After: 30", '"retryable":true'})
		upstream(301, "", {location = {"https://www.erp.example.com/api/index.php/invoices/42/validate"}},
			{"HTTP 301", "redirected to https://www.erp.example.com/", "domain and install path"})
		-- With the API module off, Dolibarr answers HTTP 200 with a plain-text warning.
		upstream(200, "WarningModuleNotActive", {}, {"not JSON", "https://erp.example.com/api/index.php/status", "may have been saved"})
		upstream(200, "", {}, {"not JSON"})

		local function read(code, body, expected, absent)
			status, payload, responseHeaders = code, body, {}
			local ok, err = pcall(function() erp.listInvoices() end)
			for _, text in expected do
				assert(not ok and string.find(tostring(err), text, 1, true), "missing " .. text .. " in " .. tostring(err))
			end
			for _, text in absent or {} do
				assert(not string.find(tostring(err), text, 1, true), "unexpected " .. text .. " in " .. tostring(err))
			end
		end
		-- A read that failed upstream is safe to repeat.
		read(502, "<html><body>Bad gateway</body></html>", {"HTTP 502: Bad gateway", '"retryable":true'}, {"may have been saved"})
		-- Only Dolibarr's own 404 is an empty list; a web server's 404 means a wrong address.
		read(404, "<html><body>Not Found</body></html>", {"HTTP 404: Not Found", "install path", "https://erp.example.com/api/index.php"})
		-- Restler answers a bare "Not Found" for a route this Dolibarr lacks, which is not an empty list.
		read(404, '{"error":{"code":404,"message":"Not Found"}}', {"HTTP 404: Not Found", '"retryable":false'})
		read(403, '{"error":{"code":403,"message":"Forbidden: Access not allowed for login houston"}}', {"Access not allowed for login houston", '"retryable":false'})
		-- Dolibarr reports SQL errors as JSON 503, and an IP restriction as plain 503: retrying fails again.
		read(503, '{"error":{"code":503,"message":"Service Unavailable: Error when retrieve invoice list : Unknown column t.nosuch"}}', {"Unknown column t.nosuch", '"retryable":false'})
		read(503, "API not allowed from your IP", {"HTTP 503: API not allowed from your IP", '"retryable":false'})
		read(500, '{"error":{"code":500,"message":"Internal Server Error: Error when retrieving invoice list"}}', {'"retryable":false'})
		status, payload, responseHeaders = 503, "Maintenance", {["retry-after"] = {"5"}}
		local waitOK, waitErr = pcall(function() erp.listInvoices() end)
		assert(not waitOK and string.find(tostring(waitErr), '"retryable":true', 1, true), tostring(waitErr))
	end,
}
