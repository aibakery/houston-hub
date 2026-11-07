return {
	contract = function(m)
		m.authentication({
			{
				auth = { token = "synthetic-method-secret-32-chars" },
				config = { store_host = "shop.example.com" },
				endpoint = { "GET", "https://shop.example.com/api/orders" },
				expected = "Basic c3ludGhldGljLW1ldGhvZC1zZWNyZXQtMzItY2hhcnM6",
				header = "Authorization",
				method = "key",
				publisher = {},
			},
		})
	end,
}
