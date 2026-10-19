return {
	scenario = {publisher = {}, config = {access = "read-write", own_app = true, client_id = "fixture-client", client_secret = "fixture-secret"},
		auth_method = "own_app", auth_config = {}},
	configure = function()
		requests = {}
		uploaded = nil
		status = 200
		payload = "{}"
		fs = fixture.files()
		http = {request = function(req)
			table.insert(requests, req)
			if req.body ~= nil and type(req.body) ~= "string" then
				uploaded = await(req.body:readAll())
				await(req.body:close())
			end
			return fixture.operation({statusCode = status, headers = {}, body = fixture.reader(payload)})
		end}
	end,
	run = function(carta)
		local API = "https://api.carta.com/v1alpha1"
		local FUND = API .. "/investors/firms/FIRM1/funds/FUND1"
		local function last() return requests[#requests] end
		local function sent() return json.decode(last().body) end
		local function usd(value) return {currencyCode = {value = "USD"}, amount = {value = value}} end

		local count = 0
		for name in carta do if name ~= "help" then count += 1 end end
		assert(count == 79, "wrong read-write surface: " .. count)

		payload = '{"capitalCall":{"id":"CC1","status":"CAPITAL_CALL_STATUS_DRAFT","webUrl":"https://app.carta.com/x"},"replayed":false}'
		local call = carta.createCapitalCall({firmId = "FIRM1", fundId = "FUND1", externalReferenceId = "ref-1", sourceSystem = "houston",
			dueDate = {value = "2026-11-01"}, amount = {value = "250000.00"}, postAsDraft = true, interestIds = json.decode("[]")})
		assert(last().method == "POST" and last().url == FUND .. "/capitalCalls")
		assert(last().headers["Content-Type"][1] == "application/json" and last().headers.Authorization == nil)
		local body = sent()
		assert(body.externalReferenceId == "ref-1" and body.postAsDraft == true and body.amount.value == "250000.00" and body.dueDate.value == "2026-11-01")
		assert(json.encode(body.interestIds) == "[]" and body.firmId == nil and body.fundId == nil, "path fields leaked into the body")
		assert(call.capitalCall.id == "CC1" and call.replayed == false)

		carta.getCapitalCall({firmId = "FIRM1", fundId = "FUND1", capitalCallId = "CC1"})
		assert(last().method == "GET" and last().url == FUND .. "/capitalCalls/CC1" and last().body == nil)
		carta.adjustCapitalCall({firmId = "FIRM1", fundId = "FUND1", capitalCallId = "CC1", externalReferenceId = "ref-2", sourceSystem = "houston",
			amount = {value = "200000.00"}})
		assert(last().method == "POST" and last().url == FUND .. "/capitalCalls/CC1:adjust" and sent().amount.value == "200000.00")

		carta.createManagementFee({firmId = "FIRM1", fundId = "FUND1", externalReferenceId = "fee-1", sourceSystem = "houston", periodStart = {value = "2026-07-01"},
			periodEnd = {value = "2026-09-30"}, effectiveDate = {value = "2026-09-30"}, amount = usd("100.00"),
			interestAmounts = {{interestId = "I1", amount = {value = "100.00"}}}})
		body = sent()
		assert(last().url == FUND .. "/managementFees" and body.interestAmounts[1].interestId == "I1" and body.amount.currencyCode.value == "USD")
		carta.createCarriedInterestAllocation({firmId = "FIRM1", fundId = "FUND1", externalReferenceId = "carry-1", sourceSystem = "houston",
			effectiveDate = {value = "2026-09-30"}, deltas = {{interestId = "I1", amount = {value = "-5.00"}}, {interestId = "I2", amount = {value = "5.00"}}}})
		assert(last().url == FUND .. "/carriedInterestAllocations" and sent().deltas[1].amount.value == "-5.00")

		carta.updateExerciseMoneyMovement({issuerId = "7", exerciseId = "EX1", moneyMovement = {completionDate = {value = "2026-10-19"}}})
		assert(last().url == API .. "/issuers/7/optionExercises/EX1:updateMoneyMovement" and sent().moneyMovement.completionDate.value == "2026-10-19")
		carta.updateExerciseTaxWithholding({issuerId = "7", exerciseId = "EX1", taxWithholdings = json.decode("[]")})
		assert(last().url == API .. "/issuers/7/optionExercises/EX1:updateTaxWithholding" and last().body == '{"taxWithholdings":[]}')
		carta.createDraftOptionGrant({issuerId = "7", draftOptionGrantSetId = "S1", draftOptionGrant = {quantity = {value = "1000"}}})
		assert(last().url == API .. "/issuers/7/draftOptionGrantSets/S1/draftOptionGrants" and sent().draftOptionGrant.quantity.value == "1000")

		status = 202
		payload = '{"secondaryTransactionId":"0b8e6f5a-1c2d-4e3f-8a9b-0c1d2e3f4a5b","transactionState":"PENDING_EXERCISE"}'
		local trade = carta.initiateSecondarySettlement({issuerId = "7", externalReferenceId = "trade-1", rightOfFirstRefusalOutcome = "WAIVED",
			pricePerShare = usd("4.20"), buyerInformation = {entityName = "Buyer LLC", email = "buyer@example.com"},
			securities = {{securityType = "OPTION_GRANT", securityId = "S1", quantity = {value = "10"}}}})
		assert(last().url == API .. "/issuers/7/secondaryTransactions" and trade.secondaryTransactionId ~= nil)
		assert(sent().securities[1].quantity.value == "10" and sent().pricePerShare.amount.value == "4.20")
		payload = ""
		local final = carta.finalizeSecondarySettlement({issuerId = "7", secondaryTransactionId = trade.secondaryTransactionId})
		assert(last().url == API .. "/issuers/7/secondaryTransactions/" .. trade.secondaryTransactionId .. ":finalize" and last().body == "{}")
		assert(final.success == true, "an accepted write without a body reports success")

		status = 200
		payload = '{"draftIssuer":{"id":"D1","primaryContact":{"registrationUrl":"https://app.carta.com/register?token=x"}}}'
		carta.createDraftIssuer({draftIssuer = {legalName = "Newco"}})
		assert(last().url == API .. "/draftIssuers" and sent().draftIssuer.legalName == "Newco")
		carta.getDraftIssuer({id = "D1"})
		assert(last().method == "GET" and last().url == API .. "/draftIssuers/D1")
		carta.uploadFile({file = {filePayload = "SGVsbG8=", uploadDetails = {name = "hello.txt"}}})
		assert(last().url == API .. "/files:upload" and sent().file.uploadDetails.name == "hello.txt")

		local zip = fs.open("captable.zip", "w")
		zip:write("PK\3\4ocf")
		await(zip:close())
		payload = '{"id":"OCF1","state":"PROCESSING"}'
		local ocf = carta.uploadOpenCapTable({path = "captable.zip"})
		assert(last().method == "POST" and last().url == API .. "/openCapTables" and last().headers["Content-Type"][1] == "application/zip")
		assert(uploaded == "PK\3\4ocf" and ocf.state == "PROCESSING", "the OCF archive is sent as the raw body")

		local before = #requests
		local function rejected(fn, expected)
			local ok, err = pcall(fn)
			assert(not ok and string.find(tostring(err), expected, 1, true), tostring(err))
		end
		rejected(function() carta.createCapitalCall({firmId = "FIRM1", fundId = "FUND1", externalReferenceId = "ref-1", sourceSystem = "houston",
			dueDate = {value = "2026-11-01"}, amount = {value = "1.00"}}) end, "postAsDraft is required")
		rejected(function() carta.createManagementFee({firmId = "FIRM1", fundId = "FUND1", externalReferenceId = "fee-1", sourceSystem = "houston",
			periodStart = {value = "2026-07-01"}, periodEnd = {value = "2026-09-30"}, effectiveDate = {value = "2026-09-30"}, amount = json.decode("null"),
			interestAmounts = json.decode("[]")}) end, "amount is required")
		rejected(function() carta.uploadOpenCapTable({}) end, "path is required")
		rejected(function() carta.uploadOpenCapTable({path = 7}) end, "path must be a session file path")
		rejected(function() carta.uploadOpenCapTable({path = "captable.zip", contentType = "application/zip"}) end, "uploadOpenCapTable has no option contentType")
		assert(#requests == before and #requests == 14)
	end,
}
