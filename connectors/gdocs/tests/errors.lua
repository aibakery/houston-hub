return {
	scenario = {publisher = {client_id = "fixture-client", client_secret = "fixture-private-secret"}, config = {}, auth_method = "oauth", auth_config = {}},
	config = {access = "read-write"},
	configure = function()
		calls, status, payload, responseHeaders = 0, 200, "{}", {}
		http = {request = function(req)
			calls += 1
			return fixture.operation({statusCode = status, headers = responseHeaders, body = fixture.reader(payload)})
		end}
	end,
	run = function(c)
		local function upstream(code, body, headers, expected)
			status, payload, responseHeaders = code, body, headers
			local before = calls
			local ok, err = pcall(c.batchUpdate, {documentId = "d1", requests = {{deleteContentRange = {range = {startIndex = 1, endIndex = 5}}}}})
			for _, text in expected do
				assert(not ok and string.find(tostring(err), text, 1, true), "missing " .. text .. " in " .. tostring(err))
			end
			assert(calls == before + 1, "failed write was retried")
		end
		upstream(403, '{"error":{"code":403,"message":"The caller does not have permission","status":"PERMISSION_DENIED"}}', {},
			{"HTTP 403 (PERMISSION_DENIED): The caller does not have permission", '"retryable":false'})
		upstream(400, '{"error":{"code":400,"message":"Invalid requests[0].deleteContentRange: The range cannot include the newline character at the end of the segment.","status":"INVALID_ARGUMENT"}}', {},
			{"HTTP 400 (INVALID_ARGUMENT)", "newline character at the end of the segment", '"retryable":false'})
		upstream(429, '{"error":{"code":429,"message":"Quota exceeded for quota metric \'Write requests\' and limit \'Write requests per minute per user\'","status":"RESOURCE_EXHAUSTED"}}', {["retry-after"] = {"30"}},
			{"HTTP 429 (RESOURCE_EXHAUSTED)", "Retry-After: 30", '"retryable":true'})
		upstream(400, "<html><title>Error 400 (Bad Request)</title></html>", {}, {"Google HTTP 400", '"retryable":false'})
		upstream(503, '{"error":{"code":503,"message":"The service is currently unavailable.","status":"UNAVAILABLE"}}', {}, {"HTTP 503", '"retryable":true'})
		upstream(200, "<html>Maintenance</html>", {}, {"invalid JSON object"})
		upstream(200, "[]", {}, {"invalid JSON object"})
		status, payload = 404, '{"error":{"code":404,"message":"Requested entity was not found.","status":"NOT_FOUND"}}'
		local before = calls
		local ok, err = pcall(c.getDocument, {documentId = "missing"})
		assert(not ok and string.find(tostring(err), "NOT_FOUND", 1, true) and string.find(tostring(err), '"operation":"getDocument"', 1, true), tostring(err))
		assert(string.find(tostring(err), '"retryable":false', 1, true) and calls == before + 1, tostring(err))
	end,
}
