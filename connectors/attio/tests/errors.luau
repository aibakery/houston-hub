return {
	scenario = {publisher = {}, config = {}, auth_method = "token", auth_config = {token = "attio-fixture-private-key"}},
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
	run = function(attio)
		local RECORD = "891dcbfc-9141-415d-9b2a-2238a6cc012d"
		local function upstream(code, body, headers, call, expected, absent)
			status, payload, responseHeaders = code, body, headers
			local before = calls
			local ok, err = pcall(call)
			for _, text in expected do
				assert(not ok and string.find(tostring(err), text, 1, true), "missing " .. text .. " in " .. tostring(err))
			end
			if absent then assert(not string.find(tostring(err), absent, 1, true), "unbounded error: " .. #tostring(err)) end
			assert(calls == before + 1, "a failed request was repeated")
		end
		local function list() attio.listNotes() end
		local function query() attio.queryRecords("people", {limit = 10}) end
		local function record() attio.getRecord("people", RECORD) end

		upstream(401, '{"status_code":401,"type":"auth_error","code":"unauthorized","message":"Authentication failed."}', {}, list,
			{"Attio HTTP 401 unauthorized: Authentication failed.", "check the connection's API key", '"retryable":false', '"upstream_status":401'})
		upstream(403, '{"status_code":403,"type":"auth_error","code":"missing_scopes","message":"Token is missing scope note:read"}', {}, list,
			{"HTTP 403 missing_scopes", "note:read", "lacks a scope", '"retryable":false'})
		upstream(404, '{"status_code":404,"type":"invalid_request_error","code":"not_found","message":"Record not found."}', {}, record,
			{"HTTP 404 not_found: Record not found.", '"retryable":false'}, "API key")
		upstream(400, '{"status_code":400,"type":"invalid_request_error","code":"validation_type","message":"' .. string.rep("x", 1000) .. '"}', {}, query,
			{"HTTP 400 validation_type: " .. string.rep("x", 300)}, string.rep("x", 301))
		upstream(400, '{"code":"validation_type","message":"' .. string.rep("x", 5000) .. '"}', {}, query, {"Attio HTTP 400"}, "xxx")
		upstream(429, '{"status_code":429,"type":"rate_limit_error","code":"rate_limit_exceeded","message":"Rate limit exceeded, please try again later"}',
			{["retry-after"] = {"Sun, 01 Nov 2026 12:00:05 GMT"}}, query,
			{"HTTP 429 rate_limit_exceeded", "retry after Sun, 01 Nov 2026 12:00:05 GMT", '"retryable":true'})
		upstream(502, "<html>Bad gateway</html>", {}, list, {"Attio HTTP 502", '"retryable":true'}, "html")
		upstream(200, "<html>Maintenance</html>", {}, list, {"unexpected response", '"retryable":false'})
		upstream(200, "[]", {}, record, {"unexpected response"})
		upstream(200, '{"data":null}', {}, list, {"unexpected response"})
		upstream(200, '{"active":false}', {}, list, {"unexpected response"})

		status, payload = 200, '{"active":false}'
		assert(attio.identify().active == false, "identify returns the token state unchanged")
	end,
}
