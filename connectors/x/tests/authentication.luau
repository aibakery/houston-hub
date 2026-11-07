return {
	contract = function(m)
		m.authentication({
			{
				auth = { token = "synthetic-method-secret" },
				config = {},
				endpoint = { "GET", "https://api.x.com/2/tweets/123" },
				expected = "Bearer synthetic-method-secret",
				header = "Authorization",
				method = "token",
				publisher = {},
			},
		})
	end,
}
