-- TLS mode require encrypts without checking the certificate, so it needs no CA certificate.
return {
	scenario = {publisher = {}, auth_method = "", auth_config = {}, config = {host = "imap.example.com", username = "ada@example.com", password = "fixture-password", tls_mode = "require"}},
	configure = function()
		requests = {}
		imap = {command = function(request)
			table.insert(requests, request)
			return fixture.operation(json.decode("[]"))
		end}
	end,
	run = function(c)
		assert(json.encode(c.listMailFolders()) == "[]" and #requests == 1 and requests[1].command == "list")
	end,
}
