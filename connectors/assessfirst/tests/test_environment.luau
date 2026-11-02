local API = "https://simu.assessfirst.com/betty-V2"
return {
	scenario = {publisher = {}, config = {access = "read-write", api_host = "simu.assessfirst.com"}, auth_method = "token", auth_config = {token = "fixture-simu-assessfirst-token"}},
	configure = function()
		payload = "{}"
		http = {request = function(req)
			request = req
			return fixture.operation({statusCode = 200, headers = {["content-type"] = {"application/json"}}, body = fixture.reader(payload)})
		end}
	end,
	run = function(af)
		payload = "[]"
		assert(json.encode(af.listLocales()) == "[]")
		assert(request.method == "GET" and request.url == API .. "/locales", "test environment not used: " .. request.url)
		assert(request.headers.Authorization == nil and request.headers["AF-Token"] == nil, "connector set credentials")

		payload = '{"uuid":"dad17c50ff5d44e7a5b772fe636291a0","status":"invitation_sent"}'
		assert(af.sendInvitation({email = "ana@example.com"}).status == "invitation_sent")
		assert(request.method == "POST" and request.url == API .. "/candidate/send-invitation", "test environment not used: " .. request.url)
	end,
}
