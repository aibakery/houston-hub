return {
	scenario = {publisher = {client_id = "fixture-client", client_secret = "fixture-private-secret"}, config = {access = "read-only"}, auth_method = "oauth", auth_config = {}},
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
		local found = c.searchObjects({objectType = "tasks", filterGroups = {{filters = {{propertyName = "hs_task_status", operator = "NEQ", value = "COMPLETED"}}}}, limit = 50})
		assert(found.total == 0 and json.encode(found.results) == "[]")
		local sent = json.decode(last().body)
		assert(last().method == "POST" and last().url == OBJECTS .. "tasks/search" and last().headers["Content-Type"][1] == "application/json", last().url)
		assert(sent.limit == 50 and sent.filterGroups[1].filters[1].value == "COMPLETED" and sent.objectType == nil, last().body)
		assert(#requests == 2 and #responses == 0)
	end,
}
