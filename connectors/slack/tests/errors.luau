return {
	scenario = {publisher = {client_id = "fixture-client", client_secret = "fixture-private-secret"}, config = {}, auth_method = "oauth", auth_config = {}},
	config = {access = "read-write"},
	configure = function()
		calls = 0
		http = {request = function()
			calls += 1
			return fixture.operation({statusCode = status, headers = responseHeaders, body = fixture.reader(payload)})
		end}
	end,
	run = function(slack)
		local function upstream(code, body, headers, expected, call)
			status, payload, responseHeaders = code, body, headers
			local before = calls
			local ok, err = pcall(call or function() slack.listMessages("C1") end)
			for _, text in expected do
				assert(not ok and string.find(tostring(err), text, 1, true), "missing " .. text .. " in " .. tostring(err))
			end
			assert(calls == before + 1, "failed call was retried")
		end
		upstream(200, '{"ok":false,"error":"not_in_channel"}', {}, {"slack: not_in_channel", '"upstream_status":200', '"retryable":false'})
		upstream(200, '{"ok":false,"error":"missing_scope","needed":"chat:write","provided":"channels:read"}', {},
			{"slack: missing_scope (needs chat:write)", "reconnect Slack", '"upstream_status":403', '"retryable":false'},
			function() slack.postMessage("C1", "Hi") end)
		upstream(200, '{"ok":false,"error":"token_revoked"}', {}, {"slack: token_revoked; reconnect Slack", '"upstream_status":401'})
		upstream(200, '{"ok":false,"error":"invalid_auth"}', {}, {"slack: invalid_auth", '"upstream_status":401'})
		upstream(429, '{"ok":false,"error":"ratelimited"}', {["retry-after"] = {"60"}},
			{"slack: ratelimited; retry after 60s", '"upstream_status":429', '"retryable":true'})
		upstream(200, '{"ok":false,"error":"internal_error"}', {}, {"slack: internal_error", '"retryable":true'})
		upstream(200, '{"ok":false,"error":"fatal_error"}', {}, {"slack: fatal_error", '"retryable":false'},
			function() slack.postMessage("C1", "Hi") end)
		upstream(503, "unavailable", {}, {"slack: HTTP 503", '"retryable":false'}, function() slack.deleteMessage("C1", "1.0") end)
		fs = fixture.files()
		local file = fs.open("report.txt", "w")
		file:write("report")
		await(file:close())
		upstream(503, "unavailable", {}, {"slack: HTTP 503", '"retryable":true'}, function() slack.uploadFile("report.txt") end)
		upstream(429, '{"ok":false,"error":"ratelimited"}', {["retry-after"] = {"30"}}, {"retry after 30s", '"retryable":true'},
			function() slack.addReaction("C1", "1.0", "eyes") end)
		upstream(503, "<html>Service unavailable</html>", {}, {"slack: HTTP 503", '"retryable":true'})
		upstream(200, "<html>Maintenance</html>", {}, {"slack: invalid JSON response"})
		upstream(200, "[]", {}, {"slack: invalid JSON response"})
		upstream(200, '{"ok":true}', {}, {"slack: response has no channel"}, function() slack.getChannel("C1") end)
		upstream(200, '{"ok":false,"error":"' .. string.rep("x", 5000) .. '"}', {}, {"slack: xxxx"})
		local ok, err = pcall(slack.listMessages, "C1")
		assert(not ok and #tostring(err) < 1000, "error messages stay bounded")
	end,
}
