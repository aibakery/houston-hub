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

func TestNativeSchemasAndConnectorTransport(t *testing.T) {
	b, err := os.ReadFile("../../connectors/gusto/lib/help.luau")
	if err != nil {
		t.Fatal(err)
	}
	modules := map[string]string{"lib/help.luau": string(b)}
	m, err := manifest.Parse([]byte(`{"schema_version":1,"name":"Gusto schema fixture","files":["main.luau"],"proxy":[{"match":{"protocol":"http","host":["example.com"]},"action":{}}]}`))
	if err != nil {
		t.Fatal(err)
	}
	for _, tc := range []struct {
		name, operation, input string
		valid                  bool
	}{

		{"numeric path", "getBenefit", "{\"benefit_id\":1}", true},
		{"unsafe identifier", "getEmployee", "{\"employee_id\":\"../employee\"}", false},
		{"query null", "listEmployees", "{\"company_id\":\"company-1\",\"page\":null}", false},
		{"CSV include", "getPayroll", "{\"company_id\":\"company-1\",\"payroll_id\":\"payroll-1\",\"include\":\"taxes,deductions\"}", true},
		{"unknown include", "getPayroll", "{\"company_id\":\"company-1\",\"payroll_id\":\"payroll-1\",\"include\":\"taxes,typo\"}", false},
		{"empty filter", "listPayrolls", "{\"company_id\":\"company-1\",\"processing_statuses\":[]}", false},
		{"employee onboarding email", "createEmployee", "{\"company_id\":\"company-1\",\"first_name\":\"Ana\",\"last_name\":\"Example\",\"self_onboarding\":true}", false},
		{"employee onboarding null email", "createEmployee", "{\"company_id\":\"company-1\",\"first_name\":\"Ana\",\"last_name\":\"Example\",\"self_onboarding\":true,\"email\":null}", false},
		{"admin onboarding null email", "createEmployee", "{\"company_id\":\"company-1\",\"first_name\":\"Ana\",\"last_name\":\"Example\",\"self_onboarding\":false,\"email\":null}", true},
		{"business contractor", "createContractor", "{\"company_id\":\"company-1\",\"type\":\"Business\",\"wage_type\":\"Fixed\",\"start_date\":\"2026-11-01\",\"business_name\":\"Example LLC\"}", true},
		{"business name required", "createContractor", "{\"company_id\":\"company-1\",\"type\":\"Business\",\"wage_type\":\"Fixed\",\"start_date\":\"2026-11-01\"}", false},
		{"hourly rate required", "createContractor", "{\"company_id\":\"company-1\",\"type\":\"Individual\",\"wage_type\":\"Hourly\",\"start_date\":\"2026-11-01\",\"first_name\":\"Bo\",\"last_name\":\"Example\"}", false},
		{"native compensation enum", "createCompensation", "{\"job_id\":\"job-1\",\"rate\":\"35.00\",\"payment_unit\":\"Hour\",\"flsa_status\":\"Nonexempt\"}", true},
		{"numeric compensation amount", "createCompensation", "{\"job_id\":\"job-1\",\"rate\":35,\"payment_unit\":\"Hour\",\"flsa_status\":\"Nonexempt\"}", false},
		{"compensation enum case", "createCompensation", "{\"job_id\":\"job-1\",\"rate\":\"35.00\",\"payment_unit\":\"hour\",\"flsa_status\":\"Nonexempt\"}", false},
		{"payroll entry version required", "updatePayroll", "{\"company_id\":\"company-1\",\"payroll_id\":\"payroll-1\",\"employee_compensations\":[{\"employee_uuid\":\"employee-1\"}]}", false},
		{"payroll native nested amount", "updatePayroll", "{\"company_id\":\"company-1\",\"payroll_id\":\"payroll-1\",\"employee_compensations\":[{\"employee_uuid\":\"employee-1\",\"version\":\"current\",\"fixed_compensations\":[{\"name\":\"Bonus\",\"amount\":100}]}]}", false},
		{"payroll partial entry", "updatePayroll", "{\"company_id\":\"company-1\",\"payroll_id\":\"payroll-1\",\"employee_compensations\":[{\"employee_uuid\":\"employee-1\",\"version\":\"current\",\"memo\":\"Thank you\"}]}", true},
		{"PTO selector exclusive", "updatePayroll", "{\"company_id\":\"company-1\",\"payroll_id\":\"payroll-1\",\"employee_compensations\":[{\"employee_uuid\":\"employee-1\",\"version\":\"current\",\"paid_time_off\":[{\"name\":\"Vacation Hours\",\"policy_uuid\":\"policy-1\",\"hours\":\"8.000\"}]}]}", false},
		{"native reimbursement number", "createRecurringReimbursement", "{\"employee_id\":\"employee-1\",\"description\":\"Internet\",\"amount\":50}", true},
		{"reimbursement string", "createRecurringReimbursement", "{\"employee_id\":\"employee-1\",\"description\":\"Internet\",\"amount\":\"50.00\"}", false},
		{"time sheet nested classification", "createTimeSheet", "{\"company_id\":\"company-1\",\"entity_type\":\"Employee\",\"entity_uuid\":\"employee-1\",\"shift_started_at\":\"2026-11-16T09:00:00Z\",\"time_zone\":\"UTC\",\"entries\":[{\"hours_worked\":8,\"pay_classification\":\"typo\"}]}", false},
		{"calculation allow list", "calculateAccruingTimeOffHours", "{\"payroll_id\":\"payroll-1\",\"employee_id\":\"employee-1\",\"regular_hours_worked\":\"8.000\"}", true},
		{"calculation unknown field", "calculateAccruingTimeOffHours", "{\"payroll_id\":\"payroll-1\",\"employee_id\":\"employee-1\",\"regular_hours_worked\":\"8.000\",\"rate\":\"100\"}", false},
		{"report integration kind", "createGeneralLedgerReport", "{\"payroll_uuid\":\"payroll-1\",\"aggregation\":\"integration\"}", false},
		{"delete version required", "deleteTimeSheet", "{\"time_sheet_uuid\":\"sheet-1\"}", false},
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
