return {
	contract = function(m)
		m.authentication({
			{
				auth = {},
				config = {},
				endpoint = { "GET", "https://www.ebi.ac.uk/chembl/api/data/molecule.json" },
				expected = "",
				header = "Authorization",
				method = "",
				publisher = {},
			},
		})
	end,
}
