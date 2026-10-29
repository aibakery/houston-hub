package main

import "testing"

func TestClinicalTrialsPublicReadRoutes(t *testing.T) {
	m := parseManifest(t, "../../connectors/clinicaltrials/houston.json")
	r, err := m.Resolve(nil, nil, nil, "")
	if err != nil {
		t.Fatal(err)
	}
	const api = "https://clinicaltrials.gov/api/v2"
	for _, route := range []string{"GET " + api + "/studies?query.cond=asthma&pageSize=100", "GET " + api + "/studies/NCT04368728?fields=ResultsSection"} {
		assertAuthorizedRoutes(t, r, "forged", true, route)
	}
	assertAuthorizedRoutes(t, r, "", false,
		"POST "+api+"/studies", "HEAD "+api+"/studies", "GET "+api+"/studies/NCT04368728/history",
		"GET "+api+"/stats/size", "GET "+api+"/version", "GET https://clinicaltrials.gov/api/legacy/study-fields",
		"GET https://www.clinicaltrials.gov/api/v2/studies", "GET https://classic.clinicaltrials.gov/api/v2/studies",
		"GET https://clinicaltrials.gov.example.com/api/v2/studies", "GET http://clinicaltrials.gov:8080/api/v2/studies",
		"GET "+api+"/studies/%2e%2e/version")
}
