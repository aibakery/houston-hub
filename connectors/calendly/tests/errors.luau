return {
	scenario = {publisher = {}, config = {access = "read-write"}, auth_method = "token", auth_config = {token = "fixture-token"}},
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
	run = function(calendly)
		local function upstream(code, body, headers, expected)
			status, payload, responseHeaders = code, body, headers
			local before = calls
			local ok, err = pcall(function() calendly.cancelScheduledEvent({event = "E1", reason = "Conflict"}) end)
			for _, text in expected do
				assert(not ok and string.find(tostring(err), text, 1, true), "missing " .. text .. " in " .. tostring(err))
			end
			assert(calls == before + 1, "failed write was retried")
		end
		upstream(403, '{"title":"Insufficient scope","message":"This operation requires the scopes listed in the required_scopes array.","required_scopes":["scheduled_events:write"]}', {},
			{"HTTP 403", "Insufficient scope", "required_scopes", "scheduled_events:write", '"retryable":false'})
		upstream(400, '{"title":"Invalid Argument","message":"The supplied parameters are invalid.","details":[{"parameter":"reason","message":"is too long"}]}', {},
			{"HTTP 400", "Invalid Argument", "reason", "is too long"})
		upstream(400, json.encode({title = "Invalid Argument", message = string.rep("x", 5000), details = {{parameter = "reason", message = "is too long"}}}), {},
			{"Invalid Argument", "is too long"})
		upstream(429, '{"title":"Too Many Requests","message":"Rate limit exceeded"}', {["x-ratelimit-reset"] = {"42"}},
			{"HTTP 429", "rate limit resets in 42s", '"retryable":true'})
		upstream(500, "<html>Internal error</html>", {}, {"HTTP 500", '"retryable":true'})
		upstream(201, "<html>Maintenance</html>", {}, {"invalid JSON object"})
		upstream(201, "[]", {}, {"invalid JSON object"})
	end,
}
