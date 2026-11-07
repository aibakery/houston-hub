return {
	contract = function(m)
		m.authentication({
			{
				auth = {},
				config = {},
				endpoint = { "GET", "https://clinicaltrials.gov/api/v2/studies" },
				expected = "caller-forgery",
				header = "Authorization",
				method = "",
				publisher = {},
			},
		})
	end,
}
