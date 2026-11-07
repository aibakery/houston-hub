return {
	contract = function(m)
		do
			local r, err = m.resolve(nil, nil, { token = "fixture-token" }, "token")
			assert(not err, tostring(err))
			local p = r.Proxy
			for _, host in
				{ "api.fastmail.com", "phl.api.fastmail.com", "ams.api.fastmail.com", "jmap.fastmail.com" }
			do
				for _, route in
					{
						{ "GET", "/jmap/session" },
						{ "POST", "/jmap/api/" },
						{ "POST", "/jmap/upload/u1/" },
						{ "GET", "/jmap/download/u1/blob/file" },
					}
				do
					local recipe, err = m.recipe(p, route[1], "https://" .. host .. route[2], nil)
					assert(not err, tostring(err))
					local h, err = m.prepare(recipe, r.Context, nil)
					if (err ~= nil) or (m.header(h, "Authorization") ~= "Bearer fixture-token") then
						m.fail("%s: %s %s", host, h, err)
					end
				end
			end
			for _, host in
				{
					"fastmailusercontent.com",
					"www.fastmailusercontent.com",
					"phl-www.fastmailusercontent.com",
				}
			do
				local recipe, err = m.recipe(
					p,
					"GET",
					"https://" .. host .. "/jmap/download/u1/blob/file?type=text%2Fplain",
					nil
				)
				assert(not err, tostring(err))
				local h, err = m.prepare(recipe, r.Context, nil)
				if (err ~= nil) or (m.header(h, "Authorization") ~= "Bearer fixture-token") then
					m.fail("%s: %s %s", host, h, err)
				end
				for _, route in
					{ { "POST", "/jmap/api/" }, { "POST", "/jmap/upload/u1/" }, { "GET", "/other" } }
				do
					do
						local _, err = m.recipe(p, route[1], "https://" .. host .. route[2], nil)
						if err == nil then
							m.fail("download host accepted %s", route)
						end
					end
				end
			end
			for _, host in
				{
					"fastmail.com",
					"app.fastmail.com",
					"evilapi.fastmail.com",
					"api.fastmail.com.evil.test",
					"www.fastmailusercontent.com.evil.test",
				}
			do
				do
					local _, err =
						m.recipe(p, "GET", "https://" .. host .. "/jmap/download/u1/blob/file", nil)
					if err == nil then
						m.fail("accepted %s", host)
					end
				end
			end
		end
	end,
}
