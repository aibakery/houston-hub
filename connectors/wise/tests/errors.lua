return {
	scenario = {config = {access = "read-write"}, auth_method = "token", auth_config = {token = "fixture-wise-token"}},
	configure = function()
		calls, status, payload, responseHeaders = 0, 200, "{}", {}
		http = {request = function(req)
			calls += 1
			return fixture.operation({statusCode = status, headers = responseHeaders, body = fixture.reader(payload)})
		end}
	end,
	run = function(c)
		local function fails(code, body, headers, expected, absent, read)
			status, payload, responseHeaders = code, body, headers
			local before = calls
			local ok, err
			if read then
				ok, err = pcall(c.getTransfer, {transferId = 9001})
			else
				ok, err = pcall(c.fundTransfer, {profileId = 202, transferId = 9001, type = "BALANCE"})
			end
			for _, part in expected do assert(not ok and string.find(tostring(err), part, 1, true), "missing " .. part .. " in " .. tostring(err)) end
			if absent then assert(not string.find(tostring(err), absent, 1, true), "leaked " .. absent) end
			assert(#tostring(err) < 2200, "unbounded error message")
			assert(calls == before + 1, "a financial write was retried")
		end
		fails(400, '{"errors":[{"code":"error.transfer.invalid","message":"Transfer cannot be funded","path":"transferId","arguments":["9001"]}]}', {["x-trace-id"] = {"trace-1"}},
			{"Wise HTTP 400", "code=error.transfer.invalid", "message=Transfer cannot be funded", "path=transferId", "x-trace-id=trace-1", '"retryable":false'})
		fails(401, '{"error":"invalid_token","error_description":"Invalid token"}', {}, {"HTTP 401", "invalid_token", "Invalid token", '"retryable":false'})
		fails(403, '{"timestamp":"2026-10-16T10:00:00Z","status":403,"error":"Forbidden","message":"You are forbidden to send this request","path":"/v3/profiles/202/transfers/9001/payments"}',
			{["x-2fa-approval-result"] = {"REJECTED"}, ["x-2fa-approval"] = {"one-time-token-secret"}},
			{"HTTP 403", "Forbidden", "strong customer authentication required", "Wise app", '"retryable":false'}, "one-time-token-secret")
		fails(404, '{"error":"Not Found","status":"404","message":"Resource not found"}', {}, {"HTTP 404", "Resource not found", '"retryable":false'})
		fails(429, '{"errors":[{"code":"rate.limited","message":"Too many requests"}]}', {["retry-after"] = {"30"}}, {"HTTP 429", "retry-after=30", '"retryable":true'})
		fails(503, string.rep("<html>", 20000), {}, {"HTTP 503", '"retryable":false'})
		fails(503, "<html>Unavailable</html>", {}, {"HTTP 503", "Unavailable", '"retryable":true'}, nil, true)
		local long = string.rep("y", 250)
		local item = {code = long, message = long, path = long}
		fails(400, json.encode({errors = {item, item, item, item, item, item}, error = long, error_description = long, message = long}), {["retry-after"] = {long}, ["x-trace-id"] = {long}}, {"HTTP 400"})
		fails(500, string.rep("X", 100000), {["x-2fa-approval-result"] = {"APPROVED"}}, {"HTTP 500", '"retryable":true'}, "strong customer authentication", true)
		fails(400, '{"errors":[{"code":"balance.insufficient"}]}', {["x-2fa-approval-result"] = {"APPROVED"}}, {"HTTP 400", "balance.insufficient", '"retryable":false'}, "strong customer authentication")
		fails(403, '{"error":"Forbidden","message":"Read only token"}', {["x-2fa-approval-result"] = {"APPROVED"}}, {"HTTP 403", "Read only token", '"retryable":false'}, "strong customer authentication")
		fails(200, '{"data":"' .. string.rep("z", 8 * 1024 * 1024) .. '"}', {}, {"exceeded 8 MiB", "narrow the interval"}, nil, true)
		status, payload, responseHeaders = 503, "Unavailable", {}
		local ok, err = pcall(c.createQuote, {profileId = 202, sourceCurrency = "EUR", targetCurrency = "GBP", sourceAmount = 1})
		assert(not ok and string.find(tostring(err), '"retryable":true', 1, true), "a quote 5xx should be retryable: " .. tostring(err))
		fails(200, "not json", {}, {"accepted the request but returned an invalid JSON response", "check the result", '"retryable":false'})
		fails(422, '{"title":"Invalid","detail":"targetAccount not found"}', {}, {"HTTP 422", "targetAccount not found"})
		fails(400, '{"errors":[{"arguments":["9001"]}]}', {}, {"HTTP 400: {", "9001"}, "; ;")
		fails(201, '"text"', {}, {"invalid JSON response"})
		fails(200, "", {}, {"Wise returned an invalid JSON response"}, nil, true)
	end,
}
