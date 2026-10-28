return {
	scenario = {publisher = {}, config = {access = "read-write"}, auth_method = "token", auth_config = {token = "fixture-key"}},
	configure = function()
		calls = 0
		status = 200
		payload = "{}"
		responseHeaders = {}
		http = {request = function(req)
			calls += 1
			assert(req.method == "POST" and req.headers.Authorization == nil)
			return fixture.operation({statusCode = status, headers = responseHeaders, body = fixture.reader(payload)})
		end}
	end,
	run = function(linear)
		local function upstream(code, body, headers, expected, unexpected)
			status, payload, responseHeaders = code, body, headers
			local before = calls
			local ok, err = pcall(function() linear.updateIssue({id = "ENG-1", input = {priority = 1}}) end)
			for _, text in expected do
				assert(not ok and string.find(tostring(err), text, 1, true), "missing " .. text .. " in " .. tostring(err))
			end
			for _, text in unexpected or {} do
				assert(not string.find(tostring(err), text, 1, true), "unexpected " .. text .. " in " .. tostring(err))
			end
			assert(calls == before + 1, "failed write was retried")
		end
		upstream(401, '{"errors":[{"message":"Authentication required, not authenticated","extensions":{"type":"authentication error","code":"AUTHENTICATION_ERROR","statusCode":401,"userError":true,"userPresentableMessage":"You need to authenticate to access this operation."}}]}', {},
			{"Linear HTTP 401", "AUTHENTICATION_ERROR: You need to authenticate", '"retryable":false'}, {"not authenticated"})
		upstream(400, '{"errors":[{"message":"Cannot query field \\"nosuchfield\\" on type \\"Issue\\".","extensions":{"code":"GRAPHQL_VALIDATION_FAILED","type":"graphql error"}}]}', {},
			{"Linear HTTP 400", "GRAPHQL_VALIDATION_FAILED", "nosuchfield", '"retryable":false'})
		upstream(429, '{"errors":[{"message":"Rate limit exceeded","extensions":{"code":"RATELIMITED"}}]}', {["retry-after"] = {"42"}, ["x-ratelimit-requests-reset"] = {"1793145600000"}},
			{"Linear HTTP 429", "RATELIMITED", "retry-after 42; x-ratelimit-requests-reset 1793145600000", '"retryable":true'})
		-- Linear can answer 200 with errors and no data; a rate-limit code is retryable at any status.
		upstream(200, '{"data":null,"errors":[{"message":"Entity not found: Issue","extensions":{"code":"INVALID_INPUT","userPresentableMessage":"Could not find referenced Issue."}},{"message":"busy","extensions":{"code":"RATELIMITED"}}]}', {},
			{"Linear HTTP 200", "INVALID_INPUT: Could not find referenced Issue.; RATELIMITED: busy", '"retryable":true'})
		upstream(400, json.encode({errors = {{message = string.rep("x", 5000), extensions = {code = "INVALID_INPUT"}}, {message = "b"}, {message = "c"}, {message = "fourth"}}}), {},
			{"INVALID_INPUT: xxx", "; b; c"}, {"fourth", string.rep("x", 601)})
		upstream(502, "<html>Bad gateway</html>", {}, {"Linear HTTP 502: <html>Bad gateway</html>", '"retryable":true'})
		upstream(200, '{"errors":[]}', {}, {"invalid GraphQL response"})
		upstream(200, '{"data":{"issueUpdate":null},"errors":[{"message":"Forbidden"}]}', {}, {"Linear answered issueUpdate with errors", "Forbidden"})
	end,
}
