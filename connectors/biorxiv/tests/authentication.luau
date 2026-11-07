return {
	contract = function(m)
		m.authentication({
			{
				auth = {},
				config = {},
				endpoint = { "GET", "https://api.biorxiv.org/details/biorxiv/10.1101/339747/na/json" },
				expected = "",
				header = "Authorization",
				method = "",
				publisher = {},
			},
		})
	end,
}
