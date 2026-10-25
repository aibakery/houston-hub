return {
	scenario = {publisher = {}, config = {}, auth_method = "token", auth_config = {token = "grn_fixture-private-key"}},
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
	run = function(granola)
		local NOTE = "not_1d3tmYTlCICgjy"
		local function upstream(code, body, headers, call, expected, absent)
			status, payload, responseHeaders = code, body, headers
			local before = calls
			local ok, err = pcall(call)
			for _, text in expected do
				assert(not ok and string.find(tostring(err), text, 1, true), "missing " .. text .. " in " .. tostring(err))
			end
			if absent then assert(not string.find(tostring(err), absent, 1, true), "unbounded error: " .. #tostring(err)) end
			assert(calls == before + 1, "a failed request was repeated")
		end
		local function list() granola.listNotes() end
		local function note() granola.getNote(NOTE, {include = "transcript"}) end

		upstream(401, '{"code":"INVALID_API_KEY","message":"Invalid API key format","requestId":"r1","timestamp":"2026-10-25T00:00:00Z"}', {}, list,
			{"HTTP 401", "INVALID_API_KEY", "Invalid API key format", "check the API key", '"retryable":false'})
		upstream(413, '{"code":"TRANSCRIPT_TOO_LARGE","message":"Transcript is too large to include"}', {}, note,
			{"HTTP 413", "TRANSCRIPT_TOO_LARGE", "getTranscript", '"retryable":false'})
		upstream(404, '{"error":"not_found","message":"The requested endpoint does not exist"}', {}, note, {"HTTP 404", "not_found", "access scopes"})
		upstream(400, '{"code":"VALIDATION_ERROR","message":"' .. string.rep("x", 5000) .. '"}', {}, list,
			{"HTTP 400", "VALIDATION_ERROR"}, string.rep("x", 301))
		upstream(429, '{"code":"RATE_LIMITED","message":"Too many requests"}', {["retry-after"] = {"7"}}, list,
			{"HTTP 429", "retry after 7s", '"retryable":true'})
		upstream(503, "<html>Unavailable</html>", {}, list, {"HTTP 503", '"retryable":true'})
		upstream(200, "<html>Maintenance</html>", {}, list, {"unexpected response", '"retryable":false'})
		upstream(200, "[]", {}, note, {"unexpected response"})
		upstream(200, '{"notes":null,"hasMore":false}', {}, list, {"unexpected response"})
		upstream(200, '{"folders":[]}', {}, list, {"unexpected response"})
	end,
}
