return {
	scenario = {config = {environment = "production"}, access = {data = "write"}, auth_method = "token", auth_config = {token = "fixture-token"}},
	configure = function()
		requests, responses = {}, {}
		fs = fixture.files()
		http = {request = function(req)
			table.insert(requests, req)
			if req.body ~= nil and type(req.body) ~= "string" then
				req.streamed = true
				req.body = await(req.body:readAll())
			end
			assert(#responses > 0, "unexpected request: " .. req.url)
			local response = table.remove(responses, 1)
			return fixture.operation({statusCode = response.status or 200, headers = response.headers or {}, body = fixture.reader(response.body or "")})
		end}
	end,
	run = function(c)
		responses = {{body = '{"persons":[{"id":"LZJW-C31","living":false}],"links":{"next":{"href":"https://api.familysearch.org/platform/tree/persons?from=next"}}}', headers = {etag = {'"v1"'}, ["set-cookie"] = {"private=secret"}}}}
		local person = c.tree.persons.readPerson({pid = "LZJW-C31", relatives = false, headers = {["Accept-Language"] = "en"}})
		assert(person.data.persons[1].id == "LZJW-C31" and person.data.persons[1].living == false)
		assert(person.statusCode == 200 and person.headers.etag[1] == '"v1"' and person.headers["set-cookie"] == nil)
		assert(requests[1].url == "https://api.familysearch.org/platform/tree/persons/LZJW-C31?relatives=false")
		assert(requests[1].headers.Accept[1] == "application/x-fs-v1+json" and requests[1].headers["Accept-Language"][1] == "en")

		responses = {{body = '{"entries":[],"links":{"next":{"href":"?start=20&count=20"}}}'}, {status = 204}}
		local page = c.tree.memories.getPersonMemories({pid = "LZJW-C31", start = 0, count = 20})
		assert(#page.data.entries == 0 and type(page.data.links.next.href) == "string")
		assert(string.find(requests[#requests].url, "count=20", 1, true) and string.find(requests[#requests].url, "start=0", 1, true))
		local empty = c.tree.memories.getPersonMemories({pid = "LZJW-C31", start = 20, count = 20})
		assert(empty.statusCode == 204 and empty.data == nil)
		responses = {{body = '{"sourceDescriptions":[]}'}}
		c.memories.readUserMemories({uid = "u1", start = 0})
		assert(string.find(requests[#requests].url, "count=100", 1, true), requests[#requests].url)

		responses = {{body = '{"entries":[]}'}}
		c.tree.search.searchTreePersons({["q.givenName"] = "Anne Marie", ["q.surname"] = "O'Brien", ["f.birthPlace0"] = "3,Canada", ["c.birthPlace1"] = "on", count = 10})
		local search = requests[#requests]
		assert(string.find(search.url, "q.givenName=Anne%20Marie", 1, true) and string.find(search.url, "f.birthPlace0=3%2CCanada", 1, true))
		assert(search.headers.Accept[1] == "application/x-gedcomx-atom+json")

		responses = {{status = 303, headers = {location = {"https://api.familysearch.org/platform/tree/persons/AAAA-BBB"}}}, {status = 304, headers = {etag = {'"v1"'}}}}
		local current = c.tree.persons.readCurrentTreePerson()
		assert(current.statusCode == 303 and current.headers.location[1] == "https://api.familysearch.org/platform/tree/persons/AAAA-BBB" and current.data == nil)
		assert(c.tree.persons.readPerson({pid = "AAAA-BBB", headers = {["If-None-Match"] = '"v1"'}}).statusCode == 304)

		responses = {{status = 201, headers = {location = {"https://api.familysearch.org/platform/tree/persons/NEW-PID"}, ["x-entity-id"] = {"NEW-PID"}}}, {status = 200, body = '{"persons":[{"id":"NEW-PID"}]}'}, {status = 204}}
		local created = c.tree.persons.createPerson({body = {persons = {{living = false, names = {{nameForms = {{fullText = "Fixture Person"}}}}}}}})
		assert(created.statusCode == 201 and created.headers["x-entity-id"][1] == "NEW-PID")
		local sent = requests[#requests]
		assert(sent.method == "POST" and sent.headers["Content-Type"][1] == "application/x-fs-v1+json" and json.decode(sent.body).persons[1].names[1].nameForms[1].fullText == "Fixture Person")
		c.tree.persons.updatePerson({pid = "NEW-PID", headers = {["X-Reason"] = "Correcting a transcription", ["If-Match"] = '"v1"'}, body = {persons = {{id = "NEW-PID", living = false}}}})
		assert(requests[#requests].headers["X-Reason"][1] == "Correcting a transcription")
		assert(c.tree.persons.deletePerson({pid = "NEW-PID", headers = {["X-Reason"] = "Remove disposable fixture"}}).statusCode == 204)

		responses = {{status = 204}}
		c.tree.preferences.updatePreferredParentRelationship({uid = "u1", pid = "p1", headers = {Location = "https://api.familysearch.org/platform/tree/child-and-parents-relationships/r1"}})
		assert(requests[#requests].url == "https://api.familysearch.org/platform/tree/users/u1/preferred-parent-relationships/p1" and requests[#requests].method == "PUT")

		responses = {{body = '{"persons":[{"id":"2:2:P12-345"}]}'}}
		local ext = c.genealogies.persons.readGenealogiesPersonsByExternalIds({tid = "2:2:12345", body = {sourceDescriptions = {{identifiers = {["https://example.org/id"] = {"123"}}}}}})
		assert(ext.data.persons[1].id == "2:2:P12-345")
		assert(requests[#requests].url == "https://api.familysearch.org/platform/genealogies/trees/2%3A2%3A12345/persons/external-ids")

		local count = #requests
		for _, id in {"..", "a/b", "a%2Fb", "a\\b", "a\n"} do assert(not pcall(c.tree.persons.readPerson, {pid = id})) end
		for _, args in {{pid = "p", count = 0}, {pid = "p", count = 1001}, {pid = "p", count = 1.5}} do assert(not pcall(c.tree.memories.getPersonMemories, args)) end
		assert(not pcall(c.tree.persons.readPerson, {pid = "p", typo = true}))
		assert(not pcall(c.tree.persons.readPerson, {pid = "p", headers = {Authorization = "Bearer attacker"}}))
		assert(not pcall(c.tree.persons.readPerson, {pid = "p", headers = {["Accept-Language"] = "en\r\nAuthorization: bad"}}))
		assert(not pcall(c.tree.persons.createPerson, {body = {{id = "p"}}}))
		assert(not pcall(c.tree.persons.createPerson, {body = json.decode("null")}))
		assert(#requests == count, "invalid input reached FamilySearch")
		assert(#responses == 0)
	end,
}
