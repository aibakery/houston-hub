return {
	scenario = {publisher = {}, config = {access = "read-write"}, auth_method = "token", auth_config = {token = "fixture-token"}},
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
	run = function(cloudflare)
		local ZONE = "023e105f4ecef8ad9ca31a8372d0c353"
		local function failure(call, code, body, headers, expected)
			status, payload, responseHeaders = code, body, headers
			local before = calls
			local ok, err = pcall(call)
			for _, text in expected do
				assert(not ok and string.find(tostring(err), text, 1, true), "missing " .. text .. " in " .. tostring(err))
			end
			assert(calls == before + 1, "failed request was retried")
		end
		local function zone() cloudflare.getZone({zone_id = ZONE}) end
		local function create() cloudflare.createDnsRecord({zone_id = ZONE, type = "A", name = "www.example.com", content = "198.51.100.4"}) end
		local function traffic() cloudflare.getZoneAnalytics({zone_id = ZONE, since = "2025-01-01", ["until"] = "2025-01-02"}) end

		failure(zone, 400, '{"success":false,"errors":[{"code":6003,"message":"Invalid request headers","error_chain":[{"code":6111,"message":"Invalid format for Authorization header"}]}],"messages":[],"result":null}',
			{}, {"Cloudflare HTTP 400: 6003 Invalid request headers (Invalid format for Authorization header)", '"upstream_status":400', '"retryable":false'})
		failure(zone, 401, '{"success":false,"errors":[{"code":10001,"message":"Unable to authenticate request"}],"messages":[],"result":null}', {},
			{"Cloudflare HTTP 401: 10001 Unable to authenticate request", '"retryable":false'})
		failure(zone, 403, '{"success":false,"errors":[{"code":10000,"message":"Authentication error"}],"messages":[],"result":null}', {},
			{"Cloudflare HTTP 403: 10000 Authentication error", '"retryable":false'})
		failure(zone, 404, '{"result":null,"success":false,"errors":[{"code":7003,"message":"Could not route to /client/v4/zones/x, perhaps your object identifier is invalid?"}],"messages":[]}', {},
			{"HTTP 404: 7003 Could not route", '"retryable":false'})
		failure(create, 400, '{"success":false,"errors":[{"code":81058,"message":"An identical record already exists."},{"code":1004,"message":"DNS Validation Error"}],"messages":[],"result":null}', {},
			{"HTTP 400: 81058 An identical record already exists.; 1004 DNS Validation Error"})
		failure(create, 400, json.encode({errors = {{code = 1, message = string.rep("x", 5000)}}}), {}, {"HTTP 400: 1 xxx"})
		failure(zone, 429, '{"success":false,"errors":[{"code":10429,"message":"Too many requests"}],"messages":[],"result":null}', {["retry-after"] = {"300"}},
			{"HTTP 429: 10429 Too many requests; retry after 300s", '"retryable":true'})
		failure(zone, 429, '{"success":false,"errors":[{"code":10429,"message":"Too many requests"}],"messages":[],"result":null}', {["retry-after"] = {"Fri, 30 Oct 2026 18:40:00 GMT"}},
			{"Too many requests; retry after Fri, 30 Oct 2026 18:40:00 GMT\"", '"retryable":true'})
		failure(zone, 502, "<html>Bad gateway</html>", {}, {'"message":"Cloudflare HTTP 502"', '"retryable":true'})
		failure(zone, 200, "<html>Maintenance</html>", {}, {"Cloudflare returned an invalid JSON object"})
		failure(zone, 200, '{"success":false,"errors":[],"messages":[],"result":null}', {}, {"Cloudflare reported an error: no details", '"upstream_status":200'})

		-- GraphQL reports some errors with HTTP 200, and others with a status.
		failure(traffic, 200, '{"data":null,"errors":[{"message":"cannot request data older than 31536000s","path":["viewer","zones","0","groups"],"extensions":{"timestamp":"2026-10-30T10:00:00Z"}}]}', {},
			{"Cloudflare reported an error: cannot request data older than 31536000s", '"upstream_status":200', '"retryable":false'})
		failure(traffic, 403, '{"data":null,"errors":[{"message":"zones [' .. ZONE .. '] are not authorized","path":["viewer","zones"]}]}', {},
			{"Cloudflare HTTP 403: zones [" .. ZONE .. "] are not authorized"})
		failure(traffic, 429, '{"data":null,"errors":[{"message":"rate limiter budget depleted, try again after 5 minutes"}]}', {},
			{"HTTP 429: rate limiter budget depleted", '"retryable":true'})
		failure(traffic, 503, '{"data":null,"errors":[{"message":"too many queries in progress, please try again later"}]}', {},
			{"HTTP 503: too many queries in progress", '"retryable":true'})
		failure(traffic, 200, "[]", {}, {"Cloudflare returned an invalid JSON object"})
	end,
}
