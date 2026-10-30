return {
	scenario = {publisher = {}, config = {access = "read-write", organization = "acme"}, auth_method = "token", auth_config = {token = "fixture-token"}},
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
	run = function(sentry)
		local function failure(call, code, body, headers, expected)
			status, payload, responseHeaders = code, body, headers
			local before = calls
			local ok, err = pcall(call)
			for _, text in expected do
				assert(not ok and string.find(tostring(err), text, 1, true), "missing " .. text .. " in " .. tostring(err))
			end
			assert(calls == before + 1, "failed request was retried")
		end
		local function update() sentry.updateIssue({issue_id = "1001", status = "resolved"}) end
		local function comment() sentry.addIssueComment({issue_id = "1001", text = "Same"}) end
		local function latest() sentry.getIssueEvent({issue_id = "1001", event_id = "latest"}) end

		failure(update, 401, '{"detail":"Invalid token"}', {}, {"Sentry HTTP 401: Invalid token", '"upstream_status":401', '"retryable":false'})
		failure(update, 403, '{"detail":"You do not have permission to perform this action."}', {}, {"HTTP 403: You do not have permission", '"retryable":false'})
		failure(update, 400, '{"statusDetails":["Invalid release"]}', {}, {"HTTP 400: {", "statusDetails", "Invalid release", '"retryable":false'})
		failure(comment, 400, '{"detail":"You have already posted that comment."}', {}, {"already posted that comment", '"retryable":false'})
		failure(update, 400, json.encode({detail = string.rep("x", 5000)}), {}, {"HTTP 400: xxx"})
		failure(update, 404, '{"detail":"The requested resource does not exist"}', {}, {"HTTP 404: The requested resource does not exist", '"retryable":false'})
		failure(update, 429, '{"detail":"You are attempting to use this endpoint too frequently. Limit is 40 requests in 1 seconds"}',
			{["x-sentry-rate-limit-reset"] = {"1793340868"}}, {"HTTP 429: You are attempting", "rate limit resets at Unix time 1793340868", '"retryable":true'})
		failure(latest, 502, "<html>Bad gateway</html>", {}, {"Sentry HTTP 502", '"retryable":true'})
		failure(update, 200, "<html>Maintenance</html>", {}, {"invalid JSON object"})
		failure(latest, 200, "not json", {}, {"Sentry returned invalid JSON"})
		failure(latest, 200, "[1,2]", {}, {"Sentry returned an invalid event"})
		failure(function() sentry.listIssues() end, 200, '{"detail":"not a list"}', {}, {"Sentry returned an invalid list"})
		failure(function() sentry.listIssueEvents({issue_id = "1001"}) end, 200, '{"id":"x"}', {}, {"Sentry returned an invalid list"})
		failure(latest, 200, '{"id":"' .. string.rep("a", 4 * 1024 * 1024) .. '"}', {}, {"more than 4 MiB", '"retryable":false'})
	end,
}
