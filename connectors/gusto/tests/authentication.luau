return {
	contract = function(m)
		m.authentication({
			{
				auth = {},
				config = {
					client_id = "synthetic-public-client",
					client_secret = "synthetic-client-secret",
					own_app = true,
				},
				endpoint = { "GET", "https://api.gusto.com/v1/token_info" },
				expected = "Bearer synthetic-oauth-token",
				header = "Authorization",
				method = "demo",
				oauth = true,
				publisher = {},
			},
			{
				auth = {},
				config = {},
				endpoint = { "GET", "https://api.gusto.com/v1/token_info" },
				expected = "Bearer synthetic-oauth-token",
				header = "Authorization",
				method = "gusto",
				oauth = true,
				publisher = {
					client_id = "synthetic-public-client",
					client_secret = "synthetic-client-secret",
				},
			},
			{
				auth = {},
				config = {
					client_id = "synthetic-public-client",
					client_secret = "synthetic-client-secret",
					own_app = true,
				},
				endpoint = { "GET", "https://api.gusto.com/v1/token_info" },
				expected = "Bearer synthetic-oauth-token",
				header = "Authorization",
				method = "own_app",
				oauth = true,
				publisher = {},
			},
		})
	end,
}
