package main

import (
	"net/http"
	"testing"

	"github.com/aibakery/houston-hub/manifest"
)

const (
	pubmedEUtilities = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils"
	pubmedBioC       = "https://www.ncbi.nlm.nih.gov/research/bionlp/RESTful/pmcoa.cgi/BioC_json"
)

func resolvePubMed(t *testing.T, key string) *manifest.Resolved {
	t.Helper()
	config := map[string]any{}
	if key != "" {
		config["api_key"] = key
	}
	r, err := parseManifest(t, "../../connectors/pubmed/houston.json").Resolve(nil, config, nil, "")
	if err != nil {
		t.Fatal(err)
	}
	return r
}

func TestPubMedPublicReadRoutes(t *testing.T) {
	for _, key := range []string{"", "synthetic-ncbi-key"} {
		r := resolvePubMed(t, key)
		assertAuthorizedRoutes(t, r, "", true,
			"POST "+pubmedEUtilities+"/esearch.fcgi", "POST "+pubmedEUtilities+"/esummary.fcgi",
			"POST "+pubmedEUtilities+"/efetch.fcgi", "POST "+pubmedEUtilities+"/elink.fcgi",
			"GET "+pubmedBioC+"/PMC4412151/unicode", "GET "+pubmedBioC+"/25977807/unicode")
		assertAuthorizedRoutes(t, r, "", false,
			"GET "+pubmedEUtilities+"/esearch.fcgi?db=pubmed&term=x", "POST "+pubmedEUtilities+"/epost.fcgi",
			"POST "+pubmedEUtilities+"/einfo.fcgi", "POST "+pubmedEUtilities+"/espell.fcgi", "GET "+pubmedEUtilities+"/ecitmatch.cgi",
			"POST "+pubmedEUtilities+"/esearch.fcgi/x", "POST https://eutils.ncbi.nlm.nih.gov.example.com/entrez/eutils/esearch.fcgi",
			"POST http://eutils.ncbi.nlm.nih.gov:8080/entrez/eutils/esearch.fcgi", "POST https://www.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi",
			"POST "+pubmedBioC+"/PMC4412151/unicode", "GET "+pubmedBioC+"/PMC4412151/ascii", "GET "+pubmedBioC+"/%2e%2e/unicode",
			"GET https://www.ncbi.nlm.nih.gov/research/bionlp/RESTful/pubmed.cgi/BioC_json/25977807/unicode",
			"GET https://www.ncbi.nlm.nih.gov/research/pubtator3-api/publications/export/biocjson",
			"GET https://pmc.ncbi.nlm.nih.gov/tools/idconv/api/v1/articles/", "GET https://ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi")
	}
}

func TestPubMedSendsTheKeyOnlyToEUtilities(t *testing.T) {
	dropped := []string{"X-HTTP-Method-Override", "X-HTTP-Method", "X-Method-Override", "Authorization", "Cookie"}
	for _, key := range []string{"", "synthetic-ncbi-key"} {
		r := resolvePubMed(t, key)
		search := pubmedEUtilities + "/esearch.fcgi"
		if key != "" {
			search += "?api_key=" + key
		}
		for _, route := range []struct{ method, url, want string }{
			{"POST", pubmedEUtilities + "/esearch.fcgi", search},
			{"GET", pubmedBioC + "/PMC4412151/unicode", pubmedBioC + "/PMC4412151/unicode"},
		} {
			recipe, err := r.Proxy.HTTPRecipe(route.method, route.url, nil)
			if err != nil {
				t.Fatal(err)
			}
			if prepared, err := recipe.PrepareURL(r.Context); err != nil || prepared != route.want {
				t.Fatalf("key %q: %s prepared as %s: %v", key, route.url, prepared, err)
			}
			caller := http.Header{"Content-Type": {"application/x-www-form-urlencoded"}}
			for _, name := range dropped {
				caller.Set(name, "caller-value")
			}
			headers, err := recipe.Prepare(r.Context, caller)
			if err != nil || headers.Get("Content-Type") != "application/x-www-form-urlencoded" {
				t.Fatalf("prepare: %v %v", headers, err)
			}
			for _, name := range dropped {
				if headers.Get(name) != "" {
					t.Fatalf("%s reached NCBI", name)
				}
			}
		}
	}
}

func TestPubMedEmptyKeyNeverReachesNCBI(t *testing.T) {
	m := parseManifest(t, "../../connectors/pubmed/houston.json")
	r, err := m.Resolve(nil, map[string]any{"api_key": ""}, nil, "")
	if err == nil {
		recipe, err := r.Proxy.HTTPRecipe("POST", pubmedEUtilities+"/esearch.fcgi", nil)
		if err != nil {
			t.Fatal(err)
		}
		prepared, _ := recipe.PrepareURL(r.Context)
		t.Fatalf("an empty key resolved and prepared %s", prepared)
	}
}
