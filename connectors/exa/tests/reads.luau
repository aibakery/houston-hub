-- Each export posts one exact JSON body to Exa, with the key left to Houston's proxy, and returns Exa's answer unchanged.
return {
	scenario = {publisher = {}, config = {}, auth_method = "api_key", auth_config = {token = "synthetic-exa-key"}},
	configure = function()
		requests, responses = {}, {}
		http = {request = function(req)
			table.insert(requests, req)
			for name in req.headers do
				local lower = string.lower(name)
				assert(lower ~= "authorization" and lower ~= "x-api-key", "the proxy adds the key")
			end
			assert(req.method == "POST" and req.timeoutMs == 23000, "one POST, with the call's time less the body's share")
			assert(req.headers["Content-Type"][1] == "application/json" and req.headers.Accept[1] == "application/json")
			assert(#responses > 0, "unexpected request: " .. req.url)
			return fixture.operation({statusCode = 200, headers = {["content-type"] = {"application/json; charset=utf-8"}},
				body = fixture.reader(table.remove(responses, 1))})
		end}
		function respond(body) table.insert(responses, body) end
	end,
	run = function(exa)
		local function same(a, b)
			if type(a) ~= "table" or type(b) ~= "table" then return a == b end
			for key, value in a do
				if not same(value, b[key]) then return false end
			end
			for key in b do
				if a[key] == nil then return false end
			end
			return true
		end
		local function posted(path, expected)
			local req = requests[#requests]
			assert(req.url == "https://api.exa.ai" .. path, req.url)
			assert(same(json.decode(req.body), expected), req.body)
			return req.body
		end

		local names = {}
		for name, fn in exa do
			assert(type(fn) == "function")
			table.insert(names, name)
		end
		table.sort(names)
		assert(table.concat(names, ",") == "answer,findSimilar,getContents,search", table.concat(names, ","))
		assert(#requests == 0, "initialization reached Exa")

		-- A bare search sends only the query; an empty result list stays an array.
		respond('{"requestId":"r0","results":[],"searchTime":412.5,"costDollars":{"total":0.007}}')
		local found = exa.search({query = "zzqx nothing matches"})
		posted("/search", {query = "zzqx nothing matches"})
		assert(json.encode(found.results) == "[]" and found.costDollars.total == 0.007 and found.requestId == "r0")

		-- Every search option, checked and copied; the caller's table is left unchanged.
		local opts = {query = "open-source vector databases", type = "auto", numResults = 25, category = "news",
			includeDomains = {"arxiv.org", "github.com/exa-labs", "*.gov"}, excludeDomains = {"example.com"},
			startPublishedDate = "2026-01-01", endPublishedDate = "2026-06-30", userLocation = "FR",
			moderation = true, objective = "Benchmarks first; skip vendor pages",
			contents = {text = {maxCharacters = 18000, verbosity = "standard", includeSections = {"body"}, excludeSections = {"footer", "navigation"},
				includeHtmlTags = false}, highlights = {query = "benchmark results", maxCharacters = 2000}, summary = {query = "Main finding"},
				extras = {links = 5, imageLinks = 0, richImageLinks = 2}, maxAgeHours = 24, livecrawlTimeout = 8000}}
		respond('{"requestId":"r1","results":[{"id":"https://arxiv.org/abs/2601.00001","url":"https://arxiv.org/abs/2601.00001",'
			.. '"title":"Benchmarking vector databases","publishedDate":"2026-01-12T00:00:00.000Z","author":null,'
			.. '"text":"# Benchmarking","highlights":["Qdrant led recall at 0.98."],"summary":"Qdrant led.","extras":{"links":["https://qdrant.tech"]}}],'
			.. '"notices":[{"code":"SITE_OPERATOR_IGNORED","path":"/query","message":"No page matched."}],'
			.. '"warnings":[{"code":"IGNORED_FIELD","path":"/x","message":"x has no effect."}],"costDollars":{"total":0.023}}')
		found = exa.search(opts)
		posted("/search", {query = "open-source vector databases", type = "auto", numResults = 25, category = "news",
			includeDomains = {"arxiv.org", "github.com/exa-labs", "*.gov"}, excludeDomains = {"example.com"},
			startPublishedDate = "2026-01-01T00:00:00.000Z", endPublishedDate = "2026-06-30T23:59:59.999Z", userLocation = "FR",
			moderation = true, objective = "Benchmarks first; skip vendor pages",
			contents = {text = {maxCharacters = 18000, verbosity = "standard", includeSections = {"body"}, excludeSections = {"footer", "navigation"},
				includeHtmlTags = false}, highlights = {query = "benchmark results", maxCharacters = 2000}, summary = {query = "Main finding"},
				extras = {links = 5, imageLinks = 0, richImageLinks = 2}, maxAgeHours = 24, livecrawlTimeout = 8000}})
		assert(found.results[1].highlights[1] == "Qdrant led recall at 0.98." and found.results[1].extras.links[1] == "https://qdrant.tech")
		assert(found.notices[1].code == "SITE_OPERATOR_IGNORED" and found.warnings[1].code == "IGNORED_FIELD")
		assert(opts.startPublishedDate == "2026-01-01" and opts.contents.text.maxCharacters == 18000, "caller options were modified")

		-- Deep search with synthesis; text = true gets the default limit, highlights = true stays true, a bare summary is an
		-- object and false leaves a content type out.
		local schema = {type = "object", properties = {leader = {type = "string"}}, required = {"leader"}}
		respond('{"requestId":"r2","results":[{"id":"u","url":"https://u.example","title":"U"}],'
			.. '"output":{"content":{"leader":"Qdrant"},"grounding":[{"field":"leader","citations":[{"url":"https://u.example","title":"U"}]}]}}')
		found = exa.search({query = "vector database leader", type = "deep", additionalQueries = {"best vector DB 2026"},
			systemPrompt = "Prefer primary sources", outputSchema = schema, userLocation = {country = "US", latitude = 37.77, longitude = -122.42},
			contents = {text = true, highlights = true, summary = true, extras = {}}, includeDomains = {"x.example"}, endPublishedDate = "2026-01-31T12:00:00+01:00"})
		local raw = posted("/search", {query = "vector database leader", type = "deep", additionalQueries = {"best vector DB 2026"},
			systemPrompt = "Prefer primary sources", outputSchema = schema, userLocation = {country = "US", latitude = 37.77, longitude = -122.42},
			contents = {text = {maxCharacters = 10000}, highlights = true, summary = {}, extras = {}}, includeDomains = {"x.example"}, endPublishedDate = "2026-01-31T12:00:00+01:00"})
		assert(string.find(raw, '"summary":{}', 1, true) and string.find(raw, '"extras":{}', 1, true), "empty options are objects: " .. raw)
		assert(found.output.content.leader == "Qdrant" and found.output.grounding[1].field == "leader")
		respond('{"results":[]}')
		exa.search({query = "x", type = "lite", contents = {text = false, highlights = true}, userLocation = {latitude = 0, longitude = 0}})
		posted("/search", {query = "x", type = "lite", contents = {highlights = true}, userLocation = {latitude = 0, longitude = 0}})

		-- The text budget counts text and sized highlights of every result: one page may take all of it.
		respond('{"results":[]}')
		exa.search({query = "x", numResults = 5, contents = {text = {maxCharacters = 90000}, highlights = {maxCharacters = 10000}}})
		posted("/search", {query = "x", numResults = 5, contents = {text = {maxCharacters = 90000}, highlights = {maxCharacters = 10000}}})

		-- Similar pages keep Exa's scores.
		respond('{"requestId":"r3","results":[{"id":"https://b.example","url":"https://b.example","title":"B","score":0.91}],"costDollars":{"total":0.005}}')
		found = exa.findSimilar({url = "https://exa.ai/blog/dynamic-highlights", numResults = 3, excludeSourceDomain = true,
			category = "company", contents = {highlights = true}})
		posted("/findSimilar", {url = "https://exa.ai/blog/dynamic-highlights", numResults = 3, excludeSourceDomain = true,
			category = "company", contents = {highlights = true}})
		assert(found.results[1].score == 0.91)
		respond('{"results":[]}')
		found = exa.findSimilar({url = "exa.ai", startPublishedDate = "2025-01-01T00:00:00+02:00", endPublishedDate = "2028-02-29", includeDomains = {"a.example", "*.gov", "github.com/exa-labs"}})
		posted("/findSimilar", {url = "exa.ai", startPublishedDate = "2025-01-01T00:00:00+02:00", endPublishedDate = "2028-02-29T23:59:59.999Z", includeDomains = {"a.example", "*.gov", "github.com/exa-labs"}})
		assert(json.encode(found.results) == "[]")

		-- Contents keep Exa's per-URL statuses, including failures inside a successful answer.
		respond('{"requestId":"r4","results":[{"id":"https://a.example","url":"https://a.example","title":"A","text":"Hello"}],'
			.. '"statuses":[{"id":"https://a.example","status":"success","source":"cached"},'
			.. '{"id":"https://gone.example","status":"error","error":{"tag":"CRAWL_NOT_FOUND","httpStatusCode":404}}],"costDollars":{"total":0.002}}')
		local pages = exa.getContents({urls = {"https://a.example", "https://gone.example"}, text = true, maxAgeHours = 0,
			snapshotAsOf = "2026-01-15"})
		posted("/contents", {urls = {"https://a.example", "https://gone.example"}, text = {maxCharacters = 10000}, maxAgeHours = 0,
			snapshotAsOf = "2026-01-15"})
		assert(pages.results[1].text == "Hello" and pages.statuses[2].error.tag == "CRAWL_NOT_FOUND")
		respond('{"results":[],"statuses":[{"id":"https://x.example","status":"error","error":{"tag":"SOURCE_NOT_AVAILABLE","httpStatusCode":403}}]}')
		pages = exa.getContents({urls = {"https://x.example"}, highlights = {query = "pricing"}, summary = {schema = schema},
			text = {maxCharacters = 500000}, snapshotAsOf = "2024-02-29T08:30:00.123456-05:30"})
		posted("/contents", {urls = {"https://x.example"}, highlights = {query = "pricing"}, summary = {schema = schema},
			text = {maxCharacters = 500000}, snapshotAsOf = "2024-02-29T08:30:00.123456-05:30"})
		assert(json.encode(pages.results) == "[]" and pages.statuses[1].status == "error")

		-- Answers can be text or structured, with or without citations.
		respond('{"requestId":"r5","answer":"Exa Labs.","citations":[{"id":"https://exa.ai","url":"https://exa.ai","title":"Exa"}],'
			.. '"costDollars":{"total":0.005}}')
		local reply = exa.answer({query = "Who makes Exa?"})
		posted("/answer", {query = "Who makes Exa?"})
		assert(reply.answer == "Exa Labs." and reply.citations[1].url == "https://exa.ai")
		respond('{"answer":{"leader":"Qdrant"},"citations":[]}')
		reply = exa.answer({query = "Which vector DB leads?", model = "exa-pro", systemPrompt = "Be brief", userLocation = "GB",
			outputSchema = schema})
		posted("/answer", {query = "Which vector DB leads?", model = "exa-pro", systemPrompt = "Be brief", userLocation = "GB",
			outputSchema = schema})
		assert(reply.answer.leader == "Qdrant" and json.encode(reply.citations) == "[]")
		assert(#responses == 0, "every queued answer was used")
	end,
}
