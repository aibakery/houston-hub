return {
	contract = function(m)
		m.authentication({
			{
				auth = { token = "synthetic-method-secret" },
				config = {},
				endpoint = { "GET", "https://app.pennylane.com/api/external/v2/me" },
				expected = "Bearer synthetic-method-secret",
				header = "Authorization",
				method = "token",
				publisher = {},
			},
		})
	end,
}
