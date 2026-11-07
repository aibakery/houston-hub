return {
	contract = function(m)
		m.authentication({
			{
				auth = {},
				config = {},
				endpoint = { "POST", "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi" },
				expected = "",
				header = "Authorization",
				method = "",
				publisher = {},
			},
		})
	end,
}
