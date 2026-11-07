return {
	contract = function(m)
		local api = "https://graph.microsoft.com/v1.0/me"
		-- Read and draft (custom) asks for Mail.ReadWrite only, but Microsoft may keep Mail.Send from an
		-- earlier grant to the same app: these routes are what refuse its sends.
		for access, scopes in {["read-only"] = {"Mail.Read"}, custom = {"Mail.ReadWrite"}, ["read-write"] = {"Mail.ReadWrite", "Mail.Send"}} do
			local r, err = m.resolve({client_id = "publisher-client", client_secret = "publisher-secret"}, {access = access}, nil, "oauth")
			assert(r and not err, tostring(err))
			assert(m.equal(r.Scopes, m.concat({"offline_access", "User.Read"}, scopes)), "requested OAuth scopes for " .. access)
			r.Context.Auth.oauth.access_token = "fixture-token"
			local reads = {
				"GET " .. api .. "?$select=userPrincipalName", "GET " .. api .. "/mailFolders?$top=100", "GET " .. api .. "/mailFolders/inbox",
				"GET " .. api .. "/mailFolders/F1/childFolders", "GET " .. api .. "/mailFolders/inbox/messages?%24skip=10",
				"GET " .. api .. "/messages?$search=%22from%3Aana%22", "GET " .. api .. "/messages/AAMk-_%3D", "GET " .. api .. "/messages/m1/attachments",
				"GET " .. api .. "/messages/m1/attachments/A1%3D/$value",
			}
			m.routes(r, "Bearer fixture-token", true, reads)
			m.rejectOverrides(r, reads)
			local drafts = {
				"POST " .. api .. "/messages", "POST " .. api .. "/messages/m1/attachments", "POST " .. api .. "/messages/m1/createReply",
				"POST " .. api .. "/messages/m1/createReplyAll", "POST " .. api .. "/messages/m1/createForward",
				"PATCH " .. api .. "/messages/m1", "DELETE " .. api .. "/messages/m1",
			}
			m.routes(r, "Bearer fixture-token", access ~= "read-only", drafts)
			if access ~= "read-only" then m.rejectOverrides(r, drafts) end
			m.routes(r, "Bearer fixture-token", access == "read-write", {
				"POST " .. api .. "/sendMail", "POST " .. api .. "/messages/m1/send", "POST " .. api .. "/messages/m1/reply",
				"POST " .. api .. "/messages/m1/replyAll", "POST " .. api .. "/messages/m1/forward", "POST " .. api .. "/messages/m1/move",
				"POST " .. api .. "/mailFolders", "POST " .. api .. "/mailFolders/F1/childFolders",
			})
			-- The token stays off Microsoft's token endpoint, batches that could wrap writes, other users
			-- and APIs, lookalike hosts and mailbox routes the connector never calls: MIME, permanent
			-- deletes, copies, folder changes, direct folder posts and attachment changes.
			m.routes(r, "Bearer fixture-token", false, {
				"POST https://login.microsoftonline.com/common/oauth2/v2.0/token", "POST https://graph.microsoft.com/v1.0/$batch",
				"GET https://graph.microsoft.com/v1.0/users/other@example.com/messages", "GET https://graph.microsoft.com/beta/me/messages",
				"GET " .. api .. "/events", "GET " .. api .. "/drive", "GET https://graph.microsoft.com.evil.test/v1.0/me",
				"GET " .. api .. "/messages/%2e%2e/x", "GET " .. api .. "/messages/m1/$value", "POST " .. api .. "/messages/m1/permanentDelete",
				"POST " .. api .. "/messages/m1/copy", "POST " .. api .. "/messages/m1/attachments/createUploadSession",
				"PATCH " .. api .. "/mailFolders/F1", "DELETE " .. api .. "/mailFolders/F1", "PUT " .. api .. "/messages/m1",
				"GET " .. api .. "/mailFolders/inbox/messages/delta", "POST " .. api .. "/mailFolders/inbox/messages",
				"PATCH " .. api .. "/messages/m1/attachments/A1", "DELETE " .. api .. "/messages/m1/attachments/A1",
			})
		end
	end,
}
