-- Invalid input never reaches the network; ChEMBL errors, slow answers and bad pages map to clear failures.
return {
	scenario = {publisher = {}, config = {}, auth_method = "", auth_config = {}},
	configure = function()
		calls = 0
		status = 200
		payload = "{}"
		responseHeaders = {}
		http = {request = function()
			calls += 1
			-- A table stands for a failure while waiting for headers, such as a timeout or a refused origin.
			if requestError then error(requestError, 0) end
			-- A body whose read fails stands in for a dropped connection or a cancelled invocation.
			local body = if readError then {readAll = function() error(readError, 0) end, close = function() end} else fixture.reader(payload)
			return fixture.operation({statusCode = status, headers = responseHeaders, body = body})
		end}
	end,
	run = function(chembl)
		local function rejected(fn, expected)
			local before = calls
			local ok, err = pcall(fn)
			assert(not ok and string.find(tostring(err), expected, 1, true), "wrong validation error: " .. tostring(err))
			assert(calls == before, "invalid input reached ChEMBL")
		end
		local function molecules(opts) return function() chembl.searchMolecules(opts) end end

		rejected(function() chembl.searchMolecules("aspirin") end, "options must be a table")
		rejected(molecules({search = "aspirin"}), "unknown option search")
		rejected(molecules({only = "pref_name"}), "unknown option only")
		rejected(molecules({q = ""}), "q must be a nonempty string")
		rejected(molecules({q = string.rep("a", 1001)}), "at most 1000 bytes")
		rejected(function() chembl.searchMechanisms({q = "EGFR"}) end, "searchMechanisms has no q text search")
		rejected(molecules({filters = "max_phase=4"}), "filters must be a table")
		-- ChEMBL ignores unknown filters and answers with every molecule, so they never reach it.
		rejected(molecules({filters = {foo = 1}}), "molecule has no filter foo")
		rejected(molecules({filters = {pref_name__bogus = "x"}}), "molecule has no filter pref_name__bogus")
		rejected(molecules({filters = {molecule_synonyms__syn_type = "x"}}), "has no filter molecule_synonyms__syn_type")
		rejected(function() chembl.substructureMolecules({smiles = "c1ccccc1", filters = {molecule_synonyms__molecule_synonym = "x"}}) end,
			"substructure search has no filter")
		rejected(molecules({filters = {["Pref_Name"] = "x"}}), "lowercase ChEMBL field names")
		rejected(molecules({filters = {[1] = "x"}}), "lowercase ChEMBL field names")
		rejected(molecules({filters = {max_phase__icontains = "4"}}), "max_phase accepts only the lookups exact gt gte")
		rejected(molecules({filters = {oral__gte = 1}}), "oral accepts only the lookups exact isnull")
		rejected(molecules({filters = {molecule_structures__canonical_smiles = "CCO"}}), "accepts only the lookups flexmatch connectivity")
		rejected(molecules({filters = {max_phase = "4"}}), "max_phase must be a finite number")
		rejected(molecules({filters = {oral = "yes"}}), "oral must be true, false or an integer")
		rejected(molecules({filters = {pref_name = true}}), "pref_name must be a nonempty string")
		rejected(molecules({filters = {pref_name = ""}}), "pref_name must be a nonempty string")
		rejected(molecules({filters = {molecule_chembl_id = "25"}}), "molecule_chembl_id must be a ChEMBL ID")
		rejected(molecules({filters = {pref_name__isnull = "false"}}), "pref_name__isnull must be true or false")
		rejected(molecules({filters = {molecule_chembl_id__in = {}}}), "must list 1 to 1000 values")
		rejected(molecules({filters = {molecule_chembl_id__in = {[1] = "CHEMBL25", [3] = "CHEMBL2"}}}), "must be a dense array")
		rejected(molecules({filters = {pref_name__in = {"A, B"}}}), "values must not contain commas")
		rejected(molecules({filters = {max_phase__range = {1, 2, 3}}}), "must list 1 to 2 values")
		rejected(molecules({filters = {max_phase__range = {1}}}), "must be {low, high}")
		rejected(molecules({filters = {max_phase__in = "3,x"}}), "max_phase__in must be a finite number")
		rejected(molecules({filters = {molecule_structures__canonical_smiles__flexmatch = "C C"}}), "without spaces")
		rejected(molecules({order_by = "score"}), "order_by contains score, which cannot sort molecule results")
		rejected(molecules({order_by = "--pref_name"}), "lowercase ChEMBL field names")
		rejected(molecules({order_by = {"pref_name", "max_phase", "usan_year", "molecule_type"}}), "order_by must list 1 to 3")
		rejected(molecules({order_by = "similarity"}), "cannot sort molecule results")
		rejected(molecules({fields = {"score"}}), "fields contains score, which is not a molecule field")
		rejected(molecules({fields = "pref_name,bogus"}), "fields contains bogus")
		rejected(molecules({fields = {}}), "fields must list 1 to 100")
		rejected(function() chembl.substructureMolecules({smiles = "c1ccccc1", fields = "molecule_synonyms"}) end,
			"not a substructure search field")
		for _, limit in {0, 2001, 1.5, "10", false} do
			rejected(molecules({limit = limit}), "limit must be an integer from 1 to 2000")
		end
		for _, offset in {-1, 0.5, 2 ^ 31} do
			rejected(molecules({offset = offset}), "offset must be an integer from 0 to 2147483647")
		end
		rejected(molecules({filters = {molecule_chembl_id__in = table.create(400, "CHEMBL1234567")}}), "the request is too long")

		rejected(function() chembl.similarMolecules() end, "similarMolecules takes either smiles or chembl_id")
		rejected(function() chembl.similarMolecules({smiles = "CCO", chembl_id = "CHEMBL25"}) end, "takes either smiles or chembl_id")
		rejected(function() chembl.similarMolecules({smiles = "CCO", similarity = 39}) end, "similarity must be an integer from 40 to 100")
		rejected(function() chembl.similarMolecules({smiles = "CCO", similarity = 101}) end, "from 40 to 100")
		rejected(function() chembl.similarMolecules({smiles = "C C O"}) end, "smiles must be a SMILES string")
		rejected(function() chembl.similarMolecules({smiles = "CCO\n"}) end, "without spaces")
		rejected(function() chembl.similarMolecules({chembl_id = "aspirin"}) end, "chembl_id must be a ChEMBL ID")
		rejected(function() chembl.similarMolecules({smiles = "CCO", q = "x"}) end, "has no q text search")
		rejected(function() chembl.substructureMolecules({smiles = "CCCC"}) end, "smiles must be a SMILES string of 5 to 1000")

		for _, id in {"CHEMBL", "CHEMBL25/../x", "25", "", 25, "BSYNRYMUTXBXSQ-UHFFFAOYSA", "BSYNRYMUTXBXSQ-UHFFFAOYSA-N/x"} do
			rejected(function() chembl.getMolecule(id) end, "id must be a ChEMBL ID such as CHEMBL25 or a standard InChIKey")
		end
		rejected(function() chembl.getTarget("BSYNRYMUTXBXSQ-UHFFFAOYSA-N") end, "id must be a ChEMBL ID such as CHEMBL25")
		rejected(function() chembl.getTarget() end, "id must be a ChEMBL ID")
		for _, id in {0, -1, 1.5, "12a", "", "CHEMBL25", 2 ^ 53} do
			rejected(function() chembl.getActivity(id) end, "id must be an integer from 1 to")
		end
		rejected(function() chembl.getMolecule("CHEMBL25", {only = "pref_name"}) end, "getMolecule received an unknown option only")
		rejected(function() chembl.getMolecule("CHEMBL25", {fields = "score"}) end, "fields contains score")
		rejected(function() chembl.getMolecule("CHEMBL25", "all") end, "getMolecule options must be a table")

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
		local search = molecules({q = "aspirin"})
		local function similar() chembl.similarMolecules({smiles = "C1CC1C(", similarity = 70}) end
		local function read() chembl.getMolecule("CHEMBL999999999") end
		local traceback = ', "traceback": "Traceback (most recent call last):\\n  File \\"/chembl_ws_py3/src/resource.py\\""}'

		upstream(400, '{"error_message": "No search query provided"}', {}, search,
			{"ChEMBL HTTP 400: No search query provided", '"retryable":false'})
		upstream(500, '{"error_message": "Problem standardizing the query molecule"' .. traceback, {}, similar,
			{"ChEMBL HTTP 500: Problem standardizing the query molecule", '"retryable":false'}, "Traceback")
		upstream(500, '{"error_message": "Python argument types in\\n    rdkit.Chem.rdmolops.SanitizeMol(NoneType)"' .. traceback, {}, similar,
			{"HTTP 500: Python argument types in rdkit.Chem.rdmolops.SanitizeMol(NoneType)"}, "chembl_ws_py3")
		upstream(400, '{"error_message": "' .. string.rep("y", 1000) .. '"}', {}, search, {"HTTP 400: " .. string.rep("y", 300)}, string.rep("y", 301))
		upstream(400, '{"error_message": "' .. string.rep("y", 299) .. 'é"}', {}, search, {"HTTP 400: " .. string.rep("y", 299)})
		upstream(404, "", {}, read, {"ChEMBL HTTP 404: molecule CHEMBL999999999 was not found", '"retryable":false'})
		upstream(404, "<!DOCTYPE html><html><title>Page not found at /chembl/api/data/x</title>" .. string.rep("<p>urlconf</p>", 9000), {}, read,
			{"HTTP 404: molecule CHEMBL999999999 was not found"}, "urlconf")
		upstream(404, '{"error_message": "Couldn\'t find an instance of \'MoleculeDictionary\' which matched \'chembl_id=[\'CHEMBL9\']\'."' .. traceback, {},
			function() chembl.similarMolecules({chembl_id = "CHEMBL9"}) end, {"HTTP 404: Couldn't find an instance of 'MoleculeDictionary'"}, "Traceback")
		upstream(500, "<html><body>Internal Server Error</body></html>", {}, search, {"ChEMBL HTTP 500", '"retryable":true'}, "Internal")
		upstream(502, "", {}, search, {"ChEMBL HTTP 502", '"retryable":true'})
		upstream(504, '{"error_message": "timeout"}', {}, read, {"HTTP 504: timeout", '"retryable":true'})
		upstream(429, "Too Many Requests", {["retry-after"] = {"7"}}, search, {"HTTP 429", "retry after 7s", '"retryable":true'}, "Too Many")
		upstream(503, "", {["retry-after"] = {"Thu, 29 Oct 2026 20:00:00 GMT"}}, search,
			{"retry after Thu, 29 Oct 2026 20:00:00 GMT", '"retryable":true'}, "GMTs")
		upstream(301, "", {location = {"https://www.ebi.ac.uk/chembl/ws"}}, read, {"HTTP 301: unexpected redirect", '"retryable":false'}, "/ws")
		upstream(200, "<?xml version='1.0'?><response/>", {}, read, {"invalid JSON object", '"retryable":false'})
		upstream(200, "[]", {}, search, {"invalid JSON object"})
		upstream(200, '{"molecules": {}, "page_meta": null}', {}, search, {"unexpected molecule page", '"retryable":false'})
		upstream(200, '{"targets": [], "page_meta": {"total_count": 0}}', {}, search, {"unexpected molecule page"})
		upstream(200, '{"molecules": [], "page_meta": {"total_count": "3"}}', {}, search, {"unexpected molecule page"})
		upstream(200, '{"x":"' .. string.rep("z", 4 * 1024 * 1024) .. '"}', {}, read,
			{"more data than one call can hold; request fewer fields", '"retryable":false'}, "limit")
		upstream(200, '{"molecules":[],"x":"' .. string.rep("z", 4 * 1024 * 1024) .. '"}', {}, search, {"more data than one call can hold; request fewer fields or a lower limit"})

		requestError = {code = "timeout", message = "request deadline"}
		upstream(200, "", {}, search, {"ChEMBL did not answer within 20 s", '"retryable":true'})
		upstream(200, "", {}, read, {"did not answer within 20 s"})
		-- Other request failures pass through unchanged; the stand-in table loses its message across the export boundary.
		requestError = {code = "access_denied", message = "origin not allowed"}
		upstream(200, "", {}, read, {"error"}, "retryable")
		requestError = nil
		readError = {code = "io_error", message = "connection reset by peer"}
		upstream(200, "", {}, search, {"ChEMBL response failed: connection reset by peer", '"retryable":true'}, "more data")
		readError = {code = "cancelled", message = "invocation cancelled"}
		local before = calls
		local ok, err = pcall(read)
		-- A stand-in error loses its native identity across the export boundary; it must still not become an upstream failure.
		assert(not ok and not string.find(tostring(err), "retryable", 1, true), "cancellation became an upstream error: " .. tostring(err))
		assert(calls == before + 1)
		readError = nil
	end,
}
