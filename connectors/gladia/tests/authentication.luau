return {
	contract = function(m)
		m.authentication({
			{
				auth = { token = "synthetic-method-secret" },
				config = {},
				endpoint = { "GET", "https://api.gladia.io/v2/transcription" },
				expected = "synthetic-method-secret",
				header = "x-gladia-key",
				method = "api_key",
				publisher = {},
			},
		})
	end,
}
