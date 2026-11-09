return {
	contract = function(m)
		local publisher = {pipedream_client_id = "fixture-client", pipedream_client_secret = "fixture-secret", pipedream_project_id = "proj_fixture", pipedream_environment = "development"}
		for _, field in {"pipedream_client_secret", "pipedream_project_id"} do
			local incomplete = table.clone(publisher)
			incomplete[field] = nil
			local _, err = m.resolve(incomplete, {access = "read-only"}, nil, "pipedream")
			assert(err, "Incomplete Pipedream settings must require " .. field)
		end
		local direct, directError = m.resolve({client_id = "google-client", client_secret = "google-secret"}, {access = "read-only"}, nil, "oauth")
		assert(direct and not directError, "Direct Google sign-in must work without Pipedream settings")
		local api = "https://gmail.googleapis.com/gmail/v1/users/me"
		local upload = "https://gmail.googleapis.com/upload/gmail/v1/users/me"
		for _, access in {"read-only", "custom", "read-write"} do
			local r, err = m.resolve(publisher, {access = access}, nil, "pipedream")
			assert(r and not err, tostring(err))
			local expected = if access == "read-only" then {
				"email", "https://www.googleapis.com/auth/gmail.metadata", "https://www.googleapis.com/auth/gmail.readonly", "openid", "profile",
			} else {
				"email", "https://www.googleapis.com/auth/gmail.compose", "https://www.googleapis.com/auth/gmail.labels", "https://www.googleapis.com/auth/gmail.metadata",
				"https://www.googleapis.com/auth/gmail.modify", "https://www.googleapis.com/auth/gmail.readonly", "https://www.googleapis.com/auth/gmail.send",
				"https://www.googleapis.com/auth/gmail.settings.basic", "openid", "profile",
			}
			assert(m.equal(r.Scopes, expected))
			assert(r.ScopeProfile == (if access == "read-only" then "read_only" else "read_write"))
			m.routes(r, "", true, {"GET " .. api .. "/profile", "GET " .. api .. "/messages?q=is%3Aunread", "GET " .. api .. "/settings/sendAs"})
			m.routes(r, "", access ~= "read-only", {"POST " .. upload .. "/drafts?uploadType=multipart", "PUT " .. upload .. "/drafts/d1?uploadType=multipart", "DELETE " .. api .. "/drafts/d1"})
			m.routes(r, "", access == "read-write", {"POST " .. upload .. "/messages/send?uploadType=multipart", "POST " .. api .. "/drafts/send", "POST " .. api .. "/messages/m1/trash"})
			m.rejectOverrides(r, {"GET " .. api .. "/messages/m1"})
			m.refused(r, "", {"POST https://api.pipedream.com/v1/connect/proxy", "GET https://gmail.googleapis.com/gmail/v1/users/someone@example.com/profile"})
		end
	end,
}
