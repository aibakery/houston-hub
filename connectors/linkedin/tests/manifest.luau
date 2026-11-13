return {
	contract = function(m)
		-- TestLinkedInPublisherOwnedClient
		do
			if not (m.publisherClient(m.raw.auth["oauth"])) then
				m.fail("LinkedIn OAuth client must belong to the publication")
			end
			for _, publisher in
				{ {}, { client_id = "client" }, { client_id = "client", client_secret = "secret" } }
			do
				local draft, err = m.draft(publisher, nil, nil, "")
				assert(not err, tostring(err))
				for _, field in draft.ConfigFields do
					if field.name ~= "access" then
						m.fail("connection form asks for %s", field.name)
					end
				end
				local want = (m.count(publisher) == 2)
				if (m.count(draft.Methods) ~= 1) or (draft.Methods[1].available ~= want) then
					m.fail("publisher=%s methods=%s; available=%s", publisher, draft.Methods, want)
				end
			end
			local publisher = { client_id = "client", client_secret = "secret" }
			do
				local _, err = m.resolve(
					publisher,
					{ client_id = "own-client", client_secret = "own-secret" },
					nil,
					"oauth"
				)
				if err == nil then
					m.fail("connection replaced the publication's OAuth client")
				end
			end
			local r, err = m.resolve(publisher, nil, nil, "oauth")
			assert(not err, tostring(err))
			if (r.PublicConfig["access"] ~= "read-only") or (m.count(r.PublicConfig) ~= 1) then
				m.fail("unexpected public settings: %s", r.PublicConfig)
			end
		end
		-- TestLinkedInScopesAndAccessRoutes
		do
			local read = { "GET https://api.linkedin.com/v2/userinfo" }
			local writes = {
				"POST https://api.linkedin.com/rest/posts",
				"POST https://api.linkedin.com/rest/images?action=initializeUpload",
				"DELETE https://api.linkedin.com/rest/posts/urn%3Ali%3Ashare%3A7",
				"PUT https://www.linkedin.com/dms-uploads/C4E10AQ/uploaded-image/0?ut=signed",
			}
			local denied = {
				"GET https://api.linkedin.com/rest/posts",
				"GET https://api.linkedin.com/v2/me",
				"DELETE https://api.linkedin.com/rest/images/urn%3Ali%3Aimage%3A1",
				"PUT https://api.linkedin.com/dms-uploads/C4E10AQ",
				"GET https://api.linkedin.com.evil.test/v2/userinfo",
			}
			for _, access in { "read-only", "read-write" } do
				local publisher = { client_id = "fixture-client", client_secret = "fixture-secret" }
				local r, err = m.resolve(publisher, { access = access }, nil, "oauth")
				assert(not err, tostring(err))
				local scopes = { "openid", "profile", "email" }
				if access == "read-write" then
					scopes = m.concat(scopes, { "w_member_social" })
				end
				if not (m.equal(r.Scopes, scopes)) or (m.raw.auth["oauth"].scope_separator ~= " ") then
					m.fail("access=%s scopes %s", access, r.Scopes)
				end
				r.Context.Auth["oauth"].access_token = "fixture-token"
				local rules = r.Proxy
				local check = function(route, allowed)
					local method, url, _ = m.cut(route, " ")
					local recipe, err = m.recipe(rules, method, url, nil)
					if (err == nil) ~= allowed then
						m.fail("access=%s %s allowed=%s: %s", access, route, (err == nil), err)
					end
					if err ~= nil then
						return
					end
					local headers, err = m.prepare(recipe, r.Context, { Authorization = { "forged" } })
					if (err ~= nil) or (m.header(headers, "Authorization") ~= "Bearer fixture-token") then
						m.fail("credential injection for %s: %s", route, err)
					end
				end
				for _, route in read do
					check(route, true)
				end
				for _, route in writes do
					check(route, (access == "read-write"))
				end
				for _, route in denied do
					check(route, false)
				end
			end
		end
	end,
}
