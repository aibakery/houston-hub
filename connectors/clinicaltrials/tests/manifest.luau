return {
	contract = function(m)
		-- TestClinicalTrialsPublicReadRoutes
		do
			local r, err = m.resolve(nil, nil, nil, "")
			assert(not err, tostring(err))
			local api = "https://clinicaltrials.gov/api/v2"
			for _, route in
				{
					"GET " .. api .. "/studies?query.cond=asthma&pageSize=100",
					"GET " .. api .. "/studies/NCT04368728?fields=ResultsSection",
				}
			do
				m.routes(r, "forged", true, { route })
			end
			m.routes(r, "", false, {
				"POST " .. api .. "/studies",
				"HEAD " .. api .. "/studies",
				"GET " .. api .. "/studies/NCT04368728/history",
				"GET " .. api .. "/stats/size",
				"GET " .. api .. "/version",
				"GET https://clinicaltrials.gov/api/legacy/study-fields",
				"GET https://www.clinicaltrials.gov/api/v2/studies",
				"GET https://classic.clinicaltrials.gov/api/v2/studies",
				"GET https://clinicaltrials.gov.example.com/api/v2/studies",
				"GET http://clinicaltrials.gov:8080/api/v2/studies",
				"GET " .. api .. "/studies/%2e%2e/version",
			})
		end
	end,
}
