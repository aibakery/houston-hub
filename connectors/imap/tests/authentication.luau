return {
	contract = function(m)
		m.authentication({
			{
				auth = {},
				config = {
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
