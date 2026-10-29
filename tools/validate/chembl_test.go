package main

import "testing"

func TestChEMBLPublicReadRoutes(t *testing.T) {
	m := parseManifest(t, "../../connectors/chembl/houston.json")
	r, err := m.Resolve(nil, nil, nil, "")
	if err != nil {
		t.Fatal(err)
	}
	const api = "https://www.ebi.ac.uk/chembl/api/data"
	for _, route := range []string{
		"GET " + api + "/molecule.json?pref_name__icontains=aspirin&only=molecule_chembl_id&limit=1000&offset=0",
		"GET " + api + "/molecule/search.json?q=aspirin", "GET " + api + "/molecule/CHEMBL25.json",
		"GET " + api + "/target/CHEMBL203.json?only=target_chembl_id", "GET " + api + "/activity/31863.json",
		"GET " + api + "/drug_indication.json?molecule_chembl_id=CHEMBL25",
		"GET " + api + "/similarity.json?smiles=CC%28%3DO%29Oc1ccccc1C%28%3DO%29O&similarity=80",
		"GET " + api + "/substructure.json?smiles=C%23CC%2FC%3DC%5Cc1ccccc1",
	} {
		assertAuthorizedRoutes(t, r, "forged", true, route)
	}
	assertAuthorizedRoutes(t, r, "", false,
		"POST "+api+"/similarity.json", "POST "+api+"/molecule.json", "DELETE "+api+"/molecule/CHEMBL25.json",
		"GET "+api+"/molecule/set/CHEMBL25;CHEMBL2.json", "GET "+api+"/similarity/CCO/80.json", "GET "+api+"/status.json",
		"GET "+api+"/chembl_id_lookup/CHEMBL25.json", "GET "+api+"/image/CHEMBL25", "GET "+api+"/molecule/%2e%2e/status.json",
		"GET https://www.ebi.ac.uk/ebisearch/ws/rest/chembl", "GET https://ebi.ac.uk/chembl/api/data/molecule.json",
		"GET https://www.ebi.ac.uk.example.com/chembl/api/data/molecule.json", "GET http://www.ebi.ac.uk:8080/chembl/api/data/molecule.json")
}

func TestChEMBLRemovesMethodOverride(t *testing.T) {
	m := parseManifest(t, "../../connectors/chembl/houston.json")
	r, err := m.Resolve(nil, nil, nil, "")
	if err != nil {
		t.Fatal(err)
	}
	recipe, err := r.Proxy.HTTPRecipe("GET", "https://www.ebi.ac.uk/chembl/api/data/molecule.json", nil)
	if err != nil {
		t.Fatal(err)
	}
	headers, err := recipe.Prepare(r.Context, map[string][]string{"X-Http-Method-Override": {"DELETE"}, "Accept": {"application/json"}})
	if err != nil || headers.Get("X-HTTP-Method-Override") != "" || headers.Get("Accept") != "application/json" {
		t.Fatalf("method override kept: %v %v", headers, err)
	}
}
