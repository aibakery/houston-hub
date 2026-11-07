return {
	contract = function(m)
		m.authentication({
			{
				auth = {},
				config = {},
				endpoint = { "GET", "https://eth.blockscout.com/api/v2/stats" },
				expected = "",
				header = "Authorization",
				method = "",
				publisher = {},
			},
		})
	end,
}
