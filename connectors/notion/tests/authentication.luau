return {
	contract = function(m)
		m.authentication({
			{
				auth = { token = "synthetic-method-secret" },
				config = {},
				endpoint = { "GET", "https://api.notion.com/admin/v1/legal_holds" },
				expected = "Bearer synthetic-method-secret",
				header = "Authorization",
				method = "admin",
				publisher = {},
			},
			{
				auth = {},
				config = {},
				endpoint = { "GET", "https://api.notion.com/v1/users/me" },
				expected = "Bearer synthetic-oauth-token",
				header = "Authorization",
				method = "oauth",
				oauth = true,
				publisher = {
					client_id = "synthetic-public-client",
					client_secret = "synthetic-client-secret",
				},
			},
			{
				auth = { token = "synthetic-method-secret" },
				config = {},
				endpoint = { "GET", "https://api.notion.com/v1/users/me" },
				expected = "Bearer synthetic-method-secret",
				header = "Authorization",
				method = "token",
				publisher = {},
			},
		})
	end,
}
