return {
	contract = function(m)
		m.authentication({
			{
				auth = { token = "synthetic-method-secret" },
				config = { organization = "acme" },
				endpoint = { "GET", "https://us.sentry.io/api/0/organizations/" },
				expected = "Bearer synthetic-method-secret",
				header = "Authorization",
				method = "token",
				publisher = {},
			},
		})
	end,
}
