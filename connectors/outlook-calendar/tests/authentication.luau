return {
	contract = function(m)
		m.authentication({
			{
				auth = {},
				config = {},
				endpoint = {"GET", "https://graph.microsoft.com/v1.0/me/calendarView"},
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
