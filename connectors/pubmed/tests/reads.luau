-- Each export posts one exact E-utilities form, or reads one BioC document, and returns NCBI's data.
return {
	scenario = {publisher = {}, config = {}, auth_method = "", auth_config = {}},
	configure = function()
		requests, responses = {}, {}
		http = {request = function(req)
			table.insert(requests, req)
			assert(req.headers == nil or req.headers.Authorization == nil, "the public API takes no credentials")
			assert(req.timeoutMs == 8000, "headers get the call's time less the body's share")
			assert(#responses > 0, "unexpected request: " .. req.url)
			local queued = table.remove(responses, 1)
			return fixture.operation({statusCode = 200, headers = {["content-type"] = {queued.type}}, body = fixture.reader(queued.body)})
		end}
		function respond(body, kind) table.insert(responses, {body = body, type = kind or "application/json; charset=UTF-8"}) end
	end,
	run = function(pubmed)
		local EUTILS = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/"
		local CONTACT = "&tool=houston&email=hello%40ok-houston.com"
		local function last() return requests[#requests] end
		local function posted(utility, body)
			local req = last()
			assert(req.method == "POST" and req.url == EUTILS .. utility .. ".fcgi", req.url)
			assert(req.headers["Content-Type"][1] == "application/x-www-form-urlencoded")
			assert(req.body == body .. CONTACT, req.body)
		end

		local names = {}
		for name, fn in pubmed do
			assert(type(fn) == "function")
			table.insert(names, name)
		end
		table.sort(names)
		assert(table.concat(names, ",") == "getFullText,getLinks,getRecords,getSummaries,searchArticles", table.concat(names, ","))
		assert(#requests == 0, "initialization reached NCBI")

		-- A minimal search keeps NCBI's defaults and its string counts; an empty idlist stays an array.
		respond('{"header":{"type":"esearch","version":"0.3"},"esearchresult":{"count":"0","retmax":"0","retstart":"0","idlist":[],'
			.. '"translationset":[],"querytranslation":"zzqx[All Fields]","warninglist":{"outputmessages":["No items found."]}}}')
		local found = pubmed.searchArticles({term = "zzqx"})
		posted("esearch", "db=pubmed&retmode=json&term=zzqx&retstart=0&retmax=20")
		assert(found.count == "0" and json.encode(found.idlist) == "[]" and found.warninglist.outputmessages[1] == "No items found.")
		assert(found.header == nil, "the result is esearchresult")

		-- Every option, encoded in a fixed order; the caller's table is left unchanged.
		local opts = {term = 'crispr[tiab] AND "Smith J"[au]', retstart = 9990, retmax = 9999, sort = "pub_date",
			mindate = "2024/01", maxdate = "2024/12/31", datetype = "pdat"}
		respond('{"esearchresult":{"count":"8026","retmax":"9","retstart":"9990","idlist":["42205224","41255389"]}}')
		found = pubmed.searchArticles(opts)
		posted("esearch", "db=pubmed&retmode=json&term=crispr%5Btiab%5D%20AND%20%22Smith%20J%22%5Bau%5D&retstart=9990&retmax=9999"
			.. "&sort=pub_date&mindate=2024%2F01&maxdate=2024%2F12%2F31&datetype=pdat")
		assert(found.count == "8026" and #found.idlist == 2 and found.idlist[2] == "41255389")
		assert(opts.retmax == 9999 and opts.term == 'crispr[tiab] AND "Smith J"[au]', "caller options were modified")
		respond('{"esearchresult":{"count":"918","retmax":"0","retstart":"0","idlist":[]}}')
		pubmed.searchArticles({term = "crispr", retmax = 0, reldate = 30, datetype = "edat", sort = "relevance"})
		posted("esearch", "db=pubmed&retmode=json&term=crispr&retstart=0&retmax=0&sort=relevance&reldate=30&datetype=edat")
		-- Leap days, partial dates and one-day ranges are valid.
		respond('{"esearchresult":{"count":"1","retmax":"0","retstart":"0","idlist":[]}}')
		pubmed.searchArticles({term = "crispr", mindate = "2024/02/29", maxdate = "2024/02/29"})
		respond('{"esearchresult":{"count":"1","retmax":"0","retstart":"0","idlist":[]}}')
		pubmed.searchArticles({term = "crispr", mindate = "2000/02/29", maxdate = "2000/02"})
		posted("esearch", "db=pubmed&retmode=json&term=crispr&retstart=0&retmax=20&mindate=2000%2F02%2F29&maxdate=2000%2F02")

		-- Summaries take numbers, strings and lists, drop repeats and keep NCBI's per-ID errors.
		respond('{"header":{"type":"esummary"},"result":{"uids":["31452104","99999999"],"31452104":{"uid":"31452104",'
			.. '"title":"Molegro Virtual Docker for Docking.","authors":[{"name":"Bitencourt-Ferreira G","authtype":"Author"}],'
			.. '"articleids":[{"idtype":"doi","value":"10.1007/978-1-4939-9752-7_10"}]},'
			.. '"99999999":{"uid":"99999999","error":"cannot get document summary"}}}')
		local summaries = pubmed.getSummaries({31452104, "99999999", "31452104"})
		posted("esummary", "db=pubmed&retmode=json&id=31452104%2C99999999")
		assert(summaries.uids[1] == "31452104" and summaries["31452104"].authors[1].name == "Bitencourt-Ferreira G")
		assert(summaries["99999999"].error == "cannot get document summary")
		respond('{"result":{"uids":["1"],"1":{"uid":"1"}}}')
		pubmed.getSummaries("1, 2 3,,4")
		posted("esummary", "db=pubmed&retmode=json&id=1%2C2%2C3%2C4")
		respond('{"result":{"uids":["5"],"5":{"uid":"5"}}}')
		pubmed.getSummaries(5)
		posted("esummary", "db=pubmed&retmode=json&id=5")

		-- MEDLINE records: continuation lines join, authors keep their IDs and affiliations, other tags stay in order.
		respond(table.concat({
			"",
			"PMID- 33782057",
			"OWN - NLM",
			"DP  - 2021 Mar 29",
			"TI  - The PRISMA 2020 statement: an updated guideline for reporting systematic ",
			"      reviews.",
			"LID - 10.1136/bmj.n71 [doi]",
			"LID - n71",
			"AB  - BACKGROUND: Systematic reviews are useful. METHODS: We updated the",
			-- Only an empty line ends a record; a line of spaces inside a value is ignored.
			"   ",
			"      guideline. CONCLUSIONS: Use it.",
			"FAU - Page, Matthew J",
			"AU  - Page MJ",
			"AUID- ORCID: 0000-0002-4242-7526",
			"AD  - School of Public Health and Preventive Medicine, Monash University, Melbourne, ",
			"      Australia matthew.page@monash.edu.",
			"FAU - McKenzie, Joanne E",
			"AU  - McKenzie JE",
			"AD  - Monash University.",
			"AD  - University of Ottawa.",
			"CN  - PRISMA Group",
			"LA  - eng",
			"PT  - Journal Article",
			"PT  - Review",
			"MH  - Checklist",
			"MH  - *Guidelines as Topic",
			"MH  - Proteins/*chemistry",
			"OTO - NOTNLM",
			"OT  - reporting",
			"PMC - PMC8005924",
			"SO  - BMJ. 2021 Mar 29;372:n71. doi: 10.1136/bmj.n71.",
			"",
			"PMID- 1",
			"TI  - Formate assay in body fluids: application in methanol poisoning.",
			"AU  - Makar AB",
			"AU  - McMartin KE",
			"",
			"PMID- 2",
			"TI  - A record without authors.",
			"",
		}, "\n"), "text/plain; charset=UTF-8")
		local records = pubmed.getRecords({"33782057", 1, "2"}).records
		posted("efetch", "db=pubmed&rettype=medline&retmode=text&id=33782057%2C1%2C2")
		assert(#records == 3)
		local prisma = records[1]
		assert(prisma.PMID == "33782057" and prisma.OWN == "NLM" and prisma.DP == "2021 Mar 29")
		assert(prisma.TI == "The PRISMA 2020 statement: an updated guideline for reporting systematic reviews.", prisma.TI)
		assert(prisma.AB == "BACKGROUND: Systematic reviews are useful. METHODS: We updated the guideline. CONCLUSIONS: Use it.",
			"wrapped lines join with one space, as Biopython joins them: " .. prisma.AB)
		assert(table.concat(prisma.LID, "|") == "10.1136/bmj.n71 [doi]|n71")
		assert(#prisma.authors == 2 and prisma.authors[1].FAU == "Page, Matthew J" and prisma.authors[1].AU == "Page MJ")
		assert(prisma.authors[1].AUID[1] == "ORCID: 0000-0002-4242-7526")
		assert(prisma.authors[1].AD[1] == "School of Public Health and Preventive Medicine, Monash University, Melbourne, Australia matthew.page@monash.edu.")
		assert(table.concat(prisma.authors[2].AD, "|") == "Monash University.|University of Ottawa." and prisma.authors[2].AUID == nil)
		assert(prisma.FAU == nil and prisma.AU == nil and prisma.AD == nil, "author tags live in authors")
		assert(prisma.CN[1] == "PRISMA Group" and prisma.LA[1] == "eng" and table.concat(prisma.PT, "|") == "Journal Article|Review")
		assert(table.concat(prisma.MH, "|") == "Checklist|*Guidelines as Topic|Proteins/*chemistry")
		assert(prisma.OTO[1] == "NOTNLM" and prisma.OT[1] == "reporting" and prisma.PMC == "PMC8005924")
		assert(prisma.SO == "BMJ. 2021 Mar 29;372:n71. doi: 10.1136/bmj.n71.")
		-- Older records list authors by AU alone.
		assert(#records[2].authors == 2 and records[2].authors[2].AU == "McMartin KE" and records[2].authors[2].FAU == nil)
		assert(json.encode(records[3].authors) == "[]", "a record without authors keeps an empty array")
		respond("\n", "text/plain; charset=UTF-8")
		records = pubmed.getRecords("99999999").records
		assert(json.encode(records) == "[]", "unknown PMIDs are left out")
		-- Lines that are not tagged, such as NCBI's note about a PMID it cannot serve, are skipped rather than failing the
		-- batch; a tag line may have an empty value without a trailing space.
		respond(table.concat({"id: 99999999 Error occurred: The following PMID is not available", "      stray continuation", "",
			"PMID- 31452104", "AB  -", "not tagged", "TI  - Molegro Virtual Docker", "      for Docking.", ""}, "\n"),
			"text/plain; charset=UTF-8")
		records = pubmed.getRecords({99999999, 31452104}).records
		assert(#records == 1 and records[1].PMID == "31452104" and records[1].AB == "", json.encode(records))
		assert(records[1].TI == "Molegro Virtual Docker for Docking.", records[1].TI)

		-- Links: one id parameter per PMID, so each gets its own linkset; absent linksetdbs pass through.
		respond('{"header":{"type":"elink"},"linksets":[{"dbfrom":"pubmed","ids":["25977807"],"linksetdbs":[{"dbto":"pubmed",'
			.. '"linkname":"pubmed_pubmed_citedin","links":["32535840","31722288"]}]},{"dbfrom":"pubmed","ids":["99999999"]}]}')
		local linksets = pubmed.getLinks({25977807, "99999999"}, "pubmed_pubmed_citedin")
		posted("elink", "dbfrom=pubmed&retmode=json&id=25977807&id=99999999&linkname=pubmed_pubmed_citedin&cmd=neighbor")
		assert(#linksets == 2 and linksets[1].linksetdbs[1].links[2] == "31722288" and linksets[2].linksetdbs == nil)
		respond('{"linksets":[{"dbfrom":"pubmed","ids":["25977807"],"linksetdbs":[{"dbto":"pubmed","linkname":"pubmed_pubmed",'
			.. '"links":[{"id":"25194848","score":26054440}]}]}]}')
		linksets = pubmed.getLinks("25977807", "pubmed_pubmed", {scores = true})
		posted("elink", "dbfrom=pubmed&retmode=json&id=25977807&linkname=pubmed_pubmed&cmd=neighbor_score")
		assert(linksets[1].linksetdbs[1].links[1].score == 26054440)
		for _, name in {"pubmed_pubmed_reviews", "pubmed_pubmed_refs", "pubmed_pmc", "pubmed_pmc_refs"} do
			respond('{"linksets":[]}')
			assert(json.encode(pubmed.getLinks(1, name, {scores = false})) == "[]")
			posted("elink", "dbfrom=pubmed&retmode=json&id=1&linkname=" .. name .. "&cmd=neighbor")
		end

		-- Full text: one bodiless GET by PMCID or PMID, returning the BioC document unchanged.
		local document = '{"bioctype":"BioCDocument","id":"PMC4412151","infons":{"license":"CC BY"},"passages":['
			.. '{"offset":0,"infons":{"section_type":"TITLE","type":"front","article-id_pmid":"25977807"},"text":"Title"},'
			.. '{"offset":6,"infons":{"section_type":"INTRO","type":"paragraph"},"text":"Neuroscience is transforming."}],'
			.. '"annotations":[],"relations":[]}'
		local BIOC = "https://www.ncbi.nlm.nih.gov/research/bionlp/RESTful/pmcoa.cgi/BioC_json/"
		for _, case in {{id = "pmc4412151", path = "PMC4412151"}, {id = 25977807, path = "25977807"}, {id = "25977807", path = "25977807"}} do
			respond('[{"bioctype":"BioCCollection","source":"PMC","documents":[' .. document .. "]}]", "application/json")
			local article = pubmed.getFullText(case.id)
			assert(last().method == "GET" and last().body == nil and last().url == BIOC .. case.path .. "/unicode", last().url)
			assert(article.id == "PMC4412151" and article.infons.license == "CC BY" and #article.passages == 2)
			assert(article.passages[2].infons.section_type == "INTRO" and json.encode(article.annotations) == "[]")
		end
	end,
}
