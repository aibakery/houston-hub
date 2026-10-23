return {
	scenario = {publisher = {}, config = {access = "read-write", own_app = true, client_id = "fixture-client", client_secret = "fixture-secret"},
		auth_method = "own_app", auth_config = {}},
	configure = function()
		requests = {}
		status = 200
		payload = "{}"
		http = {request = function(req)
			table.insert(requests, req)
			return fixture.operation({statusCode = status, headers = {}, body = fixture.reader(payload)})
		end}
	end,
	run = function(gusto)
		local API = "https://api.gusto.com/v1"
		local COMPANY = "c2b9a6f0-1f3e-4a5b-9c8d-7e6f5a4b3c2d"
		local function last() return requests[#requests] end
		local function sent() return json.decode(last().body) end
		local function same(a, b)
			if type(a) ~= "table" or type(b) ~= "table" then return a == b end
			for key, value in a do if not same(value, b[key]) then return false end end
			for key in b do if a[key] == nil then return false end end
			return true
		end
		local function rejected(fn, expected)
			local before = #requests
			local ok, err = pcall(fn)
			assert(not ok and string.find(tostring(err), expected, 1, true), "wrong validation error: " .. tostring(err))
			assert(#requests == before, "invalid input reached Gusto")
		end

		local names = {}
		for name in gusto do if name ~= "help" then table.insert(names, name) end end
		table.sort(names)
		local WRITES = {
			"addDepartmentPeople", "addTimeOffPolicyEmployees", "createCompanyBenefit", "createCompensation", "createContractor", "createDepartment",
			"createEarningType", "createEmployee", "createEmployeeBenefit", "createGarnishment", "createHomeAddress", "createLocation",
			"createPayrollSync", "createRecurringReimbursement", "createRehire", "createSection603HighEarnerStatus", "createTermination",
			"createTimeSheet", "createWorkAddress", "createYtdBenefitAmountsFromDifferentCompany", "deleteCompanyBenefit", "deleteCompensation",
			"deleteDepartment", "deleteEarningType", "deleteEmployee", "deleteEmployeeBenefit", "deleteHomeAddress", "deleteRecurringReimbursement",
			"deleteRehire", "deleteTermination", "deleteTimeSheet", "deleteWorkAddress", "preparePayroll", "removeDepartmentPeople",
			"updateCompanyBenefit", "updateCompanyBenefitEmployeeBenefits", "updateCompensation", "updateContractor", "updateContributionExclusions",
			"updateDepartment", "updateEarningType", "updateEmployee", "updateEmployeeBenefit", "updateGarnishment", "updateHomeAddress",
			"updateLocation", "updatePayroll", "updateRecurringReimbursement", "updateRehire", "updateSection603HighEarnerStatus", "updateTermination",
			"updateTimeSheet", "updateWorkAddress"
		}
		local exported = {}
		for _, name in names do exported[name] = true end
		for _, name in WRITES do assert(exported[name], "write missing: " .. name) end
		assert(#names == 62 + #WRITES, "wrong read-write surface: " .. table.concat(names, ","))

		payload = '{"uuid":"e9","first_name":"Ada","last_name":"Lovelace","version":"v1"}'
		local employee = gusto.createEmployee({company_id = COMPANY, first_name = "Ada", last_name = "Lovelace", email = "ada@example.com", self_onboarding = true})
		assert(last().method == "POST" and last().url == API .. "/companies/" .. COMPANY .. "/employees")
		assert(last().headers["Content-Type"][1] == "application/json" and last().headers["X-Gusto-API-Version"][1] == "2026-06-15")
		assert(last().headers.Accept[1] == "application/json" and last().headers.Authorization == nil)
		assert(same(sent(), {first_name = "Ada", last_name = "Lovelace", email = "ada@example.com", self_onboarding = true}), last().body)
		assert(employee.uuid == "e9")

		gusto.updateEmployee({employee_id = "e9", version = "v1", preferred_first_name = "Countess", middle_initial = json.decode("null")})
		assert(last().method == "PUT" and last().url == API .. "/employees/e9")
		assert(same(sent(), {version = "v1", preferred_first_name = "Countess", middle_initial = json.decode("null")}), last().body)

		payload = '{"payroll_uuid":"p1","processing_status":"unprocessed","employee_compensations":[{"employee_uuid":"e9","version":"ev2"}]}'
		local draft = gusto.preparePayroll({company_id = COMPANY, payroll_id = "p1", per = 100})
		assert(last().method == "PUT" and last().url == API .. "/companies/" .. COMPANY .. "/payrolls/p1/prepare?per=100" and last().body == "{}")
		gusto.preparePayroll({company_id = COMPANY, payroll_id = "p1", employee_uuids = {"e9"}})
		assert(same(sent(), {employee_uuids = {"e9"}}), last().body)
		local line = draft.employee_compensations[1]
		gusto.updatePayroll({company_id = COMPANY, payroll_id = "p1",
			employee_compensations = {{employee_uuid = line.employee_uuid, version = line.version, fixed_compensations = {{name = "Bonus", amount = "500.00"}}}}})
		assert(last().method == "PUT" and last().url == API .. "/companies/" .. COMPANY .. "/payrolls/p1")
		assert(same(sent(), {employee_compensations = {{employee_uuid = "e9", version = "ev2", fixed_compensations = {{name = "Bonus", amount = "500.00"}}}}}), last().body)

		payload = '{"uuid":"t1","effective_date":"2026-11-30","version":"tv1"}'
		gusto.createTermination({employee_id = "e9", effective_date = "2026-11-30", run_termination_payroll = false})
		assert(last().method == "POST" and last().url == API .. "/employees/e9/terminations")
		assert(same(sent(), {effective_date = "2026-11-30", run_termination_payroll = false}), last().body)
		gusto.updateSection603HighEarnerStatus({employee_id = "e9", effective_year = 2026, is_high_earner = true})
		assert(last().method == "PATCH" and last().url == API .. "/employees/e9/section603_high_earner_statuses/2026" and same(sent(), {is_high_earner = true}))

		payload = ""
		status = 204
		local deleted = gusto.deleteTimeSheet({time_sheet_uuid = "ts1", version = "tsv3"})
		assert(last().method == "DELETE" and last().url == API .. "/time_tracking/time_sheets/ts1?version=tsv3" and last().body == nil)
		assert(last().headers["Content-Type"] == nil and deleted.success == true)
		assert(gusto.deleteEmployee({employee_id = "e9"}).success == true and last().method == "DELETE" and last().url == API .. "/employees/e9")
		status = 200

		payload = "[]"
		local cleared = gusto.updateCompanyBenefitEmployeeBenefits({company_benefit_id = "cb1", employee_benefits = json.decode("[]")})
		assert(last().method == "PUT" and last().body == '{"employee_benefits":[]}' and json.encode(cleared.items) == "[]")

		rejected(function() gusto.updateEmployee({employee_id = "e9", first_name = "Ada"}) end, "version is required")
		rejected(function() gusto.updatePayroll({company_id = COMPANY, payroll_id = "p1"}) end, "employee_compensations is required")
		rejected(function() gusto.updateTermination({employee_id = "e9", effective_date = "2026-12-01", version = json.decode("null")}) end, "version is required")
		rejected(function() gusto.deleteTimeSheet({time_sheet_uuid = "ts1"}) end, "version is required")
		rejected(function() gusto.deleteTimeSheet({time_sheet_uuid = "ts1", version = "v", force = true}) end, "deleteTimeSheet has no option force")
		rejected(function() gusto.createTermination({employee_id = "e9"}) end, "effective_date is required")
		rejected(function() gusto.updatePayroll({company_id = COMPANY, payroll_id = "p1/submit", employee_compensations = json.decode("[]")}) end, "payroll_id must be a Gusto ID")
		rejected(function() gusto.deleteEmployee({employee_id = "e9/terminations"}) end, "employee_id must be a Gusto ID")
		rejected(function() gusto.preparePayroll({company_id = "..", payroll_id = "p1"}) end, "company_id must be a Gusto ID")
	end,
}
