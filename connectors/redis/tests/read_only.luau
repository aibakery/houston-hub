-- Read-only connections expose query alone, and it always asks for a read-only command.
return {
	scenario = {publisher = {}, auth_method = "", auth_config = {}, config = {host = "cache.example.com", password = "fixture-password"}},
	config = {access = "read-only"},
	configure = function()
		requests = {}
		db = {command = function(request)
			table.insert(requests, request)
			return fixture.operation(json.decode('{"name":"Ada"}'))
		end}
	end,
	run = function(exports)
		assert(exports.execute == nil, "read-only access must not expose execute")
		assert(exports.query("HGETALL", "user:42").name == "Ada")
		local request = requests[1]
		assert(request.readOnly == true and request.args[1] == "HGETALL" and request.args[2] == "user:42" and #request.args == 2)
	end,
}
