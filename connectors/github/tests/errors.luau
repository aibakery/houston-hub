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
	run = function(github)
		local function upstream(code, body, headers, expected, absent)
			status, payload, responseHeaders = code, body, headers
			local before = calls
			local ok, err = pcall(function() github.createIssueComment({owner = "o", repo = "r", issue_number = 1, body = "Hi"}) end)
			assert(not ok and type(err) ~= "string", "lost the structured upstream error")
			for _, text in expected do
				assert(not ok and string.find(tostring(err), text, 1, true), "missing " .. text .. " in " .. tostring(err))
			end
			if absent then assert(not string.find(tostring(err), absent, 1, true), "unbounded error: " .. #tostring(err)) end
			assert(calls == before + 1, "failed write was retried")
		end
		upstream(404, '{"message":"Not Found","documentation_url":"https://docs.github.com/rest/issues/comments#create-an-issue-comment","status":"404"}', {},
			{"HTTP 404: Not Found", '"retryable":false', '"upstream_status":404'})
		upstream(422, '{"message":"Validation Failed","errors":[{"resource":"IssueComment","code":"missing_field","field":"body"}],"status":"422"}', {},
			{"HTTP 422: Validation Failed", "missing_field", "IssueComment", '"retryable":false'})
		upstream(403, '{"message":"Resource not accessible by personal access token","status":"403"}', {["x-accepted-github-permissions"] = {"issues=write; pull_requests=write"}},
			{"Resource not accessible", "needs permissions issues=write; pull_requests=write", '"retryable":false'})
		upstream(403, '{"message":"API rate limit exceeded for user ID 1.","status":"403"}', {["x-ratelimit-remaining"] = {"0"}, ["x-ratelimit-reset"] = {"1792193237"}},
			{"API rate limit exceeded", "rate limit resets at 1792193237", '"retryable":true'})
		upstream(403, '{"message":"You have exceeded a secondary rate limit.","status":"403"}', {["retry-after"] = {"60"}},
			{"secondary rate limit", "retry after 60s", '"retryable":true'})
		upstream(307, '{"message":"Temporary Redirect","url":"https://api.github.com/repositories/1/issues/1/comments"}', {location = {"https://api.github.com/repositories/1/issues/1/comments"}},
			{"HTTP 307", "renamed or transferred", '"retryable":false'})
		upstream(301, '{"message":"Moved Permanently"}', {location = {"https://api.github.com/user/1"}}, {"HTTP 301"}, "renamed")
		upstream(403, '{"message":"You have exceeded a secondary rate limit. Please wait a few minutes before you try again.","status":"403"}', {},
			{"secondary rate limit", '"retryable":true'})
		upstream(301, '{"message":"Moved Permanently"}', {location = {"https://api.github.com/repos/o/r/issues/9?token=x"}}, {"moved to /repos/o/r/issues/9"}, "token=x")
		upstream(429, '{"message":"Too many requests"}', {}, {"HTTP 429", '"retryable":true'})
		upstream(502, "<html>Bad gateway</html>", {}, {"HTTP 502", '"retryable":true'})
		upstream(400, json.encode({message = string.rep("x", 5000)}), {}, {"HTTP 400", string.rep("x", 600)}, string.rep("x", 601))
		upstream(422, json.encode({message = "Validation Failed", errors = {{code = string.rep("e", 5000)}}}), {["retry-after"] = {string.rep("9", 500)}},
			{"Validation Failed", string.rep("e", 500)}, string.rep("e", 601))
		upstream(403, '{"message":"slow down"}', {["retry-after"] = {string.rep("9", 500)}}, {"retry after " .. string.rep("9", 200) .. "s"}, string.rep("9", 201))
		upstream(201, "<html>Maintenance</html>", {}, {"invalid JSON"})
		upstream(201, "", {}, {"invalid JSON"})
	end,
}
