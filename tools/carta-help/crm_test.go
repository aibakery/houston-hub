package main

import (
	"context"
	"encoding/json"
	"os"
	"strings"
	"testing"

	"github.com/aibakery/houston-hub/manifest"
	"github.com/aibakery/houston-hub/tools/conformance"
)

func TestCRMFiltersAndNativeFields(t *testing.T) {
	b, err := os.ReadFile("../../connectors/carta-crm/lib/help.luau")
	if err != nil {
		t.Fatal(err)
	}
	modules := map[string]string{"lib/help.luau": string(b)}
	m, err := manifest.Parse([]byte(`{"schema_version":1,"name":"Carta CRM schema fixture","files":["main.luau"],"proxy":[{"match":{"protocol":"http","host":["example.com"]},"action":{}}]}`))
	if err != nil {
		t.Fatal(err)
	}
	for _, tc := range []struct {
		name, operation, input string
		valid                  bool
	}{

		{"blank filter", "searchCompanies", `{"filters":[{"field_id":"website","operator":"blank"}]}`, true},
		{"not blank filter", "searchCompanies", `{"filters":[{"field_id":"website","operator":"not_blank"}]}`, true},
		{"value required", "searchCompanies", `{"filters":[{"field_id":"website","operator":"eq"}]}`, false},
		{"in requires array", "searchCompanies", `{"filters":[{"field_id":"lists","operator":"in","value":"list-1"}]}`, false},
		{"between pair", "searchCompanies", `{"filters":[{"field_id":"created","operator":"between","value":["2026-10-01","2026-10-31"]}]}`, true},
		{"between needs two", "searchCompanies", `{"filters":[{"field_id":"created","operator":"between","value":["2026-10-01"]}]}`, false},
		{"relative date", "searchCompanies", `{"filters":[{"field_id":"created","operator":"last_x","value":"12 months"}]}`, true},
		{"relative date unit", "searchCompanies", `{"filters":[{"field_id":"created","operator":"last_x","value":"12 seconds"}]}`, false},
		{"aggregate metric", "aggregateDeals", `{"group_by":["stage"],"metric":{"field_id":"amount","agg_func":"sum"}}`, true},
		{"aggregate one group", "aggregateDeals", `{"group_by":["stage","owner"]}`, false},
		{"aggregate metric required field", "aggregateDeals", `{"group_by":["stage"],"metric":{"agg_func":"sum"}}`, false},
		{"calendar day task", "createTask", `{"entityId":"65a1b2c3d4e5f60718293a4b","entityType":"DEAL","title":"Send memo","dueDate":"2026-11-30"}`, true},
		{"timestamp task", "createTask", `{"entityId":"65a1b2c3d4e5f60718293a4b","entityType":"DEAL","title":"Send memo","dueDate":"2026-11-30T12:00:00Z"}`, true},
		{"malformed date", "createTask", `{"entityId":"65a1b2c3d4e5f60718293a4b","entityType":"DEAL","title":"Send memo","dueDate":"next month"}`, false},
		{"task entity case", "createTask", `{"entityId":"65a1b2c3d4e5f60718293a4b","entityType":"deal","title":"Send memo","dueDate":"2026-11-30"}`, false},
		{"nullable frequency", "updateContact", `{"id":"65a1b2c3d4e5f60718293a4b","interactionFrequencyGoal":null}`, true},
		{"legacy import values", "createContact", `{"name":"Ana Example","dynamicInfo":{"source":"conference","year":2026}}`, true},
		{"legacy import nested value", "createContact", `{"name":"Ana Example","dynamicInfo":{"source":{"name":"conference"}}}`, false},
		{"native job dates", "createContact", `{"name":"Ana Example","jobs":[{"companyName":"Example","startedOn":{"year":2026,"month":1}}]}`, true},
		{"native job malformed date", "createContact", `{"name":"Ana Example","jobs":[{"startedOn":"2026-01"}]}`, false},
		{"typed note query", "listNotesByDomain", `{"domain":"example.com","entityTypes":["Company","Deal"]}`, true},
		{"query enum case", "listNotesByDomain", `{"domain":"example.com","entityTypes":["company"]}`, false},
		{"query timestamp", "listCalendarEvents", `{"startDate":"2026-11-01T00:00:00Z"}`, true},
		{"query null", "listCompanies", `{"limit":null}`, false},
		{"fund array", "getFundClosingsStatus", `{"fundCartaIds":[101,"102"]}`, true},
		{"empty fund array", "getFundClosingsStatus", `{"fundCartaIds":[]}`, false},
		{"domain path", "listCompanyNotes", `{"id":"example.com"}`, true},
		{"path traversal", "getCompany", `{"id":"../companies"}`, false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			operation, _ := json.Marshal(tc.operation)
			modules["main.luau"] = `local schema=require("lib/help.luau")[` + string(operation) + `].inputSchema;schema.examples={json.decode([====[` + tc.input + `]====])};return {invoke=function(input) return input end,help={text="Schema fixture",functions={invoke={description="Native input",inputSchema=schema}}}}`
			_, err := conformance.CheckCatalog(context.Background(), "", *m, modules, map[string]string{"example.luau": `return {scenario={},run=function(c) assert(type(fixture.example("invoke"))=="table") end}`})
			if tc.valid && err != nil {
				t.Fatal(err)
			}
			if !tc.valid && (err == nil || !strings.Contains(err.Error(), "inputSchema.examples[0]")) {
				t.Fatalf("invalid input should fail schema validation: %v", err)
			}
		})
	}
}
