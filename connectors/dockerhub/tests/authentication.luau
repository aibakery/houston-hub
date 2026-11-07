return {
	contract = function(m)
		m.authentication({
			{
				auth = {},
				config = {},
				endpoint = {
					"GET",
					"https://hub.docker.com/v2/namespaces/library/repositories/nginx/tags",
				},
				expected = "",
				header = "Authorization",
				method = "",
				publisher = {},
			},
		})
	end,
}
