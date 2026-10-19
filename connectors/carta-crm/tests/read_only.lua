return {
	scenario = {publisher = {}, config = {}, auth_method = "token", auth_config = {token = "fixture-key"}},
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
		local function last() return requests[#requests] end
		local function rejected(fn, expected)
			local before = #requests
			local ok, err = pcall(fn)
			assert(not ok and string.find(tostring(err), expected, 1, true), "wrong validation error: " .. tostring(err))
			assert(#requests == before, "invalid input reached Carta CRM")
		end

		local names = {}
		for name in crm do if name ~= "help" then table.insert(names, name) end end
		assert(#names == 78, "wrong read-only surface: " .. #names)
		for _, name in {"createCompany", "updateDeal", "deleteContact", "createTask", "linkDealNote", "addLpToInvestors",
			"addThemeItem", "removeContactFromList", "deleteIcMeeting", "createFee"} do
			assert(crm[name] == nil, "read-only leaked " .. name)
		end
		for _, name in {"searchCompanies", "aggregateDeals", "aggregateDealStageHistory", "searchFees"} do
			assert(crm[name] ~= nil, "read-only lost " .. name)
		end
		assert(#requests == 0, "initialization reached Carta CRM")

		payload = '{"name":"Ana","email":"ana@example.com","organization":"Fund I","realOrganization":null}'
		local me = crm.getMe()
		assert(last().method == "GET" and last().url == API .. "/v1/me" and last().body == nil)
		assert(last().headers.Accept[1] == "application/json" and last().headers.Authorization == nil)
		assert(me.email == "ana@example.com" and me.realOrganization == NULL)

		payload = '{"deals":[{"id":"' .. ID .. '","tags":[]}],"total":1}'
		local opts = {pipelines = {"p1", "p2"}, stages = {"s 1"}, search = "acme & co", limit = 25, offset = 50}
		local page = crm.listDeals(opts)
		assert(last().url == API .. "/v1/deals?pipelines=p1&pipelines=p2&stages=s%201&search=acme%20%26%20co&limit=25&offset=50", last().url)
		assert(opts.limit == 25 and #opts.pipelines == 2, "caller options were modified")
		assert(page.deals[1].id == ID and json.encode(page.deals[1].tags) == "[]")

		payload = '{"notes":[]}'
		local empty = crm.listCompanyNotes({id = "acme.com"})
		assert(last().url == API .. "/v1/companies/acme.com/notes")
		assert(json.encode(empty.notes) == "[]")

		payload = '{"companies":[]}'
		crm.searchCompanies({filters = {{field_id = "lists", operator = "in", value = {"L1"}}}, limit = 10})
		assert(last().method == "POST" and last().url == API .. "/v1/companies/search")
		assert(last().headers["Content-Type"][1] == "application/json")
		local body = json.decode(last().body)
		assert(body.limit == 10 and body.filters[1].value[1] == "L1")

		payload = '{"groups":[]}'
		crm.aggregateDeals({group_by = {"stage"}})
		assert(last().url == API .. "/v1/deals/aggregate" and json.decode(last().body).group_by[1] == "stage")
		crm.getReportData({id = ID, entityType = "deal", offset = 100})
		assert(last().url == API .. "/v1/reports/" .. ID .. "/data?entityType=deal&offset=100", last().url)
		crm.listClosingProspectStatuses({fundCartaId = "0b6f6c1e-3d1a-4f7e-9a51-2a5d0c7e9b10", prospectPublicIds = {"a1", "b2"}})
		assert(last().url == API .. "/v1/funds/0b6f6c1e-3d1a-4f7e-9a51-2a5d0c7e9b10/closing-prospect-statuses?prospectPublicIds=a1&prospectPublicIds=b2", last().url)
		crm.listTasks({done = false})
		assert(last().url == API .. "/v1/tasks?done=false")
		payload = ""
		local ok, err = pcall(function() crm.getDeal({id = ID}) end)
		assert(not ok and string.find(tostring(err), "invalid JSON object", 1, true), "an empty GET response is not a record")

		rejected(function() crm.getDeal() end, "id must be a Carta CRM ID or domain")
		rejected(function() crm.getDeal({id = "../me"}) end, "Carta CRM ID or domain")
		rejected(function() crm.getDeal({id = "a/b1"}) end, "Carta CRM ID or domain")
		rejected(function() crm.getDeal({id = "batch"}) end, "Carta CRM ID or domain")
		rejected(function() crm.getDeal({id = 7}) end, "Carta CRM ID or domain")
		rejected(function() crm.getDeal({id = string.rep("a1", 101)}) end, "Carta CRM ID or domain")
		rejected(function() crm.getCompanyAngles() end, "domain is required")
		rejected(function() crm.listReports({entityType = NULL}) end, "entityType is required")
		rejected(function() crm.aggregateDeals({}) end, "group_by is required")
		rejected(function() crm.listDeals({pipeline = "p1"}) end, "listDeals has no option pipeline")
		rejected(function() crm.listDeals({stages = json.decode("[]")}) end, "stages must not be an empty array")
		rejected(function() crm.listDeals({stages = {first = "s1"}}) end, "array, not an object")
		rejected(function() crm.listDeals({stages = {{"s1"}}}) end, "must be a string, boolean, number")
		rejected(function() crm.listDeals("acme") end, "opts must be an object")
		rejected(function() crm.listDeals({"acme"}) end, "named fields")
		assert(#requests == 9)
	end,
}
