return {
	contract = function(m)
		-- TestTipeeeCreatorRoutesAndQueryCredentials
		do
			for _, access in { "read-only", "read-write" } do
				do
					local r, err = m.resolve(
						nil,
						{ access = access },
						{ token = "synthetic +&token" },
						"token"
					)
					assert(not err, tostring(err))
					local cases = {
						{ method = "GET", path = "/v2.0/credentials/me", write = true },
						{ method = "GET", path = "/v2.0/projects/creator", write = true },
						{
							method = "GET",
							path = "/v2.0/projects/creator/campaigns/oct/subscriptions",
							write = false,
						},
						{ method = "GET", path = "/v2.0/project/unique?slug=creator", write = false },
						{ method = "GET", path = "/v2.0/projects/creator/rewards_default", write = false },
						{ method = "GET", path = "/v2.0/projects/creator/top/tippers", write = false },
						{ method = "GET", path = "/v2.0/feed/users/creator/projects/art", write = false },
						{ method = "PUT", path = "/v2.0/feed/users/creator/projects/art/read", write = true },
						{
							method = "PUT",
							path = "/v2.0/feed/users/creator/notifications/12/read",
							write = true,
						},
						{ method = "GET", path = "/v2.0/inbox/projects/art/subscription/12", write = true },
						{ method = "GET", path = "/v2.0/projects/creator/admin/messages", write = true },
						{ method = "POST", path = "/v2.0/projects/creator/admins/messages", write = true },
						{ method = "GET", path = "/documents/payments/creator_2026.csv", write = false },
						{ method = "GET", path = "/v2.0/inbox/threads/123/content", write = true },
						{ method = "GET", path = "/v2.0/projects/creator/widgets", write = true },
						{ method = "GET", path = "/documents/tippers/oct.xlsx?allTabs=1", write = true },
						{ method = "POST", path = "/v2.0/projects/creator/rewards/12", write = true },
						{
							method = "PUT",
							path = "/v2.0/projects/creator/rewards/12/transition",
							write = true,
						},
						{ method = "PUT", path = "/v2.0/projects/creator/payout", write = true },
						{ method = "DELETE", path = "/v2.0/threads/news/comments/12", write = true },
						{ method = "POST", path = "/v2.0/inbox/contents/files", write = true },
						{ method = "POST", path = "/v2.0/projects/creator/validation", write = true },
						{ method = "POST", path = "/v2.0/projects/creator/tos/validation", write = true },
						{
							method = "PUT",
							path = "/v2.0/projects/creator/delete_email_request",
							write = true,
						},
						{ method = "POST", path = "/v2.0/projects/creator/pre_delete", write = true },
					}
					for _, c in cases do
						local recipe, err = m.recipe(r, c.method, "https://api.tipeee.com" .. c.path, nil)
						local allowed = (not c.write or (access == "read-write"))
						if (err == nil) ~= allowed then
							m.fail("%s %s: %s", c.method, c.path, err)
						end
						if not allowed then
							continue
						end
						local prepared, err = m.prepareUrl(recipe, r.Context)
						assert(not err, tostring(err))
						if string.match(prepared, "[?&]access_token=([^&]*)") ~= "synthetic+%2B%26token" then
							m.fail("query credential not injected", prepared)
						end
						m.rejectPreparedOverrides(recipe, r.Context, c.method .. " " .. c.path)
						local h, err = m.prepare(recipe, r.Context, {
							Authorization = { "forged" },
							Cookie = { "session=forged" },
							Accept = { "application/json" },
						})
						if
							((err ~= nil) or (m.count(h) ~= 1))
							or (m.header(h, "Accept") ~= "application/json")
						then
							m.fail("unsafe caller headers: %s %s", h, err)
						end
					end
					for _, c in
						{
							{ "GET", "https://api.tipeee.com.evil.example/v2.0/credentials/me" },
							{ "GET", "http://api.tipeee.com/v2.0/credentials/me" },
							{ "POST", "https://api.tipeee.com/oauth/v2/token" },
							{ "GET", "https://api.tipeee.com/v2.0/projects/creator/apikey" },
							{ "POST", "https://api.tipeee.com/v2.0/projects/creator/apikeys" },
							{ "GET", "https://api.tipeee.com/v2.0/projects/creator/subscriptions/last" },
							{ "POST", "https://api.tipeee.com/v2.0/projects/creator/simulate_events" },
							{ "GET", "https://api.tipeee.com/v2.0/projects/../credentials/me" },
							{ "POST", "https://api.tipeee.com/v2.0/projects/creator/tips" },
							{ "DELETE", "https://api.tipeee.com/v2.0/credentials/me" },
						}
					do
						do
							local _, err = m.recipe(r, c[1], c[2], nil)
							if err == nil then
								m.fail("forbidden route allowed: %s", c)
							end
						end
					end
				end
			end
		end
	end,
}
