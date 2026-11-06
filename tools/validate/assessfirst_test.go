package main

import (
	"net/http"
	"strings"
	"testing"
)

// AssessFirst reads the bare token from AF-Token. Only API v2 is routed: v1 reaches
// consents and campaigns, and the candidate iframe takes assessments as the candidate.
// Each connection reaches either production or the Simu test environment, never both.
// Completion status only ("custom") keeps the reads that return no assessment results.
func TestAssessFirstAccessRoutes(t *testing.T) {
	m := parseManifest(t, "../../connectors/assessfirst/houston.json")
	const token = "fixture-af-token"
	const c, pm, g = "/ab4699c9169d469c81082accfbe91584", "/1d9c92277e264fe49a4ce330e51e6ac7", "/786a70ccd1454e83bfae271ffa721c0d"
	if _, err := m.Resolve(nil, nil, nil, "token"); err == nil {
		t.Fatal("accepted missing token")
	}
	if _, err := m.Resolve(nil, map[string]any{"api_host": "attacker.example"}, map[string]any{"token": token}, "token"); err == nil || !strings.Contains(err.Error(), "api_host") {
		t.Fatalf("accepted an environment host outside the options: %v", err)
	}
	for _, hosts := range [][2]string{{"app.assessfirst.com", "simu.assessfirst.com"}, {"simu.assessfirst.com", "app.assessfirst.com"}} {
		host, other := hosts[0], hosts[1]
		api := "https://" + host + "/betty-V2"
		for _, access := range []string{"custom", "read-only", "read-write"} {
			r, err := m.Resolve(nil, map[string]any{"access": access, "api_host": host}, map[string]any{"token": token}, "token")
			if err != nil {
				t.Fatal(err)
			}
			if len(r.PublicConfig) != 2 || r.PublicConfig["access"] != access || r.PublicConfig["api_host"] != host {
				t.Fatalf("unexpected Lua config: %v", r.PublicConfig)
			}
			assert := func(allowed bool, routes ...string) {
				t.Helper()
				for _, route := range routes {
					method, url, _ := strings.Cut(route, " ")
					recipe, err := r.Proxy.HTTPRecipe(method, url, nil)
					if (err == nil) != allowed {
						t.Fatalf("%s %s allowed=%v: %v", access, route, err == nil, err)
					}
					if err != nil {
						continue
					}
					assertPrepareRejectsMethodOverrides(t, recipe, r.Context, access+" "+route)
					headers, err := recipe.Prepare(r.Context, http.Header{"Af-Token": {"forged"}})
					if err != nil || headers.Get("AF-Token") != token {
						t.Fatalf("credential injection for %s: %v %v", route, headers, err)
					}
				}
			}
			assert(true, "GET "+api+"/candidates?email=a%40example.com&page=2", "GET "+api+"/candidate"+c+"/completion?pm_uuid=x",
				"GET "+api+"/predictive-models", "GET "+api+"/groups", "GET "+api+"/groups"+g+"/users")
			assert(access != "custom", "GET "+api+"/locales", "GET "+api+"/candidate"+c, "GET "+api+"/candidate"+c+"/scores",
				"GET "+api+"/candidate"+c+"/synthesis", "GET "+api+"/candidate"+c+"/reports", "GET "+api+"/candidate"+c+"/report/20?pm_uuid=x",
				"GET "+api+"/candidate"+c+"/adequacies"+pm, "GET "+api+"/candidate"+c+"/career/top", "GET "+api+"/candidate"+c+"/init-voice"+pm,
				"GET "+api+"/onepager/candidate"+c+"/results", "GET "+api+"/benchmarks", "GET "+api+"/recruiters", "GET "+api+"/webhooks")
			assert(access == "read-write", "POST "+api+"/candidate/send-invitation", "POST "+api+"/candidate", "POST "+api+"/candidate"+c+"/init-voice"+pm,
				"POST "+api+"/webhooks", "DELETE "+api+"/webhooks"+g, "POST "+api+"/groups", "DELETE "+api+"/groups"+g,
				"POST "+api+"/groups"+g+"/user"+c, "DELETE "+api+"/groups"+g+"/user"+c)
			assert(false, "GET "+api+"/candidate/iframe/token/assessment", "GET https://"+host+"/betty/consents",
				"POST https://"+host+"/betty/users", "GET https://"+other+"/betty-V2/locales",
				"GET https://report.assessfirst.com/report/summary_report"+c, "GET https://"+host+".attacker.test/betty-V2/locales",
				"GET http://"+host+"/betty-V2/locales", "GET https://"+host+":8443/betty-V2/locales",
				"PUT "+api+"/groups"+g, "PATCH "+api+"/webhooks"+g, "DELETE "+api+"/candidate"+c, "GET "+api+"/candidate/%2e%2e/recruiters")
		}
	}
}
