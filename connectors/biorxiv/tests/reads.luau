-- Each export sends exact requests to the bioRxiv API or Europe PMC, pages within its limits and returns the providers' data.
return {
	scenario = {publisher = {}, config = {}, auth_method = "", auth_config = {}},
	configure = function()
		requests, responses = {}, {}
		http = {request = function(req)
			table.insert(requests, req)
			assert(req.method == "GET" and req.body == nil, "every request is a GET")
			assert(req.headers.Authorization == nil and req.headers.Cookie == nil, "the public APIs take no credentials")
			assert(#responses > 0, "unexpected request: " .. req.url)
			local queued = table.remove(responses, 1)
			if queued.requestError then error(queued.requestError, 0) end
			local body = if queued.readError
				then {readAll = function() error(queued.readError, 0) end, readPrefix = function() error(queued.readError, 0) end, close = function() end}
				else fixture.reader(queued.body)
			return fixture.operation({statusCode = queued.status or 200, headers = queued.headers or {}, body = body})
		end}
		function respond(body, extra)
			local queued = extra or {}
			queued.body = body
			table.insert(responses, queued)
		end
		-- A details page of n versions numbered from first, as the API sends it with a trailing blank line.
		function details(total, first, n, extra)
			local rows = {}
			for i = first, first + n - 1 do
				table.insert(rows, {doi = "10.1101/2025.03.20." .. tostring(600000 + i), version = "1", title = "Preprint " .. tostring(i),
					date = "2025-3-2", server = "bioRxiv", published = "NA", category = "neuroscience"})
			end
			local message = {status = "ok", category = "all", interval = "2025-03-01:2025-03-07", cursor = if first == 0 then 0 else tostring(first),
				count = n, count_new_papers = "250", total = tostring(total)}
			for key, value in extra or {} do message[key] = value end
			return '{"messages":[' .. json.encode(message) .. '], "collection":' .. (if n == 0 then "[]" else json.encode(rows)) .. "}\n\n\n"
		end
	end,
	run = function(rxiv)
		local API = "https://api.biorxiv.org"
		local EPMC = "https://www.ebi.ac.uk/europepmc/webservices/rest/search?query="
		local function req(i) return requests[i] end

		local names = {}
		for name, fn in rxiv do
			assert(type(fn) == "function")
			table.insert(names, name)
		end
		table.sort(names)
		assert(table.concat(names, ",") == "downloadPdf,getPreprint,getPublication,listPreprints,listPublications,searchPreprints",
			table.concat(names, ","))
		assert(#requests == 0, "initialization made a request")

		-- Search: a query wrapped in the preprint filter for both servers, Europe PMC's defaults and an empty array.
		respond('{"version":"6.9","hitCount":0,"request":{},"resultList":{"result":[]}}')
		local found = rxiv.searchPreprints({query = "zzqx OR (a AND b)"})
		assert(req(1).url == EPMC .. "%28zzqx%20OR%20%28a%20AND%20b%29%29%20AND%20SRC%3APPR%20AND%20%28PUBLISHER%3A%22bioRxiv%22%20OR%20PUBLISHER%3A%22medRxiv%22%29"
			.. "&resultType=core&pageSize=25&format=json&cursorMark=%2A", req(1).url)
		assert(req(1).headers.Accept[1] == "application/json" and req(1).timeoutMs == 8000, "one-request calls give headers 8 s")
		assert(found.hitCount == 0 and json.encode(found.results) == "[]" and found.nextCursorMark == nil)

		-- Every option; a full page returns Europe PMC's cursor, and the caller's table is left unchanged.
		local opts = {query = 'TITLE:"base editing"', server = "medrxiv", from = "2024-02-29", to = "2024-12-31",
			sort = "FIRST_PDATE_D desc", resultType = "lite", limit = 2, cursorMark = "AoIIQIKqFyg1MjgxNzYwNA=="}
		respond('{"hitCount":5,"nextCursorMark":"AoIIQE8BmCg0OTg4NTYzMA==","resultList":{"result":[{"id":"PPR1","doi":"10.1101/2020.09.09.20191205",'
			.. '"bookOrReportDetails":{"publisher":"medRxiv"}},{"id":"PPR2","doi":"10.64898/2026.09.01.26361059"}]}}')
		found = rxiv.searchPreprints(opts)
		assert(req(2).url == EPMC .. "%28TITLE%3A%22base%20editing%22%29%20AND%20SRC%3APPR%20AND%20PUBLISHER%3A%22medRxiv%22"
			.. "%20AND%20FIRST_PDATE%3A%5B2024-02-29%20TO%202024-12-31%5D&resultType=lite&pageSize=2&format=json"
			.. "&cursorMark=AoIIQIKqFyg1MjgxNzYwNA%3D%3D&sort=FIRST_PDATE_D%20desc", req(2).url)
		assert(found.hitCount == 5 and #found.results == 2 and found.results[1].bookOrReportDetails.publisher == "medRxiv")
		assert(found.nextCursorMark == "AoIIQE8BmCg0OTg4NTYzMA==")
		assert(opts.server == "medrxiv" and opts.limit == 2, "caller options were modified")
		-- A short page is the last one; relevance is Europe PMC's default order, so it sends no sort.
		respond('{"hitCount":3,"nextCursorMark":"AoIIQE8BmCg0OTg4NTYzMA==","resultList":{"result":[{"id":"PPR3"}]}}')
		found = rxiv.searchPreprints({query = "x", server = "biorxiv", sort = "relevance", limit = 2})
		assert(req(3).url == EPMC .. "%28x%29%20AND%20SRC%3APPR%20AND%20PUBLISHER%3A%22bioRxiv%22&resultType=core&pageSize=2&format=json&cursorMark=%2A",
			req(3).url)
		assert(#found.results == 1 and found.nextCursorMark == nil)
		respond('{"hitCount":0,"resultList":{"result":[]}}')
		rxiv.searchPreprints({query = "x", resultType = "lite", limit = 1000})
		assert(string.find(req(#requests).url, "&resultType=lite&pageSize=1000&", 1, true), req(#requests).url)
		respond('{"hitCount":0,"resultList":{"result":[]}}')
		rxiv.searchPreprints({query = "x", limit = 102})
		assert(string.find(req(#requests).url, "&resultType=core&pageSize=102&", 1, true), req(#requests).url)
		-- A cursor equal to the one sent ends the search; quotes and escapes may hold parentheses.
		respond('{"hitCount":3,"nextCursorMark":"AoIIQ==","resultList":{"result":[{"id":"PPR4"}]}}')
		found = rxiv.searchPreprints({query = '"a (b" AND c\\)', limit = 1, cursorMark = "AoIIQ==", sort = "CITED desc"})
		assert(found.nextCursorMark == nil and string.find(req(#requests).url, "&sort=CITED%20desc", 1, true))

		-- A single DOI: every version, each with its PDF address.
		respond('{"messages":[{"status":"ok","category":"all"}], "collection":[{"doi":"10.1101\\/339747","version":"1","server":"bioRxiv",'
			.. '"date":"2018-06-05","published":"10.1038\\/s41592-019-0476-5"},{"doi":"10.1101\\/339747","version":"4","date":"2019-05-10"}]}')
		local preprint = rxiv.getPreprint({server = "biorxiv", doi = "10.1101/339747"})
		assert(req(#requests).url == API .. "/details/biorxiv/10.1101/339747/na/json" and req(#requests).timeoutMs == 8000, req(#requests).url)
		assert(#preprint.collection == 2 and preprint.collection[1].published == "10.1038/s41592-019-0476-5")
		assert(preprint.collection[1].pdf_url == "https://www.biorxiv.org/content/10.1101/339747v1.full.pdf")
		assert(preprint.collection[2].pdf_url == "https://www.biorxiv.org/content/10.1101/339747v4.full.pdf")
		respond('{"messages":[{"status":"ok"}], "collection":[{"doi":"10.64898\\/2026.09.01.26361059","version":"2"},{"doi":"bad","version":"1"}]}')
		preprint = rxiv.getPreprint({server = "medrxiv", doi = "10.64898/2026.09.01.26361059"})
		assert(req(#requests).url == API .. "/details/medrxiv/10.64898/2026.09.01.26361059/na/json")
		assert(preprint.collection[1].pdf_url == "https://www.medrxiv.org/content/10.64898/2026.09.01.26361059v2.full.pdf")
		assert(preprint.collection[2].pdf_url == nil, "a malformed row gets no PDF address")

		-- Journal links by preprint or article DOI; an unpublished preprint and an article without a preprint have none.
		respond('{"messages":[{"status":"ok"}], "collection":[{"preprint_doi":"10.1101\\/2021.04.29.21256344",'
			.. '"published_doi":"10.1371\\/journal.pone.0256482","published_journal":"PLOS ONE"}]}')
		local link = rxiv.getPublication({server = "medrxiv", doi = "10.1371/journal.pone.0256482"})
		assert(req(#requests).url == API .. "/pubs/medrxiv/10.1371/journal.pone.0256482/na/json", req(#requests).url)
		assert(link.collection[1].published_journal == "PLOS ONE")
		-- A suffix with punctuation, as in Lancet DOIs, is URL-encoded; the API decodes it.
		respond('{"messages":[{"status":"ok"}], "collection":[{"preprint_doi":"10.1101\\/2020.04.01.20049908","published_doi":"10.1016\\/S2468-2667(20)30133-X"}]}')
		link = rxiv.getPublication({server = "medrxiv", doi = "10.1016/S2468-2667(20)30133-X"})
		assert(req(#requests).url == API .. "/pubs/medrxiv/10.1016/S2468-2667%2820%2930133-X/na/json", req(#requests).url)
		assert(link.collection[1].preprint_doi == "10.1101/2020.04.01.20049908")
		respond('{"messages":[{"status":"ok"}], "collection":[]}')
		rxiv.getPublication({server = "biorxiv", doi = "10.1002/(SICI)1097-0258(19980815)17:15<1661::AID-SIM968>3.0.CO;2-2"})
		assert(req(#requests).url == API .. "/pubs/biorxiv/10.1002/%28SICI%291097-0258%2819980815%2917%3A15%3C1661%3A%3AAID-SIM968%3E3.0.CO%3B2-2/na/json",
			req(#requests).url)
		respond('{"messages":[{"status":"no articles found for published version of 10.1101\\/339747"}], "collection":[]}')
		assert(json.encode(rxiv.getPublication({server = "biorxiv", doi = "10.1101/339747"}).collection) == "[]")
		respond('{"messages":[{"status":"Preprint for DOI 10.1038\\/s41586-020-2012-7 not found"}], "collection":[]}')
		assert(json.encode(rxiv.getPublication({server = "biorxiv", doi = "10.1038/s41586-020-2012-7"}).collection) == "[]")

		-- A range of one page: the whole call time, the API's string totals as numbers and the PDF addresses.
		local before = #requests
		respond(details(2, 0, 2))
		local page = rxiv.listPreprints({server = "biorxiv", from = "2025-03-01", to = "2025-03-07"})
		assert(req(before + 1).url == API .. "/details/biorxiv/2025-03-01/2025-03-07/0/json", req(before + 1).url)
		assert(req(before + 1).timeoutMs == 8000)
		assert(page.total == 2 and page.count_new_papers == 250 and #page.collection == 2 and page.next_cursor == nil)
		assert(page.collection[2].pdf_url == "https://www.biorxiv.org/content/10.1101/2025.03.20.600001v1.full.pdf")
		assert(page.collection[1].date == "2025-3-2", "dates stay as the API sends them")

		-- Several pages: the first gets 12 s, later ones 7.5 s, the last page is cut at limit and next_cursor follows it.
		before = #requests
		respond(details(1267, 30, 30))
		respond(details(1267, 60, 30))
		page = rxiv.listPreprints({server = "medrxiv", from = "2025-03-01", to = "2025-03-07", category = "Cardiovascular_Medicine",
			cursor = 30, limit = 40})
		assert(#requests == before + 2)
		assert(req(before + 1).url == API .. "/details/medrxiv/2025-03-01/2025-03-07/30/json?category=cardiovascular_medicine", req(before + 1).url)
		assert(req(before + 2).url == API .. "/details/medrxiv/2025-03-01/2025-03-07/60/json?category=cardiovascular_medicine", req(before + 2).url)
		assert(req(before + 1).timeoutMs == 9000 and req(before + 2).timeoutMs == 5000)
		assert(#page.collection == 40 and page.collection[40].title == "Preprint 69" and page.total == 1267 and page.next_cursor == 70)
		assert(page.collection[1].pdf_url == "https://www.medrxiv.org/content/10.1101/2025.03.20.600030v1.full.pdf")

		-- At most three pages; the total ends the call without a needless request.
		before = #requests
		respond(details(95, 0, 30))
		respond(details(95, 30, 30))
		respond(details(95, 60, 30))
		page = rxiv.listPreprints({server = "biorxiv", from = "2025-03-01", to = "2025-03-07", limit = 90})
		assert(#requests == before + 3 and #page.collection == 90 and page.next_cursor == 90)
		before = #requests
		respond(details(95, 90, 5))
		page = rxiv.listPreprints({server = "biorxiv", from = "2025-03-01", to = "2025-03-07", limit = 90, cursor = 90})
		assert(#requests == before + 1 and #page.collection == 5 and page.next_cursor == nil)
		-- An exactly full last page stops at the total.
		before = #requests
		respond(details(60, 0, 30))
		respond(details(60, 30, 30))
		page = rxiv.listPreprints({server = "biorxiv", from = "2025-03-01", to = "2025-03-07", limit = 90})
		assert(#requests == before + 2 and #page.collection == 60 and page.next_cursor == nil)

		-- No posts: an empty range, or a cursor at its end, is an empty array.
		respond('{"messages":[{"status":"no posts found"}], "collection":[]}')
		page = rxiv.listPreprints({server = "biorxiv", from = "2030-01-01", to = "2030-01-01"})
		assert(json.encode(page.collection) == "[]" and page.total == nil and page.next_cursor == nil, "an unknown total is absent")
		before = #requests
		respond(details(1267, 30, 30))
		respond('{"messages":[{"status":"no posts found"}], "collection":[]}')
		page = rxiv.listPreprints({server = "biorxiv", from = "2025-03-01", to = "2025-03-07", limit = 90, cursor = 30})
		assert(#requests == before + 2 and #page.collection == 30 and page.next_cursor == nil, "a page without posts ends the range")

		-- Any failure of a later page returns the versions so far and where to continue.
		local failures = {
			{status = 500, body = "<html>error</html>"},
			{status = 429, body = "", headers = {["retry-after"] = {"30"}}},
			{requestError = {code = "timeout", message = "request deadline"}},
			{readError = {code = "timeout", message = "await timed out"}},
			{readError = {code = "io_error", message = "connection reset"}},
			{body = "<html>maintenance</html>"},
			{body = '{"messages":[{"status":"Both dates must be in yyyy-mm-dd format"}], "collection":[]}'},
			{body = '{"messages":[{"status":"ok","total":"many"}], "collection":[{"doi":"10.1101/1"}]}'},
			-- The first page used part of the budget, so this one overflows what remains.
			{body = '{"x":"' .. string.rep("z", 4 * 1024 * 1024 - 1000) .. '"}'},
		}
		for _, failure in failures do
			before = #requests
			respond(details(1267, 0, 30))
			table.insert(responses, failure)
			page = rxiv.listPreprints({server = "biorxiv", from = "2025-03-01", to = "2025-03-07", limit = 90})
			assert(#requests == before + 2 and #page.collection == 30 and page.next_cursor == 30 and page.total == 1267, "a later failure lost the collected versions")
		end

		-- A funder narrows the range; its versions keep their funder arrays.
		before = #requests
		respond(details(1, 0, 1, {funder = "European Commission : https://ror.org/00k4n6c32"}))
		page = rxiv.listPreprints({server = "biorxiv", from = "2025-04-10", to = "2025-07-10", funder = "https://ror.org/00k4n6c32",
			category = "cell biology"})
		assert(req(before + 1).url == API .. "/funder/biorxiv/2025-04-10/2025-07-10/00k4n6c32/0/json?category=cell_biology", req(before + 1).url)
		assert(#page.collection == 1)

		-- Published-article links page by 100, without a category or PDF addresses.
		before = #requests
		local links = {}
		for i = 1, 100 do links[i] = {preprint_doi = "10.1101/" .. tostring(i), published_doi = "10.1/x" .. tostring(i)} end
		respond('{"messages":[{"status":"ok","interval":"2025-04-01:2025-04-30","cursor":0,"count":100,"total":"250"}], "collection":'
			.. json.encode(links) .. "}")
		respond('{"messages":[{"status":"ok","cursor":"100","count":100,"total":"250"}], "collection":' .. json.encode(links) .. "}")
		page = rxiv.listPublications({server = "biorxiv", from = "2025-04-01", to = "2025-04-30", limit = 150})
		assert(req(before + 1).url == API .. "/pubs/biorxiv/2025-04-01/2025-04-30/0", req(before + 1).url)
		assert(req(before + 2).url == API .. "/pubs/biorxiv/2025-04-01/2025-04-30/100", req(before + 2).url)
		assert(#page.collection == 150 and page.total == 250 and page.next_cursor == 150 and page.collection[1].pdf_url == nil)
		assert(page.count_new_papers == nil)
		respond('{"messages":[{"status":"ok","cursor":0,"count":0,"total":"0"}], "collection":[]}')
		page = rxiv.listPublications({server = "medrxiv", from = "2025-04-01", to = "2025-04-01"})
		assert(json.encode(page.collection) == "[]" and page.next_cursor == nil)
		assert(#responses == 0, "a queued response was not requested")
	end,
}
