return {
	scenario = {publisher = {}, config = {access = "read-write"}, auth_method = "token", auth_config = {token = "fixture-token"}},
	configure = function()
		calls = 0
		status = 200
		payload = "{}"
		responseHeaders = {}
		http = {request = function(req)
			calls += 1
			return fixture.operation({statusCode = status, headers = responseHeaders, body = fixture.reader(payload)})
		end}
	end,
	run = function(c)
		local names = {}
		for name in c do table.insert(names, name) end
		table.sort(names)
		assert(table.concat(names, ",") == "batchReadAssociations,batchReadObjects,createAssociation,createDefaultAssociation,createObject,deleteAssociation,"
			.. "getObject,getOwner,getPipeline,getProperty,listAssociationLabels,listAssociations,listObjects,listOwners,listPipelines,listProperties,"
			.. "searchObjects,updateObject", "token read-write got " .. table.concat(names, ","))

		local CONTACT = {objectType = "contacts", objectId = "101"}
		local CREATE = {objectType = "contacts", properties = {email = "ana@example.com"}}
		local UPDATE = {objectType = "deals", objectId = "9876", properties = {amount = "abc"}}
		local LINK = {objectType = "contacts", objectId = "101", toObjectType = "companies", toObjectId = "512", types = {{associationCategory = "HUBSPOT_DEFINED", associationTypeId = 1}}}
		local function upstream(code: number, body: string, headers: {[string]: {string}}, fn: (any) -> any, input: any, expected: {string}, absent: {string}?): string
			status, payload, responseHeaders = code, body, headers
			local before = calls
			local ok, err = pcall(fn, input)
			local message = tostring(err)
			assert(not ok, "call succeeded")
			for _, text in expected do assert(string.find(message, text, 1, true), "missing " .. text .. " in " .. message) end
			for _, text in absent or {} do assert(not string.find(message, text, 1, true), "unexpected " .. text .. " in " .. message) end
			assert(calls == before + 1, "a failed call was repeated")
			return message
		end

		upstream(401, '{"status":"error","message":"Authentication credentials not found.","correlationId":"c-401","category":"INVALID_AUTHENTICATION"}', {},
			c.listOwners, nil, {"HubSpot HTTP 401 (INVALID_AUTHENTICATION): Authentication credentials not found.", "correlationId c-401",
				"check the connection's access token, or reconnect", '"retryable":false'})
		upstream(403, json.encode({status = "error", message = "This app hasn't been granted all required scopes to make this call.", correlationId = "c-403",
			category = "MISSING_SCOPES", errors = {{message = "One or more of the following scopes are required.",
				context = {requiredGranularScopes = {"crm.objects.contacts.read", "crm.objects.contacts.sensitive.read"}}}}}), {},
			c.getObject, CONTACT, {"HTTP 403 (MISSING_SCOPES)", "One or more of the following scopes are required.",
				"needs one of: crm.objects.contacts.read, crm.objects.contacts.sensitive.read", '"retryable":false'})
		upstream(400, json.encode({status = "error", message = "Property values were not valid", correlationId = "c-400", category = "VALIDATION_ERROR",
			errors = {{message = "Property amount must be a number", code = "INVALID_DECIMAL", context = {propertyName = {"amount"}}}}}), {},
			c.updateObject, UPDATE, {"HTTP 400 (VALIDATION_ERROR): Property values were not valid; Property amount must be a number", "correlationId c-400", '"retryable":false'})
		-- Long bodies keep their category and cut messages; a body beyond the 16 KiB read for errors
		-- gives the status line alone.
		local long = upstream(400, json.encode({status = "error", category = "VALIDATION_ERROR", message = string.rep("x", 5000),
			errors = {{message = string.rep("y", 5000)}, {message = "second"}, {message = "third"}, {message = "fourth"}}}), {},
			c.searchObjects, {objectType = "contacts"}, {"HTTP 400 (VALIDATION_ERROR): " .. string.rep("x", 600), string.rep("y", 200), "; second; third"},
			{string.rep("x", 601), string.rep("y", 201), "fourth"})
		assert(#long < 2000, "error message is not bounded: " .. #long)
		upstream(400, json.encode({status = "error", category = "VALIDATION_ERROR", message = string.rep("x", 20000)}), {},
			c.searchObjects, {objectType = "contacts"}, {"HubSpot HTTP 400", '"retryable":false'}, {"VALIDATION_ERROR", "xxx"})
		upstream(409, '{"status":"error","message":"Contact already exists. Existing ID: 101","category":"CONFLICT"}', {},
			c.createObject, CREATE, {"HTTP 409 (CONFLICT): Contact already exists", '"retryable":false'})

		-- Throttling: the rolling and per-second search limits pass; the daily limit lasts until midnight.
		upstream(429, '{"status":"error","message":"You have reached your ten_secondly_rolling limit.","errorType":"RATE_LIMIT","correlationId":"c-429","policyName":"TEN_SECONDLY_ROLLING"}', {},
			c.listObjects, {objectType = "contacts"}, {"HTTP 429 (RATE_LIMIT)", "policy TEN_SECONDLY_ROLLING", '"retryable":true'})
		upstream(429, '{"status":"error","message":"You have reached your daily limit.","errorType":"RATE_LIMIT","policyName":"DAILY"}', {},
			c.createObject, CREATE, {"HTTP 429 (RATE_LIMIT): You have reached your daily limit.", "policy DAILY", '"retryable":false'})
		upstream(429, '{"status":"error","message":"You have reached your secondly limit.","errorType":"RATE_LIMIT"}', {},
			c.searchObjects, {objectType = "deals"}, {"HTTP 429", "secondly limit", '"retryable":true'})
		-- Access tokens also report the daily quota in a header, which decides even when the body is unreadable.
		local SPENT = {["x-hubspot-ratelimit-daily-remaining"] = {"0"}}
		upstream(429, "<html>Too many requests</html>", SPENT, c.listObjects, {objectType = "deals"}, {"HubSpot HTTP 429", "daily limit reached", '"retryable":false'})
		upstream(429, json.encode({status = "error", errorType = "RATE_LIMIT", policyName = "DAILY", message = string.rep("x", 20000)}), SPENT,
			c.getObject, CONTACT, {"HubSpot HTTP 429", "daily limit reached", '"retryable":false'})
		upstream(429, '{"status":"error","errorType":"RATE_LIMIT","policyName":"TEN_SECONDLY_ROLLING"}', SPENT,
			c.listOwners, nil, {"policy TEN_SECONDLY_ROLLING", "daily limit reached", '"retryable":false'})
		upstream(429, "<html>Too many requests</html>", {["x-hubspot-ratelimit-daily-remaining"] = {"5000"}}, c.listObjects, {objectType = "deals"},
			{"HubSpot HTTP 429", '"retryable":true'}, {"daily limit"})
		upstream(423, '{"status":"error","message":"Locked"}', {}, c.createAssociation, LINK, {"HubSpot HTTP 423: Locked", '"retryable":true'})
		upstream(477, '{"status":"error","message":"Migration in progress"}', {["retry-after"] = {"3600"}},
			c.getObject, CONTACT, {"HTTP 477", "Retry-After: 3600", '"retryable":true'})

		-- Server errors: reads, updates and association changes are safe to repeat; a create may have been applied.
		upstream(502, "<html><body>Bad gateway</body></html>", {}, c.listObjects, {objectType = "deals"}, {"HubSpot HTTP 502", '"retryable":true'}, {"html"})
		upstream(502, "", {}, c.updateObject, UPDATE, {"HubSpot HTTP 502", '"retryable":true'})
		upstream(500, '{"status":"error","message":"internal error"}', {}, c.createObject, CREATE, {"HTTP 500: internal error", '"retryable":false'})
		upstream(500, '{"status":"error","message":"internal error"}', {}, c.createAssociation, LINK, {"HTTP 500: internal error", '"retryable":true'})
		upstream(503, "", {}, c.createDefaultAssociation, {fromObjectType = "contacts", fromObjectId = "101", toObjectType = "companies", toObjectId = "512"}, {"HubSpot HTTP 503", '"retryable":true'})
		upstream(504, "", {}, c.deleteAssociation, {objectType = "contacts", objectId = "101", toObjectType = "companies", toObjectId = "512"}, {"HubSpot HTTP 504", '"retryable":true'})
		upstream(404, "<!DOCTYPE html><html><head><title>Not found</title></head></html>", {}, c.getProperty,
			{objectType = "contacts", propertyName = "missing"}, {"HubSpot HTTP 404", '"retryable":false'}, {"html", "Not found"})

		-- A success must carry a JSON object.
		upstream(200, "<html>Maintenance</html>", {}, c.getObject, CONTACT, {"HubSpot returned an invalid JSON object", '"retryable":false'})
		upstream(200, "[]", {}, c.listObjects, {objectType = "contacts"}, {"invalid JSON object"})
		-- Only deleteAssociation answers with an empty body (204); any other empty success is malformed.
		upstream(200, "", {}, c.getObject, CONTACT, {"invalid JSON object"})
		upstream(201, "", {}, c.createObject, CREATE, {"invalid JSON object", '"retryable":false'})
		upstream(204, "", {}, c.createAssociation, LINK, {"invalid JSON object"})
	end,
}
