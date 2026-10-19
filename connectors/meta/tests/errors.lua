return {
	scenario = {publisher = {}, config = {access = "read-write"}, auth_method = "token", auth_config = {token = "fixture-page-token"}},
	configure = function()
		calls = 0
		status, payload, responseHeaders = 200, "{}", {}
		http = {request = function(req)
			calls += 1
			return fixture.operation({statusCode = status, headers = responseHeaders, body = fixture.reader(payload)})
		end}
	end,
	run = function(meta)
		local function upstream(code, body, headers, expected, absent)
			status, payload, responseHeaders = code, body, headers
			local before = calls
			local ok, err = pcall(function() meta.createPost({message = "Fresh bread"}) end)
			for _, text in expected do
				assert(not ok and string.find(tostring(err), text, 1, true), "missing " .. text .. " in " .. tostring(err))
			end
			if absent then assert(not string.find(tostring(err), absent, 1, true), "unexpected " .. absent .. " in " .. tostring(err)) end
			assert(calls == before + 1, "failed write was retried")
		end
		upstream(400, '{"error":{"message":"(#200) The permission(s) pages_manage_posts are not available.","type":"OAuthException","code":200,"fbtrace_id":"AZSAqjOKJ6IRMp"}}', {},
			{"Meta HTTP 400 (#200)", "pages_manage_posts", "fbtrace_id AZSAqjOKJ6IRMp", '"retryable":false', '"upstream_status":400'})
		upstream(400, '{"error":{"message":"Invalid parameter","type":"OAuthException","code":100,"error_subcode":1363026,"error_user_msg":"The scheduled time must be at least 10 minutes ahead."}}', {},
			{"(#100/1363026): Invalid parameter The scheduled time must be at least 10 minutes ahead.", '"retryable":false'})
		upstream(401, '{"error":{"message":"Invalid OAuth access token - Cannot parse access token","type":"OAuthException","code":190}}', {},
			{"Meta HTTP 401 (#190)", "create a new one and update the connection", '"retryable":false'})
		upstream(400, '{"error":{"message":"(#80001) There have been too many calls to this Page account.","type":"OAuthException","code":80001}}',
			{["x-business-use-case-usage"] = {'{"101":[{"type":"pages","call_count":100,"total_cputime":20,"total_time":20,"estimated_time_to_regain_access":12.5}]}'}},
			{"(#80001)", "succeed again in about 13 min", '"retryable":true'})
		upstream(400, '{"error":{"message":"(#4) Application request limit reached","type":"OAuthException","code":4}}', {["x-business-use-case-usage"] = {"not json"}},
			{"(#4)", '"retryable":true'}, "succeed again")
		upstream(400, '{"error":{"message":"(#613) Calls to this api have exceeded the rate limit.","type":"OAuthException","code":613}}',
			{["x-business-use-case-usage"] = {'{"101":[{"estimated_time_to_regain_access":0}]}'}}, {"(#613)", '"retryable":true'}, "succeed again")
		upstream(400, '{"error":{"message":"(#368) The action attempted has been deemed abusive","type":"OAuthException","code":368}}', {},
			{"(#368)", '"retryable":false'})
		upstream(500, '{"error":{"message":"Service temporarily unavailable","type":"FacebookApiException","code":2,"is_transient":true}}', {},
			{"Meta HTTP 500 (#2)", '"retryable":true'})
		upstream(400, '{"error":{"message":"An unexpected error has occurred.","type":"OAuthException","code":1,"is_transient":true}}', {},
			{"(#1)", '"retryable":true'})
		upstream(429, "", {}, {"Meta HTTP 429", '"retryable":true'})
		upstream(502, "<html>Bad gateway</html>", {}, {"Meta HTTP 502", '"retryable":true'})
		upstream(400, json.encode({error = {message = string.rep("x", 5000), code = 100}}), {}, {"(#100)"})
		upstream(200, "<html>Maintenance</html>", {}, {"invalid JSON object", '"upstream_status":200'})
		upstream(200, "[]", {}, {"invalid JSON object"})
	end,
}
