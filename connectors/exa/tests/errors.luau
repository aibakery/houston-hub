-- Invalid input never reaches Exa, and Exa's errors, slow answers and bad bodies map to clear failures.
return {
	scenario = {publisher = {}, config = {}, auth_method = "api_key", auth_config = {token = "synthetic-exa-key"}},
	configure = function()
		calls = 0
		status = 200
		payload = "{}"
		responseHeaders = {}
		http = {request = function(req)
			calls += 1
			-- A table stands for a failure while waiting for headers, such as a timeout or a refused origin.
			if requestError then error(requestError, 0) end
			-- A body whose read fails stands in for a dropped connection or a cancelled invocation.
			local body = if readError
				then {readAll = function() error(readError, 0) end, readPrefix = function() error(readError, 0) end, close = function() end}
				else fixture.reader(payload)
			return fixture.operation({statusCode = status, headers = responseHeaders, body = body})
		end}
	end,
	run = function(exa)
		local function rejected(fn, expected)
			local before = calls
			local ok, err = pcall(fn)
			assert(not ok and string.find(tostring(err), expected, 1, true), "wrong validation error: " .. tostring(err))
			assert(calls == before, "invalid input reached Exa")
		end
		local function search(opts) return function() exa.search(opts) end end
		local function contents(opts) return function() exa.getContents(opts) end end

		rejected(function() exa.search("vector databases") end, "search must be an options table")
		rejected(function() exa.search() end, "search must be an options table")
		rejected(search({}), "search requires query")
		rejected(search({query = " \n"}), "query must be a string of at most 4096 bytes, not only spaces")
		rejected(search({query = string.rep("a", 4097)}), "query must be a string of at most 4096 bytes")
		rejected(search({query = 42}), "query must be a string")
		rejected(search({query = "x", q = "y"}), "search received an unknown option q")
		rejected(search({"x"}), "search received an unknown option 1")
		-- Deprecated and unsupported options are refused rather than sent.
		for _, field in {"includeText", "startCrawlDate", "stream", "compliance", "userIdentifier", "context"} do
			rejected(search({query = "x", [field] = true}), "search received an unknown option " .. field)
		end
		for _, value in {"fast", "instant", "deep-reasoning", "neural", 1} do
			rejected(search({query = "x", type = value}), "type must be one of auto, lite, deep-lite, deep")
		end
		for _, value in {0, 26, 1.5, "10", 100} do
			rejected(search({query = "x", numResults = value}), "numResults must be an integer from 1 to 25")
		end
		for _, value in {"research paper", "pdf", "tweet", "github", ""} do
			rejected(search({query = "x", category = value}), "category must be one of company, people, news, publication")
		end
		rejected(search({query = "x", includeDomains = {}}), "includeDomains must be a dense array of 1 to 1200 entries")
		rejected(search({query = "x", includeDomains = "arxiv.org"}), "includeDomains must be an array")
		rejected(search({query = "x", includeDomains = {[1] = "a", [3] = "c"}}), "includeDomains must be a dense array")
		rejected(search({query = "x", excludeDomains = {domain = "a"}}), "excludeDomains must be a dense array")
		rejected(search({query = "x", excludeDomains = {"a", ""}}), "excludeDomains[2] must be a URL or host")
		for _, value in {"arxiv .org", "arxiv.org\n", "\tgithub.com"} do
			rejected(search({query = "x", includeDomains = {value}}), "includeDomains[1] must be a URL or host of at most 2048 bytes without spaces")
		end
		local domains = {}
		for i = 1, 1201 do domains[i] = "d" .. i .. ".example" end
		rejected(search({query = "x", includeDomains = domains}), "includeDomains must be a dense array of 1 to 1200 entries")
		for _, value in {"2026-1-01", "01/31/2026", "2026-01-31 12:00", "2026-01-31T12:00", "2026-01-31T12:00Z", "2026-01-31T12:00::Z", "2026-01-31T12:00:001234Z", "2026-01-31T99:99:99Z", "2026-01-31T24:00:00Z", "2026-01-31T12:60:00Z", "2026-01-31T12:00:60Z", "2026-01-31T12:00:00.Z", "2026-01-31T12:00:00+24:00", "2026-01-31T12:00:00+01:60", "2026-01-31T12:00:00+0100", "2026-02-31", "2025-02-29", "2026-04-31", "1900-02-29", "2026-13-01", "2026-00-10", "2026-01-32", "2026-01-31T12:00:00", "yesterday", 20260131} do
			rejected(search({query = "x", startPublishedDate = value}), "startPublishedDate must be an ISO 8601 date")
		end
		rejected(search({query = "x", endPublishedDate = "2026"}), "endPublishedDate must be an ISO 8601 date")
		for _, value in {"USA", "u", 1, {country = "USA"}, {latitude = 91, longitude = 0}, {latitude = 0, longitude = -181},
			{latitude = 1}, {}, {country = "US", city = "SF"}} do
			rejected(search({query = "x", userLocation = value}), "userLocation")
		end
		rejected(search({query = "x", moderation = "yes"}), "moderation must be true or false")
		rejected(search({query = "x", objective = string.rep("o", 4097)}), "objective must be a string of at most 4096 bytes")
		rejected(search({query = "x", additionalQueries = {}}), "additionalQueries must be a dense array of 1 to 10 entries")
		rejected(search({query = "x", additionalQueries = {"a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k"}}), "1 to 10 entries")
		for _, value in {{}, {"text"}, "text", true} do
			rejected(search({query = "x", outputSchema = value}), "outputSchema must be a JSON Schema object")
		end

		-- Contents options, nested names included.
		rejected(search({query = "x", contents = true}), "contents must be an options table")
		rejected(search({query = "x", contents = {subpages = 2}}), "contents received an unknown option subpages")
		rejected(search({query = "x", contents = {livecrawl = "always"}}), "contents received an unknown option livecrawl")
		rejected(search({query = "x", contents = {text = "yes"}}), "contents.text must be an options table")
		rejected(search({query = "x", contents = {text = {maxCharacters = 500001}}}), "contents.text.maxCharacters must be an integer from 1 to 500000")
		rejected(search({query = "x", contents = {text = {maxCharacters = 0}}}), "contents.text.maxCharacters must be an integer from 1 to 500000")
		rejected(search({query = "x", contents = {text = {verbosity = "max"}}}), "contents.text.verbosity must be one of compact, standard, full")
		rejected(search({query = "x", contents = {text = {includeSections = {"main"}}}}), "contents.text.includeSections[1] must be one of header")
		rejected(search({query = "x", contents = {text = {includeHtmlTags = 1}}}), "contents.text.includeHtmlTags must be true or false")
		rejected(search({query = "x", contents = {highlights = {numSentences = 2}}}), "contents.highlights received an unknown option numSentences")
		rejected(search({query = "x", contents = {highlights = {dynamic = true}}}), "contents.highlights received an unknown option dynamic")
		rejected(search({query = "x", contents = {highlights = {maxCharacters = 10001}}}), "contents.highlights.maxCharacters must be an integer from 1 to 10000")
		rejected(search({query = "x", contents = {summary = {schema = {}}}}), "contents.summary.schema must be a JSON Schema object")
		rejected(search({query = "x", contents = {extras = {links = 21}}}), "contents.extras.links must be an integer from 0 to 20")
		rejected(search({query = "x", contents = {extras = {codeBlocks = 1}}}), "contents.extras received an unknown option codeBlocks")
		rejected(search({query = "x", contents = {maxAgeHours = 721}}), "contents.maxAgeHours must be an integer from -1 to 720")
		rejected(search({query = "x", contents = {maxAgeHours = -2}}), "contents.maxAgeHours must be an integer from -1 to 720")
		rejected(search({query = "x", contents = {livecrawlTimeout = 8001}}), "contents.livecrawlTimeout must be an integer from 1 to 8000")
		rejected(search({query = "x", contents = {snapshotAsOf = "last week"}}), "contents.snapshotAsOf must be an ISO 8601 date")
		-- The text budget counts Exa's default of 10 results.
		rejected(search({query = "x", contents = {text = {maxCharacters = 50001}}}), "text.maxCharacters (default 10000) plus highlights.maxCharacters, times the number of results, must be at most 500000")
		rejected(search({query = "x", numResults = 25, contents = {text = {maxCharacters = 20001}}}), "must be at most 500000")
		rejected(search({query = "x", numResults = 25, contents = {text = {maxCharacters = 10001}, highlights = {maxCharacters = 10000}}}), "must be at most 500000")
		rejected(function() exa.findSimilar({url = "https://a.example", numResults = 11, contents = {text = {maxCharacters = 50000}}}) end,
			"must be at most 500000")

		rejected(function() exa.findSimilar({}) end, "findSimilar requires url")
		rejected(function() exa.findSimilar({url = "https://a.example/x y"}) end, "url must be a URL or host of at most 2048 bytes without spaces")
		rejected(function() exa.findSimilar({url = "https://a.example/" .. string.rep("p", 2048)}) end, "url must be a URL or host of at most 2048")
		rejected(function() exa.findSimilar({url = "https://a.example", query = "x"}) end, "findSimilar received an unknown option query")
		rejected(function() exa.findSimilar({url = "https://a.example", excludeSourceDomain = "true"}) end, "excludeSourceDomain must be true or false")
		rejected(function() exa.findSimilar({url = "https://a.example", type = "auto"}) end, "findSimilar received an unknown option type")

		rejected(contents({text = true}), "getContents requires urls")
		rejected(contents({urls = {"https://a.example"}}), "getContents requires text, highlights or summary")
		rejected(contents({urls = {"https://a.example"}, text = false}), "getContents requires text, highlights or summary")
		rejected(contents({urls = {}, text = true}), "urls must be a dense array of 1 to 25 entries")
		rejected(contents({urls = "https://a.example", text = true}), "urls must be an array")
		rejected(contents({urls = {"https://a.example", "bad url"}, text = true}), "urls[2] must be a URL or host")
		rejected(contents({ids = {"https://a.example"}, text = true}), "getContents received an unknown option ids")
		rejected(contents({urls = {"https://a.example"}, text = true, subpages = 1}), "getContents received an unknown option subpages")
		rejected(contents({urls = {"https://a.example"}, contents = {text = true}}), "getContents received an unknown option contents")
		local urls = {}
		for i = 1, 26 do urls[i] = "https://a.example/" .. i end
		rejected(contents({urls = urls, highlights = true}), "urls must be a dense array of 1 to 25 entries")
		table.remove(urls)
		rejected(contents({urls = urls, text = {maxCharacters = 20001}}), "must be at most 500000")

		rejected(function() exa.answer({}) end, "answer requires query")
		rejected(function() exa.answer({query = "x", model = "gpt-4"}) end, "model must be one of exa, exa-pro, exa-fast")
		rejected(function() exa.answer({query = "x", model = "exa-research"}) end, "model must be one of")
		rejected(function() exa.answer({query = "x", text = true}) end, "answer received an unknown option text")
		rejected(function() exa.answer({query = "x", stream = true}) end, "answer received an unknown option stream")
		rejected(function() exa.answer({query = "x", outputSchema = "json"}) end, "outputSchema must be a JSON Schema object")

		local function upstream(code, body, headers, call, expected, absent)
			status, payload, responseHeaders = code, body, headers
			local before = calls
			local ok, err = pcall(call)
			for _, text in expected do
				assert(not ok and string.find(tostring(err), text, 1, true), "missing " .. text .. " in " .. tostring(err))
			end
			if absent then assert(not string.find(tostring(err), absent, 1, true), "unexpected " .. absent .. " in " .. tostring(err)) end
			assert(calls == before + 1, "a failed request was repeated")
		end
		local find = search({query = "x"})
		local function similar() exa.findSimilar({url = "https://a.example"}) end
		local read = contents({urls = {"https://a.example"}, highlights = true})
		local function ask() exa.answer({query = "x"}) end
		local function envelope(tag, message) return '{"requestId":"a1b2c3","error":"' .. message .. '","tag":"' .. tag .. '"}' end

		upstream(401, envelope("INVALID_API_KEY", "Invalid API key."), {}, find,
			{"Exa HTTP 401 INVALID_API_KEY: Invalid API key. (request a1b2c3)", '"retryable":false', '"upstream_status":401'})
		upstream(401, "", {}, ask, {"Exa HTTP 401: check the connection's Exa API key", '"retryable":false'})
		upstream(402, envelope("NO_MORE_CREDITS", "You have run out of credits."), {}, read,
			{"Exa HTTP 402 NO_MORE_CREDITS: You have run out of credits.", '"retryable":false'})
		upstream(403, envelope("FEATURE_DISABLED", "Deep search is not enabled for your plan."), {}, find,
			{"Exa HTTP 403 FEATURE_DISABLED: Deep search", '"retryable":false'})
		upstream(400, envelope("INVALID_REQUEST_BODY", 'Not supported with type \\"lite\\": contents.summary.'), {}, find,
			{'Exa HTTP 400 INVALID_REQUEST_BODY: Not supported with type', 'lite', ': contents.summary.', '"retryable":false'})
		upstream(429, envelope("RATE_LIMIT_EXCEEDED", "Rate limit exceeded."), {["retry-after"] = {"2"}}, similar,
			{"Exa HTTP 429 RATE_LIMIT_EXCEEDED: Rate limit exceeded. (request a1b2c3); retry after 2s", '"retryable":true', '"upstream_status":429'})
		upstream(503, envelope("SERVICE_OVERLOADED", "Exa is over capacity."), {["retry-after"] = {"Fri, 30 Oct 2026 07:00:00 GMT"}}, ask,
			{"Exa HTTP 503 SERVICE_OVERLOADED: Exa is over capacity. (request a1b2c3); retry after Fri, 30 Oct 2026 07:00:00 GMT", '"retryable":true'}, "GMTs")
		upstream(500, "", {}, read, {"Exa HTTP 500", '"retryable":true'})
		upstream(502, "<html>Bad Gateway</html>", {}, find, {"Exa HTTP 502", '"retryable":true'}, "Gateway")
		upstream(504, '{"message":"timeout"}', {}, find, {"Exa HTTP 504", '"retryable":true'}, "timeout")
		upstream(400, '{"error":"' .. string.rep("y", 1000) .. '","tag":"bad tag!"}', {}, find, {"Exa HTTP 400: " .. string.rep("y", 300)}, string.rep("y", 301))
		upstream(400, '{"error":"x","tag":"bad tag!"}', {}, find, {"Exa HTTP 400: x"}, "bad tag")
		upstream(307, "", {location = {"https://elsewhere.example"}}, find, {"Exa HTTP 307: unexpected redirect", '"retryable":false'}, "elsewhere")

		upstream(200, "<html>maintenance</html>", {}, find, {"Exa returned an unexpected answer", '"retryable":false'}, "maintenance")
		upstream(200, "[]", {}, read, {"Exa returned an unexpected answer"})
		upstream(200, '{"requestId":"r"}', {}, similar, {"Exa returned an unexpected answer"})
		upstream(200, '{"results":[]}', {}, ask, {"Exa returned an unexpected answer"})
		upstream(200, '{"results":null}', {}, find, {"Exa returned an unexpected answer"})
		upstream(200, '{"results":"none"}', {}, read, {"Exa returned an unexpected answer"})
		upstream(200, '{"answer":null}', {}, ask, {"Exa returned an unexpected answer"})
		upstream(200, '{"answer":42}', {}, ask, {"Exa returned an unexpected answer"})
		upstream(200, '{"results":[' .. string.rep('{"text":"' .. string.rep("z", 1024) .. '"},', 4 * 1024) .. '{}]}', {}, find,
			{"Exa returned more than 4 MiB; request fewer results or less text", '"retryable":false'}, "limit")

		requestError = {code = "timeout", message = "request deadline"}
		upstream(200, "", {}, find, {"Exa did not answer within 23 s; Exa may still bill it", '"retryable":false'})
		-- Other request failures pass through unchanged; the stand-in table loses its message across the export boundary.
		requestError = {code = "access_denied", message = "origin not allowed"}
		upstream(200, "", {}, ask, {"error"}, "retryable")
		requestError = nil
		readError = {code = "timeout", message = "await timed out"}
		upstream(200, "", {}, read, {"Exa did not finish sending its answer within 4 s; retry", '"retryable":true'})
		readError = {code = "io_error", message = "connection reset by peer"}
		upstream(200, "", {}, similar, {"Exa response failed: connection reset by peer", '"retryable":true'})
		-- An error body that stalls or breaks still gives the structured failure.
		upstream(503, "", {}, find, {"Exa HTTP 503", '"retryable":true', '"upstream_status":503'}, "reset")
		readError = {code = "timeout", message = "await timed out"}
		upstream(402, "", {}, ask, {"Exa HTTP 402", '"retryable":false', '"upstream_status":402'}, "timed out")
		readError = {code = "cancelled", message = "invocation cancelled"}
		local before = calls
		local ok, err = pcall(find)
		-- A stand-in error loses its native identity across the export boundary; it must still not become an upstream failure.
		assert(not ok and not string.find(tostring(err), "retryable", 1, true), "cancellation became an upstream error: " .. tostring(err))
		assert(calls == before + 1)
		readError = nil
	end,
}
