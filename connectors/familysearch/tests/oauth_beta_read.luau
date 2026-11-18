return {
	scenario = {config = {environment = "beta", client_id = "fixture-app"}, access = {data = "read"}, auth_method = "oauth_beta", auth_config = {}},
	configure = function()
		requests = {}
		http = {request = function(req)
			table.insert(requests, req)
			return fixture.operation({statusCode = 200, headers = {}, body = fixture.reader('{"persons":[],"sourceDescriptions":[],"users":[{"id":"U1"}]}')})
		end}
	end,
	run = function(c)
		local user = c.users.readCurrentUser()
		assert(user.data.users[1].id == "U1" and requests[1].url == "https://apibeta.familysearch.org/platform/users/current")
		local changes = fixture.example("sources.descriptions.getSourceDescriptionChanges")
		assert(changes.statusCode == 200 and requests[#requests].method == "POST" and string.find(requests[#requests].url, "https://apibeta.familysearch.org/platform/sources/descriptions/changes?since=1346107362000", 1, true) == 1)
		local found = fixture.example("genealogies.persons.readGenealogiesPersonsByExternalIds")
		assert(#found.data.persons == 0 and requests[#requests].method == "POST" and string.find(requests[#requests].url, "/persons/external-ids", 1, true))
		assert(c.tree.persons.updatePerson == nil and c.users.updatePartnerAccount == nil and c.genealogies.media.createGenealogiesMedia == nil)
		assert(#requests == 3)
	end,
}
