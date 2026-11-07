return {
	scenario = {
		publisher = {pipedream_client_id = "fixture-client", pipedream_client_secret = "fixture-secret", pipedream_project_id = "proj_fixture", pipedream_environment = "development"},
		config = {}, auth_method = "pipedream", auth_config = {},
	},
	config = {access = "read-only"},
	configure = function()
		http = {request = function(req)
			assert(req.method == "GET" and req.url == "https://gmail.googleapis.com/gmail/v1/users/me/profile")
			return fixture.operation({statusCode = 200, headers = {}, body = fixture.reader('{"emailAddress":"reader@example.com","messagesTotal":42}')})
		end}
	end,
	run = function(c)
		local profile = c.getProfile()
		assert(profile.emailAddress == "reader@example.com" and profile.messagesTotal == 42)
		assert(type(c.listMessages) == "function" and c.sendMessage == nil)
	end,
}
