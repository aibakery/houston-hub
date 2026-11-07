return {
	contract = function(m)
		local pubmedEUtilities = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils"
		local pubmedBioC = "https://www.ncbi.nlm.nih.gov/research/bionlp/RESTful/pmcoa.cgi/BioC_json"
		local resolvePubMed = function(key)
			local config = {}
			if key ~= "" then
				config.api_key = key
			end
			local r, err = m.resolve(nil, config, nil, "")
			assert(not err, tostring(err))
			return r
		end
		-- TestPubMedPublicReadRoutes
		do
			for _, key in { "", "synthetic-ncbi-key" } do
				local r = resolvePubMed(key)
				m.routes(r, "", true, {
					"POST " .. pubmedEUtilities .. "/esearch.fcgi",
					"POST " .. pubmedEUtilities .. "/esummary.fcgi",
					"POST " .. pubmedEUtilities .. "/efetch.fcgi",
					"POST " .. pubmedEUtilities .. "/elink.fcgi",
					"GET " .. pubmedBioC .. "/PMC4412151/unicode",
					"GET " .. pubmedBioC .. "/25977807/unicode",
				})
				m.routes(r, "", false, {
					"GET " .. pubmedEUtilities .. "/esearch.fcgi?db=pubmed&term=x",
					"POST " .. pubmedEUtilities .. "/epost.fcgi",
					"POST " .. pubmedEUtilities .. "/einfo.fcgi",
					"POST " .. pubmedEUtilities .. "/espell.fcgi",
					"GET " .. pubmedEUtilities .. "/ecitmatch.cgi",
					"POST " .. pubmedEUtilities .. "/esearch.fcgi/x",
					"POST https://eutils.ncbi.nlm.nih.gov.example.com/entrez/eutils/esearch.fcgi",
					"POST http://eutils.ncbi.nlm.nih.gov:8080/entrez/eutils/esearch.fcgi",
					"POST https://www.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi",
					"POST " .. pubmedBioC .. "/PMC4412151/unicode",
					"GET " .. pubmedBioC .. "/PMC4412151/ascii",
					"GET " .. pubmedBioC .. "/%2e%2e/unicode",
					"GET https://www.ncbi.nlm.nih.gov/research/bionlp/RESTful/pubmed.cgi/BioC_json/25977807/unicode",
					"GET https://www.ncbi.nlm.nih.gov/research/pubtator3-api/publications/export/biocjson",
					"GET https://pmc.ncbi.nlm.nih.gov/tools/idconv/api/v1/articles/",
					"GET https://ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi",
				})
			end
		end
		-- TestPubMedSendsTheKeyOnlyToEUtilities
		do
			local dropped = { "Authorization", "Cookie" }
			for _, key in { "", "synthetic-ncbi-key" } do
				local r = resolvePubMed(key)
				local search = pubmedEUtilities .. "/esearch.fcgi"
				if key ~= "" then
					search ..= "?api_key=" .. key
				end
				for _, route in
					{
						{ method = "POST", url = pubmedEUtilities .. "/esearch.fcgi", want = search },
						{
							method = "GET",
							url = pubmedBioC .. "/PMC4412151/unicode",
							want = pubmedBioC .. "/PMC4412151/unicode",
						},
					}
				do
					local recipe, err = m.recipe(r, route.method, route.url, nil)
					assert(not err, tostring(err))
					do
						local prepared, err = m.prepareUrl(recipe, r.Context)
						if (err ~= nil) or (prepared ~= route.want) then
							m.fail("key %s: %s prepared as %s: %s", key, route.url, prepared, err)
						end
					end
					m.rejectPreparedOverrides(recipe, r.Context, route.method .. " " .. route.url)
					local caller = { ["Content-Type"] = { "application/x-www-form-urlencoded" } }
					for _, name in dropped do
						caller[name] = { "caller-value" }
					end
					local headers, err = m.prepare(recipe, r.Context, caller)
					if
						(err ~= nil)
						or (m.header(headers, "Content-Type") ~= "application/x-www-form-urlencoded")
					then
						m.fail("prepare: %s %s", headers, err)
					end
					for _, name in dropped do
						if m.header(headers, name) ~= "" then
							m.fail("%s reached NCBI", name)
						end
					end
				end
			end
		end
		-- TestPubMedEmptyKeyNeverReachesNCBI
		do
			local r, err = m.resolve(nil, { api_key = "" }, nil, "")
			if err == nil then
				local recipe, err = m.recipe(r, "POST", pubmedEUtilities .. "/esearch.fcgi", nil)
				assert(not err, tostring(err))
				local prepared, _ = m.prepareUrl(recipe, r.Context)
				m.fail("an empty key resolved and prepared %s", prepared)
			end
		end
	end,
}
