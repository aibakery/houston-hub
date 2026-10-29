-- Invalid input never reaches a provider, and provider errors, slow answers and bad bodies map to clear failures.
return {
	scenario = {publisher = {}, config = {}, auth_method = "", auth_config = {}},
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
	run = function(rxiv)
		local function rejected(fn, expected)
			local before = calls
			local ok, err = pcall(fn)
			assert(not ok and string.find(tostring(err), expected, 1, true), "wrong validation error: " .. tostring(err))
			assert(calls == before, "invalid input reached a provider")
		end
		local function call(name, opts) return function() rxiv[name](opts) end end
		local RANGE = {server = "biorxiv", from = "2025-03-01", to = "2025-03-07"}
		local function with(base, extra)
			local out = table.clone(base)
			for key, value in extra do out[key] = value end
			return out
		end

		for _, name in {"searchPreprints", "listPreprints", "getPreprint", "getPublication", "listPublications", "downloadPdf"} do
			rejected(call(name, nil), name .. " takes one options table")
			rejected(call(name, "x"), name .. " takes one options table")
		end
		for _, value in {"bioRxiv", "arxiv", "", 1} do
			rejected(call("listPreprints", with(RANGE, {server = value})), "server must be biorxiv or medrxiv")
			rejected(call("getPreprint", {server = value, doi = "10.1101/339747"}), "server must be biorxiv or medrxiv")
			rejected(call("searchPreprints", {query = "x", server = value}), "server must be biorxiv or medrxiv")
		end
		rejected(call("getPreprint", {doi = "10.1101/339747"}), "server must be biorxiv or medrxiv")

		-- Dates: real calendar days in order.
		for _, value in {"2025-3-1", "2025/03/01", "2025-02-29", "2024-02-30", "2025-13-01", "2025-00-10", "2025-04-31", "1900-02-29", 20250301} do
			rejected(call("listPreprints", with(RANGE, {from = value})), "from must be a date such as 2025-03-21")
		end
		rejected(call("listPublications", with(RANGE, {to = "2025-03-07x"})), "to must be a date")
		rejected(call("listPreprints", with(RANGE, {from = "2025-03-08"})), "from must not be after to")
		rejected(call("listPreprints", {server = "biorxiv", from = "2025-03-01"}), "from and to go together")
		rejected(call("searchPreprints", {query = "x", to = "2025-03-01"}), "from and to go together")
		rejected(call("searchPreprints", {query = "x", from = "2025-03-02", to = "2025-03-01"}), "from must not be after to")

		-- Paging bounds come from the API's page sizes.
		for _, value in {0, 91, 1.5, "30", false} do
			rejected(call("listPreprints", with(RANGE, {limit = value})), "limit must be an integer from 1 to 90")
		end
		rejected(call("listPublications", with(RANGE, {limit = 301})), "limit must be an integer from 1 to 300")
		for _, value in {-1, 2 ^ 31, 0.5, "30"} do
			rejected(call("listPreprints", with(RANGE, {cursor = value})), "cursor must be an integer from 0 to 2147483647")
		end
		-- The API would silently ignore an unknown category and list every one.
		for _, value in {"neurology", "cell-biology", "all", 5} do
			rejected(call("listPreprints", with(RANGE, {category = value})), "category must be one of the bioRxiv categories: animal behavior")
		end
		rejected(call("listPreprints", with(RANGE, {server = "medrxiv", category = "neuroscience"})), "category must be one of the medRxiv categories")
		rejected(call("listPublications", with(RANGE, {category = "neuroscience"})), "listPublications received an unknown option category")
		for _, value in {"00k4n6c3", "00K4N6C32", "10k4n6c32", "00k4n6c3x", "https://ror.org/", "ror.org/00k4n6c32", 1} do
			rejected(call("listPreprints", with(RANGE, {funder = value})), "funder must be a ROR ID such as 00k4n6c32")
		end
		rejected(call("listPreprints", with(RANGE, {interval = "30d"})), "listPreprints received an unknown option interval")

		for _, value in {"339747", "10.1101/339747v2", "doi:10.1101/339747", "https://doi.org/10.1101/339747", "10.1371/journal.pone.1",
			"10.1101/", "10.1101/2025.03.", "10.1101/../x", "10.1101/1/2", "10.1101/" .. string.rep("1", 41), 10.1101} do
			rejected(call("getPreprint", {server = "biorxiv", doi = value}), "doi must be a bare bioRxiv or medRxiv DOI")
			rejected(call("downloadPdf", {server = "biorxiv", doi = value, version = 1, session_path = "a.pdf"}), "doi must be a bare")
		end
		rejected(call("getPreprint", {server = "biorxiv", doi = "10.1101/1", version = 1}), "getPreprint received an unknown option version")
		for _, value in {"10.1093/nar/gkaf118", "10.1/x", "10.1101/a b", "10.1101/x?y", "10.1101/x%2F", "10.1101/..", "https://doi.org/10.1101/1"} do
			rejected(call("getPublication", {server = "biorxiv", doi = value}), "doi must be a bare DOI with one slash")
		end

		rejected(call("searchPreprints", {}), "query must be a Europe PMC query of at most 2000 bytes")
		rejected(call("searchPreprints", {query = " \n"}), "not only spaces")
		rejected(call("searchPreprints", {query = string.rep("a", 2001)}), "at most 2000 bytes")
		-- Unbalanced parentheses or quotes could escape the preprint filter.
		for _, value in {"x) OR (y", "(x", 'x"', "x)", '"x\\"', "x\\"} do
			rejected(call("searchPreprints", {query = value}), "query must balance its parentheses and double quotes")
		end
		-- Europe PMC answers an unknown sort with a misleading 503.
		for _, value in {"date", "P_PDATE_D desc", "CITED asc", 1} do
			rejected(call("searchPreprints", {query = "x", sort = value}), "sort must be one of relevance, FIRST_PDATE_D desc")
		end
		rejected(call("searchPreprints", {query = "x", resultType = "idlist"}), "resultType must be one of core, lite")
		for _, value in {0, 501, 2.5} do
			rejected(call("searchPreprints", {query = "x", limit = value}), "limit must be an integer from 1 to 500")
		end
		for _, value in {"", "a b", "a&b", string.rep("A", 257), 1} do
			rejected(call("searchPreprints", {query = "x", cursorMark = value}), "cursorMark must be the nextCursorMark")
		end
		rejected(call("searchPreprints", {query = "x", synonym = true}), "searchPreprints received an unknown option synonym")

		local PDF = {server = "biorxiv", doi = "10.1101/339747", version = 4, session_path = "a.pdf"}
		for _, value in {0, 1000, 1.5, "v4", "", false} do
			rejected(call("downloadPdf", with(PDF, {version = value})), "version must be an integer from 1 to 999")
		end
		rejected(call("downloadPdf", {server = "biorxiv", doi = "10.1101/339747", session_path = "a.pdf"}), "version must be an integer")
		rejected(call("downloadPdf", with(PDF, {session_path = ""})), "session_path must name a session file")
		rejected(call("downloadPdf", with(PDF, {format = "xml"})), "downloadPdf received an unknown option format")

		local function upstream(code, body, headers, fn, expected, absent)
			status, payload, responseHeaders = code, body, headers
			local before = calls
			local ok, err = pcall(fn)
			for _, text in expected do
				assert(not ok and string.find(tostring(err), text, 1, true), "missing " .. text .. " in " .. tostring(err))
			end
			if absent then assert(not string.find(tostring(err), absent, 1, true), "unexpected " .. absent .. " in " .. tostring(err)) end
			assert(calls == before + 1, "a failed request was repeated")
		end
		local list = call("listPreprints", RANGE)
		local get = call("getPreprint", {server = "medrxiv", doi = "10.1101/2020.09.09.20191205"})
		local links = call("getPublication", {server = "biorxiv", doi = "10.1101/339747"})
		local search = call("searchPreprints", {query = "x"})
		local resume = call("searchPreprints", {query = "x", cursorMark = "AoIIQ=="})

		-- The API answers HTTP 200 with a status for errors: rejections of input are final, anything else a fault.
		upstream(200, '{"messages":[{"status":"no posts found"}], "collection":[]}', {}, get,
			{"medRxiv has no preprint with DOI 10.1101/2020.09.09.20191205; check the server", '"retryable":false', '"upstream_status":200'})
		upstream(200, '{"messages":[{"status":"Both dates must be in yyyy-mm-dd format"}], "collection":[]}', {}, list,
			{"bioRxiv API: Both dates must be in yyyy-mm-dd format", '"retryable":false'})
		upstream(200, '{"messages":[{"status":"DOI not recognizable"}], "collection":[]}', {}, links, {"bioRxiv API: DOI not recognizable", '"retryable":false'})
		upstream(200, '{"messages":[{"status":"Server not recognized"}], "collection":[]}', {}, get, {"Server not recognized", '"retryable":false'})
		upstream(200, '{"messages":[{"status":"funder value not found"}], "collection":[]}', {}, call("listPreprints", with(RANGE, {funder = "00k4n6c32"})),
			{"bioRxiv API: funder value not found", '"retryable":false'})
		upstream(200, '{"messages":[{"status":"database   unavailable"}], "collection":[]}', {}, list, {"bioRxiv API: database unavailable", '"retryable":true'})
		upstream(200, '{"messages":[{"status":"ok","total":"many"}], "collection":[]}', {}, list, {"bioRxiv API returned a page without its total"})
		upstream(200, '{"messages":[], "collection":[]}', {}, get, {"bioRxiv API returned an unexpected answer", '"retryable":false'})
		upstream(200, '{"messages":[{"status":"ok"}]}', {}, links, {"bioRxiv API returned an unexpected answer"})
		upstream(200, "<html>Maintenance</html>", {}, list, {"bioRxiv API returned an invalid JSON object", '"retryable":false'}, "Maintenance")
		upstream(200, "[]", {}, get, {"bioRxiv API returned an invalid JSON object"})
		upstream(404, "<!DOCTYPE HTML><title>404 Not Found</title>", {}, get, {"bioRxiv API HTTP 404", '"retryable":false', '"upstream_status":404'}, "DOCTYPE")
		upstream(503, "", {["retry-after"] = {"120"}}, list, {"bioRxiv API HTTP 503; retry after 120s", '"retryable":true'})
		upstream(301, "", {location = {"https://example.com/"}}, links, {"bioRxiv API HTTP 301: unexpected redirect", '"retryable":false'}, "example")
		upstream(200, '{"x":"' .. string.rep("z", 4 * 1024 * 1024) .. '"}', {}, list,
			{"bioRxiv API returned more data than one call can hold; call again with a lower limit", '"retryable":false'}, "limit_exceeded")

		upstream(503, '{"errCode":503,"errMsg":"Search service is temporarily unavailable. Please retry later."}', {}, search,
			{"Europe PMC HTTP 503: Search service is temporarily unavailable. Please retry later.", '"retryable":true'}, "cursorMark")
		upstream(503, '{"errCode":503,"errMsg":"Search service is temporarily unavailable."}', {}, resume,
			{"Europe PMC HTTP 503: Search service is temporarily unavailable.; if this persists, the cursorMark may not belong to this query"})
		upstream(429, "", {["retry-after"] = {"Thu, 29 Oct 2026 20:00:00 GMT"}}, search,
			{"Europe PMC HTTP 429; retry after Thu, 29 Oct 2026 20:00:00 GMT", '"retryable":true'}, "GMTs")
		upstream(400, '{"errCode":400,"errMsg":"' .. string.rep("y", 1000) .. '"}', {}, search,
			{"Europe PMC HTTP 400: " .. string.rep("y", 300), '"retryable":false'}, string.rep("y", 301))
		upstream(200, '{"hitCount":"3","resultList":{"result":[]}}', {}, search, {"Europe PMC returned an unexpected answer", '"retryable":false'})
		upstream(200, '{"hitCount":3}', {}, search, {"Europe PMC returned an unexpected answer"})
		upstream(200, '{"hitCount":1,"resultList":{"result":[{"abstractText":"' .. string.rep("w", 4 * 1024 * 1024) .. '"}]}}', {}, search,
			{"Europe PMC returned more data than one call can hold; call again with a lower limit or resultType lite", '"retryable":false'})

		requestError = {code = "timeout", message = "request deadline"}
		upstream(200, "", {}, search, {"Europe PMC did not answer within 8 s; retry", '"retryable":true'})
		upstream(200, "", {}, call("listPreprints", with(RANGE, {limit = 90})), {"bioRxiv API did not answer within 9 s; retry", '"retryable":true'})
		-- Other request failures pass through unchanged; the stand-in table loses its message across the export boundary.
		requestError = {code = "access_denied", message = "origin not allowed"}
		upstream(200, "", {}, get, {"error"}, "retryable")
		requestError = nil
		readError = {code = "timeout", message = "await timed out"}
		upstream(200, "", {}, get, {"bioRxiv API did not finish sending its answer within 19 s; retry", '"retryable":true'})
		upstream(200, "", {}, call("listPreprints", with(RANGE, {limit = 31})), {"did not finish sending its answer within 3 s"})
		readError = {code = "io_error", message = "connection reset by peer"}
		upstream(200, "", {}, search, {"Europe PMC response failed: connection reset by peer", '"retryable":true'}, "more data")
		-- An error body that stalls or breaks still gives the structured failure.
		upstream(502, "", {}, list, {"bioRxiv API HTTP 502", '"retryable":true', '"upstream_status":502'}, "reset")
		readError = {code = "timeout", message = "await timed out"}
		upstream(400, "", {}, search, {"Europe PMC HTTP 400", '"retryable":false', '"upstream_status":400'}, "timed out")
		readError = {code = "cancelled", message = "invocation cancelled"}
		for _, fn in {list, search, call("listPreprints", with(RANGE, {limit = 60}))} do
			local before = calls
			local ok, err = pcall(fn)
			-- A stand-in error loses its native identity across the export boundary; it must still not become an upstream failure.
			assert(not ok and not string.find(tostring(err), "retryable", 1, true), "cancellation became an upstream error: " .. tostring(err))
			assert(calls == before + 1)
		end
		readError = nil
	end,
}
