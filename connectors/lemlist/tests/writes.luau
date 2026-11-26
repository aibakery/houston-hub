return {
	scenario = {publisher = {}, config = {}, access = {data = "write"}, auth_method = "api_key", auth_config = {token = "lemlist_fixture_key"}},
	configure = function()
		requests = {}
		payload = "{}"
		contentType = "application/json"
		http = {request = function(req)
			table.insert(requests, req)
			return fixture.operation({statusCode = 200, headers = {["content-type"] = {contentType}}, body = fixture.reader(payload)})
		end}
	end,
	run = function(lemlist)
		local API = "https://api.lemlist.com/api"
		local CAMPAIGN = "cam_A1b2C3d4E5f6G7h8J"
		local LEAD = "lea_P2q3R4s5T6u7V8w9X"
		local SEQUENCE = "seq_B2c3D4e5F6g7H8j9K"
		local STEP = "stp_C3d4E5f6G7h8J9k2L"
		local function last() return requests[#requests] end
		local function rejected(fn, expected)
			local before = #requests
			local ok, err = pcall(fn)
			assert(not ok and string.find(tostring(err), expected, 1, true), "wrong validation error: " .. tostring(err))
			assert(#requests == before, "invalid input reached lemlist")
		end

		local names = {}
		for name in lemlist do if name ~= "help" then table.insert(names, name) end end
		assert(#names == 182, "wrong read-write surface: " .. #names)
		assert(lemlist.getTeam and lemlist.sendEmail and lemlist.bulkEnrich, "read-write exposes writes")

		payload = '{"_id":"tea_1","hooks":[],"slackWebhook":"https://hooks.slack.com/x"}'
		local team = lemlist.getTeam()
		assert(last().url == API .. "/team?version=v2" and json.encode(team.hooks) == "[]")

		payload = '{"_id":"' .. LEAD .. '","email":"ana@example.com"}'
		local lead = lemlist.addLeadToCampaign({campaignId = CAMPAIGN, deduplicate = true, findEmail = false,
			email = "ana@example.com", firstName = "Ana", plan = "Pro"})
		assert(last().method == "POST" and last().url == API .. "/campaigns/" .. CAMPAIGN .. "/leads?deduplicate=true&findEmail=false", last().url)
		assert(last().headers["Content-Type"][1] == "application/json" and last().headers.Authorization == nil)
		local body = json.decode(last().body)
		assert(body.email == "ana@example.com" and body.firstName == "Ana" and body.plan == "Pro" and body.campaignId == nil and body.deduplicate == nil)
		assert(lead._id == LEAD)

		payload = "{}"
		lemlist.removeCampaignLead({campaignId = CAMPAIGN, leadIdOrEmail = "ana@example.com", action = "remove"})
		assert(last().method == "DELETE" and last().url == API .. "/campaigns/" .. CAMPAIGN .. "/leads/ana@example.com?action=remove" and last().body == nil, last().url)

		local started = lemlist.startCampaign({campaignId = CAMPAIGN})
		assert(last().method == "POST" and last().url == API .. "/campaigns/" .. CAMPAIGN .. "/start" and last().body == nil)
		assert(last().headers["Content-Type"] == nil and next(started) == nil)

		payload = ""
		local empty = lemlist.pauseLead({leadId = LEAD, campaignId = CAMPAIGN})
		assert(last().url == API .. "/leads/pause/" .. LEAD .. "?campaignId=" .. CAMPAIGN and next(empty) == nil)

		payload, contentType = "Message sent", "text/plain"
		local sent = lemlist.sendWhatsappMessage({sendUserId = "usr_D4e5F6g7H8j9K2m3N", sendUserWhatsappAccountId = "uwa_1",
			contactId = "ctc_K9m8N7p6Q5r4S3t2U", leadId = LEAD, message = "Hi Ana"})
		assert(last().url == API .. "/inbox/whatsapp" and json.decode(last().body).message == "Hi Ana")
		assert(sent.message == "Message sent", "plain-text confirmations are returned")
		payload, contentType = "{}", "application/json"

		lemlist.addLeadVariables({leadId = LEAD, variables = {plan = "Pro plan", seats = 12}})
		assert(last().method == "POST" and last().url == API .. "/leads/" .. LEAD .. "/variables?plan=Pro%20plan&seats=12" and last().body == nil, last().url)

		lemlist.updateSequenceStep({sequenceId = SEQUENCE, stepId = STEP, type = "email", subject = "Hello", delay = 2})
		assert(last().method == "PATCH" and last().url == API .. "/sequences/" .. SEQUENCE .. "/steps/" .. STEP)
		body = json.decode(last().body)
		assert(body.type == "email" and body.subject == "Hello" and body.delay == 2 and body.stepId == nil)

		lemlist.replaceCampaignSenders({campaignId = CAMPAIGN, senders = {{userId = "usr_D4e5F6g7H8j9K2m3N", channels = {"email"}}}})
		assert(last().method == "PUT" and last().url == API .. "/campaigns/" .. CAMPAIGN .. "/senders")
		assert(json.decode(last().body).senders[1].channels[1] == "email" and last().headers["Content-Type"][1] == "application/json")
		lemlist.resetEnrichmentWaterfall({waterfallId = "64f1c2e9a7b3d1e2f3a4b5c6"})
		assert(last().method == "PUT" and last().url == API .. "/v2/enrichments/waterfalls/64f1c2e9a7b3d1e2f3a4b5c6/reset" and last().body == nil and last().headers["Content-Type"] == nil)

		lemlist.removeConversationLabels({contactId = "ctc_K9m8N7p6Q5r4S3t2U", labelIds = {"lbl_1"}})
		assert(last().method == "DELETE" and json.decode(last().body).labelIds[1] == "lbl_1", "label removal sends a body")

		lemlist.bulkEnrich({webhookUrl = "https://example.com/hook", requests = {{input = {email = "ana@example.com"}, enrichmentRequests = {"find_phone"}}}})
		assert(last().url == API .. "/v2/enrichments/bulk?webhookUrl=https%3A%2F%2Fexample.com%2Fhook", last().url)
		body = json.decode(last().body)
		assert(body[1].input.email == "ana@example.com" and body[1].enrichmentRequests[1] == "find_phone")

		lemlist.enrich({email = "ana@example.com", findPhone = true})
		assert(last().url == API .. "/enrich?findPhone=true&email=ana%40example.com" and last().body == nil, last().url)

		lemlist.unsubscribeVariables({values = {"https://www.linkedin.com/in/ana", "example.com"}})
		assert(json.decode(last().body).values[1] == "https://www.linkedin.com/in/ana")

		lemlist.getConversation({contactId = "ctc_K9m8N7p6Q5r4S3t2U", markAsRead = true})
		assert(string.find(last().url, "markAsRead=true", 1, true), "read-write may mark as read")

		lemlist.addWebhook({targetUrl = "https://example.com/hook", campaignId = CAMPAIGN, isFirst = true})
		assert(last().url == API .. "/hooks", "webhook filters travel in the body: " .. last().url)
		body = json.decode(last().body)
		assert(body.targetUrl == "https://example.com/hook" and body.campaignId == CAMPAIGN and body.isFirst == true)

		lemlist.markLeadInterested({leadIdOrEmail = LEAD, pauseAllCampaignsForThisLead = true})
		assert(last().method == "POST" and last().url == API .. "/leads/interested/" .. LEAD and json.decode(last().body).pauseAllCampaignsForThisLead == true)
		lemlist.markCampaignLeadNotInterested({campaignId = CAMPAIGN, leadIdOrEmail = "ana@example.com"})
		assert(last().url == API .. "/campaigns/" .. CAMPAIGN .. "/leads/ana@example.com/notinterested" and last().body == "{}", last().body)

		lemlist.deleteSignalAgent({watchListId = "wat_E5f6G7h8J9k2L3m4N"})
		assert(last().method == "DELETE" and last().url == API .. "/watchlist?watchListId=wat_E5f6G7h8J9k2L3m4N")

		rejected(function() lemlist.addLeadVariables({leadId = LEAD, variables = {}}) end, "variables must be a nonempty object")
		rejected(function() lemlist.addLeadVariables({leadId = LEAD, variables = {access_token = "other"}}) end, "must not contain access_token")
		rejected(function() lemlist.addLeadVariables({leadId = LEAD, variables = {["a&b"] = "x"}}) end, "variable names")
		rejected(function() lemlist.addLeadVariables({leadId = LEAD, variables = {plan = {"x"}}}) end, "must be a string, boolean, number")
		rejected(function() lemlist.createCampaign({name = "Q4", access_token = "other"}) end, "must not contain access_token")
		rejected(function() lemlist.createCampaign({timezone = "Europe/Paris"}) end, "name is required")
		rejected(function() lemlist.bulkEnrich({requests = {{access_token = "other"}}}) end, "must not contain access_token")
		rejected(function() lemlist.bulkEnrich({requests = json.decode("[]")}) end, "requests must be a nonempty array")
		rejected(function() lemlist.removeCampaignLead({campaignId = CAMPAIGN, leadIdOrEmail = "ana"}) end, "lemlist ID or an email")
		rejected(function() lemlist.startCampaign({campaignId = CAMPAIGN, force = true}) end, "startCampaign has no option force")
		assert(#requests == 19, "request count " .. #requests)
	end,
}
