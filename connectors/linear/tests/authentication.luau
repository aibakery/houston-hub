return {
	contract = function(m)
		m.authentication({
			{
				auth = {},
				config = {
					client_id = "synthetic-public-client",
					client_secret = "synthetic-client-secret",
				},
				endpoint = { "GET", "https://api.linear.app/graphql" },
				expected = "Bearer synthetic-oauth-token",
				header = "Authorization",
				method = "oauth",
				oauth = true,
				publisher = {},
				scopes = true,
			},
			{
				auth = { token = "synthetic-method-secret" },
				config = {},
				endpoint = { "GET", "https://api.linear.app/graphql" },
				expected = "synthetic-method-secret",
				header = "Authorization",
				method = "token",
				publisher = {},
			},
		})
	end,
}
