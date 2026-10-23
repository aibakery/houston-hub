return {
	scenario = {publisher = {client_id = "fixture-client", client_secret = "fixture-private-secret"}, config = {}, auth_method = "oauth", auth_config = {}, caller_access = "read-only"},
	config = {access = "read-write"},
	run = function(c)
		local names = {}
		for name in c do table.insert(names, name) end
		table.sort(names)
		assert(table.concat(names, ",") == "getDocument,getDocumentText", "read-only caller got " .. table.concat(names, ","))
	end,
}
