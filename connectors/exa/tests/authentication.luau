return {
	contract = function(m)
		m.authentication({
			{
				auth = { token = "synthetic-method-secret" },
				config = {},
				endpoint = { "POST", "https://api.exa.ai/search" },
				expected = "synthetic-method-secret",
				header = "x-api-key",
				method = "api_key",
				publisher = {},
			},
		})
	end,
}
