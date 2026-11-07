return {
	contract = function(m)
		m.authentication({
			{
				auth = {},
				config = {},
				endpoint = { "POST", "https://api.dropboxapi.com/2/files/list_folder" },
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
