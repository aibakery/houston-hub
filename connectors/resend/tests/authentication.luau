return {
	contract = function(m)
		m.authentication({
			{
				auth = { token = "synthetic-method-secret" },
				config = {},
				endpoint = { "GET", "https://api.resend.com/domains" },
				expected = "Bearer synthetic-method-secret",
				header = "Authorization",
				method = "api_key",
				publisher = {},
			},
		})
	end,
}
