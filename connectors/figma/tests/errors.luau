return {
	scenario = {publisher = {}, config = {access = "read-write"}, auth_method = "token", auth_config = {token = "figd_fixture"}},
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
	run = function(figma)
		local function upstream(code, body, headers, expected)
			status, payload, responseHeaders = code, body, headers
			local before = calls
			local ok, err = pcall(function() figma.postComment({file_key = "aBcDeFgHiJkLmNoPqRsTuV12", message = "Hi"}) end)
			for _, text in expected do
				assert(not ok and string.find(tostring(err), text, 1, true), "missing " .. text .. " in " .. tostring(err))
			end
			assert(calls == before + 1, "failed write was retried")
		end
		upstream(403, '{"status":403,"err":"Invalid token"}', {}, {"Figma HTTP 403: Invalid token", '"retryable":false'})
		upstream(400, '{"error":true,"status":400,"message":"Comment message is required"}', {}, {"Figma HTTP 400: Comment message is required"})
		upstream(404, json.encode({status = 404, err = string.rep("x", 5000)}), {}, {"Figma HTTP 404: xxx"})
		upstream(429, '{"status":429,"err":"Rate limit exceeded"}', {["retry-after"] = {"60"}, ["x-figma-rate-limit-type"] = {"low"}, ["x-figma-plan-tier"] = {"starter"}},
			{"Figma HTTP 429: Rate limit exceeded; retry-after 60; x-figma-rate-limit-type low; x-figma-plan-tier starter", '"retryable":true'})
		upstream(500, "<html>Error</html>", {}, {"Figma HTTP 500", '"retryable":true'})
		upstream(200, "<html>Maintenance</html>", {}, {"invalid JSON object"})
		upstream(200, "[]", {}, {"invalid JSON object"})
	end,
}
