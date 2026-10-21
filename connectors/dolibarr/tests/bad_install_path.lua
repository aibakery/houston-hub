return {
	scenario = {publisher = {}, config = {host = "example.com", install_path = "/srv/www/dolibarr"}, auth_method = "key",
		auth_config = {token = "Zx81Kq0PnB2vLm4TcR7wYs9dHf3jGa6E"}},
	configure = function()
		calls = 0
		http = {request = function()
			calls += 1
			return fixture.operation({statusCode = 200, headers = {}, body = fixture.reader("{}")})
		end}
	end,
	run = function(erp)
		-- The proxy allows at most two folders; deeper or dot paths fail before any request.
		local ok, err = pcall(function() erp.getStatus() end)
		assert(not ok and string.find(tostring(err), "install path must be empty or one or two folders", 1, true), tostring(err))
		assert(calls == 0, "an invalid install path reached Dolibarr")
	end,
}
