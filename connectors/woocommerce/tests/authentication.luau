return {
	contract = function(m)
		m.authentication({
			{
				auth = {
					consumer_key = "synthetic-method-key",
					consumer_secret = "synthetic-method-secret",
				},
				config = { store_host = "shop.example.com" },
				endpoint = { "GET", "https://shop.example.com/wp-json/wc/v3/orders" },
				expected = "Basic c3ludGhldGljLW1ldGhvZC1rZXk6c3ludGhldGljLW1ldGhvZC1zZWNyZXQ=",
				header = "Authorization",
				method = "keys",
				publisher = {},
			},
		})
	end,
}
