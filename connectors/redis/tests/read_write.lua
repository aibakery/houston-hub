-- Read-write connections add execute, which sends a command allowed to write.
return {
	scenario = {publisher = {}, auth_method = "", auth_config = {}, config = {host = "cache.example.com", password = "fixture-password", database = 2}},
	config = {access = "read-write"},
	configure = function()
		requests = {}
		db = {command = function(request)
			table.insert(requests, request)
			return fixture.operation("OK")
		end}
	end,
	run = function(exports)
		assert(exports.execute("SET", "greeting", "hello", "EX", 3600) == "OK")
		local args = requests[1].args
		assert(requests[1].readOnly == false and #args == 5 and args[5] == 3600)
	end,
}
