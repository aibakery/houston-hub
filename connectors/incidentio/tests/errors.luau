return {
	scenario = {publisher = {}, config = {access = "read-write"}, auth_method = "token", auth_config = {token = "fixture-token"}},
	configure = function()
		calls = 0
		status = 200
		payload = "{}"
		responseHeaders = {}
		http = {request = function(req)
			calls += 1
			-- A table stands for a failure while waiting for headers, such as a timeout.
			if requestError then error(requestError, 0) end
			-- A body whose read fails stands in for a stalled answer or a cancelled invocation.
			local body = if readError
				then {readAll = function() error(readError, 0) end, readPrefix = function() error(readError, 0) end, close = function() end}
				else fixture.reader(payload)
			return fixture.operation({statusCode = status, headers = responseHeaders, body = body})
		end}
	end,
	run = function(incidentio)
		local function failure(call, code, body, headers, expected)
			status, payload, responseHeaders = code, body, headers
			local before = calls
			local ok, err = pcall(call)
			for _, text in expected do
				assert(not ok and string.find(tostring(err), text, 1, true), "missing " .. text .. " in " .. tostring(err))
			end
			assert(calls == before + 1, "failed request was retried")
		end
		local function declare() incidentio.createIncident({idempotency_key = "k1", visibility = "public", name = "Checkout down"}) end
		local function read() incidentio.getIncident({id = "01HZINC"}) end
		local function list() incidentio.listIncidents() end
		local function follow() incidentio.createFollowUp({incident_id = "01HZINC", title = "Add a canary"}) end

		failure(read, 401, '{"type":"authentication_error","status":401,"request_id":"req-1","errors":[{"code":"missing_authorization_material","message":"No authorization material provided in request"}]}', {},
			{"incident.io HTTP 401 (authentication_error): No authorization material provided in request; request_id req-1", '"upstream_status":401', '"retryable":false'})
		failure(declare, 403, '{"type":"authorization_error","status":403,"errors":[{"code":"missing_scope","message":"Your API key is missing a required scope"}]}', {},
			{"HTTP 403 (authorization_error): Your API key is missing a required scope", '"retryable":false'})
		failure(declare, 422, '{"type":"validation_error","status":422,"request_id":"req-3","errors":[{"code":"is_required","message":"A severity is required to open an incident","source":{"field":"severity_id"}},'
			.. '{"code":"is_required","message":"Pick a type","source":null}]}', {},
			{"HTTP 422 (validation_error): A severity is required to open an incident (severity_id); Pick a type; request_id req-3", '"retryable":false'})
		-- Nulls in the envelope are skipped rather than treated as values.
		failure(read, 404, '{"type":null,"status":404,"request_id":null,"errors":[null,{"code":"not_found","message":null},{"message":"Not found","source":{"field":null}}]}', {},
			{"incident.io HTTP 404: Not found", '"retryable":false'})
		failure(read, 404, '{"type":"not_found","errors":null}', {}, {"incident.io HTTP 404 (not_found)", '"retryable":false'})
		failure(list, 400, json.encode({type = "invalid_request", errors = {{message = string.rep("x", 5000)}}}), {}, {"HTTP 400 (invalid_request): xxx"})
		failure(list, 429, '{"type":"too_many_requests","status":429,"rate_limit":{"name":"Houston","limit":60,"remaining":0},"errors":[{"code":"too_many_requests","message":"Too many requests hit the API too quickly."}]}',
			{["retry-after"] = {"30"}}, {"HTTP 429 (too_many_requests): Too many requests hit the API too quickly.; retry after 30 s", '"retryable":true'})
		failure(list, 429, '{"type":"too_many_requests"}', {["retry-after"] = {"Fri, 30 Oct 2026 18:00:00 GMT"}}, {'HTTP 429 (too_many_requests)"', '"retryable":true'})
		failure(read, 502, "<html>Bad gateway</html>", {}, {"incident.io HTTP 502", '"upstream_status":502', '"retryable":true'})
		-- A 5xx after a write may hide a saved change: only writes incident.io de-duplicates are retryable.
		failure(declare, 503, "", {}, {"incident.io HTTP 503; it may still have applied the change: read it back, and repeat it only with the same idempotency_key", '"retryable":true'})
		failure(follow, 502, "<html>Bad gateway</html>", {}, {"incident.io HTTP 502; it may still have applied the change, so read it back before repeating it", '"retryable":false'})
		failure(read, 200, "<html>Maintenance</html>", {}, {"incident.io returned an invalid JSON object"})
		failure(read, 200, "[1,2]", {}, {"incident.io returned an invalid JSON object"})

		-- A read that gets no answer in time can be retried; a write may have been applied.
		requestError = {code = "timeout", message = "request deadline"}
		failure(list, 200, "", {}, {"incident.io did not answer within 25 s; request a smaller page_size", '"retryable":true'})
		failure(read, 200, "", {}, {"incident.io did not answer within 25 s; try again", '"retryable":true'})
		failure(declare, 200, "", {}, {"did not answer within 25 s; it may still have applied the change: read it back, and repeat it only with the same idempotency_key", '"retryable":true'})
		failure(follow, 200, "", {}, {"did not answer within 25 s; it may still have applied the change, so read it back", '"retryable":false'})
		-- Other request failures pass through instead of becoming upstream failures.
		requestError = {code = "access_denied", message = "origin not allowed"}
		local ok, err = pcall(read)
		assert(not ok and not string.find(tostring(err), "retryable", 1, true), tostring(err))
		requestError = nil

		-- A body that stalls is bounded too; an error body that stalls still reports the status.
		readError = {code = "timeout", message = "await timed out"}
		failure(follow, 200, "", {}, {"did not answer within 25 s; it may still have applied the change", '"upstream_status":200', '"retryable":false'})
		failure(read, 429, "", {}, {"incident.io HTTP 429", '"upstream_status":429', '"retryable":true'})
		-- A write's answer that breaks off after its 2xx headers keeps the status and the read-back hint; a read's error passes through.
		readError = {code = "io_error", message = "connection reset by peer"}
		failure(follow, 201, "", {}, {"incident.io did not finish its answer; it may still have applied the change", '"upstream_status":201', '"retryable":false'})
		ok, err = pcall(read)
		assert(not ok and not string.find(tostring(err), "retryable", 1, true), tostring(err))
		readError = {code = "cancelled", message = "invocation cancelled"}
		ok, err = pcall(read)
		assert(not ok and not string.find(tostring(err), "retryable", 1, true), "cancellation became an upstream error: " .. tostring(err))
		readError = nil
	end,
}
