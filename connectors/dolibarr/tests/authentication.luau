return {
	contract = function(m)
		m.authentication({
			{
				auth = { token = "synthetic-method-secret" },
				config = { host = "erp.example.com" },
				endpoint = { "GET", "https://erp.example.com/api/index.php/status" },
				expected = "synthetic-method-secret",
				header = "DOLAPIKEY",
				method = "key",
				publisher = {},
			},
		})
	end,
}
