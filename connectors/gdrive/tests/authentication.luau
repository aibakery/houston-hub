return {
	contract = function(m)
		m.authentication({
			{
				auth = {},
				config = {},
				endpoint = { "GET", "https://www.googleapis.com/drive/v3/files" },
				expected = "Bearer synthetic-oauth-token",
				header = "Authorization",
				method = "oauth",
				oauth = true,
				publisher = {
					client_id = "synthetic-public-client",
					client_secret = "synthetic-client-secret",
				},
				scopes = true,
			},
		})
	end,
}
