return {
	scenario = {publisher = {client_id = "fixture-client", client_secret = "fixture-private-secret"}, config = {}, auth_method = "oauth", auth_config = {}},
	config = {access = "read-only"},
	configure = function()
		requests, responses = {}, {}
		http = {request = function(req)
			table.insert(requests, req)
			assert(#responses > 0, "unexpected request: " .. req.url)
			return fixture.operation(table.remove(responses, 1))
		end}
		function respond(status, body)
			table.insert(responses, {statusCode = status, headers = {}, body = fixture.reader(body)})
		end
	end,
	run = function(c)
		local count = 0
		for _, fn in c do
			assert(type(fn) == "function")
			count += 1
		end
		assert(count == 1 and c.getProfile and #requests == 0, "read-only exposes only getProfile; help is offline")

		respond(200, '{"sub":"782bbtaQ","name":"John Doe","given_name":"John","family_name":"Doe","locale":"en-US","email":"doe@example.com","email_verified":true}')
		local me = c.getProfile()
		assert(me.urn == "urn:li:person:782bbtaQ" and me.name == "John Doe" and me.email == "doe@example.com")
		assert(requests[1].method == "GET" and requests[1].url == "https://api.linkedin.com/v2/userinfo")
		assert(requests[1].headers == nil, "credentials stay in the proxy")

		respond(200, '{"sub":"x1","name":"No Email"}')
		assert(c.getProfile().email == nil)

		for _, raw in {"not json", "[]", '{"name":"No member ID"}'} do
			respond(200, raw)
			assert(not pcall(c.getProfile), "invalid profile accepted: " .. raw)
		end

		respond(401, '{"status":401,"serviceErrorCode":65601,"code":"REVOKED_ACCESS_TOKEN","message":"The token used in the request has been revoked by the user"}')
		local ok, err = pcall(c.getProfile)
		assert(not ok and string.find(tostring(err), "LinkedIn HTTP 401 (REVOKED_ACCESS_TOKEN): The token used", 1, true))
		assert(string.find(tostring(err), "reconnect LinkedIn", 1, true))

		respond(503, "upstream unavailable")
		ok, err = pcall(c.getProfile)
		assert(not ok and string.find(tostring(err), "LinkedIn HTTP 503", 1, true))
		assert(#requests == 7 and #responses == 0, "failures must not be retried")
	end,
}
