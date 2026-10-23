return {
	scenario = {publisher = {}, config = {access = "read-write", own_app = true, client_id = "fixture-client", client_secret = "fixture-secret"},
		auth_method = "playground", auth_config = {}},
	configure = function()
		requests = {}
		http = {request = function(req)
			table.insert(requests, req)
			return fixture.operation({statusCode = 200, headers = {}, body = fixture.reader('{"managementFee":{"id":"MF1"},"portfolios":[]}')})
		end}
	end,
	run = function(carta)
		local API = "https://api.playground.carta.team/v1alpha1"
		local empty = carta.listPortfolios()
		assert(requests[1].method == "GET" and requests[1].url == API .. "/portfolios" and json.encode(empty.portfolios) == "[]")
		carta.getManagementFee({firmId = "FIRM1", fundId = "FUND1", managementFeeId = "MF1"})
		assert(requests[2].url == API .. "/investors/firms/FIRM1/funds/FUND1/managementFees/MF1")
		carta.getStockSplitChanges({issuerId = "7", securities = json.decode("[]"), since = {value = "2026-01-01T00:00:00Z"}})
		carta.createDraftIssuer({draftIssuer = {legalName = "Playco"}})
		assert(requests[4].method == "POST" and requests[4].url == API .. "/draftIssuers")
		assert(#requests == 4)
	end,
}
