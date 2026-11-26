return {
	scenario = {publisher = {}, config = {}, auth_method = "api_key", auth_config = {token = "lemlist_fixture_key"}},
	configure = function()
		requests = {}
		payload = "{}"
		http = {request = function(req)
			table.insert(requests, req)
			return fixture.operation({statusCode = 200, headers = {}, body = fixture.reader(payload)})
		end}
	end,
	run = function(lemlist)
		local API = "https://api.lemlist.com/api"
		local NULL = json.decode("null")
		local CAMPAIGN = "cam_A1b2C3d4E5f6G7h8J"
		local CONTACT = "ctc_K9m8N7p6Q5r4S3t2U"
		local function last() return requests[#requests] end
		local function rejected(fn, expected)
			local before = #requests
			local ok, err = pcall(fn)
			assert(not ok and string.find(tostring(err), expected, 1, true), "wrong validation error: " .. tostring(err))
			assert(#requests == before, "invalid input reached lemlist")
		end

		local names = {}
		for name in lemlist do if name ~= "help" then table.insert(names, name) end end
		assert(#names == 73, "wrong read-only surface: " .. #names)
		for _, name in {"getTeam", "createCampaign", "startCampaign", "addLeadToCampaign", "removeCampaignLead", "sendEmail", "sendSms",
			"enrich", "bulkEnrich", "addWebhook", "deleteContact", "mergeCompanies", "unsubscribeVariable", "updateWarmupSettings", "disconnectEmailAccount"} do
			assert(lemlist[name] == nil, "read-only leaked " .. name)
		end
		assert(lemlist.searchPeopleDatabase and lemlist.getBatchCampaignStats, "POST searches only read")
		assert(#requests == 0, "initialization reached lemlist")

		payload = '{"campaigns":[{"_id":"' .. CAMPAIGN .. '","name":"Q4","labels":[],"archived":null}],"pagination":{"totalRecords":1}}'
		local campaigns = lemlist.listCampaigns({status = "running", limit = 20, sortOrder = "desc"})
		assert(last().method == "GET" and last().body == nil, "listCampaigns is a plain GET")
		assert(last().url == API .. "/campaigns?version=v2&limit=20&status=running&sortOrder=desc", last().url)
		assert(last().headers.Accept[1] == "application/json" and last().headers.Authorization == nil)
		assert(campaigns.campaigns[1].name == "Q4" and json.encode(campaigns.campaigns[1].labels) == "[]" and campaigns.campaigns[1].archived == NULL)

		payload = "[]"
		local leads = lemlist.listCampaignLeads({campaignId = CAMPAIGN, state = "interested", offset = 500, limit = 500})
		assert(last().url == API .. "/campaigns/" .. CAMPAIGN .. "/leads?state=interested&offset=500&limit=500", last().url)
		assert(json.encode(leads) == "[]")

		payload = '[{"value":"ana@example.com"}]'
		local unsubscribes = lemlist.listUnsubscribedVariables({offset = 100})
		assert(json.encode(unsubscribes) == '[{"value":"ana@example.com"}]')
		assert(last().url == API .. "/v2/unsubscribes/variables?offset=100&limit=100", "offset lists need a default limit: " .. last().url)

		payload = "{}"
		lemlist.getLead({email = "ana+q4@example.com"})
		assert(last().url == API .. "/leads?version=v2&email=ana%2Bq4%40example.com", last().url)
		lemlist.getContact({idOrEmail = "ana+q4@example.com"})
		assert(last().url == API .. "/contacts/ana+q4@example.com", "emails stay unencoded in paths: " .. last().url)
		lemlist.getContact({idOrEmail = CONTACT})
		assert(last().url == API .. "/contacts/" .. CONTACT)
		lemlist.getUnsubscribedVariable({value = "+33612345678"})
		assert(last().url == API .. "/v2/unsubscribes/variables/+33612345678", last().url)
		lemlist.getCampaignReports({campaignIds = {CAMPAIGN, "cam_Z9y8X7w6V5u4T3s2R"}})
		assert(last().url == API .. "/campaigns/reports?campaignIds=" .. CAMPAIGN .. ",cam_Z9y8X7w6V5u4T3s2R", last().url)
		lemlist.getCampaignStats({campaignId = CAMPAIGN, startDate = "2026-10-01T00:00:00Z", endDate = "2026-10-30T00:00:00Z", channels = {"email", "linkedin"}})
		assert(last().url == API .. "/v2/campaigns/" .. CAMPAIGN .. "/stats?startDate=2026-10-01T00%3A00%3A00Z&endDate=2026-10-30T00%3A00%3A00Z&channels=%5B%22email%22%2C%22linkedin%22%5D", last().url)
		lemlist.getMessageTemplate({templateId = "64f1c2e9a7b3d1e2f3a4b5c6"})
		assert(last().url == API .. "/message-templates/64f1c2e9a7b3d1e2f3a4b5c6")
		lemlist.getConversation({contactId = CONTACT, limit = 10, markAsRead = false})
		assert(last().url == API .. "/inbox/" .. CONTACT .. "?limit=10", "markAsRead=false would still mark it read: " .. last().url)
		lemlist.getConversation({contactId = CONTACT, userId = "usr_D4e5F6g7H8j9K2m3N"})
		assert(last().url == API .. "/inbox/" .. CONTACT .. "?userId=usr_D4e5F6g7H8j9K2m3N", last().url)

		payload = '{"results":[],"total":0}'
		local search = lemlist.searchPeopleDatabase({filters = {{filterId = "currentTitle", ["in"] = {"CTO"}, out = json.decode("[]")}}, size = 20})
		assert(last().method == "POST" and last().url == API .. "/database/people")
		assert(last().headers["Content-Type"][1] == "application/json")
		local body = json.decode(last().body)
		assert(body.size == 20 and body.filters[1]["in"][1] == "CTO" and json.encode(body.filters[1].out) == "[]")
		assert(json.encode(search.results) == "[]")

		payload = ""
		local ok, err = pcall(function() lemlist.getCampaign({campaignId = CAMPAIGN}) end)
		assert(not ok and string.find(tostring(err), "invalid JSON", 1, true), "an empty GET response is not data")

		rejected(function() lemlist.getCampaign() end, "campaignId must be a lemlist ID")
		rejected(function() lemlist.getCampaign({campaignId = "reports"}) end, "campaignId must be a lemlist ID")
		rejected(function() lemlist.getContact({idOrEmail = "export"}) end, "idOrEmail must be a lemlist ID or an email")
		rejected(function() lemlist.getContact({idOrEmail = "../team"}) end, "idOrEmail must be a lemlist ID or an email")
		rejected(function() lemlist.getCompany({companyId = "lists"}) end, "companyId must be a lemlist ID")
		rejected(function() lemlist.getConversation({contactId = "labels"}) end, "contactId must be a lemlist ID")
		rejected(function() lemlist.getUnsubscribedVariable({value = "https://linkedin.com/in/ana"}) end, "without '/'")
		rejected(function() lemlist.getUnsubscribedVariable({value = ".."}) end, "value must")
		rejected(function() lemlist.getUnsubscribedVariable({value = "ana%40example.com"}) end, "without '/'")
		rejected(function() lemlist.getMessageTemplate({templateId = "a/b"}) end, "templateId must be an ID")
		rejected(function() lemlist.getConversation({contactId = CONTACT, markAsRead = true}) end, "needs write access")
		rejected(function() lemlist.getCampaignStats({campaignId = CAMPAIGN, startDate = "a", endDate = "b", channels = "email"}) end, "channels must be an array")
		rejected(function() lemlist.getConversation({contactId = CONTACT, markAsRead = "false"}) end, "markAsRead must be a boolean")
		rejected(function() lemlist.listCampaigns({access_token = "other"}) end, "must not contain access_token")
		rejected(function() lemlist.searchPeopleDatabase({filters = {}, access_token = "other"}) end, "must not contain access_token")
		rejected(function() lemlist.listCampaigns({version = "v1"}) end, "listCampaigns has no option version")
		rejected(function() lemlist.getCampaignStats({campaignId = CAMPAIGN, startDate = "2026-10-01"}) end, "endDate is required")
		rejected(function() lemlist.getCampaignStats({campaignId = CAMPAIGN, startDate = NULL, endDate = "x"}) end, "startDate is required")
		rejected(function() lemlist.getCampaignReports({campaignIds = json.decode("[]")}) end, "must not be an empty array")
		rejected(function() lemlist.listCampaigns({status = {running = true}}) end, "array, not an object")
		rejected(function() lemlist.listCampaigns("running") end, "opts must be an object")
		rejected(function() lemlist.listCampaigns({"running"}) end, "named fields")
		assert(#requests == 14, "request count " .. #requests)
	end,
}
