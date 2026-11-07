return {
	contract = function(m)
		m.authentication({
			{
				auth = { token = "synthetic-method-secret" },
				config = {},
				endpoint = { "GET", "https://api.cal.com/v2/me" },
				expected = "Bearer synthetic-method-secret",
				header = "Authorization",
				method = "api_key",
				publisher = {},
			},
		})
	end,
}
