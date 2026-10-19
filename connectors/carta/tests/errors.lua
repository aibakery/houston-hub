return {
	scenario = {publisher = {client_id = "fixture-client", client_secret = "fixture-secret"}, config = {access = "read-write"}, auth_method = "carta", auth_config = {}},
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
	run = function(carta)
		local function upstream(code, body, headers, expected, call)
			status, payload, responseHeaders = code, body, headers
			local before = calls
			local ok, err = pcall(call or function()
				carta.createCapitalCall({firmId = "FIRM1", fundId = "FUND1", externalReferenceId = "ref-1", sourceSystem = "houston",
					dueDate = "2026-11-01", amount = {currencyCode = "USD", value = "1.00"}, postAsDraft = true})
			end)
			for _, text in expected do
				assert(not ok and string.find(tostring(err), text, 1, true), "missing " .. text .. " in " .. tostring(err))
			end
			assert(calls == before + 1, "failed write was retried")
			return tostring(err)
		end
		upstream(403, '{"code":7,"message":"Access to resource denied","details":[{"@type":"type.googleapis.com/carta.proto.publicapi.errors.v1alpha1.ErrorInfo","reason":"INSUFFICIENT_SCOPE","metadata":{}}]}', {},
			{"Carta HTTP 403", "(INSUFFICIENT_SCOPE)", "Access to resource denied", '"retryable":false'})
		upstream(401, '{"code":16,"message":"Unauthenticated","details":[{"reason":"MISSING_OR_INVALID_ACCESS_TOKEN"}]}', {},
			{"Carta HTTP 401 (MISSING_OR_INVALID_ACCESS_TOKEN): Unauthenticated"})
		upstream(401, "Unauthorized", {}, {"Carta HTTP 401", '"upstream_status":401'})
		local long = upstream(409, json.encode({code = 6, message = string.rep("x", 5000), details = {}}), {}, {"Carta HTTP 409: xxx", '"retryable":false'})
		assert(not string.find(long, string.rep("x", 601), 1, true), "error message not bounded")
		upstream(404, '{"code":5,"message":"Resource not found","details":[]}', {}, {"Carta HTTP 404: Resource not found"},
			function() carta.getIssuer({id = "999"}) end)
		upstream(429, '{"message":"API rate limit exceeded"}', {["ratelimit-reset"] = {"1"}},
			{"Carta HTTP 429: API rate limit exceeded", "rate limit resets in 1s", '"retryable":true'})
		upstream(503, '{"code":14,"message":"Service unavailable","details":[]}', {}, {"Carta HTTP 503", '"retryable":true'})
		upstream(500, "<html>Internal error</html>", {}, {"Carta HTTP 500", '"retryable":true'})
		upstream(200, "<html>Maintenance</html>", {}, {"invalid JSON object"})
		upstream(200, "[]", {}, {"invalid JSON object"}, function() carta.listIssuers() end)
		upstream(200, "", {}, {"invalid JSON object"}, function() carta.listFirms() end)
	end,
}
