return {
	scenario = {publisher = {}, config = {access = "read-write", team = "My-Team"}, auth_method = "token", auth_config = {token = "fixture-token"}},
	configure = function()
		calls = 0
		status = 200
		payload = "{}"
		responseHeaders = {}
		lastUrl = ""
		http = {request = function(req)
			calls += 1
			lastUrl = req.url
			return fixture.operation({statusCode = status, headers = responseHeaders, body = fixture.reader(payload)})
		end}
	end,
	run = function(vercel)
		local function upstream(code, body, headers, expected)
			status, payload, responseHeaders = code, body, headers
			local before = calls
			local ok, err = pcall(function() vercel.cancelDeployment({id = "dpl_1"}) end)
			for _, text in expected do
				assert(not ok and string.find(tostring(err), text, 1, true), "missing " .. text .. " in " .. tostring(err))
			end
			assert(calls == before + 1, "failed write was retried")
		end
		upstream(403, '{"error":{"code":"forbidden","message":"Not authorized","invalidToken":true}}', {},
			{"Vercel HTTP 403 (forbidden): Not authorized", '"retryable":false'})
		-- A slug team goes lowercased as slug.
		assert(lastUrl == "https://api.vercel.com/v12/deployments/dpl_1/cancel?slug=my-team", lastUrl)
		upstream(400, '{"error":{"code":"bad_request","message":"The deployment is already READY"}}', {},
			{"HTTP 400 (bad_request): The deployment is already READY", '"retryable":false'})
		upstream(400, json.encode({error = {code = "bad_request", message = string.rep("x", 5000)}}), {}, {"(bad_request): xxx"})
		upstream(429, '{"error":{"code":"rate_limited","message":"The rate limit of 100 exceeded","limit":{"remaining":0,"reset":1793143768}}}', {["x-ratelimit-reset"] = {"1793143768"}},
			{"HTTP 429 (rate_limited)", "rate limit resets at Unix time 1793143768", '"retryable":true'})
		upstream(503, "<html>Unavailable</html>", {}, {"Vercel HTTP 503", '"retryable":true'})
		upstream(200, "<html>Maintenance</html>", {}, {"invalid JSON object"})
		upstream(200, "[]", {}, {"invalid JSON object"})

		status, payload = 404, '{"error":{"code":"not_found","message":"Deployment not found"}}'
		local ok, err = pcall(function() vercel.listRuntimeLogs({projectId = "prj_1", deploymentId = "dpl_1"}) end)
		assert(not ok and string.find(tostring(err), "HTTP 404 (not_found): Deployment not found", 1, true), tostring(err))
		status, payload = 200, '{"projects":"nope"}'
		ok, err = pcall(function() vercel.listProjects() end)
		assert(not ok and string.find(tostring(err), "invalid project list", 1, true), tostring(err))
	end,
}
