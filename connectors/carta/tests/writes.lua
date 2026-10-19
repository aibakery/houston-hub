return {
	scenario = {publisher = {}, config = {access = "read-write", own_app = true, client_id = "fixture-client", client_secret = "fixture-secret"},
		auth_method = "own_app", auth_config = {}},
	configure = function()
		requests = {}
		status = 200
		payload = "{}"
		http = {request = function(req)
			table.insert(requests, req)
			return fixture.operation({statusCode = status, headers = {}, body = fixture.reader(payload)})
		end}
	end,
	run = function(carta)
		local API = "https://api.carta.com/v1alpha1"
		local FUND = API .. "/investors/firms/FIRM1/funds/FUND1"
		local function last() return requests[#requests] end
		local function sent() return json.decode(last().body) end

		local count = 0
		for name in carta do if name ~= "help" then count += 1 end end
		assert(count == 79, "wrong read-write surface: " .. count)

		payload = '{"capitalCall":{"id":"CC1","status":"DRAFT","webUrl":"https://app.carta.com/x"},"replayed":false}'
		local call = carta.createCapitalCall({firmId = "FIRM1", fundId = "FUND1", externalReferenceId = "ref-1", sourceSystem = "houston",
			dueDate = "2026-11-01", amount = {currencyCode = "USD", value = "250000.00"}, postAsDraft = true, interestIds = json.decode("[]")})
		assert(last().method == "POST" and last().url == FUND .. "/capitalCalls")
		assert(last().headers["Content-Type"][1] == "application/json" and last().headers.Authorization == nil)
		local body = sent()
		assert(body.externalReferenceId == "ref-1" and body.postAsDraft == true and body.amount.value == "250000.00")
		assert(json.encode(body.interestIds) == "[]" and body.firmId == nil and body.fundId == nil, "path fields leaked into the body")
		assert(call.capitalCall.id == "CC1" and call.replayed == false)

		carta.getCapitalCall({firmId = "FIRM1", fundId = "FUND1", capitalCallId = "CC1"})
		assert(last().method == "GET" and last().url == FUND .. "/capitalCalls/CC1" and last().body == nil)
		carta.adjustCapitalCall({firmId = "FIRM1", fundId = "FUND1", capitalCallId = "CC1", externalReferenceId = "ref-2", sourceSystem = "houston",
			amount = {currencyCode = "USD", value = "200000.00"}})
		assert(last().method == "POST" and last().url == FUND .. "/capitalCalls/CC1:adjust" and sent().amount.value == "200000.00")

		carta.createManagementFee({firmId = "FIRM1", fundId = "FUND1", externalReferenceId = "fee-1", sourceSystem = "houston", periodStart = "2026-07-01",
			periodEnd = "2026-09-30", effectiveDate = "2026-09-30", amount = {currencyCode = "USD", value = "100.00"},
			interestAmounts = {{interestId = "I1", amount = {currencyCode = "USD", value = "100.00"}}}})
		assert(last().url == FUND .. "/managementFees" and sent().interestAmounts[1].interestId == "I1")
		carta.createCarriedInterestAllocation({firmId = "FIRM1", fundId = "FUND1", externalReferenceId = "carry-1", sourceSystem = "houston",
			effectiveDate = "2026-09-30", deltas = {{interestId = "I1", amount = {currencyCode = "USD", value = "-5.00"}}}})
		assert(last().url == FUND .. "/carriedInterestAllocations" and sent().deltas[1].amount.value == "-5.00")

		carta.updateExerciseMoneyMovement({issuerId = "7", exerciseId = "EX1", moneyMovement = {status = "COMPLETED"}})
		assert(last().url == API .. "/issuers/7/optionExercises/EX1:updateMoneyMovement" and sent().moneyMovement.status == "COMPLETED")
		carta.updateExerciseTaxWithholding({issuerId = "7", exerciseId = "EX1", taxWithholdings = json.decode("[]")})
		assert(last().url == API .. "/issuers/7/optionExercises/EX1:updateTaxWithholding" and last().body == '{"taxWithholdings":[]}')
		carta.createDraftOptionGrant({issuerId = "7", draftOptionGrantSetId = "S1", draftOptionGrant = {stakeholderId = "611", quantity = "1000"}})
		assert(last().url == API .. "/issuers/7/draftOptionGrantSets/S1/draftOptionGrants" and sent().draftOptionGrant.quantity == "1000")

		status = 202
		payload = '{"secondaryTransactionId":"0b8e6f5a-1c2d-4e3f-8a9b-0c1d2e3f4a5b"}'
		local trade = carta.initiateSecondarySettlement({issuerId = "7", externalReferenceId = "trade-1", rightOfFirstRefusalOutcome = "WAIVED",
			pricePerShare = {currencyCode = "USD", value = "4.20"}, securities = {{securityId = "S1", quantity = "10"}}})
		assert(last().url == API .. "/issuers/7/secondaryTransactions" and trade.secondaryTransactionId ~= nil)
		payload = ""
		local final = carta.finalizeSecondarySettlement({issuerId = "7", secondaryTransactionId = trade.secondaryTransactionId})
		assert(last().url == API .. "/issuers/7/secondaryTransactions/" .. trade.secondaryTransactionId .. ":finalize" and last().body == "{}")
		assert(final.success == true, "an accepted write without a body reports success")

		status = 200
		payload = '{"draftIssuer":{"id":"D1","registrationUrl":"https://app.carta.com/register/x"}}'
		carta.createDraftIssuer({draftIssuer = {legalName = "Newco"}})
		assert(last().url == API .. "/draftIssuers" and sent().draftIssuer.legalName == "Newco")
		carta.uploadOpenCapTable({contentType = "application/zip", data = "UEsDBA=="})
		assert(last().url == API .. "/openCapTables" and sent().data == "UEsDBA==")
		carta.uploadFile({file = {filePayload = "SGVsbG8=", uploadDetails = {name = "hello.txt"}}})
		assert(last().url == API .. "/files:upload" and sent().file.uploadDetails.name == "hello.txt")

		local before = #requests
		local ok, err = pcall(function() carta.createCapitalCall({firmId = "FIRM1", fundId = "FUND1", externalReferenceId = "ref-1", sourceSystem = "houston",
			dueDate = "2026-11-01", amount = {currencyCode = "USD", value = "1.00"}}) end)
		assert(not ok and string.find(tostring(err), "postAsDraft is required", 1, true), tostring(err))
		ok, err = pcall(function() carta.createManagementFee({firmId = "FIRM1", fundId = "FUND1", externalReferenceId = "fee-1", sourceSystem = "houston",
			periodStart = "2026-07-01", periodEnd = "2026-09-30", effectiveDate = "2026-09-30", amount = json.decode("null"), interestAmounts = json.decode("[]")}) end)
		assert(not ok and string.find(tostring(err), "amount is required", 1, true), tostring(err))
		assert(#requests == before and #requests == 13)
	end,
}
