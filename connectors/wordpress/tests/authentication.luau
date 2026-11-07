return {
	contract = function(m)
		m.authentication({
			{
				auth = { password = "synthetic-method-secret", username = "editor" },
				config = { site_host = "blog.example.com" },
				endpoint = { "GET", "https://blog.example.com/wp-json/wp/v2/posts" },
				expected = "Basic ZWRpdG9yOnN5bnRoZXRpYy1tZXRob2Qtc2VjcmV0",
				header = "Authorization",
				method = "application_password",
				publisher = {},
			},
		})
	end,
}
