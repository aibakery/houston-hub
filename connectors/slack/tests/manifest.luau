return {
	contract = function(m)
		-- TestSlackPublisherOwnedClient
		do
			if not (m.publisherClient(m.raw.auth["oauth"])) then
				m.fail("Slack OAuth client must belong to the publication")
			end
		end
		-- TestSlackScopesAndAccessRoutes
		do
			local read = {
				"GET https://slack.com/api/auth.test",
				"GET https://slack.com/api/users.conversations?types=im",
				"GET https://slack.com/api/conversations.history?channel=C1",
				"GET https://slack.com/api/conversations.replies?channel=C1&ts=1.2",
				"GET https://slack.com/api/conversations.info?channel=C1",
				"GET https://slack.com/api/conversations.members?channel=C1",
				"GET https://slack.com/api/users.info?user=U1",
				"GET https://slack.com/api/users.list?limit=200",
				"GET https://slack.com/api/chat.getPermalink?channel=C1&message_ts=1.2",
				"GET https://slack.com/api/files.info?file=F1",
				"GET https://files.slack.com/files-pri/T1-F1/download/report.pdf",
				"GET https://files.slack.com/files-pri/T1-F1/download/100%25%20done.pdf",
			}
			local writes = {
				"POST https://slack.com/api/chat.postMessage",
				"POST https://slack.com/api/chat.update",
				"POST https://slack.com/api/chat.delete",
				"POST https://slack.com/api/conversations.open",
				"POST https://slack.com/api/reactions.add",
				"POST https://slack.com/api/reactions.remove",
				"POST https://slack.com/api/files.getUploadURLExternal",
				"POST https://slack.com/api/files.completeUploadExternal",
			}
			local upload = "POST https://files.slack.com/upload/v1/CwABAAAAXQoAAQ%2FBz%3D"
			local denied = {
				"GET https://slack.com/api/chat.postMessage?channel=C1&text=hi",
				"GET https://slack.com/api/files.getUploadURLExternal?filename=a&length=1",
				"POST https://slack.com/api/oauth.v2.access",
				"GET https://slack.com/api/oauth.v2.access",
				"POST https://slack.com/api/auth.revoke",
				"POST https://slack.com/api/conversations.history",
				"GET https://slack.com/api/users.profile.set",
				"GET https://files.slack.com/upload/v1/signed",
				"POST https://files.slack.com/files-pri/T1-F1/download/report.pdf",
				"GET https://files.slack.com/files-pri/../upload/v1/signed",
				"GET https://slack.com.evil.test/api/auth.test",
				"GET https://evil.slack.com/api/auth.test",
			}
			local readScopes = {
				"channels:read",
				"channels:history",
				"groups:read",
				"groups:history",
				"im:read",
				"im:history",
				"mpim:read",
				"mpim:history",
				"users:read",
				"files:read",
			}
			for _, access in { "read-only", "read-write" } do
				local publisher = { client_id = "fixture-client", client_secret = "fixture-secret" }
				local r, err = m.resolve(publisher, { access = access }, nil, "oauth")
				assert(not err, tostring(err))
				local scopes = table.clone(readScopes)
				if access == "read-write" then
					scopes = m.concat(
						scopes,
						{ "chat:write", "files:write", "im:write", "mpim:write", "reactions:write" }
					)
				end
				if not (m.equal(r.Scopes, scopes)) then
					m.fail("access=%s scopes %s", access, r.Scopes)
				end
				r.Context.Auth["oauth"].access_token = "xoxp-fixture"
				m.routes(r, "Bearer xoxp-fixture", true, read)
				m.routes(r, "Bearer xoxp-fixture", (access == "read-write"), writes)
				m.routes(r, "", (access == "read-write"), { upload })
				m.routes(r, "Bearer xoxp-fixture", false, denied)
			end
		end
	end,
}
