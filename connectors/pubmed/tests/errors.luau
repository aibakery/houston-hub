-- With an API key, which the proxy adds: invalid input never reaches NCBI, and NCBI's errors, slow answers and bad
-- bodies map to clear failures.
return {
	scenario = {publisher = {}, config = {api_key = "synthetic-ncbi-key"}, auth_method = "", auth_config = {}},
	configure = function()
		calls = 0
		status = 200
		payload = "{}"
		responseHeaders = {}
		http = {request = function(req)
			calls += 1
			assert(not string.find(req.url .. (req.body or ""), "api_key", 1, true), "the proxy adds the key")
			-- A table stands for a failure while waiting for headers, such as a timeout or a refused origin.
			if requestError then error(requestError, 0) end
			-- A body whose read fails stands in for a dropped connection or a cancelled invocation.
			local body = if readError
				then {readAll = function() error(readError, 0) end, readPrefix = function() error(readError, 0) end, close = function() end}
				else fixture.reader(payload)
			return fixture.operation({statusCode = status, headers = responseHeaders, body = body})
		end}
	end,
	run = function(pubmed)
		local function rejected(fn, expected)
			local before = calls
			local ok, err = pcall(fn)
			assert(not ok and string.find(tostring(err), expected, 1, true), "wrong validation error: " .. tostring(err))
			assert(calls == before, "invalid input reached NCBI")
		end
		local function search(opts) return function() pubmed.searchArticles(opts) end end

		rejected(function() pubmed.searchArticles("crispr") end, "searchArticles options must be a table")
		rejected(search({}), "term must be a PubMed query of at most 4000 bytes")
		-- NCBI answers a blank term with "Search is temporarily unavailable".
		rejected(search({term = "  \n"}), "not only spaces")
		rejected(search({term = string.rep("a", 4001)}), "at most 4000 bytes")
		rejected(search({term = 42}), "term must be a PubMed query")
		rejected(search({term = "x", query = "y"}), "unknown option query")
		rejected(search({term = "x", db = "pmc"}), "unknown option db")
		rejected(search({term = "x", usehistory = "y"}), "unknown option usehistory")
		for _, value in {-1, 9999, 1.5, "10"} do
			rejected(search({term = "x", retstart = value}), "retstart must be an integer from 0 to 9998")
		end
		for _, value in {-1, 10000, 0.5, false} do
			rejected(search({term = "x", retmax = value}), "retmax must be an integer from 0 to 9999")
		end
		-- NCBI ignores an unknown sort and returns relevance order.
		for _, value in {"date", "pub+date", "author", 1} do
			rejected(search({term = "x", sort = value}), "sort must be one of relevance, pub_date, Author, JournalName")
		end
		rejected(search({term = "x", mindate = "2024"}), "mindate and maxdate go together")
		rejected(search({term = "x", maxdate = "2024"}), "mindate and maxdate go together")
		for _, value in {"2024-01-01", "24", "2024/1", "2024/01/1", 2024} do
			rejected(search({term = "x", mindate = value, maxdate = "2025"}), "mindate must be YYYY, YYYY/MM or YYYY/MM/DD")
		end
		rejected(search({term = "x", mindate = "2024", maxdate = "2025/13/01x"}), "maxdate must be YYYY")
		-- NCBI answers impossible or reversed dates with no matches rather than an error.
		for _, value in {"2024/13", "2024/00", "2024/01/00", "2024/01/32", "2024/04/31", "2023/02/29", "1900/02/29", "0000"} do
			rejected(search({term = "x", mindate = value, maxdate = "2025"}), "mindate must be YYYY, YYYY/MM or YYYY/MM/DD")
		end
		rejected(search({term = "x", mindate = "2025", maxdate = "2024/12/31"}), "mindate must not be after maxdate")
		rejected(search({term = "x", mindate = "2024/06/02", maxdate = "2024/06/01"}), "mindate must not be after maxdate")
		for _, value in {0, 100001, 1.5, "30"} do
			rejected(search({term = "x", reldate = value}), "reldate must be an integer from 1 to 100000")
		end
		rejected(search({term = "x", datetype = "pdat"}), "datetype applies only with mindate and maxdate, or reldate")
		rejected(search({term = "x", reldate = 7, datetype = "crdt"}), "datetype must be one of edat, pdat, mdat")

		for _, ids in {{}, "", ",, ", {"abc"}, {"0"}, {0}, {-5}, {1.5}, {"1234567890"}, {"12a"}, {"01"}, {true}, {[1] = 1, [3] = 3},
			{{1}}, "1;2"} do
			rejected(function() pubmed.getSummaries(ids) end, "ids must")
		end
		rejected(function() pubmed.getSummaries() end, "ids must list 1 to 200 PMIDs")
		rejected(function() pubmed.getFullText() end, "id must be a PMCID")
		rejected(function() pubmed.getSummaries({[1] = 1, [3] = 3}) end, "ids must be a dense array")
		rejected(function() pubmed.getSummaries({id = 1}) end, "ids must be a dense array")
		rejected(function() pubmed.getRecords("12a") end, "ids must contain PMIDs, positive integers such as 31452104")
		local many = {}
		for i = 1, 201 do many[i] = i end
		rejected(function() pubmed.getRecords(many) end, "ids must list 1 to 200 PMIDs")
		rejected(function() pubmed.getLinks(table.move(many, 1, 101, 1, {}), "pubmed_pubmed") end, "ids must list 1 to 100 PMIDs")
		rejected(function() pubmed.getLinks(1) end, "linkname must be one of pubmed_pubmed, pubmed_pubmed_reviews, "
			.. "pubmed_pubmed_citedin, pubmed_pubmed_refs, pubmed_pmc, pubmed_pmc_refs")
		rejected(function() pubmed.getLinks(1, "pubmed_gene") end, "linkname must be one of")
		rejected(function() pubmed.getLinks(1, "pubmed_pubmed", {scores = "yes"}) end, "scores must be true or false")
		rejected(function() pubmed.getLinks(1, "pubmed_pubmed", {cmd = "prlinks"}) end, "getLinks received an unknown option cmd")
		rejected(function() pubmed.getLinks(1, "pubmed_pubmed", "scores") end, "getLinks options must be a table")
		for _, id in {"PMC", "PMC0", "PMC12a", "PMC1/../x", "PMC12345678901", "NIHMS123", "", "0", 0, 1.5, "1234567890", {"PMC1"}} do
			rejected(function() pubmed.getFullText(id) end, "id must be a PMCID such as PMC4412151 or a PMID such as 25977807")
		end

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
		local find = search({term = "crispr"})
		local function summaries() pubmed.getSummaries(1) end
		local function records() pubmed.getRecords(1) end
		local function links() pubmed.getLinks(1, "pubmed_pubmed") end
		local function fullText() pubmed.getFullText("PMC1") end
		local JSON = {["content-type"] = {"application/json"}}

		upstream(429, '{"error":"API rate limit exceeded","api-key":"203.0.113.9","count":"4","limit":"3"}', {["retry-after"] = {"2"}}, find,
			{"NCBI HTTP 429: API rate limit exceeded; retry after 2s", '"retryable":true', '"upstream_status":429'})
		upstream(429, "<html><title>Too Many Requests</title></html>", {["retry-after"] = {"Thu, 29 Oct 2026 20:00:00 GMT"}}, fullText,
			{"NCBI HTTP 429; retry after Thu, 29 Oct 2026 20:00:00 GMT", '"retryable":true'}, "GMTs")
		upstream(400, '{"error":"API key invalid","api-key":"[redacted]","type":"invalid","status":"unknown"}', {}, summaries,
			{"NCBI HTTP 400: API key invalid", '"retryable":false'})
		upstream(400, '<?xml version="1.0"?>\n<eFetchResult>\n\t<ERROR>Database:   nope - is not supported</ERROR>\n</eFetchResult>', {}, records,
			{"NCBI HTTP 400: Database: nope - is not supported", '"retryable":false'})
		upstream(414, "<html><body>Request-URI Too Long</body></html>", {}, links, {"NCBI HTTP 414", '"retryable":false'}, "Request-URI")
		upstream(400, '{"error":"' .. string.rep("y", 1000) .. '"}', {}, find, {"NCBI HTTP 400: " .. string.rep("y", 300)}, string.rep("y", 301))
		upstream(500, "", {}, find, {"NCBI HTTP 500", '"retryable":true'})
		upstream(502, "<html>Bad Gateway</html>", {}, fullText, {"NCBI HTTP 502", '"retryable":true'}, "Gateway")
		upstream(503, "", {["retry-after"] = {"30"}}, records, {"NCBI HTTP 503; retry after 30s", '"retryable":true'})
		upstream(301, "", {location = {"https://www.ncbi.nlm.nih.gov/elsewhere"}}, find, {"NCBI HTTP 301: unexpected redirect", '"retryable":false'}, "elsewhere")

		-- Errors inside a successful answer: known input rejections are final, other failures are server faults.
		upstream(200, '{"esearchresult":{"ERROR":"Search Backend failed: An error occurred while processing request.\\nStatus: 500."}}', {}, find,
			{"NCBI: Search Backend failed: An error occurred while processing request. Status: 500.", '"retryable":true', '"upstream_status":200'})
		upstream(200, '{"esummaryresult":["Unable to obtain query #1"]}', {}, summaries, {"NCBI: Unable to obtain query #1", '"retryable":true'})
		upstream(200, '{"error":"Too many UIDs in request. Maximum number of UIDs is 500 for JSON format output."}', {}, summaries,
			{"NCBI: Too many UIDs in request.", '"retryable":false'})
		upstream(200, '{"ERROR":"Invalid linkname"}', {}, links, {"NCBI: Invalid linkname", '"retryable":false'})
		-- NCBI answers a query of only parentheses this way: it names the empty term after its generic outage text.
		upstream(200, '{"esearchresult":{"ERROR":"Search Backend failed: An error occurred while processing request. Status: 500. Details: Search is temporarily unavailable. Please try again later. Details: Empty Term in the request"}}', {},
			find, {"Empty Term in the request", '"retryable":false'})
		upstream(200, '{"error":"API key not wellformed"}', {}, summaries, {"NCBI: API key not wellformed", '"retryable":false'})
		upstream(200, "<html>maintenance</html>", {}, find, {"NCBI returned an invalid JSON object", '"retryable":false'}, "maintenance")
		upstream(200, "[]", {}, summaries, {"NCBI returned an invalid JSON object"})
		-- ELink stops after about 15 s and then sends an empty 200.
		upstream(200, "", {}, links, {"NCBI returned an empty answer; retry, or pass fewer ids", '"retryable":true'})
		upstream(200, '{"result":"none"}', {}, summaries, {"NCBI returned an unexpected answer", '"retryable":false'})
		upstream(200, '{"header":{}}', {}, links, {"NCBI returned an unexpected answer"})
		upstream(200, "<eFetchResult><ERROR>Backend unavailable</ERROR></eFetchResult>", {}, records,
			{"NCBI: Backend unavailable", '"retryable":true'})
		upstream(200, "<html><body>Maintenance</body></html>", {}, records, {"NCBI returned an unexpected MEDLINE answer", '"retryable":false'}, "Maintenance")
		upstream(200, "TI  - No PMID\n", {}, records, {"NCBI returned a MEDLINE record without a PMID", '"retryable":false'})

		upstream(200, "[Error] : No result can be found. <BR><HR><B> - https://www.ncbi.nlm.nih.gov/research/bionlp/RESTful/</B>",
			{["content-type"] = {"text/html"}}, fullText,
			{"PMC has no open-access full text for PMC1; only open-access and author manuscript articles have one", '"retryable":false'}, "<BR>")
		upstream(200, "<html>Service unavailable</html>", {["content-type"] = {"text/html"}}, fullText,
			{"NCBI returned an unexpected full-text answer"}, "Service")
		upstream(200, "[]", JSON, fullText, {"NCBI returned an unexpected full-text answer"})
		upstream(200, '[{"documents":[{"id":"PMC1"}]}]', JSON, fullText, {"unexpected full-text answer"})
		upstream(200, '{"documents":[]}', JSON, fullText, {"unexpected full-text answer"})

		upstream(200, '{"x":"' .. string.rep("z", 4 * 1024 * 1024) .. '"}', JSON, fullText,
			{"NCBI returned more data than one call can hold; this article's full text is too large for one call", '"retryable":false'}, "limit")
		upstream(200, string.rep("PMID- 1\n\n", 600 * 1024), {}, records, {"more data than one call can hold; request fewer IDs"})
		upstream(200, '{"esearchresult":{"x":"' .. string.rep("z", 4 * 1024 * 1024) .. '"}}', {}, find, {"more data than one call can hold; lower retmax"})

		requestError = {code = "timeout", message = "request deadline"}
		upstream(200, "", {}, find, {"NCBI did not answer within 8 s; retry", '"retryable":true'})
		-- Other request failures pass through unchanged; the stand-in table loses its message across the export boundary.
		requestError = {code = "access_denied", message = "origin not allowed"}
		upstream(200, "", {}, fullText, {"error"}, "retryable")
		requestError = nil
		readError = {code = "timeout", message = "await timed out"}
		upstream(200, "", {}, summaries, {"NCBI did not finish sending its answer within 19 s; retry", '"retryable":true'})
		readError = {code = "io_error", message = "connection reset by peer"}
		upstream(200, "", {}, links, {"NCBI response failed: connection reset by peer", '"retryable":true'}, "more data")
		-- An error body that stalls or breaks still gives the structured failure.
		upstream(503, "", {}, find, {"NCBI HTTP 503", '"retryable":true', '"upstream_status":503'}, "reset")
		readError = {code = "timeout", message = "await timed out"}
		upstream(400, "", {}, records, {"NCBI HTTP 400", '"retryable":false', '"upstream_status":400'}, "timed out")
		readError = {code = "cancelled", message = "invocation cancelled"}
		local before = calls
		local ok, err = pcall(records)
		-- A stand-in error loses its native identity across the export boundary; it must still not become an upstream failure.
		assert(not ok and not string.find(tostring(err), "retryable", 1, true), "cancellation became an upstream error: " .. tostring(err))
		assert(calls == before + 1)
		readError = nil
	end,
}
