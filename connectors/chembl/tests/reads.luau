-- Searches build exact ChEMBL queries and page within one call; records are read by ID.
return {
	scenario = {publisher = {}, config = {}, auth_method = "", auth_config = {}},
	configure = function()
		requests, responses = {}, {}
		http = {request = function(req)
			table.insert(requests, req)
			assert(req.method == "GET" and req.body == nil, "ChEMBL reads must be bodiless GETs")
			assert(req.headers.Authorization == nil, "the public API takes no credentials")
			assert(req.headers.Accept[1] == "application/json")
			assert(#responses > 0, "unexpected request: " .. req.url)
			local queued = table.remove(responses, 1)
			if type(queued) == "string" then
				return fixture.operation({statusCode = 200, headers = {}, body = fixture.reader(queued)})
			end
			-- A table with a code fails while waiting for headers, such as a timeout; one with a status answers with it;
			-- one with readError has a body whose read fails.
			if queued.code then error(queued, 0) end
			local body = if queued.readError
				then {readAll = function() error(queued.readError, 0) end, readPrefix = function() error(queued.readError, 0) end, close = function() end}
				else fixture.reader(queued.body or "")
			return fixture.operation({statusCode = queued.status or 200, headers = {}, body = body})
		end}
		function respond(body) table.insert(responses, body) end
		-- One ChEMBL page: rows are JSON texts, and more links a next page.
		function page(key, rows, total, more)
			return '{"' .. key .. '":[' .. table.concat(rows, ",") .. '],"page_meta":{"limit":20,"next":'
				.. (if more then '"/chembl/api/data/next"' else "null") .. ',"offset":0,"previous":null,"total_count":'
				.. tostring(total) .. "}}"
		end
		function molecules(from, count, padding)
			local rows = {}
			for i = from, from + count - 1 do
				table.insert(rows, '{"molecule_chembl_id":"CHEMBL' .. i .. '"' .. (if padding then ',"p":"' .. string.rep("x", padding) .. '"' else "") .. "}")
			end
			return rows
		end
	end,
	run = function(chembl)
		local API = "https://www.ebi.ac.uk/chembl/api/data"
		local MOLECULE = "only=molecule_chembl_id%2Cpref_name%2Cmax_phase%2Cmolecule_type%2Cfirst_approval%2Cmolecule_properties"
		local function url(i) return requests[i or #requests].url end

		local names = {}
		for name, fn in chembl do
			assert(type(fn) == "function")
			table.insert(names, name)
		end
		table.sort(names)
		assert(table.concat(names, ",") == "getActivity,getAssay,getDocument,getDrugIndication,getMechanism,getMolecule,getTarget,"
			.. "searchActivities,searchAssays,searchDocuments,searchDrugIndications,searchMechanisms,searchMolecules,searchTargets,"
			.. "similarMolecules,substructureMolecules", table.concat(names, ","))
		assert(#requests == 0, "initialization reached ChEMBL")

		-- Default search: compact fields, default limit, one page when ChEMBL links no next page.
		respond(page("molecules", molecules(1, 2), 2, false))
		local found = chembl.searchMolecules()
		assert(url() == API .. "/molecule.json?" .. MOLECULE .. "&limit=100&offset=0", url())
		assert(requests[1].timeoutMs == 20000)
		assert(#found.molecules == 2 and found.molecules[2].molecule_chembl_id == "CHEMBL2")
		assert(found.total_count == 2 and found.next_offset == nil)

		-- Text search with every filter kind: filters sorted and encoded, order_by kept in order, then fields.
		local opts = {q = "aspirin", filters = {max_phase = 4, molecule_properties__full_mwt__range = {100, 200.5},
			pref_name__isnull = false, molecule_chembl_id__in = "chembl25, CHEMBL2", oral = true,
			molecule_structures__canonical_smiles__flexmatch = "C#N", molecule_synonyms__molecule_synonym__iexact = "Aspirin 81",
			atc_classifications__level5 = "N02BA01", availability_type__in = {1, 2}, first_approval__range = "1990, 2000.5"},
			order_by = {"-max_phase", "pref_name"}, fields = "molecule_chembl_id,pref_name", limit = 5, offset = 10}
		respond(page("molecules", molecules(25, 1), 1, false))
		found = chembl.searchMolecules(opts)
		assert(url() == API .. "/molecule/search.json?atc_classifications__level5=N02BA01&availability_type__in=1%2C2"
			.. "&first_approval__range=1990%2C2000.5&max_phase=4&molecule_chembl_id__in=CHEMBL25%2CCHEMBL2&molecule_properties__full_mwt__range=100%2C200.5"
			.. "&molecule_structures__canonical_smiles__flexmatch=C%23N&molecule_synonyms__molecule_synonym__iexact=Aspirin%2081"
			.. "&oral=true&pref_name__isnull=false&q=aspirin&order_by=-max_phase&order_by=pref_name"
			.. "&only=molecule_chembl_id%2Cpref_name&limit=5&offset=10", url())
		assert(#found.molecules == 1 and found.next_offset == nil)
		assert(opts.limit == 5 and opts.filters.max_phase == 4 and opts.fields == "molecule_chembl_id,pref_name",
			"caller options were modified")

		-- Other resources keep their own row keys and compact fields; empty results stay arrays.
		respond(page("activities", {}, 0, false))
		found = chembl.searchActivities({filters = {target_chembl_id = "CHEMBL203", standard_type__in = {"IC50", "Ki"},
			pchembl_value__gte = 7, potential_duplicate = 0}, order_by = "-pchembl_value"})
		assert(url() == API .. "/activity.json?pchembl_value__gte=7&potential_duplicate=0&standard_type__in=IC50%2CKi"
			.. "&target_chembl_id=CHEMBL203&order_by=-pchembl_value&only=activity_id%2Cmolecule_chembl_id%2Cmolecule_pref_name"
			.. "%2Ctarget_chembl_id%2Ctarget_pref_name%2Ctarget_organism%2Cassay_chembl_id%2Cassay_type%2Cdocument_chembl_id"
			.. "%2Cstandard_type%2Cstandard_relation%2Cstandard_value%2Cstandard_units%2Cpchembl_value&limit=100&offset=0", url())
		assert(json.encode(found.activities) == "[]" and found.total_count == 0 and found.next_offset == nil)
		respond(page("targets", {'{"target_chembl_id":"CHEMBL203"}'}, 1, false))
		found = chembl.searchTargets({filters = {target_components__accession = "P00533"}, fields = {"target_chembl_id"}})
		assert(url() == API .. "/target.json?target_components__accession=P00533&only=target_chembl_id&limit=100&offset=0", url())
		assert(found.targets[1].target_chembl_id == "CHEMBL203")
		for _, case in {
			{fn = chembl.searchAssays, path = "assay/search.json?q=EGFR%20kinase&", key = "assays",
				args = {q = "EGFR kinase", fields = "all"}, size = 32},
			{fn = chembl.searchDocuments, path = "document.json?pubmed_id=23028140&", key = "documents",
				args = {filters = {pubmed_id = 23028140}, fields = "all"}, size = 32},
			{fn = chembl.searchMechanisms, path = "mechanism.json?parent_molecule_chembl_id=CHEMBL941&", key = "mechanisms",
				args = {filters = {parent_molecule_chembl_id = "CHEMBL941"}, fields = "all"}, size = 32},
			{fn = chembl.searchDrugIndications, path = "drug_indication.json?efo_term__icontains=fibrillation&", key = "drug_indications",
				args = {filters = {efo_term__icontains = "fibrillation"}, fields = {"drugind_id", "efo_term"}, limit = 50}, size = 50},
		} do
			respond(page(case.key, {"{}"}, 1, false))
			local result = case.fn(case.args)
			local only = if type(case.args.fields) == "table" then "only=drugind_id%2Cefo_term&" else ""
			assert(url() == API .. "/" .. case.path .. only .. "limit=" .. case.size .. "&offset=0", url())
			assert(#result[case.key] == 1 and result.total_count == 1)
		end

		-- Two pages: the second asks for the rest with less time, and an exactly full limit keeps next_offset.
		respond(page("molecules", molecules(1, 1000), 4000, true))
		respond(page("molecules", molecules(1001, 500), 9999, true))
		local first = #requests + 1
		found = chembl.searchMolecules({limit = 1500})
		assert(url(first) == API .. "/molecule.json?" .. MOLECULE .. "&limit=1000&offset=0", url(first))
		assert(url() == API .. "/molecule.json?" .. MOLECULE .. "&limit=500&offset=1000", url())
		assert(requests[first].timeoutMs == 20000 and requests[first + 1].timeoutMs == 8000)
		assert(#found.molecules == 1500 and found.molecules[1500].molecule_chembl_id == "CHEMBL1500")
		assert(found.total_count == 4000 and found.next_offset == 1500, "total_count comes from the first page")

		-- next_offset continues from the caller's offset; a page without a next link ends the search early.
		respond(page("molecules", molecules(1, 1000), 1600, true))
		respond(page("molecules", molecules(1001, 600), 1600, false))
		found = chembl.searchMolecules({limit = 2000, offset = 0})
		assert(#found.molecules == 1600 and found.next_offset == nil)
		respond(page("molecules", molecules(1, 1000), 4000, true))
		respond(page("molecules", molecules(1001, 1000), 4000, true))
		found = chembl.searchMolecules({limit = 2000, offset = 2000})
		assert(url() == API .. "/molecule.json?" .. MOLECULE .. "&limit=1000&offset=3000", url())
		assert(#found.molecules == 2000 and found.next_offset == 4000)
		found = nil

		-- Records beyond the compact defaults start with 32 rows; the next page fits the remaining byte budget.
		respond(page("molecules", molecules(1, 32, 100 * 1024), 500, true))
		respond(page("molecules", molecules(33, 4), 500, true))
		first = #requests + 1
		found = chembl.searchMolecules({fields = "all", limit = 2000})
		assert(url(first) == API .. "/molecule.json?limit=32&offset=0", url(first))
		assert(url() == API .. "/molecule.json?limit=4&offset=32", url())
		assert(#found.molecules == 36 and found.next_offset == 36)
		found = nil

		-- When nothing more fits, the call ends after one page.
		respond(page("molecules", molecules(1, 32, 125 * 1024), 500, true))
		first = #requests
		found = chembl.searchMolecules({fields = {"molecule_structures"}, limit = 2000})
		assert(#requests == first + 1, "the byte budget must stop paging")
		assert(url() == API .. "/molecule.json?only=molecule_structures&limit=32&offset=0", url())
		assert(#found.molecules == 32 and found.next_offset == 32)
		found = nil

		-- A second page over the remaining budget, or too slow, ends the call with what was collected.
		respond(page("molecules", molecules(1, 1000, 1000), 4000, true))
		respond(page("molecules", molecules(1001, 1, 3 * 1024 * 1024 + 100 * 1024), 4000, true))
		found = chembl.searchMolecules({limit = 2000})
		assert(#found.molecules == 1000 and found.next_offset == 1000, "collected molecules were discarded")
		respond(page("molecules", molecules(1, 10), 4000, true))
		respond({code = "timeout", message = "request deadline"})
		found = chembl.searchMolecules({limit = 20, offset = 5})
		assert(url() == API .. "/molecule.json?" .. MOLECULE .. "&limit=10&offset=15", url())
		assert(#found.molecules == 10 and found.next_offset == 15)
		-- Any other failure of a later page also keeps the collected rows; cancellation still ends the call.
		for _, failed in {{status = 500, body = '{"error_message": "statement timeout"}'}, {status = 404}, {code = "io_error", message = "reset"},
			{readError = {code = "io_error", message = "reset"}}, '<html>', '{"molecules": null}'} do
			respond(page("molecules", molecules(1, 10), 4000, true))
			respond(failed)
			found = chembl.searchMolecules({limit = 20})
			assert(#found.molecules == 10 and found.next_offset == 10, "a later page failure discarded the collected rows")
		end
		respond(page("molecules", molecules(1, 10), 4000, true))
		respond({readError = {code = "cancelled", message = "invocation cancelled"}})
		local cancelled, err = pcall(chembl.searchMolecules, {limit = 20})
		assert(not cancelled and not string.find(tostring(err), "retryable", 1, true), "cancellation became a result: " .. tostring(err))
		found = nil

		-- Structure searches use the query-string form, so SMILES characters such as # and / are encoded.
		local SIMILAR = MOLECULE .. "%2Csimilarity"
		respond(page("molecules", {'{"molecule_chembl_id":"CHEMBL25","similarity":"100"}'}, 1, false))
		found = chembl.similarMolecules({smiles = "CC(=O)Oc1ccccc1C(=O)O"})
		assert(url() == API .. "/similarity.json?similarity=80&smiles=CC%28%3DO%29Oc1ccccc1C%28%3DO%29O&" .. SIMILAR
			.. "&limit=100&offset=0", url())
		assert(found.molecules[1].similarity == "100")
		respond(page("molecules", {}, 0, false))
		found = chembl.similarMolecules({chembl_id = "chembl25", similarity = 40, filters = {max_phase = 4},
			order_by = "-similarity", limit = 10})
		assert(url() == API .. "/similarity.json?chembl_id=CHEMBL25&max_phase=4&similarity=40&order_by=-similarity&"
			.. SIMILAR .. "&limit=10&offset=0", url())
		assert(json.encode(found.molecules) == "[]" and found.next_offset == nil)
		respond(page("molecules", molecules(1, 3), 30000, true))
		found = chembl.substructureMolecules({smiles = "C#CC/C=C\\c1ccccc1", limit = 3})
		assert(url() == API .. "/substructure.json?smiles=C%23CC%2FC%3DC%5Cc1ccccc1&" .. MOLECULE .. "&limit=3&offset=0", url())
		assert(#found.molecules == 3 and found.total_count == 30000 and found.next_offset == 3)
		respond(page("molecules", {}, 0, false))
		chembl.substructureMolecules({chembl_id = "CHEMBL25", fields = "all"})
		assert(url() == API .. "/substructure.json?chembl_id=CHEMBL25&limit=32&offset=0", url())

		-- Records by ID: ChEMBL IDs are upper-cased, InChIKeys and integer IDs pass as they are.
		for _, case in {
			{fn = chembl.getMolecule, id = "chembl25", path = "molecule/CHEMBL25.json"},
			{fn = chembl.getMolecule, id = "BSYNRYMUTXBXSQ-UHFFFAOYSA-N", path = "molecule/BSYNRYMUTXBXSQ-UHFFFAOYSA-N.json"},
			{fn = chembl.getTarget, id = "CHEMBL203", path = "target/CHEMBL203.json"},
			{fn = chembl.getAssay, id = "CHEMBL1217643", path = "assay/CHEMBL1217643.json"},
			{fn = chembl.getDocument, id = "CHEMBL1139451", path = "document/CHEMBL1139451.json"},
			{fn = chembl.getActivity, id = 31863, path = "activity/31863.json"},
			{fn = chembl.getMechanism, id = "241", path = "mechanism/241.json"},
			{fn = chembl.getDrugIndication, id = 22713, path = "drug_indication/22713.json"},
		} do
			respond('{"id":"record"}')
			assert(case.fn(case.id).id == "record")
			assert(url() == API .. "/" .. case.path, url())
			assert(requests[#requests].timeoutMs == 20000)
		end
		respond('{"target_chembl_id":"CHEMBL203","target_components":[]}')
		local target = chembl.getTarget("CHEMBL203", {fields = {"target_chembl_id", "target_components"}})
		assert(url() == API .. "/target/CHEMBL203.json?only=target_chembl_id%2Ctarget_components", url())
		assert(json.encode(target.target_components) == "[]")
		respond('{"molecule_chembl_id":"CHEMBL25"}')
		chembl.getMolecule("CHEMBL25", {fields = "all"})
		assert(url() == API .. "/molecule/CHEMBL25.json", url())
		assert(#responses == 0, "unused responses")
	end,
}
