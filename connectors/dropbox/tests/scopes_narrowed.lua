return {
	scenario = {config = {client_id = "fixture-app-key", client_secret = "fixture-private-secret"}, auth_method = "oauth", granted_scopes = {"files.content.read","sharing.write",}},
	config = {access = "read-only"},
	run = function(c)
		local expected = {}
		expected.getTemporaryLink = true
		expected.download = true
		expected.downloadZip = true
		expected.export = true
		expected.getPreview = true
		expected.getThumbnail = true
		for name in expected do assert(type(c[name]) == "function", "missing permitted export: " .. name) end
		for name in c do assert(name == "help" or expected[name], "unexpected export: " .. name) end
	end,
}
