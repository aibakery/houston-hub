return {
	contract = function(m)
		-- TestDropboxScopesAndRoutes
		do
			local readScopes = {
				"account_info.read",
				"files.metadata.read",
				"files.content.read",
				"sharing.read",
				"file_requests.read",
			}
			local writeScopes = { "files.content.write", "sharing.write", "file_requests.write" }
			local method = "oauth"
			for _, access in { "read-only", "read-write" } do
				local publisher = { client_id = "publisher-key", client_secret = "publisher-secret" }
				local config = { access = access }
				local r, err = m.resolve(publisher, config, nil, method)
				assert(not err, tostring(err))
				local scopes = readScopes
				if access == "read-write" then
					scopes = m.concat(readScopes, writeScopes)
				end
				if not (m.equal(r.Scopes, scopes)) then
					m.fail("access=%s scopes %s", access, r.Scopes)
				end
				r.Context.Auth[method].access_token = "fixture-token"
				m.routes(r, "Bearer fixture-token", true, {
					"POST https://api.dropboxapi.com/2/files/list_folder",
					"POST https://api.dropboxapi.com/2/sharing/revoke_shared_link",
					"POST https://content.dropboxapi.com/2/files/download",
					"POST https://content.dropboxapi.com/2/files/upload",
				})
				m.routes(r, "Bearer fixture-token", false, {
					"POST https://api.dropboxapi.com/oauth2/token",
					"GET https://api.dropboxapi.com/2/files/list_folder",
					"POST https://notify.dropboxapi.com/2/files/list_folder/longpoll",
					"GET https://dl.dropboxusercontent.com/apitl/1/file",
					"POST https://api.dropboxapi.com.evil.test/2/files/list_folder",
				})
			end
		end
		-- TestDropboxPublisherClient
		do
			local publisher = { client_id = "publisher-key", client_secret = "publisher-secret" }
			local r, err = m.resolve(publisher, nil, nil, "oauth")
			assert(not err, tostring(err))
			local client, err = m.render(m.raw.auth["oauth"].client_id, r.Context)
			if
				((err ~= nil) or (client ~= "publisher-key")) or not (m.publisherClient(m.raw.auth["oauth"]))
			then
				m.fail("wrong OAuth client: %s %s", client, err)
			end
			for _, field in r.ConnectionFields do
				if
					((field.name == "client_id") or (field.name == "client_secret"))
					or (field.name == "own_app")
				then
					m.fail("connection exposes app credentials")
				end
			end
			for _, missing in { "client_id", "client_secret" } do
				local inputs = table.clone(publisher)
				inputs[missing] = nil
				do
					local _, err = m.resolve(inputs, nil, nil, "oauth")
					if err == nil then
						m.fail("missing %s accepted", missing)
					end
				end
			end
		end
	end,
}
