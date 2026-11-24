return {
	contract = function(m)
		local endpoints = {}
		for name, method, path, read, qualified in string.gmatch(m.modules["catalog.luau"], '\n\t([%w_]+) = %{method = "([A-Z]+)", path = "([^"]+)", read = (%a+), export = "([^"]+)"') do
			table.insert(endpoints, {name = qualified, method = method, path = path, read = read == "true"})
		end
		assert(#endpoints == 216, "exercise the full documented FamilySearch API catalog")
		assert(m.raw.connections == "personal-only", "each user must authorize their own FamilySearch account")
		for _, environment in {"production", "beta"} do
			local host = if environment == "production" then "api.familysearch.org" else "apibeta.familysearch.org"
			local otherHost = if environment == "production" then "apibeta.familysearch.org" else "api.familysearch.org"
			for _, level in {"read", "write"} do
				local resolved, err = m.resolve({}, {environment = environment}, {token = "familysearch-fixture-token"}, "token", {data = level})
				assert(resolved and not err, tostring(err))
				local expectedNames = {}
				for _, entry in endpoints do
					local path = string.gsub(entry.path, "{[^}]+}", "FIXTURE-1")
					local allowed = entry.read or level == "write"
					m.routes(resolved, "Bearer familysearch-fixture-token", allowed, {entry.method .. " https://" .. host .. path})
					if allowed then table.insert(expectedNames, entry.name) end
				end
				local discovered, discoveryError = m.exports(resolved.PublicConfig, "token", nil, nil, resolved.Access)
				assert(discovered and not discoveryError and discovered.type == "result", tostring(discoveryError))
				m.sortedEqual(expectedNames, discovered.exports)
				m.routes(resolved, "Bearer familysearch-fixture-token", false, {
					"GET https://" .. otherHost .. "/platform/users/current",
					"GET https://" .. host .. ".untrusted.example/platform/users/current",
					"GET https://ident.familysearch.org/cis-web/oauth2/v3/authorization",
					"POST https://identbeta.familysearch.org/cis-web/oauth2/v3/token",
					"GET https://" .. host .. "/platform/tree/persons/%2e%2e/users/current",
					"PATCH https://" .. host .. "/platform/tree/persons/FIXTURE-1",
				})
				m.rejectOverrides(resolved, {
					"GET https://" .. host .. "/platform/users/current",
					"POST https://" .. host .. "/platform/tree/matches",
				})
				m.routes(resolved, "Bearer familysearch-fixture-token", true, {
					"GET https://" .. host .. "/platform/genealogies/persons/2%3A2%3AP12-345",
					"GET https://" .. host .. "/platform/genealogies/media/2%3A3%3A54321",
					"POST https://" .. host .. "/platform/genealogies/trees/2%3A2%3A12345/persons/external-ids",
				})
				m.routes(resolved, "Bearer familysearch-fixture-token", level == "write", {
					"POST https://" .. host .. "/platform/genealogies/persons/2%3A2%3AP12-345/merges/2%3A2%3AP54-321",
					"POST https://" .. host .. "/platform/genealogies/trees/2%3A2%3A12345/media",
				})
			end
		end
	end,
}
