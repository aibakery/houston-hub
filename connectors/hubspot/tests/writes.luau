return {
	scenario = {publisher = {client_id = "fixture-client", client_secret = "fixture-private-secret"}, config = {}, auth_method = "oauth", auth_config = {}},
	config = {access = "read-write"},
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
		local function same(a: any, b: any): boolean
			if type(a) ~= "table" or type(b) ~= "table" then return a == b end
			for key, value in a do if not same(value, b[key]) then return false end end
			for key in b do if a[key] == nil then return false end end
			return true
		end
		local function sent(method: string, href: string, expected: any)
			assert(last().method == method and last().url == href, last().method .. " " .. last().url)
			assert(last().headers["Content-Type"][1] == "application/json", "JSON body without Content-Type")
			assert(same(json.decode(last().body), expected), "unexpected body " .. last().body)
		end
		local function fails(expected: {string}, fn: (...any) -> any, ...: any)
			local ok, err = pcall(fn, ...)
			assert(not ok, "call succeeded")
			for _, text in expected do assert(string.find(tostring(err), text, 1, true), "missing " .. text .. " in " .. tostring(err)) end
		end
		local names = {}
		for name in c do table.insert(names, name) end
		table.sort(names)
		assert(table.concat(names, ",") == "batchReadAssociations,batchReadObjects,createAssociation,createDefaultAssociation,createObject,deleteAssociation,"
			.. "getObject,getOwner,getPipeline,getProperty,listAssociationLabels,listAssociations,listObjects,listOwners,listPipelines,listProperties,"
			.. "searchObjects,updateObject", "read-write got " .. table.concat(names, ","))

		-- Creates send {properties, associations?}; values keep their JSON types.
		responses = {
			{status = 201, body = '{"id":"101","properties":{"email":"ana@example.com"},"archived":false}'},
			{status = 201, body = '{"id":"301","properties":{"hs_note_body":"Called about renewal."}}'},
			{status = 201, body = '{"id":"401"}'},
		}
		local contact = {email = "ana@example.com", firstname = "Ana", hs_count = 3, opted_in = false}
		assert(c.createObject({objectType = "contacts", properties = contact}).id == "101")
		sent("POST", OBJECTS .. "contacts", {properties = contact})
		local note = {hs_timestamp = "2026-11-13T10:00:00Z", hs_note_body = "Called about renewal."}
		local links = {{to = {id = "101"}, types = {{associationCategory = "HUBSPOT_DEFINED", associationTypeId = 202}}},
			{to = {id = "512"}, types = {{associationCategory = "HUBSPOT_DEFINED", associationTypeId = 190}}}}
		c.createObject({objectType = "notes", properties = note, associations = links})
		sent("POST", OBJECTS .. "notes", {properties = note, associations = links})
		assert(string.find(last().body, '"types":[{', 1, true) ~= nil, last().body)
		local task = {hs_timestamp = "2026-11-20T09:00:00Z", hs_task_subject = "Send contract", hs_task_status = "NOT_STARTED"}
		local onDeal = {{to = {id = "9876"}, types = {{associationCategory = "HUBSPOT_DEFINED", associationTypeId = 216}}}}
		c.createObject({objectType = "tasks", properties = task, associations = onDeal})
		sent("POST", OBJECTS .. "tasks", {properties = task, associations = onDeal})

		-- Updates PATCH only the named properties, by record ID or by a unique property.
		responses = {{body = '{"id":"9876","properties":{"dealstage":"closedwon"}}'}, {body = '{"id":"101"}'}, {body = '{"id":"7"}'}}
		assert(c.updateObject({objectType = "deals", objectId = "9876", properties = {dealstage = "closedwon", amount = ""}}).properties.dealstage == "closedwon")
		sent("PATCH", OBJECTS .. "deals/9876", {properties = {dealstage = "closedwon", amount = ""}})
		c.updateObject({objectType = "contacts", objectId = "ana@example.com", idProperty = "email", properties = {jobtitle = "CTO"}})
		sent("PATCH", OBJECTS .. "contacts/ana%40example.com?idProperty=email", {properties = {jobtitle = "CTO"}})
		c.updateObject({objectType = "contacts", objectId = "sku:123", idProperty = "sku", properties = {jobtitle = "CTO"}})
		sent("PATCH", OBJECTS .. "contacts/sku%3A123?idProperty=sku", {properties = {jobtitle = "CTO"}})

		-- Associations: a default link has an empty body, a labelled one a JSON array, and a delete none.
		responses = {
			{body = '{"status":"COMPLETE","results":[{"from":{"id":"101"},"to":{"id":"512"},"associationSpec":{"associationCategory":"HUBSPOT_DEFINED","associationTypeId":279}}]}'},
			{status = 201, body = '{"fromObjectTypeId":"0-1","fromObjectId":101,"toObjectTypeId":"0-2","toObjectId":512,"labels":["Primary"]}'},
			{status = 204},
		}
		assert(c.createDefaultAssociation({fromObjectType = "contacts", fromObjectId = "101", toObjectType = "companies", toObjectId = "512"}).results[1].to.id == "512")
		assert(last().method == "PUT" and last().url == OBJECTS .. "contacts/101/associations/default/companies/512", last().url)
		assert(last().body == "" and (last().headers == nil or last().headers["Content-Type"] == nil), "a default association sends an empty body")
		local types = {{associationCategory = "HUBSPOT_DEFINED", associationTypeId = 1}, {associationCategory = "USER_DEFINED", associationTypeId = 36}}
		local labels = c.createAssociation({objectType = "contacts", objectId = "101", toObjectType = "companies", toObjectId = "512", types = types})
		assert(labels.labels[1] == "Primary" and labels.toObjectId == 512)
		sent("PUT", OBJECTS .. "contacts/101/associations/companies/512", types)
		assert(string.sub(last().body, 1, 1) == "[", last().body)
		local removed = c.deleteAssociation({objectType = "contacts", objectId = "101", toObjectType = "companies", toObjectId = "512"})
		assert(removed.success == true and last().method == "DELETE" and last().url == OBJECTS .. "contacts/101/associations/companies/512" and last().body == nil, last().url)

		-- Invalid writes never reach the network.
		local before = #requests
		local LINK = {{associationCategory = "HUBSPOT_DEFINED", associationTypeId = 1}}
		fails({"properties must be a nonempty object"}, c.createObject, {objectType = "contacts", properties = {}})
		fails({"properties must be a nonempty object"}, c.createObject, {objectType = "contacts"})
		fails({"properties.address must be a string, number or boolean"}, c.createObject, {objectType = "contacts", properties = {address = {street = "1 Main St"}}})
		fails({"properties must have property names as keys"}, c.updateObject, {objectType = "deals", objectId = "1", properties = {"closedwon"}})
		fails({"objectId must be a string of digits"}, c.updateObject, {objectType = "deals", properties = {dealstage = "closedwon"}})
		fails({"createObject received an unknown option idProperty"}, c.createObject, {objectType = "contacts", properties = {email = "a@example.com"}, idProperty = "email"})
		fails({"updateObject received an unknown option associations"}, c.updateObject, {objectType = "deals", objectId = "1", properties = {dealstage = "x"}, associations = {}})
		fails({"objectType must be one of"}, c.createObject, {objectType = "products", properties = {name = "Widget"}})
		fails({"types must be an array of 1 to 100 items"}, c.createAssociation, {objectType = "contacts", objectId = "1", toObjectType = "companies", toObjectId = "2", types = {}})
		fails({"types[1].associationCategory must be one of HUBSPOT_DEFINED, USER_DEFINED, INTEGRATOR_DEFINED"}, c.createAssociation,
			{objectType = "contacts", objectId = "1", toObjectType = "companies", toObjectId = "2", types = {{associationCategory = "PRIMARY", associationTypeId = 1}}})
		fails({"types[1].associationTypeId must be an integer"}, c.createAssociation,
			{objectType = "contacts", objectId = "1", toObjectType = "companies", toObjectId = "2", types = {{associationCategory = "HUBSPOT_DEFINED", associationTypeId = 1.5}}})
		fails({"types[1].associationTypeId must be an integer"}, c.createAssociation,
			{objectType = "contacts", objectId = "1", toObjectType = "companies", toObjectId = "2", types = {{associationCategory = "HUBSPOT_DEFINED", associationTypeId = "1"}}})
		fails({"types[1] received an unknown field label"}, c.createAssociation,
			{objectType = "contacts", objectId = "1", toObjectType = "companies", toObjectId = "2", types = {{associationCategory = "HUBSPOT_DEFINED", associationTypeId = 1, label = "Primary"}}})
		fails({"associations[1].to.id must be a string of digits"}, c.createObject, {objectType = "notes", properties = {hs_timestamp = "1"}, associations = {{to = {}, types = LINK}}})
		fails({"associations[1].to must be an object"}, c.createObject, {objectType = "notes", properties = {hs_timestamp = "1"}, associations = {{types = LINK}}})
		fails({"associations[1].types must be an array"}, c.createObject, {objectType = "notes", properties = {hs_timestamp = "1"}, associations = {{to = {id = "1"}}}})
		fails({"associations[1] received an unknown field toObjectType"}, c.createObject,
			{objectType = "notes", properties = {hs_timestamp = "1"}, associations = {{to = {id = "1"}, types = LINK, toObjectType = "contacts"}}})
		fails({"toObjectType must be one of"}, c.createDefaultAssociation, {fromObjectType = "contacts", fromObjectId = "1", toObjectType = "products", toObjectId = "2"})
		fails({"toObjectType must be one of"}, c.createDefaultAssociation, {fromObjectType = "contacts", fromObjectId = "101", toObjectType = "quotes", toObjectId = "7"})
		fails({"toObjectType must be one of"}, c.createAssociation, {objectType = "contacts", objectId = "101", toObjectType = "quotes", toObjectId = "7", types = LINK})
		fails({"toObjectType must be one of"}, c.deleteAssociation, {objectType = "contacts", objectId = "101", toObjectType = "quotes", toObjectId = "7"})
		fails({"toObjectId must be a string of digits"}, c.deleteAssociation, {objectType = "contacts", objectId = "1", toObjectType = "companies", toObjectId = "../2"})
		fails({"deleteAssociation received an unknown option types"}, c.deleteAssociation, {objectType = "contacts", objectId = "1", toObjectType = "companies", toObjectId = "2", types = LINK})
		assert(#requests == before, "invalid writes reached HubSpot")

		-- A failed write is reported once and never repeated.
		responses = {{status = 500, body = '{"status":"error","message":"internal error","category":"INTERNAL_ERROR"}'}}
		fails({"HubSpot HTTP 500 (INTERNAL_ERROR)", '"retryable":false'}, c.createObject, {objectType = "contacts", properties = {email = "ana@example.com"}})
		assert(#requests == before + 1 and #responses == 0)
	end,
}
