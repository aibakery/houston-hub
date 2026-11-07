return {
	contract = function(m)
		m.authentication({
			{
				auth = {},
				config = {},
				endpoint = { "GET", "https://api.carta.com/v1alpha1/user" },
				expected = "Bearer synthetic-oauth-token",
				header = "Authorization",
				method = "carta",
				oauth = true,
				publisher = {
					client_id = "synthetic-public-client",
					client_secret = "synthetic-client-secret",
				},
				scopes = true,
			},
			{
				auth = {},
				config = {
					client_id = "synthetic-public-client",
					client_secret = "synthetic-client-secret",
					own_app = true,
				},
				endpoint = { "GET", "https://api.carta.com/v1alpha1/user" },
				expected = "Bearer synthetic-oauth-token",
				header = "Authorization",
				method = "own_app",
				oauth = true,
				publisher = {},
				scopes = true,
			},
			{
				auth = {},
				config = {
					client_id = "synthetic-public-client",
					client_secret = "synthetic-client-secret",
					own_app = true,
				},
				endpoint = { "GET", "https://api.carta.com/v1alpha1/user" },
				expected = "Bearer synthetic-oauth-token",
				header = "Authorization",
				method = "playground",
				oauth = true,
				publisher = {},
				scopes = true,
			},
		})
	end,
}
