-- Read-write connections add execute, which sends a statement allowed to write.
return {
	scenario = {publisher = {}, auth_method = "", auth_config = {}, config = {host = "db.example.com", database = "app", username = "writer", password = "fixture-password"}},
	config = {access = "read-write"},
	configure = function()
		requests = {}
		db = {query = function(request)
			table.insert(requests, request)
			return fixture.operation({columns = json.decode("[]"), rows = json.decode("[]"), truncated = false, affectedRows = 1, lastInsertId = 12})
		end}
	end,
	run = function(exports)
		local result = exports.execute("INSERT INTO tasks (title) VALUES (?)", {"Ship it"})
		assert(result.affectedRows == 1 and result.lastInsertId == 12)
		assert(requests[1].readOnly == false and requests[1].params[1] == "Ship it")
	end,
}
