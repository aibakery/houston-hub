-- Searches page inside one call and continue only through sealed tokens; study reads select fields.
return {
	scenario = {publisher = {}, config = {}, auth_method = "", auth_config = {}},
	configure = function()
		requests, responses = {}, {}
		-- Sealing is native; a table of opaque handles stands in for it.
		local sealed, count = {}, 0
		houston = table.clone(houston)
		houston.seal = function(value)
			count += 1
			sealed["sealed:" .. count] = json.encode(value)
			return "sealed:" .. count
		end
		houston.unseal = function(token)
			assert(type(token) == "string" and sealed[token], "invalid sealed token")
			return json.decode(sealed[token])
		end
		http = {request = function(req)
			table.insert(requests, req)
			assert(req.method == "GET" and req.body == nil, "ClinicalTrials.gov reads must be bodiless GETs")
			assert(req.headers.Authorization == nil, "the public API takes no credentials")
			assert(req.headers.Accept[1] == "application/json")
			assert(#responses > 0, "unexpected request: " .. req.url)
			return fixture.operation({statusCode = 200, headers = {}, body = fixture.reader(table.remove(responses, 1))})
		end}
		function respond(body) table.insert(responses, body) end
	end,
	run = function(trials)
		local API = "https://clinicaltrials.gov/api/v2"
		local SUMMARY = "fields=NCTId%2CBriefTitle%2COverallStatus%2CPhase%2CStudyType%2CCondition%2CInterventionName%2CLeadSponsorName%2CEnrollmentCount%2CStartDate%2CPrimaryCompletionDate%2CHasResults"
		local function study(id) return '{"protocolSection":{"identificationModule":{"nctId":"' .. id .. '"}},"hasResults":false}' end
		local function url(i) return requests[i].url end

		local names = {}
		for name, fn in trials do
			assert(type(fn) == "function")
			table.insert(names, name)
		end
		table.sort(names)
		assert(table.concat(names, ",") == "getStudy,searchStudies", table.concat(names, ","))
		assert(#requests == 0, "initialization reached ClinicalTrials.gov")

		-- Default search: summary fields, default limit, no token when the page has none.
		respond('{"studies":[' .. study("NCT00000001") .. ']}')
		local page = trials.searchStudies()
		assert(url(1) == API .. "/studies?" .. SUMMARY .. "&pageSize=50", url(1))
		assert(#page.studies == 1 and page.studies[1].protocolSection.identificationModule.nctId == "NCT00000001")
		assert(page.nextPageToken == nil and page.totalCount == nil)

		-- Every criterion, sorted and encoded; countTotal only on the first page.
		local opts = {["query.cond"] = "type 2 diabetes", ["query.intr"] = "metformin OR insulin", ["query.locn"] = "Boston",
			["query.term"] = "AREA[StudyType]INTERVENTIONAL", ["query.titles"] = "t", ["query.outc"] = "o", ["query.spons"] = "s",
			["query.lead"] = "l", ["query.id"] = "i", ["query.patient"] = "p", ["filter.geo"] = "distance(42.36,-71.06,25mi)",
			["filter.overallStatus"] = "RECRUITING, NOT_YET_RECRUITING", ["filter.advanced"] = "AREA[Phase](PHASE2 OR PHASE3)",
			["filter.ids"] = {"NCT04368728", "NCT05730322"}, sort = {"LastUpdatePostDate:desc", "@relevance"},
			fields = "NCTId|@query", countTotal = true, limit = 3}
		respond('{"totalCount":388,"studies":[' .. study("NCT04368728") .. "," .. study("NCT05730322") .. '],"nextPageToken":"t+1/="}')
		respond('{"totalCount":999,"studies":[' .. study("NCT00000003") .. '],"nextPageToken":"t2"}')
		page = trials.searchStudies(opts)
		local query = "fields=NCTId%2C%40query&filter.advanced=AREA%5BPhase%5D%28PHASE2%20OR%20PHASE3%29"
			.. "&filter.geo=distance%2842.36%2C-71.06%2C25mi%29&filter.ids=NCT04368728%2CNCT05730322"
			.. "&filter.overallStatus=RECRUITING%2CNOT_YET_RECRUITING&query.cond=type%202%20diabetes&query.id=i"
			.. "&query.intr=metformin%20OR%20insulin&query.lead=l&query.locn=Boston&query.outc=o&query.patient=p"
			.. "&query.spons=s&query.term=AREA%5BStudyType%5DINTERVENTIONAL&query.titles=t"
			.. "&sort=LastUpdatePostDate%3Adesc%2C%40relevance"
		assert(url(2) == API .. "/studies?" .. query .. "&pageSize=3&countTotal=true", url(2))
		assert(url(3) == API .. "/studies?" .. query .. "&pageSize=1&pageToken=t%2B1%2F%3D", url(3))
		assert(#page.studies == 3 and page.totalCount == 388, "totalCount comes from the first page")
		assert(opts.limit == 3 and opts.fields == "NCTId|@query", "caller options were modified")

		-- A sealed token continues the same query, whatever limit the caller picks.
		respond('{"studies":[' .. study("NCT00000004") .. "]}")
		local more = trials.searchStudies({pageToken = page.nextPageToken, limit = 10})
		assert(url(4) == API .. "/studies?" .. query .. "&pageSize=10&pageToken=t2", url(4))
		assert(#more.studies == 1 and more.nextPageToken == nil and more.totalCount == nil)

		-- An exactly full page keeps a token, then an empty page ends the search.
		respond('{"studies":[' .. study("NCT00000005") .. '],"nextPageToken":"full"}')
		respond('{"studies":[],"nextPageToken":"stale"}')
		page = trials.searchStudies({["query.cond"] = "asthma", limit = 5})
		assert(url(5) == API .. "/studies?" .. SUMMARY .. "&query.cond=asthma&pageSize=5", url(5))
		assert(url(6) == API .. "/studies?" .. SUMMARY .. "&query.cond=asthma&pageSize=4&pageToken=full", url(6))
		assert(#page.studies == 1 and page.nextPageToken == nil, "an empty page must end the search")

		-- Empty results stay an array.
		respond('{"totalCount":0,"studies":[]}')
		page = trials.searchStudies({["query.cond"] = "nothing", countTotal = true})
		assert(json.encode(page.studies) == "[]" and page.totalCount == 0 and page.nextPageToken == nil)

		-- The first page starts small: 1,000 ProtocolSection records are about 11.7 MB, and 100 ResultsSection ones 3.9 MB.
		local protocol = '{"protocolSection":{"descriptionModule":{"detailedDescription":"' .. string.rep("p", 12 * 1024) .. '"}}}'
		respond('{"studies":[' .. string.rep(protocol .. ",", 49) .. protocol .. '],"nextPageToken":"r2"}')
		respond('{"studies":[]}')
		page = trials.searchStudies({fields = {"ProtocolSection"}, limit = 2000})
		assert(url(#requests - 1) == API .. "/studies?fields=ProtocolSection&pageSize=50", url(#requests - 1))
		local grown = tonumber(string.match(url(#requests), "pageSize=(%d+)&pageToken=r2$"))
		assert(grown and grown > 50 and grown < 1000, "later pages grow within the budget: " .. url(#requests))
		assert(#page.studies == 50 and page.nextPageToken == nil)
		protocol, page = nil, nil

		-- Later pages shrink to the remaining byte budget, and stop when nothing more fits.
		local big = '{"protocolSection":{"descriptionModule":{"briefSummary":"' .. string.rep("x", 1024 * 1024) .. '"}}}'
		respond('{"studies":[' .. big .. '],"nextPageToken":"p2"}')
		respond('{"studies":[' .. big .. '],"nextPageToken":"p3"}')
		local first = #requests + 1
		page = trials.searchStudies({fields = {"ProtocolSection"}, limit = 2000})
		assert(#requests == first + 1, "the byte budget must stop paging")
		for i, expected in {"pageSize=50", "pageSize=1&pageToken=p2"} do
			assert(url(first + i - 1) == API .. "/studies?fields=ProtocolSection&" .. expected, url(first + i - 1))
		end
		assert(#page.studies == 2 and page.nextPageToken ~= nil, "a budget stop keeps the continuation token")
		local token = page.nextPageToken
		big, page = nil, nil
		respond('{"studies":[' .. study("NCT00000010") .. "]}")
		trials.searchStudies({pageToken = token})
		assert(url(#requests) == API .. "/studies?fields=ProtocolSection&pageSize=50&pageToken=p3", url(#requests))

		-- A later page over the remaining budget ends the call with what was collected and that page's token.
		local medium = '{"protocolSection":{"descriptionModule":{"briefSummary":"' .. string.rep("m", 512 * 1024) .. '"}}}'
		respond('{"studies":[' .. medium .. '],"nextPageToken":"q2"}')
		respond('{"studies":[{"x":"' .. string.rep("o", 3584 * 1024) .. '"}],"nextPageToken":"q3"}')
		page = trials.searchStudies({fields = {"ProtocolSection"}, limit = 2000})
		assert(url(#requests) == API .. "/studies?fields=ProtocolSection&pageSize=3&pageToken=q2", url(#requests))
		assert(#page.studies == 1 and page.nextPageToken ~= nil, "collected studies were discarded")
		token, medium, page = page.nextPageToken, nil, nil
		respond('{"studies":[]}')
		trials.searchStudies({pageToken = token, limit = 1})
		assert(url(#requests) == API .. "/studies?fields=ProtocolSection&pageSize=1&pageToken=q2", url(#requests))

		-- Study reads: full record, selected modules, and the table form.
		respond('{"protocolSection":{"identificationModule":{"nctId":"NCT04368728"}},"resultsSection":{},"hasResults":true}')
		local record = trials.getStudy("NCT04368728")
		assert(url(#requests) == API .. "/studies/NCT04368728", url(#requests))
		assert(record.hasResults == true and record.protocolSection.identificationModule.nctId == "NCT04368728")
		respond('{"resultsSection":{"outcomeMeasuresModule":{"outcomeMeasures":[]}}}')
		record = trials.getStudy("NCT04368728", {fields = {"OutcomeMeasuresModule", "AdverseEventsModule"}})
		assert(url(#requests) == API .. "/studies/NCT04368728?fields=OutcomeMeasuresModule%2CAdverseEventsModule", url(#requests))
		assert(json.encode(record.resultsSection.outcomeMeasuresModule.outcomeMeasures) == "[]")
		respond("{}")
		local args = {nctId = "NCT00587795", fields = "ResultsSection"}
		assert(next(trials.getStudy(args)) == nil)
		assert(url(#requests) == API .. "/studies/NCT00587795?fields=ResultsSection", url(#requests))
		assert(args.nctId == "NCT00587795" and args.fields == "ResultsSection", "caller table was modified")
		assert(#responses == 0, "unused responses")
	end,
}
