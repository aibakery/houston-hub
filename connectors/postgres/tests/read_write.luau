-- Read-write connections add execute, which sends a statement allowed to write.
return {
	scenario = {publisher = {}, auth_method = "", auth_config = {}, config = {host = "db.example.com", database = "app", username = "writer", password = "fixture-password"}},
	config = {access = "read-write"},
	configure = function()
		requests = {}
		db = {query = function(request)
			table.insert(requests, request)
			return fixture.operation({columns = {"id"}, rows = {{id = 42}}, truncated = false, affectedRows = 1})
		end}
	end,
	run = function(exports)
		local result = fixture.example("execute")
		assert(result.affectedRows == 1 and result.rows[1].id == 42)
		assert(requests[1].readOnly == false and requests[1].params[1] == 42)
		local read = fixture.example("query")
		assert(read.rows[1].id == 42 and read.truncated == false)
		assert(#requests == 2 and requests[2].readOnly == true and requests[2].params[1] == "core")
	end,
}
