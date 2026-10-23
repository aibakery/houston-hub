return {
	scenario = {publisher = {}, config = {access = "read-write"}, auth_method = "api_key", auth_config = {token = "cal_live_fixture"}},
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
	run = function(cal)
		local function upstream(code, body, headers, expected)
			status, payload, responseHeaders = code, body, headers
			local before = calls
			local ok, err = pcall(function() cal.cancelBooking({bookingUid = "b1", cancellationReason = "Conflict"}) end)
			for _, text in expected do
				assert(not ok and string.find(tostring(err), text, 1, true), "missing " .. text .. " in " .. tostring(err))
			end
			assert(calls == before + 1, "failed write was retried")
		end
		upstream(401, '{"status":"error","timestamp":"2026-10-14T09:00:00Z","path":"/v2/bookings/b1/cancel","error":{"code":"UnauthorizedException","message":"Invalid API key","details":{"statusCode":401}}}', {},
			{"HTTP 401", "UnauthorizedException", "Invalid API key"})
		upstream(400, '{"status":"error","error":{"code":"BadRequestException","message":"Bad Request","details":{"message":["cancellationReason must be a string"]}}}', {},
			{"HTTP 400", "BadRequestException", "cancellationReason must be a string"})
		upstream(400, json.encode({status = "error", error = {code = "BadRequestException", message = string.rep("x", 5000), details = {message = {"start must be a date"}}}}), {},
			{"BadRequestException", "start must be a date"})
		upstream(429, '{"status":"error","error":{"code":"ThrottlerException","message":"Too Many Requests"}}', {["retry-after"] = {"60"}},
			{"HTTP 429", "ThrottlerException", "Retry-After: 60"})
		upstream(500, "<html>Internal error</html>", {}, {"HTTP 500"})
		upstream(200, '{"status":"error","error":{"code":"NotFoundException","message":"Booking not found"}}', {},
			{"HTTP 200", "NotFoundException", "Booking not found"})
		upstream(200, "<html>Maintenance</html>", {}, {"invalid JSON object"})
		upstream(200, "[]", {}, {"invalid JSON object"})
	end,
}
