return {
	scenario = {publisher = {}, config = {region = "eu.posthog.com"}, auth_method = "token", auth_config = {token = "phx_fixture-private-key"}},
	configure = function()
		calls = 0
		status = 200
		payload = "{}"
		responseHeaders = {}
		raise = nil
		urls = {}
		http = {request = function(req)
			calls += 1
			table.insert(urls, req.url)
			assert(req.headers.Authorization == nil, "credentials must remain in the proxy")
			if raise then error(raise, 0) end
			return fixture.operation({statusCode = status, headers = responseHeaders, body = fixture.reader(payload)})
		end}
	end,
	run = function(posthog)
		local function upstream(code, body, headers, call, expected, absent)
			status, payload, responseHeaders = code, body, headers
			local before = calls
			local ok, err = pcall(call)
			assert(not ok, "the call should have failed")
			for _, text in expected do
				assert(string.find(tostring(err), text, 1, true), "missing " .. text .. " in " .. tostring(err))
			end
			if absent then assert(not string.find(tostring(err), absent, 1, true), "unexpected " .. absent .. " in " .. tostring(err)) end
			assert(calls == before + 1, "a failed request was repeated")
		end
		local function events() posthog.listEvents(12345) end
		local function query() posthog.query(12345, "select 1") end
		local function insight() posthog.getInsight(12345, 7) end

		status, payload = 200, '{"count":0,"next":null,"previous":null,"results":[]}'
		posthog.listOrganizations()
		assert(urls[#urls] == "https://eu.posthog.com/api/organizations/?limit=100", urls[#urls])
		status, payload = 200, '{"columns":[],"types":[],"results":[],"hasMore":false}'
		query()
		assert(urls[#urls] == "https://eu.posthog.com/api/projects/12345/query/", urls[#urls])

		upstream(401, '{"type":"authentication_error","code":"authentication_failed","detail":"Personal API key found in request Authorization header is invalid.","attr":null}', {}, events,
			{"PostHog HTTP 401 authentication_failed: Personal API key found", "check the personal API key", "cloud region", '"retryable":false', '"upstream_status":401'})
		upstream(403, '{"type":"authentication_error","code":"permission_denied","detail":"API key missing required scope \'query:read\'","attr":null}', {}, query,
			{"HTTP 403 permission_denied: API key missing required scope 'query:read'", "read scope", '"retryable":false'})
		upstream(403, '{"type":"authentication_error","code":"permission_denied","detail":"API keys with scoped projects are only supported on project-based endpoints.","attr":null}', {},
			function() posthog.listProjects() end, {"scoped projects", "access to this organization or project"})
		upstream(404, '{"type":"invalid_request","code":"not_found","detail":"Not found.","attr":null}', {}, insight, {"HTTP 404 not_found: Not found."}, "read scope")
		upstream(400, '{"type":"validation_error","code":"invalid_input","detail":"Unable to resolve field: nope","attr":"query"}', {}, query,
			{"HTTP 400 invalid_input (query): Unable to resolve field: nope", '"retryable":false'})
		upstream(400, '{"type":"validation_error","code":"invalid_input","detail":"' .. string.rep("x", 1000) .. '"}', {}, query,
			{"invalid_input: " .. string.rep("x", 500)}, string.rep("x", 501))
		upstream(400, '{"type":"validation_error","code":"invalid_input","detail":"' .. string.rep("x", 5000) .. '"}', {}, query,
			{"invalid_input: " .. string.rep("x", 500)}, string.rep("x", 501))
		upstream(400, '{"type":"validation_error","code":"invalid_input","detail":"' .. string.rep("x", 40000) .. '"}', {}, query, {"PostHog HTTP 400"}, "xxx")
		upstream(429, '{"type":"throttled_error","code":"api_queries_budget_exceeded","detail":"Hourly read budget exhausted."}', {["retry-after"] = {"120"}}, query,
			{"HTTP 429 api_queries_budget_exceeded", "retry after 120s", '"retryable":true'})
		upstream(429, '{"type":"throttled_error","code":"throttled","detail":"Request was throttled."}', {["retry-after"] = {"Fri, 30 Oct 2026 07:00:00 GMT"}}, events,
			{"retry after Fri, 30 Oct 2026 07:00:00 GMT", '"retryable":true'}, "GMTs")
		upstream(502, "<html>Bad gateway</html>", {}, events, {"PostHog HTTP 502", '"retryable":true'}, "html")
		upstream(302, "", {location = {"https://eu.posthog.com/login"}}, events, {"HTTP 302: unexpected redirect"}, "login")
		upstream(200, "<html>Maintenance</html>", {}, events, {"unexpected response", '"retryable":false'})
		upstream(200, "[]", {}, insight, {"unexpected response"})
		upstream(200, '{"next":null,"results":null}', {}, events, {"unexpected response"})
		upstream(200, '{"query_status":{"id":"q1","complete":false}}', {}, query, {"still running the query", '"retryable":true'})
		upstream(200, '{"columns":[]}', {}, query, {"unexpected response", '"retryable":false'})
		upstream(200, '{"results":[' .. string.rep('"x",', 4 * 1024 * 1024 // 4) .. '"x"]}', {}, query, {"more than 4 MiB", "lower LIMIT", '"retryable":false'})

		local before = calls
		raise = {code = "timeout", message = "operation timed out"}
		local ok, err = pcall(events)
		assert(not ok and string.find(tostring(err), "did not answer within 15 s", 1, true) and string.find(tostring(err), '"retryable":true', 1, true), tostring(err))
		raise = {code = "cancelled", message = "cancelled"}
		ok, err = pcall(events)
		assert(not ok and not string.find(tostring(err), "PostHog", 1, true), "cancellation must pass through unchanged: " .. tostring(err))
		assert(calls == before + 2, "a failed request was repeated")
	end,
}
