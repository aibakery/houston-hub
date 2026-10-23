-- Read-write connections add execute, which sends a statement allowed to write.
return {
	scenario = {publisher = {}, auth_method = "", auth_config = {}, config = {host = "db.example.com", username = "writer", password = "fixture-password"}},
	config = {access = "read-write"},
	configure = function()
		requests = {}
		db = {query = function(request)
			table.insert(requests, request)
			return fixture.operation({columns = json.decode("[]"), rows = json.decode("[]"), truncated = false})
		end}
	end,
	run = function(exports)
		local result = exports.execute("INSERT INTO events (day, event) VALUES ({day:Date}, {event:String})", {day = "2026-01-31", event = "signup"})
		assert(#result.rows == 0 and result.affectedRows == nil)
		assert(requests[1].readOnly == false and requests[1].params.event == "signup")
	end,
}
