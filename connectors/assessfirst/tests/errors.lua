local C = "dad17c50ff5d44e7a5b772fe636291a0"
return {
	scenario = {publisher = {}, config = {access = "read-write"}, auth_method = "token", auth_config = {token = "fixture-private-assessfirst-token"}},
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
	run = function(af)
		local function upstream(fn, code, body, headers, expected, absent)
			status, payload, responseHeaders = code, body, headers
			local before = calls
			local ok, err = pcall(fn)
			for _, text in expected do
				assert(not ok and string.find(tostring(err), text, 1, true), "missing " .. text .. " in " .. tostring(err))
			end
			if absent then assert(not string.find(tostring(err), absent, 1, true), "unexpected " .. absent .. " in " .. tostring(err)) end
			assert(calls == before + 1, "failed request was retried")
		end
		local function invite() af.sendInvitation({email = "ana@example.com"}) end
		local function candidate() af.getCandidate({candidate_uuid = C}) end
		local function scores() af.getCandidateScores({candidate_uuid = C}) end

		upstream(invite, 500, '{"code":0,"message":"an error occured","data":[],"status":500}', {},
			{"AssessFirst HTTP 500: an error occured", "invalid or revoked", '"retryable":true', '"upstream_status":500', '"operation":"sendInvitation"'})
		upstream(invite, 422, '{"message":"The email field must be a valid email address.","errors":{"email":["The email field must be a valid email address."]}}', {},
			{"HTTP 422: The email field must be a valid email address.", 'email address. {\\"email\\":[\\"The email field', '"retryable":false'}, "revoked")
		upstream(candidate, 404, '{"code":0,"message":"candidate_not_found","data":[],"status":404}', {},
			{"HTTP 404: candidate_not_found", '"retryable":false'})
		upstream(candidate, 401, '{"code":401,"status":"error","message":"Unauthenticated."}', {}, {"HTTP 401: Unauthenticated."})
		upstream(candidate, 400, json.encode({message = string.rep("x", 5000), errors = {uuid = {"invalid"}}}), {}, {"HTTP 400", '{\\"uuid\\":[\\"invalid\\"]}'}, string.rep("x", 601))
		upstream(candidate, 429, '{"message":"Too Many Attempts."}', {["retry-after"] = {"60"}}, {"HTTP 429: Too Many Attempts.", "Retry-After: 60", '"retryable":true'})
		upstream(candidate, 503, "<html>Cloudflare</html>", {}, {"AssessFirst HTTP 503", '"retryable":true'})
		upstream(candidate, 200, "<html>Maintenance</html>", {}, {"invalid JSON object", '"upstream_status":200', '"retryable":false'})
		upstream(candidate, 200, '"ok"', {}, {"invalid JSON object"})
		upstream(scores, 200, '{"data":[]}', {}, {"invalid JSON array"})
	end,
}
