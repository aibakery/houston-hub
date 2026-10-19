return {
	scenario = {publisher = {}, config = {access = "read-write"}, auth_method = "token", auth_config = {token = "fixture-key"}},
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
	run = function(crm)
		local function upstream(code, body, headers, expected)
			status, payload, responseHeaders = code, body, headers
			local before = calls
			local ok, err = pcall(function() crm.createNote({title = "Call notes"}) end)
			for _, text in expected do
				assert(not ok and string.find(tostring(err), text, 1, true), "missing " .. text .. " in " .. tostring(err))
			end
			assert(calls == before + 1, "failed write was retried")
		end
		upstream(401, '{"message":"Unauthorized"}', {}, {"Carta CRM HTTP 401: Unauthorized", '"retryable":false'})
		upstream(401, "Unauthorized", {}, {"Carta CRM HTTP 401", '"retryable":false'})
		upstream(400, '{"success":false,"error":"Folder not found","code":"FOLDER_NOT_FOUND"}', {},
			{"HTTP 400 (FOLDER_NOT_FOUND): Folder not found", '"retryable":false'})
		upstream(422, json.encode({success = false, error = string.rep("x", 5000)}), {}, {"HTTP 422"})
		upstream(429, '{"message":"Too many requests"}', {["ratelimit-reset"] = {"42"}}, {"HTTP 429", "rate limit resets in 42s", '"retryable":true'})
		upstream(502, "<html>Bad gateway</html>", {}, {"HTTP 502", '"retryable":true'})
		upstream(200, "<html>Maintenance</html>", {}, {"invalid JSON object"})
		upstream(200, "[]", {}, {"invalid JSON object"})
	end,
}
