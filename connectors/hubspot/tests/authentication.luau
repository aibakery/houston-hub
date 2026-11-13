return {
	contract = function(m)
		m.authentication({
			{
				auth = {},
				config = {},
				endpoint = {"GET", "https://api.hubapi.com/crm/owners/2026-09"},
				expected = "Bearer synthetic-oauth-token",
				header = "Authorization",
				method = "oauth",
				oauth = true,
				publisher = {client_id = "synthetic-public-client", client_secret = "synthetic-client-secret"},
				scopes = true,
			},
			{
				auth = {token = "synthetic-method-secret"},
				config = {},
				endpoint = {"GET", "https://api.hubapi.com/crm/owners/2026-09"},
				expected = "Bearer synthetic-method-secret",
				header = "Authorization",
				method = "token",
				publisher = {},
			},
		})
	end,
}
