return {
	scenario = {publisher = {}, config = {access = "read-write"}, auth_method = "token", auth_config = {token = "sk_fixture"}},
	configure = function()
		calls = 0
		status = 200
		payload = "{}"
		responseHeaders = {}
		http = {request = function(req)
			calls += 1
			assert(req.headers.Authorization == nil, "credentials must remain in the proxy")
			return fixture.operation({statusCode = status, headers = responseHeaders, body = fixture.reader(payload)})
		end}
	end,
	run = function(revenuecat)
		local function upstream(code, body, headers, call, expected, absent)
			status, payload, responseHeaders = code, body, headers
			local before = calls
			local ok, err = pcall(call)
			assert(not ok, "the call should have failed")
			for _, text in expected do
				assert(string.find(tostring(err), text, 1, true), "missing " .. text .. " in " .. tostring(err))
			end
			if absent then assert(not string.find(tostring(err), absent, 1, true), "unexpected " .. absent .. " in " .. tostring(err)) end
			assert(calls == before + 1, "a failed request was repeated")
		end
		local function read() revenuecat.getCustomer({project_id = "proj1", customer_id = "user-1"}) end
		local function list() revenuecat.listCustomers({project_id = "proj1"}) end
		local function grant() revenuecat.grantEntitlement({project_id = "proj1", customer_id = "user-1", entitlement_id = "entl1", expires_at = 1793143768000}) end

		upstream(401, '{"object":"error","type":"authentication_error","message":"Invalid API key.","retryable":false,"doc_url":"https://errors.rev.cat/authentication-error"}', {}, read,
			{"RevenueCat HTTP 401 authentication_error: Invalid API key.", "v2 secret API key", '"retryable":false', '"upstream_status":401'})
		upstream(403, '{"object":"error","type":"authorization_error","message":"The API key does not have the required permission(s): customer_information:customers:read_write","retryable":false}', {}, grant,
			{"HTTP 403 authorization_error: The API key does not have the required permission(s): customer_information:customers:read_write", "lacks the permission", '"retryable":false'})
		upstream(404, '{"object":"error","type":"resource_missing","message":"Customer not found","param":null,"retryable":false}', {}, read,
			{"HTTP 404 resource_missing: Customer not found", '"retryable":false'}, "null)")
		upstream(400, '{"object":"error","type":"parameter_error","param":"expires_at","message":"expires_at must be in the future","retryable":false}', {}, grant,
			{"HTTP 400 parameter_error (expires_at): expires_at must be in the future", '"retryable":false'})
		upstream(400, '{"object":"error","type":"parameter_error","message":"' .. string.rep("x", 5000) .. '"}', {}, grant,
			{"parameter_error: " .. string.rep("x", 600)}, string.rep("x", 601))
		upstream(400, '{"object":"error","type":"parameter_error","message":"' .. string.rep("x", 40000) .. '"}', {}, grant, {"RevenueCat HTTP 400"}, "xxx")
		upstream(423, '{"object":"error","type":"resource_locked_error","message":"The resource is locked","retryable":true,"backoff_ms":1500}', {}, grant,
			{"HTTP 423 resource_locked_error: The resource is locked; retry after 1500 ms", '"retryable":true'})
		local archived = {}
		for index = 1, 11 do table.insert(archived, '"prod' .. index .. '"') end
		upstream(422, '{"object":"error","type":"entity_references_archived_entities","message":"The package references archived products","retryable":false,"backoff_ms":null,"referenced_object_ids":[null,'
			.. table.concat(archived, ",") .. ']}', {}, function() revenuecat.attachPackageProducts({project_id = "proj1", package_id = "pkge1", products = {{product_id = "prod1", eligibility_criteria = "all"}}}) end,
			{"HTTP 422 entity_references_archived_entities: The package references archived products [prod1, prod2, prod3, prod4, prod5, prod6, prod7, prod8, prod9, prod10]", '"retryable":false'},
			"prod11")
		upstream(429, '{"object":"error","type":"rate_limit_error","message":"Rate limit exceeded","retryable":true,"backoff_ms":30000}', {["retry-after"] = {"30"}}, list,
			{"HTTP 429 rate_limit_error: Rate limit exceeded", "retry after 30s", '"retryable":true'})
		upstream(429, '{"object":"error","type":"rate_limit_error","message":"Rate limit exceeded","retryable":true}', {}, list, {"HTTP 429", '"retryable":true'}, "retry after")
		upstream(503, "<html>Unavailable</html>", {}, read, {"RevenueCat HTTP 503", '"retryable":true'}, "html")
		-- A write may have been applied before a 5xx, so only reads report it as retryable.
		upstream(502, "<html>Bad gateway</html>", {}, grant, {"RevenueCat HTTP 502", '"retryable":false'})
		upstream(500, '{"object":"error","type":"server_error","message":"Internal error","retryable":true}', {},
			function() revenuecat.createPackage({project_id = "proj1", offering_id = "ofrng1", lookup_key = "$rc_monthly", display_name = "Monthly"}) end,
			{"HTTP 500 server_error: Internal error", '"retryable":false'})
		upstream(302, "", {location = {"https://app.revenuecat.com/login"}}, read, {"HTTP 302: unexpected redirect"}, "login")
		upstream(200, "<html>Maintenance</html>", {}, read, {"invalid JSON object"})
		upstream(200, "[]", {}, read, {"invalid JSON object"})
		upstream(200, '{"object":"list","items":null,"next_page":null}', {}, list, {"invalid list"})
		upstream(200, '{"object":"list","items":"nope"}', {}, list, {"invalid list"})
	end,
}
