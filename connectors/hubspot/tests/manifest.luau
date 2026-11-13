local API = "https://api.hubapi.com"
local OBJECTS = API .. "/crm/objects/2026-09/"
local TYPES = {"contacts", "companies", "deals", "tickets", "notes", "tasks", "calls", "meetings", "emails"}
local READ_SCOPES = {
	"oauth", "crm.objects.contacts.read", "crm.objects.companies.read", "crm.objects.deals.read",
	"crm.objects.tickets.read", "crm.objects.owners.read", "crm.schemas.contacts.read", "crm.schemas.companies.read",
	"crm.schemas.deals.read", "crm.schemas.tickets.read", "sales-email-read",
}
local WRITE_SCOPES = {"crm.objects.contacts.write", "crm.objects.companies.write", "crm.objects.deals.write", "crm.objects.tickets.write"}

return {
	contract = function(m)
		local reads = {
			"GET " .. OBJECTS .. "contacts/ana%40example.com?idProperty=email&properties=email",
			"GET " .. OBJECTS .. "contacts/sku%3A123?idProperty=sku",
			"GET " .. OBJECTS .. "deals/9876/associations/contacts?limit=500&after=x1",
			"POST " .. OBJECTS .. "deals/search", "POST " .. OBJECTS .. "notes/batch/read?archived=true",
			"POST " .. API .. "/crm/associations/2026-09/deals/companies/batch/read",
			"GET " .. API .. "/crm/associations/2026-09/contacts/companies/labels",
			"GET " .. API .. "/crm/pipelines/2026-09/deals", "GET " .. API .. "/crm/pipelines/2026-09/tickets/0",
			"GET " .. API .. "/crm/owners/2026-09?email=ana%40example.com&limit=500",
			"GET " .. API .. "/crm/owners/2026-09/41629779?idProperty=userId",
		}
		local writes = {}
		for _, kind in TYPES do
			table.insert(reads, "GET " .. OBJECTS .. kind .. "?limit=100&properties=hs_timestamp,hubspot_owner_id")
			table.insert(reads, "GET " .. OBJECTS .. kind .. "/101")
			table.insert(reads, "POST " .. OBJECTS .. kind .. "/search")
			table.insert(reads, "GET " .. API .. "/crm/properties/2026-09/" .. kind .. "?archived=true")
			table.insert(reads, "GET " .. API .. "/crm/properties/2026-09/" .. kind .. "/hs_timestamp")
			table.insert(writes, "POST " .. OBJECTS .. kind)
			table.insert(writes, "PATCH " .. OBJECTS .. kind .. "/101?idProperty=email")
			table.insert(writes, "PATCH " .. OBJECTS .. kind .. "/sku%3A123?idProperty=sku")
			table.insert(writes, "PUT " .. OBJECTS .. kind .. "/101/associations/companies/512")
			table.insert(writes, "PUT " .. OBJECTS .. kind .. "/101/associations/default/companies/512")
			table.insert(writes, "DELETE " .. OBJECTS .. kind .. "/101/associations/companies/512")
		end
		-- The token never reaches HubSpot's OAuth endpoints (token exchange, introspection, revocation,
		-- or /oauth/v1/access-tokens, which echoes the token), account details, other hosts, record
		-- deletes, bulk writes, merges, schema administration, other object types or API versions.
		-- Some routes stay reachable although the connector never sends them. An {objectId} placeholder
		-- admits any one segment, and /crm/properties/2026-09/<type>/{propertyName} also admits
		-- "groups" (property groups); both are GET and expose nothing beyond the granted scopes. The
		-- {fromObjectType} and {toObjectType} placeholders of the association routes admit any object type,
		-- such as quotes: a manifest cannot constrain placeholder values, and listing every pair of the
		-- nine types would take about 500 paths. Luau bounds them to the nine types, and the token's scopes
		-- bound what HubSpot answers.
		local anyTypeReads = {
			"GET " .. OBJECTS .. "contacts/101/associations/quotes", "GET " .. API .. "/crm/associations/2026-09/contacts/quotes/labels",
			"POST " .. API .. "/crm/associations/2026-09/quotes/contacts/batch/read",
		}
		local anyTypeWrites = {
			"PUT " .. OBJECTS .. "contacts/101/associations/quotes/7", "PUT " .. OBJECTS .. "contacts/101/associations/default/quotes/7",
			"DELETE " .. OBJECTS .. "contacts/101/associations/quotes/7",
		}
		local denied = {
			"POST " .. API .. "/oauth/2026-09/token", "POST " .. API .. "/oauth/v3/token", "POST " .. API .. "/oauth/v1/token",
			"GET " .. API .. "/oauth/v1/access-tokens/fixture-token", "GET " .. API .. "/oauth/v1/refresh-tokens/x",
			"DELETE " .. API .. "/oauth/v1/refresh-tokens/x", "POST " .. API .. "/oauth/2026-09/token/introspect",
			"POST " .. API .. "/oauth/2026-09/token/revoke", "POST " .. API .. "/oauth/v2/private-apps/get/access-token-info",
			"POST https://api.hubspot.com/oauth/2026-09/token", "GET https://api.hubspot.com/crm/owners/2026-09",
			"GET https://api.hubapi.com.evil.test/crm/owners/2026-09", "GET https://api-eu1.hubapi.com/crm/owners/2026-09",
			"GET https://app.hubspot.com/oauth/authorize", "GET " .. API .. "/account-info/2026-09/details",
			"DELETE " .. OBJECTS .. "contacts/101", "POST " .. OBJECTS .. "contacts/batch/create",
			"POST " .. OBJECTS .. "contacts/batch/update", "POST " .. OBJECTS .. "contacts/batch/upsert",
			"POST " .. OBJECTS .. "contacts/batch/archive", "POST " .. OBJECTS .. "contacts/merge",
			"POST " .. OBJECTS .. "contacts/gdpr-delete", "PUT " .. OBJECTS .. "contacts/101",
			"POST " .. API .. "/crm/associations/2026-09/contacts/companies/batch/create",
			"POST " .. API .. "/crm/associations/2026-09/contacts/companies/batch/archive",
			"POST " .. API .. "/crm/associations/2026-09/contacts/companies/batch/associate/default",
			"POST " .. API .. "/crm/associations/2026-09/contacts/companies/labels",
			"DELETE " .. API .. "/crm/associations/2026-09/contacts/companies/labels/36",
			"GET " .. API .. "/crm/associations/2026-09/definitions/configurations/all",
			"POST " .. API .. "/crm/pipelines/2026-09/deals", "DELETE " .. API .. "/crm/pipelines/2026-09/deals/default",
			"PATCH " .. API .. "/crm/pipelines/2026-09/deals/default", "GET " .. API .. "/crm/pipelines/2026-09/deals/default/audit",
			"POST " .. API .. "/crm/properties/2026-09/contacts", "PATCH " .. API .. "/crm/properties/2026-09/contacts/email",
			"DELETE " .. API .. "/crm/properties/2026-09/contacts/email",
			"GET " .. OBJECTS .. "products", "GET " .. OBJECTS .. "users", "GET " .. OBJECTS .. "2-1234",
			"POST " .. OBJECTS .. "products", "GET " .. API .. "/crm/objects/v3/contacts", "GET " .. API .. "/crm/v3/objects/contacts",
			"GET " .. API .. "/crm/objects/2026-03/contacts", "GET " .. API .. "/crm/pipelines/2026-09/orders",
			"GET " .. OBJECTS .. "contacts/%2e%2e/users", "GET " .. OBJECTS .. "contacts/101/../../users",
			"GET " .. OBJECTS .. "contacts/101%2Fassociations/companies",
		}
		local publisher = {client_id = "publisher-client", client_secret = "publisher-secret"}
		for _, method in {"oauth", "token"} do
			for _, access in {"read-only", "read-write"} do
				local r, err = m.resolve(if method == "oauth" then publisher else nil, {access = access},
					if method == "token" then {token = "fixture-token"} else nil, method)
				assert(r and not err, tostring(err))
				if method == "oauth" then
					local expected = if access == "read-write" then m.concat(READ_SCOPES, WRITE_SCOPES) else READ_SCOPES
					assert(m.equal(r.Scopes, expected), "requested OAuth scopes for " .. access)
					r.Context.Auth.oauth.access_token = "fixture-token"
				else
					assert(m.count(r.Scopes) == 0, "a manual token requests no scopes")
				end
				m.routes(r, "Bearer fixture-token", true, reads)
				m.rejectOverrides(r, reads)
				m.routes(r, "Bearer fixture-token", true, anyTypeReads)
				m.routes(r, "Bearer fixture-token", access == "read-write", writes)
				m.routes(r, "Bearer fixture-token", access == "read-write", anyTypeWrites)
				if access == "read-write" then m.rejectOverrides(r, writes) end
				m.routes(r, "Bearer fixture-token", false, denied)
			end
		end
	end,
}
