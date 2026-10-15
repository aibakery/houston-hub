return {
	scenario = {publisher = {}, config = {access = "read-write"}, auth_method = "api_key", auth_config = {token = "re_fixture"}},
	configure = function()
		calls = 0
		status = 200
		payload = "{}"
		responseHeaders = {}
		cdnStatus = 200
		http = {request = function(req)
			calls += 1
			if string.find(req.url, "^https://inbound%-cdn%.resend%.com/") then
				return fixture.operation({statusCode = cdnStatus, headers = {}, body = fixture.reader("<Error><Code>AccessDenied</Code></Error>")})
			end
			return fixture.operation({statusCode = status, headers = responseHeaders, body = fixture.reader(payload)})
		end}
	end,
	run = function(resend)
		local function upstream(code, body, headers, expected)
			status, payload, responseHeaders = code, body, headers
			local before = calls
			local ok, err = pcall(function() resend.sendEmail({from = "hello@acme.com", to = "ana@example.com", subject = "Hi", text = "Hello"}) end)
			for _, text in expected do
				assert(not ok and string.find(tostring(err), text, 1, true), "missing " .. text .. " in " .. tostring(err))
			end
			assert(calls == before + 1, "failed send was retried")
		end
		upstream(422, '{"statusCode":422,"message":"The `to` field is missing.","name":"missing_required_field"}', {},
			{"HTTP 422", "missing_required_field", "The `to` field is missing.", '"retryable":false'})
		upstream(403, '{"statusCode":403,"message":"The acme.com domain is not verified.","name":"validation_error"}', {},
			{"HTTP 403", "validation_error", "domain is not verified", '"retryable":false'})
		upstream(401, '{"message":"This API key is restricted to only send emails.","name":"restricted_api_key","statusCode":401}', {},
			{"HTTP 401", "restricted_api_key", "only send emails", '"retryable":false'})
		upstream(400, json.encode({statusCode = 400, name = "validation_error", message = string.rep("x", 5000)}), {},
			{"HTTP 400", "validation_error"})
		local ok, err = pcall(function() resend.sendEmail({from = "hello@acme.com", to = "ana@example.com", subject = "Hi", text = "Hello"}) end)
		assert(not ok and string.find(tostring(err), string.rep("x", 600), 1, true) and not string.find(tostring(err), string.rep("x", 601), 1, true), "message not capped at 600 characters")
		upstream(429, '{"statusCode":429,"message":"Too many requests.","name":"rate_limit_exceeded"}', {["retry-after"] = {"1"}},
			{"HTTP 429", "rate_limit_exceeded", "Retry-After: 1", '"retryable":true'})
		upstream(429, '{"statusCode":429,"message":"You have reached your daily email sending quota.","name":"daily_quota_exceeded"}', {},
			{"HTTP 429", "daily_quota_exceeded", '"retryable":false'})
		upstream(429, "Too Many Requests", {}, {"HTTP 429", '"retryable":true'})
		upstream(409, '{"statusCode":409,"message":"Same idempotency key is being processed.","name":"concurrent_idempotent_requests"}', {},
			{"HTTP 409", "concurrent_idempotent_requests", '"retryable":true'})
		upstream(409, '{"statusCode":409,"message":"Another request is already updating this resource.","name":"resource_locked"}', {},
			{"HTTP 409", "resource_locked", '"retryable":true'})
		upstream(409, '{"statusCode":409,"message":"Same idempotency key used with a different payload.","name":"invalid_idempotent_request"}', {},
			{"HTTP 409", "invalid_idempotent_request", '"retryable":false'})
		upstream(500, "<html>Internal error</html>", {}, {"HTTP 500", '"retryable":true'})
		upstream(200, "<html>Maintenance</html>", {}, {"invalid JSON object"})
		upstream(200, "[]", {}, {"invalid JSON object"})

		-- An expired signed link fails without retrying either request.
		status, payload, responseHeaders = 200, '{"object":"attachment","id":"a1","download_url":"https://inbound-cdn.resend.com/t1/attachments/a1?signature=old"}', {}
		cdnStatus = 403
		local before = calls
		ok, err = pcall(function() resend.getReceivedEmailAttachment({email_id = "r1", attachment_id = "a1", path = "a.pdf"}) end)
		assert(not ok and string.find(tostring(err), "HTTP 403", 1, true) and string.find(tostring(err), '"retryable":false', 1, true), tostring(err))
		assert(not string.find(tostring(err), "signature", 1, true), "error leaked the signed link")
		assert(calls == before + 2)
	end,
}
