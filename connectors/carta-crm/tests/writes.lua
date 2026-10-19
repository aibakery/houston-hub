return {
	scenario = {publisher = {}, config = {access = "read-write"}, auth_method = "token", auth_config = {token = "fixture-key"}},
	configure = function()
		requests = {}
		payload = "{}"
		http = {request = function(req)
			table.insert(requests, req)
			return fixture.operation({statusCode = 200, headers = {}, body = fixture.reader(payload)})
		end}
	end,
	run = function(crm)
		local API = "https://crm-public-api.app.carta.com"
		local NULL = json.decode("null")
		local ID = "65a1b2c3d4e5f60718293a4b"
		local NOTE = "65a1b2c3d4e5f60718293a4c"
		local function last() return requests[#requests] end
		local function sent() return json.decode(last().body) end

		local count = 0
		for name in crm do if name ~= "help" then count += 1 end end
		assert(count == 122, "wrong read-write surface: " .. count)

		payload = '{"id":"' .. ID .. '","stageId":"s1"}'
		local deal = crm.createDeal({company = {name = "Acme", url = "https://acme.com"}, pipelineId = "p1", stageId = "s1", tags = json.decode("[]")})
		assert(last().method == "POST" and last().url == API .. "/v1/deals")
		assert(last().headers["Content-Type"][1] == "application/json" and last().headers.Authorization == nil)
		local body = sent()
		assert(body.company.name == "Acme" and body.pipelineId == "p1" and json.encode(body.tags) == "[]")
		assert(deal.id == ID)

		crm.updateContact({id = ID, title = "CFO", location = NULL})
		assert(last().method == "PATCH" and last().url == API .. "/v1/contacts/" .. ID)
		body = sent()
		assert(body.title == "CFO" and body.location == NULL and body.id == nil, "path field leaked into the body")
		crm.updateDeal({id = ID})
		assert(last().body == "{}", "an empty body must still be a JSON object")

		crm.createTask({entityId = ID, entityType = "DEAL", title = "Send memo", dueDate = "2026-11-01"})
		assert(last().url == API .. "/v1/tasks" and sent().entityType == "DEAL")
		crm.addThemeItem({id = ID, entityId = NOTE, entityType = "NOTE"})
		assert(last().url == API .. "/v1/themes/" .. ID .. "/theme-items" and sent().entityId == NOTE)

		payload = '{"success":true}'
		local linked = crm.linkDealNote({id = ID, noteId = NOTE})
		assert(last().method == "POST" and last().url == API .. "/v1/deals/" .. ID .. "/notes/" .. NOTE)
		assert(last().body == nil and last().headers["Content-Type"] == nil and linked.success == true)
		crm.linkCompanyNote({id = "acme.com", noteId = NOTE})
		assert(last().url == API .. "/v1/companies/acme.com/notes/" .. NOTE, "company note routes take a domain")
		crm.addCompanyToList({id = ID, listId = "L1"})
		assert(last().url == API .. "/v1/companies/" .. ID .. "/lists/L1" and last().body == nil)

		payload = ""
		local deleted = crm.deleteNote({id = NOTE})
		assert(last().method == "DELETE" and last().url == API .. "/v1/notes/" .. NOTE and last().body == nil)
		assert(deleted.success == true)
		crm.deleteIcMeeting({id = ID, agenda = "unschedule"})
		assert(last().url == API .. "/v1/ic-meetings/" .. ID .. "?agenda=unschedule")

		local ok, err = pcall(function() crm.createTask({entityId = ID, entityType = "DEAL", title = "Memo"}) end)
		assert(not ok and string.find(tostring(err), "dueDate is required", 1, true))
		ok, err = pcall(function() crm.updateDeal({id = "batch", deals = {}}) end)
		assert(not ok and string.find(tostring(err), "Carta CRM ID or domain", 1, true), "an ID must not name a sibling route")
		assert(#requests == 10)
	end,
}
