-- TLS mode require encrypts without checking the certificate, so it needs no CA certificate.
return {
	scenario = {publisher = {}, auth_method = "", auth_config = {}, config = {host = "203.0.113.7", database = "app", username = "reader", password = "fixture-password", tls_mode = "require"}},
	configure = function()
		requests = {}
		db = {query = function(request)
			table.insert(requests, request)
			return fixture.operation({columns = {"ok"}, rows = {{ok = 1}}, truncated = false})
		end}
	end,
	run = function(exports)
		assert(exports.query("SELECT 1 AS ok").rows[1].ok == 1 and #requests == 1)
	end,
}
