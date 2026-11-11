return {
	contract = function(m)
		local api = "https://graph.microsoft.com/v1.0/me"
		for access, scopes in {["read-only"] = {"Contacts.Read"}, ["read-write"] = {"Contacts.ReadWrite"}} do
			local r, err = m.resolve({client_id = "publisher-client", client_secret = "publisher-secret"}, {access = access}, nil, "oauth")
			assert(r and not err, tostring(err))
			assert(m.equal(r.Scopes, m.concat({"offline_access", "User.Read"}, scopes)), "requested OAuth scopes for " .. access)
			r.Context.Auth.oauth.access_token = "fixture-token"
			local reads = {
				"GET " .. api .. "/contacts?$select=id,displayName&$top=100", "GET " .. api .. "/contacts/AAMk-_%3D",
				"GET " .. api .. "/contacts?$filter=emailAddresses%2Fany(a%3Aa%2Faddress%20eq%20%27ana%40example.com%27)",
				"GET " .. api .. "/contactFolders?$top=100", "GET " .. api .. "/contactFolders/AQMk-_%3D%3D/childFolders",
				"GET " .. api .. "/contactFolders/F1/contacts?$skip=10", "GET " .. api .. "/contactFolders/F1/contacts/C1",
			}
			m.routes(r, "Bearer fixture-token", true, reads)
			m.rejectOverrides(r, reads)
			local writes = {
				"POST " .. api .. "/contacts", "POST " .. api .. "/contactFolders/F1/contacts", "POST " .. api .. "/contactFolders",
				"POST " .. api .. "/contactFolders/F1/childFolders", "PATCH " .. api .. "/contacts/C1", "DELETE " .. api .. "/contacts/C1",
				"PATCH " .. api .. "/contactFolders/F1/contacts/C1", "DELETE " .. api .. "/contactFolders/F1/contacts/C1",
				"PATCH " .. api .. "/contactFolders/F1", "DELETE " .. api .. "/contactFolders/F1",
			}
			m.routes(r, "Bearer fixture-token", access == "read-write", writes)
			if access == "read-write" then m.rejectOverrides(r, writes) end
			-- The token stays off Microsoft's token endpoint, batches that could wrap writes, other users,
			-- APIs and mailboxes, lookalike hosts and contact routes the connector never calls: photos,
			-- extensions, folder delta, permanent deletes, folder reads by id, deeper paths and other methods.
			-- An {id} placeholder still admits any one segment, so contacts/delta, which returns the same
			-- contacts, stays reachable.
			m.routes(r, "Bearer fixture-token", false, {
				"POST https://login.microsoftonline.com/common/oauth2/v2.0/token", "POST https://graph.microsoft.com/v1.0/$batch",
				"GET https://graph.microsoft.com/v1.0/users/other@example.com/contacts", "GET https://graph.microsoft.com/beta/me/contacts",
				"GET https://graph.microsoft.com.evil.test/v1.0/me/contacts", "GET " .. api, "GET " .. api .. "/messages",
				"GET " .. api .. "/people", "GET " .. api .. "/calendar", "GET " .. api .. "/contacts/C1/photo/$value",
				"PUT " .. api .. "/contacts/C1/photo/$value", "GET " .. api .. "/contacts/C1/extensions", "POST " .. api .. "/contacts/C1/extensions",
				"GET " .. api .. "/contactFolders/delta",
				"POST " .. api .. "/contacts/C1/permanentDelete", "POST " .. api .. "/contactFolders/F1/permanentDelete",
				"GET " .. api .. "/contactFolders/F1", "GET " .. api .. "/contactFolders/F1/childFolders/F2/contacts",
				"PUT " .. api .. "/contacts/C1", "PATCH " .. api .. "/contacts", "DELETE " .. api .. "/contactFolders/F1/childFolders",
				"POST " .. api .. "/contacts/C1", "GET " .. api .. "/contacts/%2e%2e/messages", "GET " .. api .. "/contacts/C1/../../messages",
				"GET " .. api .. "/contactFolders/../messages", "GET https://graph.microsoft.com/v1.0/users/other@example.com/contactFolders/F1/contacts",
			})
		end
	end,
}
