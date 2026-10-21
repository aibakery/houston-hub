return {
	scenario = {publisher = {client_id = "fixture-client", client_secret = "fixture-secret"}, config = {access = "read-write"}, auth_method = "gusto", auth_config = {}},
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
	run = function(gusto)
		local function upstream(code, body, headers, expected, call)
			status, payload, responseHeaders = code, body, headers
			local before = calls
			local ok, err = pcall(call or function()
				gusto.createDepartment({company_id = "c1", title = "Engineering"})
			end)
			for _, text in expected do
				assert(not ok and string.find(tostring(err), text, 1, true), "missing " .. text .. " in " .. tostring(err))
			end
			assert(calls == before + 1, "failed write was retried")
			return tostring(err)
		end
		upstream(422, '{"errors":[{"error_key":"title","category":"invalid_attribute_value","message":"Title has already been taken"},{"error_key":"base","category":"invalid_operation"}]}', {},
			{"Gusto HTTP 422: invalid_attribute_value title Title has already been taken; invalid_operation base", '"retryable":false'})
		upstream(409, '{"errors":[{"error_key":"version","category":"invalid_resource_version","message":"stale"}]}', {},
			{"Gusto HTTP 409: invalid_resource_version version stale"},
			function() gusto.updateDepartment({department_uuid = "d1", title = "Eng", version = "old"}) end)
		upstream(403, '{"errors":[{"error_key":"base","category":"missing_oauth_scopes","message":"Missing scope compensations:read"}]}', {},
			{"Gusto HTTP 403: missing_oauth_scopes base Missing scope compensations:read", '"upstream_status":403', '"retryable":false'},
			function() gusto.getCompensation({compensation_id = "k1"}) end)
		upstream(401, "", {["www-authenticate"] = {'Bearer realm="Doorkeeper", error="invalid_token", error_description="The access token is invalid"'}},
			{"Gusto HTTP 401: The access token is invalid", '"retryable":false'}, function() gusto.getTokenInfo() end)
		local long = upstream(422, json.encode({errors = {{category = "invalid_parameter", message = string.rep("x", 5000)}}}), {}, {"Gusto HTTP 422: invalid_parameter xxx"})
		assert(not string.find(long, string.rep("x", 301), 1, true), "error message not bounded")
		upstream(404, '{"errors":[{"error_key":"employee","category":"not_found","message":"Resource not found"}]}', {}, {"Gusto HTTP 404: not_found employee Resource not found"},
			function() gusto.getEmployee({employee_id = "missing"}) end)
		upstream(429, '{"errors":[{"category":"rate_limit_exceeded","message":"Too many requests"}]}', {["retry-after"] = {"30"}},
			{"Gusto HTTP 429: rate_limit_exceeded Too many requests; retry after 30s", '"retryable":true'})
		upstream(422, json.encode({errors = {{error_key = "employee_compensations", category = "nested_errors", errors = {
			{error_key = "fixed_compensations", category = "invalid_attribute_value", message = "Amount must be positive", metadata = {employee_uuid = "e9"}}}}}}), {},
			{"Gusto HTTP 422: nested_errors employee_compensations; invalid_attribute_value fixed_compensations Amount must be positive"},
			function() gusto.updatePayroll({company_id = "c1", payroll_id = "p1", employee_compensations = {{employee_uuid = "e9", version = "v"}}}) end)
		local many = {}
		for index = 1, 8 do table.insert(many, {category = "invalid_parameter", error_key = "field" .. index}) end
		local capped = upstream(422, json.encode({errors = many}), {}, {"field5"})
		assert(not string.find(capped, "field6", 1, true), "error list not capped")
		local dated = upstream(429, "", {["retry-after"] = {"Wed, 21 Oct 2026 07:28:00 GMT"}}, {"Gusto HTTP 429", '"retryable":true'})
		assert(not string.find(dated, "retry after", 1, true), "a dated Retry-After was reported as seconds")
		upstream(503, "<html>Unavailable</html>", {}, {"Gusto HTTP 503", '"retryable":true'})
		upstream(500, '{"errors":[{"category":"internal_error","message":"Something went wrong"}]}', {}, {"Gusto HTTP 500: internal_error", '"retryable":true'})
		upstream(200, "<html>Maintenance</html>", {}, {"invalid JSON"})
		upstream(200, "", {}, {"invalid JSON"}, function() gusto.listEmployees({company_id = "c1"}) end)
		upstream(200, '"text"', {}, {"invalid JSON"}, function() gusto.getCompany({company_id = "c1"}) end)
	end,
}
