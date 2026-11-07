return {
	contract = function(m)
		m.authentication({
			{
				auth = { token = "synthetic-method-secret" },
				config = {},
				endpoint = { "GET", "https://graph.facebook.com/v26.0/me" },
				expected = "Bearer synthetic-method-secret",
				header = "Authorization",
				method = "token",
				publisher = {},
			},
		})
	end,
}
