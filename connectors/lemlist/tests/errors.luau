return {
	scenario = {publisher = {}, config = {}, access = {data = "write"}, auth_method = "api_key", auth_config = {token = "lemlist_fixture_key"}},
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
	run = function(lemlist)
		local function upstream(code, body, headers, expected)
			status, payload, responseHeaders = code, body, headers
			local before = calls
			local ok, err = pcall(function() lemlist.startCampaign({campaignId = "cam_A1b2C3d4E5f6G7h8J"}) end)
			for _, text in expected do
				assert(not ok and string.find(tostring(err), text, 1, true), "missing " .. text .. " in " .. tostring(err))
			end
			assert(calls == before + 1, "failed write was retried")
		end
		upstream(401, "The authentication you supplied is incorrect", {}, {"lemlist HTTP 401", "authentication you supplied is incorrect", '"retryable":false'})
		upstream(402, "route is available starting emailPro plan", {}, {"HTTP 402", "emailPro", "plan does not include", '"retryable":false'})
		upstream(404, '{"error":"Campaign not found"}', {["content-type"] = {"application/json"}}, {"HTTP 404", "Campaign not found", '"retryable":false'})
		upstream(400, '{"error":"Invalid campaign state","code":"BAD_STATE"}', {}, {"HTTP 400", "(BAD_STATE)", "Invalid campaign state"})
		upstream(429, "Too Many Requests", {["retry-after"] = {"1.42"}}, {"HTTP 429", "Too Many Requests", "Retry-After: 1.42", '"retryable":true'})
		upstream(500, "<html>Internal error</html>", {}, {"HTTP 500", '"retryable":true'})
		upstream(503, '{"error":"Internal server error"}', {}, {"HTTP 503", "Internal server error", '"retryable":true'})

		status, payload = 402, '{"error":"Insufficient credits"}'
		local ok, err = pcall(function() lemlist.startCampaign({campaignId = "cam_A1b2C3d4E5f6G7h8J"}) end)
		assert(not ok and string.find(tostring(err), "Insufficient credits", 1, true) and not string.find(tostring(err), "plan does not include", 1, true), "402 is not always a plan gate")

		status, payload = 400, json.encode({error = string.rep("x", 5000), code = string.rep("C", 5000)})
		ok, err = pcall(function() lemlist.startCampaign({campaignId = "cam_A1b2C3d4E5f6G7h8J"}) end)
		assert(not ok and string.find(tostring(err), string.rep("x", 600), 1, true) and string.find(tostring(err), string.rep("C", 100), 1, true))
		assert(not string.find(tostring(err), string.rep("x", 601), 1, true) and not string.find(tostring(err), string.rep("C", 101), 1, true), "error bodies are bounded")

		status, payload = 404, "Lead not found"
		ok, err = pcall(function() lemlist.getLead({email = "ana@example.com"}) end)
		assert(not ok and string.find(tostring(err), "lemlist HTTP 404: Lead not found", 1, true) and string.find(tostring(err), '"retryable":false', 1, true), "reads share the error mapping")

		status, payload, responseHeaders = 200, "<html>Maintenance</html>", {}
		ok, err = pcall(function() lemlist.getCampaign({campaignId = "cam_A1b2C3d4E5f6G7h8J"}) end)
		assert(not ok and string.find(tostring(err), "invalid JSON", 1, true), "HTML is not a campaign")
		status, payload = 200, '{"campaign"'
		ok, err = pcall(function() lemlist.startCampaign({campaignId = "cam_A1b2C3d4E5f6G7h8J"}) end)
		assert(not ok and string.find(tostring(err), "invalid JSON", 1, true), "truncated JSON is not a confirmation")
	end,
}
