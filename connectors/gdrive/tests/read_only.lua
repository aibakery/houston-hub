return {
	scenario = {publisher = {client_id = "fixture-client", client_secret = "fixture-private-secret"}, config = {}, auth_method = "oauth", auth_config = {}},
	config = {access = "read-only"},
	run = function(c)
		for _, name in {"createFile", "updateFile", "copyFile", "deleteFile", "uploadFile", "createPermission", "deletePermission"} do
			assert(c[name] == nil, "read-only leaked " .. name)
		end
		for _, name in {"getAbout", "listFiles", "getFile", "listDrives", "listPermissions", "downloadFile", "exportFile", "statFile"} do
			assert(type(c[name]) == "function", "missing " .. name)
		end
	end,
}
