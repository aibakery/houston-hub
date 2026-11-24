return {
	contract = function(m)
		local cases = {}
		for _, environment in {"production", "beta"} do
			local host = if environment == "production" then "api.familysearch.org" else "apibeta.familysearch.org"
			local method = if environment == "production" then "oauth" else "oauth_beta"
			for _, level in {"read", "write"} do
				table.insert(cases, {
					publisher = {}, access = {data = level}, config = {environment = environment, client_id = "synthetic-public-client"},
					auth = {}, method = method, oauth = true,
					endpoint = {"GET", "https://" .. host .. "/platform/users/current"},
					header = "Authorization", expected = "Bearer synthetic-oauth-token",
				})
				table.insert(cases, {
					publisher = {}, access = {data = level}, config = {environment = environment},
					auth = {token = "synthetic-method-secret"}, method = "token",
					endpoint = {"GET", "https://" .. host .. "/platform/users/current"},
					header = "Authorization", expected = "Bearer synthetic-method-secret",
				})
			end
		end
		m.authentication(cases)
		for _, environment in {"production", "beta"} do
			local method = if environment == "production" then "oauth" else "oauth_beta"
			local identityHost = if environment == "production" then "ident.familysearch.org" else "identbeta.familysearch.org"
			local apiHost = if environment == "production" then "api.familysearch.org" else "apibeta.familysearch.org"
			local settings = m.raw.auth[method]
			assert(settings.type == "oauth2" and settings.client_auth == "none" and settings.pkce == "S256")
			assert(settings.authorize_url == "https://" .. identityHost .. "/cis-web/oauth2/v3/authorization")
			assert(settings.token_url == "https://" .. identityHost .. "/cis-web/oauth2/v3/token")
			assert(not m.publisherClient(settings), "each connection owns its registered app key and callback")
			assert(settings.account.url == "https://" .. apiHost .. "/platform/users/current")
			assert(settings.account.label == "/users/0/id", "bind the connection to the authenticated FamilySearch user")
			local resolved, err = m.resolve({}, {environment = environment, client_id = "connection-app-key"}, {}, method)
			assert(resolved and not err, tostring(err))
			assert(resolved.Access.data == "read", "default access must restrict writes")
			local client, clientError = m.render(settings.client_id, resolved.Context)
			assert(client == "connection-app-key" and not clientError)
			assert(m.count(resolved.Scopes) == 0, "API access is granted by FamilySearch app compatibility, not OAuth read/write scopes")
			local otherMethod = if method == "oauth" then "oauth_beta" else "oauth"
			local _, wrongEnvironment = m.resolve({}, {environment = environment, client_id = "connection-app-key"}, {}, otherMethod)
			assert(wrongEnvironment, "OAuth environment must match the API environment")
			local _, missingKey = m.resolve({}, {environment = environment}, {}, method)
			assert(missingKey, "OAuth requires the connection's registered app key")
		end
	end,
}
