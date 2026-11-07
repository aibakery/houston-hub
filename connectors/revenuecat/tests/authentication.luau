return {
	contract = function(m)
		m.authentication({
			{
				auth = { token = "synthetic-method-secret" },
				config = {},
				endpoint = { "GET", "https://api.revenuecat.com/v2/projects" },
				expected = "Bearer synthetic-method-secret",
				header = "Authorization",
				method = "token",
				publisher = {},
			},
		})
	end,
}
