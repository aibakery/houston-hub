return {
	scenario = {publisher = {}, config = {host = "example.com", install_path = " /dolibarr/htdocs/index.php/ "}, auth_method = "key",
		auth_config = {token = "Zx81Kq0PnB2vLm4TcR7wYs9dHf3jGa6E"}},
	configure = function()
		requests = {}
		http = {request = function(req)
			table.insert(requests, req)
			return fixture.operation({statusCode = 200, headers = {}, body = fixture.reader('{"id":"3"}')})
		end}
	end,
	run = function(erp)
		-- The address people open, with or without index.php, gives the API's folder.
		assert(erp.getOrder(3).id == "3")
		assert(requests[1].url == "https://example.com/dolibarr/htdocs/api/index.php/orders/3", requests[1].url)
		assert(#requests == 1)
	end,
}
