return {
	scenario = {publisher = {}, config = {own_app = true, client_id = "fixture-client", client_secret = "fixture-secret"}, auth_method = "demo", auth_config = {}},
	configure = function()
		requests = {}
		http = {request = function(req)
			table.insert(requests, req)
			return fixture.operation({statusCode = 200, headers = {}, body = fixture.reader('[{"uuid":"l1","city":"Denver"}]')})
		end}
	end,
	run = function(gusto)
		assert(gusto.createLocation == nil and gusto.listLocations ~= nil, "demo read-only surface is wrong")
		local locations = gusto.listLocations({company_id = "c1"})
		assert(requests[1].method == "GET" and requests[1].url == "https://api.gusto-demo.com/v1/companies/c1/locations")
		assert(locations.items[1].city == "Denver" and #requests == 1)
	end,
}
