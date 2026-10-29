package main

import (
	"net/http"
	"testing"

	"github.com/aibakery/houston-hub/manifest"
)

func resolveBioRxiv(t *testing.T) *manifest.Resolved {
	t.Helper()
	r, err := parseManifest(t, "../../connectors/biorxiv/houston.json").Resolve(nil, nil, nil, "")
	if err != nil {
		t.Fatal(err)
	}
	return r
}

func TestBioRxivPublicReadRoutes(t *testing.T) {
	r := resolveBioRxiv(t)
	const api = "https://api.biorxiv.org"
	const search = "https://www.ebi.ac.uk/europepmc/webservices/rest/search"
	assertAuthorizedRoutes(t, r, "", true,
		"GET "+api+"/details/biorxiv/2025-03-01/2025-03-07/30/json?category=cell_biology",
		"GET "+api+"/details/medrxiv/10.1101/2020.09.09.20191205/na/json",
		"GET "+api+"/funder/biorxiv/2025-04-10/2025-07-10/00k4n6c32/0/json",
		"GET "+api+"/pubs/medrxiv/10.1371/journal.pone.0256482/na/json",
		"GET "+api+"/pubs/medrxiv/10.1016/S2468-2667%2820%2930133-X/na/json", "GET "+api+"/pubs/biorxiv/2025-04-01/2025-04-30/100",
		"GET "+search+"?query=%28x%29%20AND%20SRC%3APPR&resultType=core&pageSize=25&format=json&cursorMark=%2A",
		"GET https://www.biorxiv.org/content/10.1101/339747v4.full.pdf",
		"GET https://www.medrxiv.org/content/10.64898/2026.09.01.26361059v2.full.pdf")
	assertAuthorizedRoutes(t, r, "", false,
		"POST "+api+"/details/biorxiv/2025-03-01/2025-03-07/0/json", "GET "+api+"/details/arxiv/2025-03-01/2025-03-07",
		"GET "+api+"/sum/m", "GET "+api+"/usage/m/biorxiv", "GET "+api+"/pub/2025-03-01/2025-03-07", "GET "+api+"/publisher/10.15252/2025-03-01/2025-03-07",
		"GET "+api+"/details/biorxiv/%2e%2e/sum/m", "GET https://api.biorxiv.org.example.com/details/biorxiv/1/na/json",
		"GET http://api.biorxiv.org:8080/details/biorxiv/1/na/json", "GET https://connect.biorxiv.org/details/biorxiv/1/na/json",
		"POST "+search, "GET "+search+"POST", "GET https://www.ebi.ac.uk/europepmc/webservices/rest/PPR1/fullTextXML",
		"GET https://www.ebi.ac.uk/chembl/api/data/molecule.json",
		"POST https://www.biorxiv.org/content/10.1101/339747v4.full.pdf", "GET https://www.biorxiv.org/content/early/2019/05/10/339747.source.xml",
		"GET https://www.biorxiv.org/content/10.1101/339747/v4/full.pdf", "GET https://www.biorxiv.org/content/10.1000/339747.full.pdf",
		"GET https://www.biorxiv.org/user/login", "GET https://biorxiv.org/content/10.1101/339747v4.full.pdf",
		"GET https://connect.biorxiv.org/content/10.1101/339747v4.full.pdf")
}

func TestBioRxivDropsCallerOverridesAndCredentials(t *testing.T) {
	r := resolveBioRxiv(t)
	dropped := []string{"X-HTTP-Method-Override", "X-HTTP-Method", "X-Method-Override", "Authorization", "Cookie"}
	for _, target := range []string{
		"https://api.biorxiv.org/details/biorxiv/10.1101/339747/na/json",
		"https://www.ebi.ac.uk/europepmc/webservices/rest/search",
		"https://www.medrxiv.org/content/10.1101/2020.09.09.20191205v2.full.pdf",
	} {
		recipe, err := r.Proxy.HTTPRecipe("GET", target, nil)
		if err != nil {
			t.Fatal(err)
		}
		caller := http.Header{"Accept": {"application/json"}}
		for _, name := range dropped {
			caller.Set(name, "caller-value")
		}
		headers, err := recipe.Prepare(r.Context, caller)
		if err != nil || headers.Get("Accept") != "application/json" {
			t.Fatalf("prepare %s: %v %v", target, headers, err)
		}
		for _, name := range dropped {
			if headers.Get(name) != "" {
				t.Fatalf("%s reached %s", name, target)
			}
		}
	}
}
