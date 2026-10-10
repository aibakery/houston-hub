-- Read-only connections expose query alone, and it always asks for a read-only statement.
return {
	scenario = {publisher = {}, auth_method = "", auth_config = {}, config = {host = "db.example.com", database = "app", username = "reader", password = "fixture-password"}},
	config = {access = "read-only"},
	configure = function()
		requests = {}
		db = {query = function(request)
			table.insert(requests, request)
			return fixture.operation({columns = {"id"}, rows = {{id = 7}}, truncated = false})
		end}
	end,
	run = function(exports)
		assert(exports.execute == nil, "read-only access must not expose execute")
		local result = exports.query("SELECT id FROM users WHERE team = $1", {"core"})
		assert(result.rows[1].id == 7 and result.truncated == false)
		local request = requests[1]
		assert(request.sql == "SELECT id FROM users WHERE team = $1" and request.params[1] == "core")
		assert(request.readOnly == true and request.maxRows == 10000)
	end,
}
