return {
	contract = function(m)
		local graph = "https://graph.microsoft.com/v1.0"
		local api = graph .. "/me/drive"
		for access, scope in {["read-only"] = "Files.Read", ["read-write"] = "Files.ReadWrite"} do
			local r, err = m.resolve({client_id = "publisher-client", client_secret = "publisher-secret"}, {access = access}, nil, "oauth")
			assert(r and not err, tostring(err))
			assert(m.equal(r.Scopes, {"offline_access", "User.Read", scope}), "requested OAuth scopes for " .. access)
			r.Context.Auth.oauth.access_token = "fixture-token"
			local reads = {
				"GET " .. api, "GET " .. api .. "/root", "GET " .. api .. "/root/children?$skiptoken=MjAx",
				"GET " .. api .. "/root/search(q='O%27%27Brien%20plan')", "GET " .. api .. "/root/search(q='10:30%20notes')", "GET " .. api .. "/root:/Documents/Q3%20report.pdf:",
				"GET " .. api .. "/items/D4648F06C91D9D3D%2154927", "GET " .. api .. "/items/f1/children", "GET " .. api .. "/items/f1/content?format=pdf",
				"GET " .. api .. "/items/f1/permissions",
				-- Business accounts may page through drive-keyed links.
				"GET " .. graph .. "/drives/b!x-1/items/01ABC/children?%24skiptoken=UGFn",
				"GET " .. graph .. "/drives/b!x-1/root/children?%24skiptoken=UGFn",
				"GET " .. graph .. "/drives/b!x-1/items/01ABC/permissions?%24skiptoken=UGFn",
			}
			m.routes(r, "Bearer fixture-token", true, reads)
			m.rejectOverrides(r, reads)
			-- Content redirects to preauthenticated hosts, which never receive the token.
			m.routes(r, "", true, {
				"GET https://contoso-my.sharepoint.com/personal/ana/_layouts/15/download.aspx?UniqueId=1&tempauth=abc",
				"GET https://b0mpua.by3301.files.1drv.com/y23vmag", "GET https://my.microsoftpersonalcontent.com/y/abc",
				"GET https://public.bn1304.livefilestore.com/y4m", "GET https://westus1-mediap.svc.ms/transform/pdf?provider=spo",
			})
			local writes = {
				"POST " .. api .. "/root/children", "POST " .. api .. "/items/f1/children", "POST " .. api .. "/items/f1/copy",
				"POST " .. api .. "/items/f1/createLink", "POST " .. api .. "/items/f1/invite", "PATCH " .. api .. "/items/f1",
				"DELETE " .. api .. "/items/f1", "DELETE " .. api .. "/items/f1/permissions/p1", "PUT " .. api .. "/items/f1/content",
				"PUT " .. api .. "/root:/report.pdf:/content?@microsoft.graph.conflictBehavior=rename",
				"PUT " .. api .. "/items/D4648F06C91D9D3D%21101:/Q3%20plan.pdf:/content?@microsoft.graph.conflictBehavior=replace",
			}
			m.routes(r, "Bearer fixture-token", access == "read-write", writes)
			if access == "read-write" then m.rejectOverrides(r, writes) end
			-- The token stays off Microsoft's token endpoint, batches, other APIs, sharing-link redemption,
			-- lookalike hosts and routes the connector never calls: upload sessions, permanent deletes,
			-- other drives' items, mail and thumbnails. The proxy cannot filter queries, so the connector
			-- refuses nextLinks of other routes or with $expand itself.
			m.routes(r, "Bearer fixture-token", false, {
				"POST https://login.microsoftonline.com/common/oauth2/v2.0/token", "POST " .. graph .. "/$batch",
				"GET " .. graph .. "/users/other@example.com/drive", "GET https://graph.microsoft.com/beta/me/drive",
				"GET " .. graph .. "/shares/u!abc/driveItem", "GET https://graph.microsoft.com.evil.test/v1.0/me/drive",
				"GET " .. api .. "/items/f1%2F..%2Fx", "POST " .. api .. "/items/f1/createUploadSession",
				"POST " .. api .. "/items/f1:/x.pdf:/createUploadSession", "POST " .. api .. "/items/f1/permanentDelete",
				"GET " .. graph .. "/drives/b!x-1/items/01ABC", "GET " .. graph .. "/me/messages", "PATCH " .. api .. "/items/f1/permissions/p1",
				"PUT " .. api .. "/items/f1", "GET " .. api .. "/sharedWithMe", "GET " .. api .. "/items/f1/thumbnails",
			})
			-- Preauthenticated hosts take no writes, and lookalike hosts get nothing.
			m.routes(r, "", false, {
				"PUT https://contoso-my.sharepoint.com/upload", "GET https://sharepoint.com/x",
				"GET https://contoso.sharepoint.com.evil.test/x", "GET https://evil.test/contoso.sharepoint.com/x",
			})
		end
	end,
}
