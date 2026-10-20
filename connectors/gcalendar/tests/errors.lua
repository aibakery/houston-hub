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
			local ok, err = pcall(c.insertEvent, {summary = "Planning", start = {date = "2026-10-21"}, ["end"] = {date = "2026-10-22"}})
			for _, text in expected do
				assert(not ok and string.find(tostring(err), text, 1, true), "missing " .. text .. " in " .. tostring(err))
			end
			assert(string.find(tostring(err), '"operation":"insertEvent"', 1, true), tostring(err))
			assert(calls == before + 1, "failed write was retried")
		end
		upstream(403, '{"error":{"code":403,"message":"Rate Limit Exceeded","errors":[{"domain":"usageLimits","reason":"rateLimitExceeded"}]}}', {},
			{"Google HTTP 403: Rate Limit Exceeded [rateLimitExceeded]", '"retryable":true'})
		upstream(403, '{"error":{"code":403,"message":"User Rate Limit Exceeded","errors":[{"domain":"usageLimits","reason":"userRateLimitExceeded"}]}}', {["retry-after"] = {"7"}},
			{"[userRateLimitExceeded]", "Retry-After: 7", '"retryable":true'})
		upstream(403, '{"error":{"code":403,"message":"Request had insufficient authentication scopes.","status":"PERMISSION_DENIED","errors":[{"reason":"insufficientPermissions"}]}}', {},
			{"HTTP 403 (PERMISSION_DENIED): Request had insufficient authentication scopes. [insufficientPermissions]", '"retryable":false'})
		upstream(409, '{"error":{"code":409,"message":"The requested identifier already exists.","errors":[{"reason":"duplicate"}]}}', {},
			{"HTTP 409", "[duplicate]", '"retryable":false'})
		upstream(429, '{"error":{"code":429,"message":"Too many requests","status":"RESOURCE_EXHAUSTED"}}', {["retry-after"] = {"30"}},
			{"HTTP 429 (RESOURCE_EXHAUSTED)", "Retry-After: 30", '"retryable":true'})
		upstream(401, "not json", {}, {"Google HTTP 401", '"retryable":false'})
		upstream(400, "<html><title>Error 400 (Bad Request)</title></html>", {}, {"Google HTTP 400", '"retryable":false'})
		upstream(503, '{"error":{"code":503,"message":"Backend Error","errors":[{"reason":"backendError"}]}}', {}, {"HTTP 503", '"retryable":true'})
		upstream(200, "<html>Maintenance</html>", {}, {"invalid JSON object"})
		upstream(200, "[]", {}, {"invalid JSON object"})
		upstream(200, "null", {}, {"invalid JSON object"})

		status, payload = 410, '{"error":{"code":410,"message":"Sync token is no longer valid, a full sync is required.","errors":[{"reason":"fullSyncRequired"}]}}'
		local ok, err = pcall(c.listEvents, {syncToken = "old"})
		assert(not ok and string.find(tostring(err), "[fullSyncRequired]", 1, true) and string.find(tostring(err), '"retryable":false', 1, true), tostring(err))
		status, payload = 404, '{"error":{"code":404,"message":"Not Found","errors":[{"reason":"notFound"}]}}'
		ok, err = pcall(c.getEvent, {eventId = "missing"})
		assert(not ok and string.find(tostring(err), "HTTP 404: Not Found [notFound]", 1, true) and string.find(tostring(err), '"operation":"getEvent"', 1, true), tostring(err))
	end,
}
