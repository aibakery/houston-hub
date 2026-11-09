return {
	contract = function(m)
		local publisher = {composio_auth_config_id = "ac_fixture", composio_api_key = "fixture-secret"}
		for _, field in {"composio_api_key", "composio_auth_config_id"} do
			local incomplete = table.clone(publisher)
			incomplete[field] = nil
			local _, err = m.resolve(incomplete, {access = "read-only"}, nil, "composio")
			assert(err, "Incomplete Composio settings must require " .. field)
		end
		local direct, directError = m.resolve({client_id = "google-client", client_secret = "google-secret"}, {access = "read-only"}, nil, "oauth")
		assert(direct and not directError, "Direct Google sign-in must work without Composio settings")
		local api = "https://gmail.googleapis.com/gmail/v1/users/me"
		local upload = "https://gmail.googleapis.com/upload/gmail/v1/users/me"
		for _, access in {"read-only", "custom", "read-write"} do
			local r, err = m.resolve(publisher, {access = access}, nil, "composio")
			assert(r and not err, tostring(err))
			m.routes(r, "", true, {"GET " .. api .. "/profile", "GET " .. api .. "/messages?q=is%3Aunread", "GET " .. api .. "/settings/sendAs"})
			m.routes(r, "", access ~= "read-only", {"POST " .. upload .. "/drafts?uploadType=multipart", "PUT " .. upload .. "/drafts/d1?uploadType=multipart", "DELETE " .. api .. "/drafts/d1"})
			m.routes(r, "", access == "read-write", {"POST " .. upload .. "/messages/send?uploadType=multipart", "POST " .. api .. "/drafts/send", "POST " .. api .. "/messages/m1/trash"})
			m.rejectOverrides(r, {"GET " .. api .. "/messages/m1"})
			m.refused(r, "", {"POST https://backend.composio.dev/api/v3.1/tools/execute/proxy", "GET https://gmail.googleapis.com/gmail/v1/users/someone@example.com/profile"})
		end
	end,
}
