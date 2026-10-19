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
		assert(#names == 83, "wrong read-only surface: " .. #names)
		for _, name in {"addCompanyToList", "addContactToList", "addLpToFundraising", "addLpToInvestors", "addThemeItem", "createCompany",
			"createContact", "createDeal", "createFee", "createFundraising", "createIcMeeting", "createIcRequest", "createInvestor", "createNote",
			"createTask", "createTheme", "deleteCompany", "deleteContact", "deleteDeal", "deleteFee", "deleteFundraising", "deleteIcMeeting",
			"deleteIcRequest", "deleteInvestor", "deleteNote", "deleteTask", "linkCalendarEventNote", "linkCompanyNote", "linkContactNote", "linkDealNote",
			"linkFundraisingNote", "linkInvestorNote", "removeCompanyFromList", "removeContactFromList", "removeThemeItem", "updateCompany",
			"updateContact", "updateDeal", "updateFee", "updateFundraising", "updateIcMeeting", "updateIcRequest", "updateInvestor", "updateNote",
			"updateTask"} do
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
		crm.aggregateFees({group_by = {"amount"}, filters = {{field_id = "date", operator = "between", value = {"2026-01-01", "2026-06-30"}}}})
		assert(last().method == "POST" and last().url == API .. "/v1/fees/aggregate" and json.decode(last().body).filters[1].value[2] == "2026-06-30")
		crm.aggregateInvestors({group_by = {"type"}})
		assert(last().url == API .. "/v1/investors/aggregate")
		crm.aggregateFundraisings({group_by = {"stage"}})
		assert(last().url == API .. "/v1/fundraisings/aggregate")
		crm.getLpCatalogFacets()
		assert(last().method == "GET" and last().url == API .. "/v1/lp-discovery/facets")
		crm.listFeesByContact({contactId = "cc-10442"})
		assert(last().url == API .. "/v1/fees/by-contact/cc-10442")
		crm.getReportData({id = ID, entityType = "deal", offset = 100})
		assert(last().url == API .. "/v1/reports/" .. ID .. "/data?entityType=deal&offset=100", last().url)
		crm.listClosingProspectStatuses({fundCartaId = "1017", prospectPublicIds = "a1,b2"})
		assert(last().url == API .. "/v1/funds/1017/closing-prospect-statuses?prospectPublicIds=a1%2Cb2", last().url)
		crm.getFundClosingsStatus({fundCartaIds = "1017,1018"})
		assert(last().url == API .. "/v1/funds/closings-status?fundCartaIds=1017%2C1018", last().url)
		crm.getFundClosingsStatus({fundCartaIds = {1017, 1018}})
		assert(last().url == API .. "/v1/funds/closings-status?fundCartaIds=1017,1018", "string-typed lists join an array with commas")
		crm.listClosingProspectStatuses({fundCartaId = 42})
		assert(last().url == API .. "/v1/funds/42/closing-prospect-statuses", "Carta fund IDs are integers")
		crm.listTasks({done = false})
		assert(last().url == API .. "/v1/tasks?done=false")
		payload = ""
		local ok, err = pcall(function() crm.getDeal({id = ID}) end)
		assert(not ok and string.find(tostring(err), "invalid JSON object", 1, true), "an empty GET response is not a record")

		rejected(function() crm.getDeal() end, "id must be a Carta CRM ID or domain")
		rejected(function() crm.getDeal({id = "../me"}) end, "Carta CRM ID or domain")
		rejected(function() crm.getDeal({id = "a/b1"}) end, "Carta CRM ID or domain")
		rejected(function() crm.getDeal({id = ".hidden"}) end, "Carta CRM ID or domain")
		rejected(function() crm.getDeal({id = -7}) end, "Carta CRM ID or domain")
		rejected(function() crm.getDeal({id = 1.5}) end, "Carta CRM ID or domain")
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
		assert(#requests == 17)
	end,
}
