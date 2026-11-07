return {
	contract = function(m)
		do
			local r, err = m.resolve(nil, nil, { token = "fixture-x-token" }, "token")
			assert(not err, tostring(err))
			if not m.raw.stateless then
				m.fail("public X browsing should offer the billing preview")
			end
			local p = r.Proxy
			for _, path in
				{
					"/2/tweets?ids=1,2",
					"/2/tweets/123",
					"/2/tweets/search/recent?query=test",
					"/2/tweets/search/all?query=test",
					"/2/users/123",
					"/2/users/by/username/XDevelopers",
					"/2/users/123/tweets",
					"/2/users/123/mentions",
				}
			do
				local recipe, err = m.recipe(p, "GET", "https://api.x.com" .. path, nil)
				assert(not err, tostring(err))
				local headers, err = m.prepare(recipe, r.Context, { Authorization = { "forged" } })
				if (err ~= nil) or (m.header(headers, "Authorization") ~= "Bearer fixture-x-token") then
					m.fail("credential injection: %s", err)
				end
				do
					local _, err = m.recipe(p, "POST", "https://api.x.com" .. path, nil)
					if err == nil then
						m.fail("write accepted: %s", path)
					end
				end
			end
			for _, url in
				{
					"https://api.x.com/2/users/123/bookmarks",
					"https://api.x.com/2/users/123/timelines/reverse_chronological",
					"https://api.x.com/2/dm_events",
					"https://api.x.com.evil.test/2/tweets/123",
					"https://api.twitter.com/2/tweets/123",
				}
			do
				do
					local _, err = m.recipe(p, "GET", url, nil)
					if err == nil then
						m.fail("unexpected endpoint accepted: %s", url)
					end
				end
			end
		end
	end,
}
