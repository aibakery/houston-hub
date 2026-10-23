return {
	scenario = {publisher = {client_id = "fixture-client", client_secret = "fixture-secret"}, config = {}, auth_method = "carta", auth_config = {}},
	configure = function()
		requests = {}
		payload = "{}"
		http = {request = function(req)
			table.insert(requests, req)
			return fixture.operation({statusCode = 200, headers = {}, body = fixture.reader(payload)})
		end}
	end,
	run = function(carta)
		local API = "https://api.carta.com/v1alpha1"
		local function last() return requests[#requests] end
		local function rejected(fn, expected)
			local before = #requests
			local ok, err = pcall(fn)
			assert(not ok and string.find(tostring(err), expected, 1, true), "wrong validation error: " .. tostring(err))
			assert(#requests == before, "invalid input reached Carta")
		end

		local names = {}
		for name in carta do if name ~= "help" then table.insert(names, name) end end
		assert(#names == 63, "wrong read-only surface: " .. #names)
		for _, name in {"createCapitalCall", "adjustCapitalCall", "getCapitalCall", "createManagementFee", "getManagementFee", "createCarriedInterestAllocation",
			"createDraftOptionGrant", "updateExerciseMoneyMovement", "updateExerciseTaxWithholding", "initiateSecondarySettlement", "getSecondaryTransaction",
			"finalizeSecondarySettlement", "createDraftIssuer", "getDraftIssuer", "uploadOpenCapTable", "uploadFile"} do
			assert(carta[name] == nil, "read-only leaked " .. name)
		end
		assert(carta.getStockSplitChanges and carta.getOpenCapTable, "reads are missing")
		assert(#requests == 0, "initialization reached Carta")

		payload = '{"user":{"id":"2184ae6f-9415-465a-9f5f-80efbc81b266","email":"tagg@example.com"}}'
		assert(carta.getCurrentUser().user.email == "tagg@example.com")
		assert(last().method == "GET" and last().url == API .. "/user" and last().body == nil)
		assert(last().headers.Accept[1] == "application/json" and last().headers.Authorization == nil)

		payload = '{"issuers":[{"id":"7","legalName":"Acme","doingBusinessAsName":null}],"nextPageToken":"ODMxMw=="}'
		local opts = {pageSize = 50, pageToken = "abc=="}
		local page = carta.listIssuers(opts)
		assert(last().url == API .. "/issuers?pageSize=50&pageToken=abc%3D%3D", last().url)
		assert(opts.pageSize == 50 and opts.pageToken == "abc==", "caller options were modified")
		assert(page.issuers[1].id == "7" and page.issuers[1].doingBusinessAsName == json.decode("null") and page.nextPageToken == "ODMxMw==")

		payload = '{"stakeholders":[]}'
		local empty = carta.listStakeholders({issuerId = "7"})
		assert(last().url == API .. "/issuers/7/stakeholders" and json.encode(empty.stakeholders) == "[]")
		carta.getStakeholder({issuerId = 7, id = "611"})
		assert(last().url == API .. "/issuers/7/stakeholders/611")
		carta.getIssuerCapitalizationTable({issuerId = "7", asOfDate = "2026-10-19"})
		assert(last().url == API .. "/issuers/7/capitalizationTable?asOfDate=2026-10-19")
		carta.listTransactions({issuerId = "7", type = "option", pageSize = 1000})
		assert(last().url == API .. "/issuers/7/transactions?type=option&pageSize=1000")
		carta.getStakeholderEquitySummary({issuerId = "7", stakeholderId = "611", includeCanceled = true})
		assert(last().url == API .. "/issuers/7/stakeholders/611/equitySummary?includeCanceled=true")

		local firm = "6f1c8a2e-0b9d-4c55-9a1e-3d2f7b8c9e10"
		carta.listPartnerContacts({firmId = firm, fundIds = {"f1", "f2"}, partnerIds = "p1"})
		assert(last().url == API .. "/investors/firms/" .. firm .. "/partnerContacts?fundIds=f1,f2&partnerIds=p1", last().url)
		carta.listFundPerformanceMetrics({firmId = firm, fundId = "-", reportType = "BY_FUND", asOfDateTime = "2026-09-30T00:00:00Z"})
		assert(last().url == API .. "/investors/firms/" .. firm .. "/funds/-/metrics?asOfDateTime=2026-09-30T00%3A00%3A00Z&reportType=BY_FUND", last().url)
		carta.getInvestmentCapitalizationTable({firmId = firm, fundId = "F1", companyId = "C1", capitalizationTableId = "C1"})
		assert(last().url == API .. "/investors/firms/" .. firm .. "/funds/F1/investments/C1/capitalizationTables/C1")

		payload = '{"downloadUrl":"https://s3.amazonaws.com/carta.public/doc.pdf?X-Amz-Signature=x","downloadUrlExpirationTime":"2026-10-19T12:00:00Z"}'
		local doc = carta.getFundInvestmentDocumentUrl({portfolioId = "P1", documentId = "J8X32hD6yttzNJULdzeugV"})
		assert(last().url == API .. "/portfolios/P1/fundInvestmentDocuments/J8X32hD6yttzNJULdzeugV:download")
		assert(string.find(doc.downloadUrl, "X-Amz-Signature", 1, true))
		carta.listPortfolioRestrictedStockUnits({portfolioId = "P1", issuerId = "7", lastModifiedDatetimeAfter = "2026-01-01T00:00:00Z"})
		assert(last().url == API .. "/portfolios/P1/issuers/7/restrictedStockUnits?lastModifiedDatetimeAfter=2026-01-01T00%3A00%3A00Z")

		payload = '{"affectedAssets":[],"asOf":{"value":"2026-10-19T00:00:00Z"},"splitOccurredSince":false}'
		local split = carta.getStockSplitChanges({issuerId = "7", securities = {{securityType = "certificate", securityId = "S1"}}, since = {value = "2026-01-01T00:00:00Z"}})
		assert(last().method == "POST" and last().url == API .. "/issuers/7/securities:stockSplitChanges")
		assert(last().headers["Content-Type"][1] == "application/json")
		local body = json.decode(last().body)
		assert(body.since.value == "2026-01-01T00:00:00Z" and body.securities[1].securityId == "S1" and body.issuerId == nil, "path field leaked into the body")
		assert(split.splitOccurredSince == false and json.encode(split.affectedAssets) == "[]")
		payload = ""
		local empty, emptyErr = pcall(function() carta.getStockSplitChanges({issuerId = "7", securities = json.decode("[]"), since = {value = "2026-01-01T00:00:00Z"}}) end)
		assert(not empty and string.find(tostring(emptyErr), "invalid JSON object", 1, true), "an empty read is not a success")
		local count = #requests

		rejected(function() carta.getIssuer() end, "id must be a Carta ID")
		rejected(function() carta.getIssuer({id = "../user"}) end, "id must be a Carta ID")
		rejected(function() carta.getIssuer({id = "7/stakeholders"}) end, "id must be a Carta ID")
		rejected(function() carta.getIssuer({id = "7?x=1"}) end, "id must be a Carta ID")
		rejected(function() carta.getIssuer({id = ""}) end, "id must be a Carta ID")
		rejected(function() carta.getIssuer({id = -1}) end, "id must be a Carta ID")
		rejected(function() carta.getIssuer({id = 1.5}) end, "id must be a Carta ID")
		rejected(function() carta.getIssuer({id = string.rep("a", 65)}) end, "id must be a Carta ID")
		rejected(function() carta.listTransactions({issuerId = "7"}) end, "type is required")
		rejected(function() carta.getStockSplitChanges({issuerId = "7", since = {value = "2026-01-01T00:00:00Z"}}) end, "securities is required")
		rejected(function() carta.getCompensationBenchmarks({corporationId = "1", jobArea = "ENGINEERING", geoAdjustmentLocation = "US"}) end, "postMoneyValuationBucket is required")
		rejected(function() carta.listIssuers({page_size = 10}) end, "listIssuers has no option page_size")
		rejected(function() carta.listPartners({firmId = firm, fundIds = json.decode("[]")}) end, "fundIds must not be an empty array")
		rejected(function() carta.listPartners({firmId = firm, fundIds = {a = "f1"}}) end, "array, not an object")
		rejected(function() carta.listIssuers("all") end, "opts must be an object")
		assert(#requests == count)
	end,
}
