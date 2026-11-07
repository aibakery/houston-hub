return {
	contract = function(m)
		local notionConnection = function(method, access)
			local publisher, input = nil, nil
			if method == "oauth" then
				publisher = { client_id = "notion-client", client_secret = "notion-publisher-secret" }
			else
				input = { token = method .. "-secret" }
			end
			local r, err = m.resolve(publisher, { access = access }, input, method)
			assert(not err, tostring(err))
			if method == "oauth" then
				do
					local err = m.credentials(r.Context)
					if err == nil then
						m.fail("OAuth connection became usable before token exchange")
					end
				end
				r.Context.Auth[method].access_token = "oauth-secret"
			end
			do
				local err = m.credentials(r.Context)
				assert(not err, tostring(err))
			end
			if not (m.equal(r.PublicConfig, { access = access })) then
				m.fail("unexpected public settings: %s", r.PublicConfig)
			end
			return r
		end
		local assertNotionRoute = function(r, route, allowed, credential, version)
			local caller = { Authorization = { "forged" }, ["Notion-Version"] = { "old" } }
			local recipe, err = m.recipe(r, route[1], "https://api.notion.com" .. route[2], caller)
			if not allowed then
				if err == nil then
					m.fail("unexpectedly allowed %s", route)
				end
				return
			end
			if err ~= nil then
				m.fail("denied %s: %s", route, err)
			end
			local headers, err = m.prepare(recipe, r.Context, caller)
			if
				((err ~= nil) or (m.header(headers, "Authorization") ~= "Bearer " .. credential))
				or (m.header(headers, "Notion-Version") ~= version)
			then
				m.fail("wrong injection for %s: %s, %s", route, headers, err)
			end
			if
				(m.header(caller, "Authorization") ~= "forged")
				or (m.header(caller, "Notion-Version") ~= "old")
			then
				m.fail("header preparation mutated caller's headers")
			end
		end
		-- TestNotionRegistrationAndAuthenticationSelection
		do
			for _, publisher in
				{
					{},
					{ client_id = "client" },
					{ client_secret = "secret" },
					{ client_id = "client", client_secret = "secret" },
				}
			do
				local draft, err = m.draft(publisher, nil, nil, "")
				assert(not err, tostring(err))
				for _, method in draft.Methods do
					local want = ((method.key ~= "oauth") or (m.count(publisher) == 2))
					if not method.eligible or (method.available ~= want) then
						m.fail("publisher=%s method=%s; available=%s", publisher, method, want)
					end
				end
				if m.count(publisher) ~= 2 then
					do
						local _, err = m.resolve(publisher, nil, nil, "oauth")
						if err == nil then
							m.fail("OAuth activated without complete publisher settings")
						end
					end
				end
				local secretField = false
				for _, field in draft.PublisherFields do
					if field.name == "client_secret" then
						secretField = true
						if field.field.type ~= "secret" then
							m.fail("active OAuth secret form field must be secret")
						end
					end
				end
				if not secretField then
					m.fail(
						"OAuth client secret publisher field must be visible before credentials are entered"
					)
				end
				if (m.count(draft.ConfigFields) ~= 1) or (draft.ConfigFields[1].name ~= "access") then
					m.fail("connection setup should ask only for access: %s", draft.ConfigFields)
				end
				local manual, err = m.resolve(publisher, nil, { token = "manual-token" }, "token")
				if (err ~= nil) or (m.credentials(manual.Context) ~= nil) then
					m.fail("token connection depends on publisher OAuth settings: %s", err)
				end
				if manual.PublicConfig["access"] ~= "read-only" then
					m.fail("new connection did not default to read-only")
				end
			end
			for _, method in { "token", "admin" } do
				do
					local _, err = m.resolve(nil, nil, nil, method)
					if err == nil then
						m.fail("manual authentication accepted missing token")
					end
				end
			end
			local publisher = { client_id = "client", client_secret = "secret" }
			do
				local _, err = m.resolve(publisher, nil, { access_token = "caller-token" }, "oauth")
				if err == nil then
					m.fail("caller supplied a managed OAuth credential")
				end
			end
		end
		-- TestNotionContentRoutesAndWriteBoundary
		do
			local reads = {
				{ "GET", "/v1/pages/page-1/properties/f%5C%5C%3Ap" },
				{ "GET", "/v1/pages/page-1/properties/a%2Fb" },
				{ "GET", "/v1/pages/page-1/properties/100%25" },
				{ "GET", "/v1/users/me" },
				{ "GET", "/v1/pages/page-1/properties/title%3Aname?page_size=1" },
				{ "GET", "/v1/pages/page-1/markdown" },
				{ "GET", "/v1/blocks/block-1/children" },
				{ "GET", "/v1/file_uploads?status=uploaded" },
				{ "GET", "/v1/views/view-1/queries/query-1" },
				{ "POST", "/v1/search" },
				{ "POST", "/v1/data_sources/source-1/query" },
				{ "POST", "/v1/agents/query" },
				{ "POST", "/v1/sessions/session-1/events/query" },
				{ "POST", "/v1/blocks/meeting_notes/query" },
			}
			local writes = {
				{ "POST", "/v1/pages" },
				{ "POST", "/v1/pages/page-1/move" },
				{ "POST", "/v1/file_uploads/file-1/send" },
				{ "POST", "/v1/file_uploads/file-1/complete" },
				{ "POST", "/v1/databases" },
				{ "POST", "/v1/data_sources" },
				{ "PATCH", "/v1/pages/page-1/markdown" },
				{ "PATCH", "/v1/blocks/block-1/children" },
				{ "DELETE", "/v1/blocks/block-1" },
				{ "DELETE", "/v1/comments/comment-1" },
				{ "POST", "/v1/sessions/session-1/cancel" },
				{ "PATCH", "/v1/agents/agent-1/credit_limit" },
			}
			for _, method in { "token", "oauth" } do
				for _, access in { "read-only", "read-write" } do
					do
						local r = notionConnection(method, access)
						r.Context.Auth.admin = { token = "inactive-admin" }
						if method == "oauth" then
							r.Context.Auth.token = { token = "inactive-token" }
						end
						for _, route in m.concat(m.concat({}, reads), writes) do
							local allowed = (access == "read-write")
							for _, read in reads do
								allowed = (allowed or (route == read))
							end
							assertNotionRoute(r, route, allowed, method .. "-secret", "2026-03-11")
						end
						for _, route in
							{
								{ "GET", "/v1/search" },
								{ "PUT", "/v1/pages/page-1" },
								{ "POST", "/v1/users" },
								{ "DELETE", "/v1/file_uploads/file-1" },
								{ "GET", "/v1/oauth/token" },
								{ "POST", "/v1/oauth/revoke" },
								{ "GET", "/admin/v1/analytics/reports" },
								{ "POST", "/admin/v1/legal_holds" },
							}
						do
							assertNotionRoute(r, route, false, "", "")
						end
					end
				end
			end
		end
		-- TestNotionAdminRouteSeparation
		do
			for _, access in { "read-only", "read-write" } do
				local r = notionConnection("admin", access)
				r.Context.Auth.token = { token = "inactive-token" }
				for _, route in
					{
						{ "GET", "/admin/v1/analytics/reports" },
						{ "GET", "/admin/v1/legal_holds/hold-1/spaces/space-1/pages" },
						{ "GET", "/admin/v1/spaces/space-1/groups/group-1/members" },
					}
				do
					assertNotionRoute(r, route, true, "admin-secret", "2026-06-01")
				end
				for _, route in
					{
						{ "POST", "/admin/v1/legal_holds/hold-1/export" },
						{ "PATCH", "/admin/v1/spaces/space-1/groups/group-1" },
						{ "PUT", "/admin/v1/spaces/space-1/agents/agent-1/credit_limit" },
						{ "DELETE", "/admin/v1/spaces/space-1/personal_access_tokens/bot-1" },
					}
				do
					assertNotionRoute(r, route, (access == "read-write"), "admin-secret", "2026-06-01")
				end
				for _, route in
					{
						{ "GET", "/v1/users/me" },
						{ "POST", "/v1/search" },
						{ "POST", "/v1/pages" },
						{ "PUT", "/admin/v1/legal_holds/hold-1" },
						{ "DELETE", "/admin/v1/spaces/space-1/users" },
					}
				do
					assertNotionRoute(r, route, false, "", "")
				end
			end
		end
		-- TestNotionDownloadBoundaries
		do
			for _, method in { "token", "oauth", "admin" } do
				local r = notionConnection(method, "read-only")
				local rules = r.Proxy
				for _, url in
					{
						"https://s3.us-west-2.amazonaws.com/secure.notion-static.com/folder/100%25%2Ffile.pdf?X-Amz-Signature=exact%2Fvalue",
						"https://prod-files-secure.s3.us-west-2.amazonaws.com/workspace/100%25.pdf",
						"https://s3.us-west-2.amazonaws.com/secure.notion-static.com/file.pdf?X-Amz-Signature=signed",
						"https://s3-us-west-2.amazonaws.com/public.notion-static.com/file.pdf",
						"https://prod-files-secure.s3.us-west-2.amazonaws.com/workspace/file.pdf",
						"https://prod-files-secure-euc1.s3.eu-central-1.amazonaws.com/workspace/file.pdf",
						"https://prod-files-secure-apne1.s3.ap-northeast-1.amazonaws.com/workspace/file.pdf",
						"https://notion-production-snapshots-2.s3.us-west-2.amazonaws.com/export.zip",
						"https://file.notion.so/f/f/file.pdf",
						"https://file.notion.com/f/f/file.pdf",
					}
				do
					local caller =
						{ Authorization = { "must-not-leak" }, ["Notion-Version"] = { "must-not-leak" } }
					local recipe, err = m.recipe(rules, "GET", url, caller)
					assert(not err, tostring(err))
					local headers, err = m.prepare(recipe, r.Context, caller)
					if
						(
							((err ~= nil) or (m.header(headers, "Authorization") ~= ""))
							or (m.header(headers, "Notion-Version") ~= "")
						) or (recipe.URL ~= url)
					then
						m.fail("download credentials or signed URL changed: %s, %s", headers, err)
					end
					do
						local _, err = m.recipe(rules, "POST", url, caller)
						if err == nil then
							m.fail("upload allowed to download-only URL %s", url)
						end
					end
				end
				for _, url in
					{
						"https://s3.us-west-2.amazonaws.com/unrelated-bucket/file.pdf",
						"https://s3.us-west-2.amazonaws.com/secure.notion-static.com.evil/file.pdf",
						"https://s3.us-west-2.amazonaws.com/secure.notion-static.com/%2e%2e/unrelated/file.pdf",
						"https://s3.us-west-2.amazonaws.com/secure.notion-static.com/file%2F..%2Fescape",
						"https://prod-files-secure.s3.us-west-2.amazonaws.com.attacker.test/file.pdf",
						"https://arbitrary-bucket.s3.us-west-2.amazonaws.com/file.pdf",
						"http://file.notion.so/file.pdf",
						"https://file.notion.so:8443/file.pdf",
						"https://api.notion.com.attacker.test/v1/users/me",
						"https://api.notion.com/v1/unknown",
					}
				do
					do
						local _, err = m.recipe(rules, "GET", url, nil)
						if err == nil then
							m.fail("untrusted route accepted: %s", url)
						end
					end
				end
			end
		end
	end,
}
