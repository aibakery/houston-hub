return {
	contract = function(m)
		m.authentication({
			{
				auth = { token = "synthetic-method-secret" },
				config = {},
				endpoint = { "GET", "https://app.assessfirst.com/betty-V2/locales" },
				expected = "synthetic-method-secret",
				header = "AF-Token",
				method = "token",
				publisher = {},
			},
		})
	end,
}
