return {
	contract = function(m)
		m.authentication({
			{
				auth = {},
				config = {
					database = 2,
					host = "database.example.com",
					password = "synthetic-root-secret",
					username = "reader",
				},
				method = "",
				native = true,
				publisher = {},
			},
		})
	end,
}
