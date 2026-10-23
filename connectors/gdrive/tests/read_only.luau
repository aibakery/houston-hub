return {
	scenario = {publisher = {client_id = "fixture-client", client_secret = "fixture-private-secret"}, config = {}, auth_method = "oauth", auth_config = {}},
	config = {access = "read-only"},
	run = function(c)
		local names = {}
		for name in c do table.insert(names, name) end
		table.sort(names)
		assert(table.concat(names, ",") == "downloadFile,exportFile,getAbout,getFile,listDrives,listFiles,listPermissions,statFile", "read-only got " .. table.concat(names, ","))
	end,
}
