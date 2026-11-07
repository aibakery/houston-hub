return {
	contract = function(m)
		m.authentication({
			{
				auth = {},
				config = {},
				endpoint = { "GET", "https://discord.com/api/v10/channels/1300000000000000001" },
				expected = "Bot synthetic-bot-secret",
				header = "Authorization",
				method = "oauth",
				oauth = true,
				publisher = {
					bot_token = "synthetic-bot-secret",
					client_id = "synthetic-public-client",
					client_secret = "synthetic-client-secret",
				},
				scopes = true,
			},
		})
	end,
}
