return {
	scenario = {publisher = {}, config = {team = " not a team! "}, auth_method = "token", auth_config = {token = "fixture-token"}},
	configure = function()
		requests = {}
		http = {request = function(req)
			table.insert(requests, req)
			return fixture.operation({statusCode = 200, headers = {}, body = fixture.reader('{"teams":[],"pagination":{"count":0,"next":null,"prev":null}}')})
		end}
	end,
	run = function(vercel)
		-- An invalid team still loads the connector; calls that send the team fail before any request.
		assert(json.encode(vercel.listTeams().teams) == "[]" and requests[1].url == "https://api.vercel.com/v2/teams")
		local ok, err = pcall(function() vercel.listDeployments() end)
		assert(not ok and string.find(tostring(err), "team must be a team ID or slug", 1, true) and #requests == 1, tostring(err))
	end,
}
