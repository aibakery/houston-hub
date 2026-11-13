return {
	scenario = {publisher = {client_id = "fixture-client", client_secret = "fixture-private-secret"}, config = {access = "read-only"}, auth_method = "oauth", auth_config = {}},
	configure = function()
		requests, responses = {}, {}
		http = {request = function(req)
			for name in req.headers or {} do assert(string.lower(name) ~= "authorization", "the proxy injects Authorization") end
			table.insert(requests, req)
			assert(#responses > 0, "unexpected request: " .. req.url)
			local response = table.remove(responses, 1)
			return fixture.operation({statusCode = response.status or 200, headers = response.headers or {}, body = fixture.reader(response.body or "")})
		end}
	end,
	run = function(c)
		local OBJECTS = "https://api.hubapi.com/crm/objects/2026-09/"
		local function last() return requests[#requests] end
		local names = {}
		for name in c do table.insert(names, name) end
		table.sort(names)
		assert(table.concat(names, ",") == "batchReadAssociations,batchReadObjects,getObject,getOwner,getPipeline,getProperty,listAssociationLabels,"
			.. "listAssociations,listObjects,listOwners,listPipelines,listProperties,searchObjects", "read-only got " .. table.concat(names, ","))

		responses = {{body = '{"id":"9876","properties":{"dealname":"Renewal","dealstage":"contractsent"}}'}, {body = '{"total":0,"results":[]}'}}
		assert(c.getObject({objectType = "deals", objectId = "9876", properties = {"dealname", "dealstage"}}).properties.dealstage == "contractsent")
		assert(last().method == "GET" and last().url == OBJECTS .. "deals/9876?properties=dealname,dealstage" and last().body == nil, last().url)
		local search = {filterGroups = {{filters = {{propertyName = "hs_task_status", operator = "NEQ", value = "COMPLETED"}}}}, limit = 50}
		local found = c.searchObjects({objectType = "tasks", filterGroups = search.filterGroups, limit = search.limit})
		assert(found.total == 0 and json.encode(found.results) == "[]")
		assert(last().method == "POST" and last().url == OBJECTS .. "tasks/search" and last().headers["Content-Type"][1] == "application/json", last().url)
		assert(json.encode(json.decode(last().body)) == json.encode(search), last().body)
		assert(#requests == 2 and #responses == 0)
	end,
}
