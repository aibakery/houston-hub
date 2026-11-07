return {
	contract = function(m)
		-- TestResendAccessRoutes
		do
			local api = "https://api.resend.com"
			for _, access in { "read-only", "read-write" } do
				local r, err = m.resolve(nil, { access = access }, { token = "re_fixture" }, "api_key")
				assert(not err, tostring(err))
				m.routes(r, "Bearer re_fixture", true, {
					"GET " .. api .. "/emails?limit=100",
					"GET " .. api .. "/emails/e1",
					"GET " .. api .. "/emails/receiving/r1/attachments/a1",
					"GET " .. api .. "/contacts/ana%2Bnews%40example.com",
					"GET " .. api .. "/suppressions/o%27brien%40example.com",
					"GET " .. api .. "/webhooks",
					"GET " .. api .. "/webhooks/w1/events/msg_1",
					"GET " .. api .. "/logs",
					"GET " .. api .. "/api-keys",
					"GET " .. api .. "/segments/s1/contacts",
					"GET " .. api .. "/usage",
					"GET "
						.. api
						.. "/inboxes/support%40acme.com/threads/search?query=refund&folders=inbox,sent",
					"GET " .. api .. "/inboxes/i1/threads/t1/emails/e1",
					"GET " .. api .. "/inboxes/i1/agent",
				})
				m.routes(r, "Bearer re_fixture", (access == "read-write"), {
					"GET " .. api .. "/webhooks/w1",
					"GET " .. api .. "/logs/l1",
					"POST " .. api .. "/emails",
					"POST " .. api .. "/emails/batch",
					"POST " .. api .. "/emails/e1/share",
					"PATCH " .. api .. "/emails/e1",
					"POST " .. api .. "/contacts/imports",
					"DELETE " .. api .. "/contacts/c1",
					"POST " .. api .. "/broadcasts/b1/send",
					"POST " .. api .. "/webhooks/w1/signing-secret/rotate",
					"POST " .. api .. "/suppressions/batch/remove",
					"POST " .. api .. "/inboxes/i1/threads/t1/emails/e1/reply",
					"POST " .. api .. "/inboxes/i1/drafts/d1/send",
					"PATCH " .. api .. "/inboxes/i1/threads/t1",
					"PUT " .. api .. "/inboxes/i1/threads/t1/labels",
					"DELETE " .. api .. "/inboxes/i1/threads/t1/labels/l1",
				})
				m.routes(r, "Bearer re_fixture", false, {
					"POST " .. api .. "/api-keys",
					"PATCH " .. api .. "/api-keys/k1",
					"DELETE " .. api .. "/api-keys/k1",
					"GET " .. api .. "/oauth/grants",
					"DELETE " .. api .. "/oauth/grants/g1",
					"POST " .. api .. "/oauth/token",
					"POST " .. api .. "/oauth/register",
					"GET " .. api .. "/audiences",
					"POST " .. api .. "/email",
					"PUT " .. api .. "/emails/e1",
					"PUT " .. api .. "/inboxes/i1/threads/t1",
					"GET https://resend.com/api-keys",
					"GET https://api.resend.com.example.com/emails",
					"GET https://eu.api.resend.com/emails",
					"GET " .. api .. "/emails/%2e%2e/api-keys",
				})
				for _, url in
					{
						"https://inbound-cdn.resend.com/t1/attachments/a1?signature=s",
						"https://outbound-cdn.resend.com/t1/attachments/a1?signature=s",
					}
				do
					local recipe, err = m.recipe(r, "GET", url, nil)
					assert(not err, tostring(err))
					local headers, err = m.prepare(recipe, r.Context, { Authorization = { "forged" } })
					if (err ~= nil) or (m.header(headers, "Authorization") ~= "") then
						m.fail("%s carried credentials: %s %s", url, headers, err)
					end
					do
						local _, err = m.recipe(r, "POST", url, nil)
						if err == nil then
							m.fail("POST %s allowed", url)
						end
					end
				end
				do
					local _, err =
						m.recipe(r, "GET", "https://cdn.resend.com/brand/resend-icon-black.svg", nil)
					if err == nil then
						m.fail("unlisted Resend host allowed")
					end
				end
				m.rejectOverrides(r, { "GET " .. api .. "/emails" })
			end
		end
	end,
}
