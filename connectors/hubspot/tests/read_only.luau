return {
	scenario = {publisher = {}, config = {}, auth_method = "token", auth_config = {token = "fixture-token"}},
	configure = function()
		requests, responses = {}, {}
		http = {request = function(req)
			assert(req.headers == nil or req.headers.Authorization == nil, "the proxy injects Authorization")
			table.insert(requests, req)
			assert(#responses > 0, "unexpected request: " .. req.url)
			local response = table.remove(responses, 1)
			return fixture.operation({statusCode = response.status or 200, headers = response.headers or {}, body = fixture.reader(response.body or "")})
		end}
	end,
	run = function(c)
		local API = "https://api.hubapi.com"
		local OBJECTS = API .. "/crm/objects/2026-09/"
		local function last() return requests[#requests] end
		local function get(href: string)
			assert(last().method == "GET" and last().url == href and last().body == nil, last().method .. " " .. last().url)
		end
		local function post(href: string): any
			assert(last().method == "POST" and last().url == href, last().method .. " " .. last().url)
			assert(last().headers["Content-Type"][1] == "application/json", "JSON body without Content-Type")
			return json.decode(last().body)
		end
		local function empty(value: any)
			assert(#value.results == 0 and json.encode(value.results) == "[]", json.encode(value))
		end
		local function fails(expected: {string}, fn: (...any) -> any, ...: any)
			local ok, err = pcall(fn, ...)
			assert(not ok, "call succeeded")
			for _, text in expected do assert(string.find(tostring(err), text, 1, true), "missing " .. text .. " in " .. tostring(err)) end
		end
		local names = {}
		for name in c do table.insert(names, name) end
		table.sort(names)
		assert(table.concat(names, ",") == "batchReadAssociations,batchReadObjects,getObject,getOwner,getPipeline,getProperty,listAssociationLabels,"
			.. "listAssociations,listObjects,listOwners,listPipelines,listProperties,searchObjects", "read-only got " .. table.concat(names, ","))

		-- Records: one page at a time, query lists comma-separated in a fixed order, archived only when true.
		responses = {
			{body = '{"results":[{"id":"101","properties":{"email":"ana@example.com","firstname":"Ana"},"archived":false}],"paging":{"next":{"after":"102","link":"x"}}}'},
			{body = '{"results":[]}'}, {body = '{}'},
			{body = '{"id":"101","properties":{"email":"ana@example.com"},"associations":{"companies":{"results":[{"id":"512","type":"contact_to_company"}]}}}'},
			{body = '{"id":"512","properties":{"name":"Acme"}}'},
		}
		local page = c.listObjects({objectType = "contacts", limit = 2, after = "100", properties = {"email", "first name"},
			propertiesWithHistory = {"lifecyclestage"}, associations = {"companies", "deals"}, archived = true})
		get(OBJECTS .. "contacts?limit=2&after=100&properties=email,first%20name&propertiesWithHistory=lifecyclestage&associations=companies,deals&archived=true")
		assert(page.results[1].properties.firstname == "Ana" and page.paging.next.after == "102", json.encode(page))
		empty(c.listObjects({objectType = "contacts", after = page.paging.next.after}))
		get(OBJECTS .. "contacts?after=102")
		empty(c.listObjects({objectType = "deals", archived = false}))
		get(OBJECTS .. "deals")
		local contact = c.getObject({objectType = "contacts", objectId = "ana@example.com", idProperty = "email", properties = {"email"}, associations = {"companies"}})
		get(OBJECTS .. "contacts/ana%40example.com?idProperty=email&properties=email&associations=companies")
		assert(contact.associations.companies.results[1].id == "512", json.encode(contact))
		assert(c.getObject({objectType = "companies", objectId = "512", propertiesWithHistory = {"name"}, archived = true}).properties.name == "Acme")
		get(OBJECTS .. "companies/512?propertiesWithHistory=name&archived=true")
		-- A unique property value may hold characters such as a colon, sent percent-encoded.
		responses = {{body = '{"id":"77","properties":{"sku":"sku:123"}}'}}
		assert(c.getObject({objectType = "contacts", objectId = "sku:123", idProperty = "sku"}).id == "77")
		get(OBJECTS .. "contacts/sku%3A123?idProperty=sku")

		-- Search and batch reads POST exactly the given fields; 207 partial batches are results.
		responses = {
			{body = '{"total":1,"results":[{"id":"9876","properties":{"dealname":"Renewal"}}],"paging":{"next":{"after":"21"}}}'},
			{body = '{"total":0,"results":[]}'},
			{status = 207, body = '{"status":"COMPLETE","results":[{"id":"101"}],"numErrors":1,"errors":[{"status":"error","category":"OBJECT_NOT_FOUND","message":"Could not get some CONTACT objects"}]}'},
			{body = '{"status":"COMPLETE","results":[{"id":"101","properties":{"email":"ana@example.com"}}]}'},
		}
		local filterGroups = {{filters = {{propertyName = "dealstage", operator = "EQ", value = "contractsent"}}},
			{filters = {{propertyName = "amount", operator = "BETWEEN", value = "1000", highValue = "5000"}, {propertyName = "hs_tag_ids", operator = "IN", values = {"a", "b"}}}}}
		local found = c.searchObjects({objectType = "deals", query = "renewal", filterGroups = filterGroups,
			sorts = {{propertyName = "closedate", direction = "ASCENDING"}}, properties = {"dealname"}, limit = 200, after = "20"})
		assert(found.total == 1 and found.results[1].id == "9876" and found.paging.next.after == "21")
		local sent = post(OBJECTS .. "deals/search")
		assert(sent.query == "renewal" and sent.limit == 200 and sent.after == "20" and sent.properties[1] == "dealname" and sent.sorts[1].direction == "ASCENDING", last().body)
		assert(#sent.filterGroups == 2 and sent.filterGroups[2].filters[1].highValue == "5000" and sent.filterGroups[2].filters[2].values[2] == "b" and sent.objectType == nil, last().body)
		local none = c.searchObjects({objectType = "notes"})
		empty(none)
		assert(none.total == 0 and post(OBJECTS .. "notes/search") ~= nil and last().body == "{}", last().body)
		local batch = c.batchReadObjects({objectType = "contacts", inputs = {{id = "101"}, {id = "999"}}, properties = {"email"},
			propertiesWithHistory = {"lifecyclestage"}, archived = true})
		assert(batch.results[1].id == "101" and batch.numErrors == 1 and batch.errors[1].category == "OBJECT_NOT_FOUND")
		sent = post(OBJECTS .. "contacts/batch/read?archived=true")
		assert(#sent.inputs == 2 and sent.inputs[2].id == "999" and sent.properties[1] == "email" and sent.propertiesWithHistory[1] == "lifecyclestage" and sent.idProperty == nil, last().body)
		c.batchReadObjects({objectType = "contacts", idProperty = "email", inputs = {{id = "ana@example.com"}}})
		sent = post(OBJECTS .. "contacts/batch/read")
		assert(sent.idProperty == "email" and sent.inputs[1].id == "ana@example.com" and sent.properties == nil, last().body)

		-- Associations between records, read one record or many at a time, and their labels.
		responses = {
			{body = '{"results":[{"toObjectId":101,"associationTypes":[{"category":"HUBSPOT_DEFINED","typeId":3,"label":null}]}],"paging":{"next":{"after":"x2"}}}'},
			{body = '{"results":[]}'},
			{status = 207, body = '{"status":"COMPLETE","results":[{"from":{"id":"9876"},"to":[{"toObjectId":512,"associationTypes":[{"category":"HUBSPOT_DEFINED","typeId":5,"label":"Primary"}]}]}],"errors":[{"status":"error","category":"OBJECT_NOT_FOUND"}]}'},
			{body = '{"results":[{"category":"HUBSPOT_DEFINED","typeId":1,"label":"Primary"},{"category":"USER_DEFINED","typeId":36,"label":"Decision maker"}]}'},
			{body = '{"results":[]}'},
		}
		local linked = c.listAssociations({objectType = "deals", objectId = "9876", toObjectType = "contacts", limit = 500, after = "x1"})
		get(OBJECTS .. "deals/9876/associations/contacts?limit=500&after=x1")
		assert(linked.results[1].toObjectId == 101 and linked.paging.next.after == "x2")
		empty(c.listAssociations({objectType = "contacts", objectId = "101", toObjectType = "notes"}))
		get(OBJECTS .. "contacts/101/associations/notes")
		local many = c.batchReadAssociations({fromObjectType = "deals", toObjectType = "companies", inputs = {{id = "9876"}, {id = "9877", after = "abc"}}})
		assert(many.results[1].to[1].associationTypes[1].label == "Primary" and many.errors[1].category == "OBJECT_NOT_FOUND")
		sent = post(API .. "/crm/associations/2026-09/deals/companies/batch/read")
		assert(#sent.inputs == 2 and sent.inputs[1].after == nil and sent.inputs[2].after == "abc", last().body)
		assert(c.listAssociationLabels({fromObjectType = "contacts", toObjectType = "companies"}).results[2].typeId == 36)
		get(API .. "/crm/associations/2026-09/contacts/companies/labels")
		empty(c.listAssociationLabels({fromObjectType = "tickets", toObjectType = "deals"}))

		-- Pipelines, owners and property definitions.
		responses = {
			{body = '{"results":[{"id":"default","label":"Sales Pipeline","stages":[{"id":"appointmentscheduled","label":"Appointment scheduled","metadata":{"probability":"0.2"}}]}]}'},
			{body = '{"results":[]}'},
			{body = '{"id":"0","label":"Support Pipeline","stages":[{"id":"1","metadata":{"ticketState":"OPEN"}}]}'},
			{body = '{"results":[{"id":"41629779","email":"ana@example.com","userId":9586504,"type":"PERSON","teams":[]}],"paging":{"next":{"after":"6"}}}'},
			{body = '{"results":[]}'},
			{body = '{"id":"41629779","userId":9586504,"firstName":"Ana"}'},
			{body = '{"results":[{"name":"dealstage","type":"enumeration","options":[{"label":"Closed won","value":"closedwon"}]}]}'},
			{body = '{}'},
			{body = '{"name":"hs_task_status","options":[{"value":"NOT_STARTED"},{"value":"COMPLETED"}]}'},
		}
		assert(c.listPipelines({objectType = "deals"}).results[1].stages[1].id == "appointmentscheduled")
		get(API .. "/crm/pipelines/2026-09/deals")
		empty(c.listPipelines({objectType = "tickets"}))
		get(API .. "/crm/pipelines/2026-09/tickets")
		assert(c.getPipeline({objectType = "tickets", pipelineId = "0"}).stages[1].metadata.ticketState == "OPEN")
		get(API .. "/crm/pipelines/2026-09/tickets/0")
		local owners = c.listOwners({email = "ana@example.com", limit = 500, after = "5", archived = true})
		get(API .. "/crm/owners/2026-09?email=ana%40example.com&limit=500&after=5&archived=true")
		assert(owners.results[1].id == "41629779" and owners.paging.next.after == "6")
		empty(c.listOwners())
		get(API .. "/crm/owners/2026-09")
		assert(c.getOwner({ownerId = "9586504", idProperty = "userId", archived = true}).firstName == "Ana")
		get(API .. "/crm/owners/2026-09/9586504?idProperty=userId&archived=true")
		assert(c.listProperties({objectType = "deals", archived = true}).results[1].options[1].value == "closedwon")
		get(API .. "/crm/properties/2026-09/deals?archived=true")
		empty(c.listProperties({objectType = "emails"}))
		get(API .. "/crm/properties/2026-09/emails")
		assert(c.getProperty({objectType = "tasks", propertyName = "hs_task_status"}).options[2].value == "COMPLETED")
		get(API .. "/crm/properties/2026-09/tasks/hs_task_status")
		assert(#responses == 0)

		-- Invalid input never reaches the network.
		local before = #requests
		local TYPE = "objectType must be one of contacts, companies, deals, tickets, notes, tasks, calls, meetings, emails"
		fails({"options must be an object"}, c.listObjects, "contacts")
		fails({"listObjects received an unknown option sort"}, c.listObjects, {objectType = "contacts", sort = "email"})
		fails({TYPE}, c.listObjects, {})
		fails({TYPE}, c.listObjects, {objectType = "products"})
		fails({TYPE}, c.searchObjects, {objectType = "Contacts"})
		fails({"toObjectType must be one of"}, c.listAssociations, {objectType = "deals", objectId = "1", toObjectType = "products"})
		fails({"fromObjectType must be one of"}, c.batchReadAssociations, {fromObjectType = "2-1234", toObjectType = "deals", inputs = {{id = "1"}}})
		fails({"objectId must be a string of digits"}, c.getObject, {objectType = "contacts", objectId = 101})
		fails({"objectId must be a string of digits"}, c.getObject, {objectType = "contacts", objectId = "abc"})
		fails({"objectId must be a string of digits"}, c.getObject, {objectType = "contacts", objectId = "../users"})
		fails({"objectId must be a string of digits"}, c.listAssociations, {objectType = "contacts", objectId = "ana@example.com", toObjectType = "companies"})
		assert(not pcall(c.getObject, {objectType = "contacts", objectId = "../users", idProperty = "email"}), "a dot segment reached the network")
		assert(not pcall(c.getObject, {objectType = "contacts", objectId = "a/b", idProperty = "email"}), "a slash reached the network")
		for _, limit in {0, 101, 1.5, "10"} do
			fails({"limit must be an integer from 1 to 100"}, c.listObjects, {objectType = "contacts", limit = limit})
		end
		fails({"limit must be an integer from 1 to 500"}, c.listOwners, {limit = 501})
		fails({"archived must be a boolean"}, c.listObjects, {objectType = "contacts", archived = "true"})
		fails({"after must be a nonempty string"}, c.listObjects, {objectType = "contacts", after = 102})
		fails({"associations[1] must be one of"}, c.listObjects, {objectType = "contacts", associations = {"products"}})
		local filter = {propertyName = "email", operator = "HAS_PROPERTY"}
		local function groups(count: number, size: number)
			local list = {}
			for _ = 1, count do
				local filters = {}
				for _ = 1, size do table.insert(filters, filter) end
				table.insert(list, {filters = filters})
			end
			return list
		end
		fails({"filterGroups must be an array of 1 to 5 items"}, c.searchObjects, {objectType = "contacts", filterGroups = groups(6, 1)})
		fails({"filterGroups[1].filters must be an array of 1 to 6 items"}, c.searchObjects, {objectType = "contacts", filterGroups = groups(1, 7)})
		fails({"at most 18 filters in all"}, c.searchObjects, {objectType = "contacts", filterGroups = groups(4, 5)})
		fails({"filterGroups[1] received an unknown field filter"}, c.searchObjects, {objectType = "contacts", filterGroups = {{filter = {filter}}}})
		fails({"filterGroups[1].filters[1] must be an object"}, c.searchObjects, {objectType = "contacts", filterGroups = {{filters = {"email"}}}})
		fails({"sorts must be an array of 1 to 1 items"}, c.searchObjects, {objectType = "contacts", sorts = {{propertyName = "a"}, {propertyName = "b"}}})
		fails({"limit must be an integer from 1 to 200"}, c.searchObjects, {objectType = "contacts", limit = 201})
		fails({"searchObjects received an unknown option archived"}, c.searchObjects, {objectType = "contacts", archived = true})
		fails({"inputs must be an array of 1 to 100 items"}, c.batchReadObjects, {objectType = "contacts", inputs = {}})
		local ids = {}
		for index = 1, 1001 do table.insert(ids, {id = tostring(index)}) end
		fails({"inputs must be an array of 1 to 100 items"}, c.batchReadObjects, {objectType = "contacts", inputs = table.move(ids, 1, 101, 1, {})})
		fails({"inputs[1].id must be a string of digits"}, c.batchReadObjects, {objectType = "contacts", inputs = {{id = 101}}})
		fails({"inputs[1] received an unknown field properties"}, c.batchReadObjects, {objectType = "contacts", inputs = {{id = "1", properties = {"email"}}}})
		fails({"inputs must be an array of 1 to 1000 items"}, c.batchReadAssociations, {fromObjectType = "deals", toObjectType = "companies", inputs = ids})
		fails({"properties must be an array of 1 to 500 items"}, c.listObjects, {objectType = "contacts", properties = {}})
		fails({"properties must be an array of 1 to 500 items"}, c.searchObjects, {objectType = "contacts", properties = "email"})
		fails({"properties[1] must be a nonempty name without commas"}, c.getObject, {objectType = "contacts", objectId = "1", properties = {"email,phone"}})
		fails({"objectType must be one of deals, tickets"}, c.listPipelines, {objectType = "contacts"})
		fails({"pipelineId must be a nonempty string"}, c.getPipeline, {objectType = "deals"})
		assert(not pcall(c.getPipeline, {objectType = "deals", pipelineId = ".."}), "a dot segment reached the network")
		fails({"propertyName must be a property's internal name"}, c.getProperty, {objectType = "contacts", propertyName = "a/b"})
		fails({"ownerId must be a string of digits"}, c.getOwner, {ownerId = "abc"})
		fails({"idProperty must be one of id, userId"}, c.getOwner, {ownerId = "1", idProperty = "email"})
		assert(#requests == before, "invalid input reached the network")
	end,
}
