return {
	scenario = {config = {environment = "production", client_id = "fixture-app"}, access = {data = "read"}, auth_method = "oauth", auth_config = {}},
	configure = function()
		requests = {}
		http = {request = function(req)
			table.insert(requests, req)
			return fixture.operation({statusCode = 200, headers = {}, body = fixture.reader('{"persons":[{"id":"P1"}],"sourceDescriptions":[]}')})
		end}
	end,
	run = function(c)
		local person = c.tree.persons.readPerson({pid = "P1"})
		assert(person.data.persons[1].id == "P1")
		local composed = fixture.example("authorities.names.createNameSegments")
		assert(composed.statusCode == 200 and requests[#requests].method == "POST" and requests[#requests].url == "https://api.familysearch.org/platform/names/segments")
		local matches = fixture.example("tree.search.performPersonMatchesByExample")
		assert(matches.data.persons[1].id == "P1" and requests[#requests].method == "POST" and string.find(requests[#requests].url, "https://api.familysearch.org/platform/tree/matches", 1, true) == 1)
		assert(c.tree.persons.createPerson == nil and c.users.createPartnerAccount == nil and c.memories.createMemories == nil)
		assert(c.tree.trees.setCurrentTree == nil and c.users.deleteUserHistory == nil)
		local expected = {}
		local expectedCount = 0
		for _, endpoint in require("catalog.luau") do
			if endpoint.read then expected[endpoint.export] = true; expectedCount += 1 end
		end
		local discoveredCount = 0
		local function inspect(node, prefix)
			assert(#node.functions + #node.namespaces > 0, "read access must not advertise empty namespaces")
			for _, name in node.functions do
				local qualified = prefix .. "." .. name
				assert(expected[qualified] and type(node[name]) == "function", "read discovery must list exactly usable operations")
				expected[qualified] = nil
				discoveredCount += 1
			end
			for _, name in node.namespaces do inspect(node[name], if prefix == "" then name else prefix .. "." .. name) end
		end
		inspect(c, "")
		assert(#c.functions == 0 and discoveredCount == expectedCount and next(expected) == nil)
		assert(table.find(c.authorities.names.functions, "createNameSegments"), "read-only POST composition remains discoverable")
		assert(string.find(c.authorities.names.help("createNameSegments"), "body", 1, true))
		assert(#requests == 3)
	end,
}
