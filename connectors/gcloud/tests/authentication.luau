return {
	contract = function(m)
		m.authentication({
			{
				auth = {},
				config = {},
				endpoint = {"GET", "https://cloudresourcemanager.googleapis.com/v3/projects:search"},
				expected = "Bearer synthetic-oauth-token",
				header = "Authorization",
				method = "oauth",
				oauth = true,
				publisher = {client_id = "synthetic-public-client", client_secret = "synthetic-client-secret"},
				scopes = true,
			},
		})
	end,
}
