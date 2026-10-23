-- Read-only connections expose query alone, and it always asks for a read-only statement.
return {
	scenario = {publisher = {}, auth_method = "", auth_config = {}, config = {host = "db.example.com", database = "app", username = "reader", password = "fixture-password"}},
	config = {access = "read-only"},
	configure = function()
		requests = {}
		db = {query = function(request)
			table.insert(requests, request)
			return fixture.operation({columns = {"n"}, rows = {{n = 7}}, truncated = false})
		end}
	end,
	run = function(exports)
		assert(exports.execute == nil, "read-only access must not expose execute")
		local result = exports.query("SELECT count() AS n FROM events WHERE day = {day:Date}", {day = "2026-01-31"})
		assert(result.rows[1].n == 7 and result.truncated == false)
		local request = requests[1]
		assert(request.params.day == "2026-01-31")
		assert(request.readOnly == true and request.maxRows == 10000)
	end,
}
