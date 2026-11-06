package main

// These requirements are stated in the versioned reference descriptions but
// omitted from its machine-readable required lists. Keep native nested schemas.
func supplement(name string, schema object) {
	when := func(field string, value any, required ...string) {
		rule := object{"if": object{"properties": object{field: object{"const": value}}, "required": []string{field}}, "then": object{"required": required}}
		schema["allOf"] = append(list(schema["allOf"]), rule)
	}
	if name == "createEmployee" || name == "createContractor" {
		when("self_onboarding", true, "email")
		schema["allOf"] = append(list(schema["allOf"]), object{"if": object{"properties": object{"self_onboarding": object{"const": true}}, "required": []string{"self_onboarding"}}, "then": object{"properties": object{"email": object{"type": "string", "minLength": 1}}}})
	}
	if name == "createContractor" {
		when("type", "Individual", "first_name", "last_name")
		when("type", "Business", "business_name")
		when("wage_type", "Hourly", "hourly_rate")
		schema["allOf"] = append(list(schema["allOf"]), object{"if": object{"properties": object{"type": object{"const": "Individual"}, "file_new_hire_report": object{"const": true}}, "required": []string{"type", "file_new_hire_report"}}, "then": object{"required": []string{"work_state"}, "properties": object{"work_state": object{"type": "string"}}}})
	}
	if name == "updatePayroll" {
		entries := obj(obj(obj(list(schema["allOf"])[0])["properties"])["employee_compensations"])
		entries["maxItems"] = 100
		entry := obj(entries["items"])
		entry["required"] = []string{"employee_uuid", "version"}
		props := obj(entry["properties"])
		for _, pair := range [][2]string{{"fixed_compensations", "amount"}, {"hourly_compensations", "hours"}} {
			item := obj(obj(props[pair[0]])["items"])
			item["required"] = []string{"name", pair[1]}
		}
		pto := obj(obj(props["paid_time_off"])["items"])
		pto["required"] = []string{"hours"}
		pto["oneOf"] = []any{object{"required": []string{"name"}, "not": object{"required": []string{"policy_uuid"}}}, object{"required": []string{"policy_uuid"}, "not": object{"required": []string{"name"}}}}
	}
	if name == "createGeneralLedgerReport" {
		when("aggregation", "integration", "integration_type")
	}
}
