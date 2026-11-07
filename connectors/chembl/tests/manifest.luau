return {
	contract = function(m)
		-- TestChEMBLPublicReadRoutes
		do
			local r, err = m.resolve(nil, nil, nil, "")
			assert(not err, tostring(err))
			local api = "https://www.ebi.ac.uk/chembl/api/data"
			for _, route in
				{
					"GET "
						.. api
						.. "/molecule.json?pref_name__icontains=aspirin&only=molecule_chembl_id&limit=1000&offset=0",
					"GET " .. api .. "/molecule/search.json?q=aspirin",
					"GET " .. api .. "/molecule/CHEMBL25.json",
					"GET " .. api .. "/target/CHEMBL203.json?only=target_chembl_id",
					"GET " .. api .. "/activity/31863.json",
					"GET " .. api .. "/drug_indication.json?molecule_chembl_id=CHEMBL25",
					"GET "
						.. api
						.. "/similarity.json?smiles=CC%28%3DO%29Oc1ccccc1C%28%3DO%29O&similarity=80",
					"GET " .. api .. "/substructure.json?smiles=C%23CC%2FC%3DC%5Cc1ccccc1",
				}
			do
				m.routes(r, "", true, { route })
			end
			m.routes(r, "", false, {
				"POST " .. api .. "/similarity.json",
				"POST " .. api .. "/molecule.json",
				"DELETE " .. api .. "/molecule/CHEMBL25.json",
				"GET " .. api .. "/molecule/set/CHEMBL25;CHEMBL2.json",
				"GET " .. api .. "/similarity/CCO/80.json",
				"GET " .. api .. "/status.json",
				"GET " .. api .. "/chembl_id_lookup/CHEMBL25.json",
				"GET " .. api .. "/image/CHEMBL25",
				"GET " .. api .. "/molecule/%2e%2e/status.json",
				"GET https://www.ebi.ac.uk/ebisearch/ws/rest/chembl",
				"GET https://ebi.ac.uk/chembl/api/data/molecule.json",
				"GET https://www.ebi.ac.uk.example.com/chembl/api/data/molecule.json",
				"GET http://www.ebi.ac.uk:8080/chembl/api/data/molecule.json",
			})
		end
		-- TestChEMBLRejectsMethodOverridesAndDropsCredentials
		do
			local r, err = m.resolve(nil, nil, nil, "")
			assert(not err, tostring(err))
			local recipe, err = m.recipe(r, "GET", "https://www.ebi.ac.uk/chembl/api/data/molecule.json", nil)
			assert(not err, tostring(err))
			m.rejectPreparedOverrides(recipe, r.Context, "GET molecule.json")
			local dropped = { "Authorization", "Cookie" }
			local caller = { Accept = { "application/json" } }
			for _, name in dropped do
				caller[name] = { "caller-value" }
			end
			local headers, err = m.prepare(recipe, r.Context, caller)
			if (err ~= nil) or (m.header(headers, "Accept") ~= "application/json") then
				m.fail("prepare: %s %s", headers, err)
			end
			for _, name in dropped do
				if m.header(headers, name) ~= "" then
					m.fail("%s reached ChEMBL", name)
				end
			end
		end
	end,
}
