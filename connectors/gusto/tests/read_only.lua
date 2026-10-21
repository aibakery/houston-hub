return {
	scenario = {publisher = {client_id = "fixture-client", client_secret = "fixture-secret"}, config = {}, auth_method = "gusto", auth_config = {}},
	configure = function()
		requests = {}
		status = 200
		payload = "{}"
		responseHeaders = {}
		http = {request = function(req)
			table.insert(requests, req)
			return fixture.operation({statusCode = status, headers = responseHeaders, body = fixture.reader(payload)})
		end}
	end,
	run = function(gusto)
		local API = "https://api.gusto.com/v1"
		local COMPANY = "c2b9a6f0-1f3e-4a5b-9c8d-7e6f5a4b3c2d"
		local function last() return requests[#requests] end
		local function rejected(fn, expected)
			local before = #requests
			local ok, err = pcall(fn)
			assert(not ok and string.find(tostring(err), expected, 1, true), "wrong validation error: " .. tostring(err))
			assert(#requests == before, "invalid input reached Gusto")
		end

		local names = {}
		for name in gusto do if name ~= "help" then table.insert(names, name) end end
		table.sort(names)
		local READS = {
			"calculateAccruingTimeOffHours", "createGeneralLedgerReport", "getBenefit", "getBenefitRequirements", "getChildSupportData", "getCompany",
			"getCompanyBenefit", "getCompanyBenefitSummary", "getCompensation", "getContractor", "getContractorPayment", "getContributionExclusions",
			"getDepartment", "getEmployee", "getEmployeeBenefit", "getEmploymentHistory", "getGarnishment", "getHomeAddress", "getLocation",
			"getPaySchedule", "getPayScheduleAssignments", "getPayroll", "getPayrollSync", "getRecurringReimbursement", "getRehire", "getReport",
			"getSection603HighEarnerStatus", "getTimeOffPolicy", "getTimeSheet", "getTokenInfo", "getWorkAddress",
			"getYtdBenefitAmountsFromDifferentCompany", "listBenefits", "listCompanyAdmins", "listCompanyBenefitEmployeeBenefits",
			"listCompanyBenefits", "listCompanyCustomFields", "listCompensations", "listContractorPayments", "listContractors", "listDepartments",
			"listEarningTypes", "listEmployeeBenefits", "listEmployeeCustomFields", "listEmployees", "listGarnishments", "listHomeAddresses",
			"listLocations", "listMinimumWages", "listNotifications", "listPayPeriods", "listPaySchedules", "listPayrolls",
			"listRecurringReimbursements", "listSection603HighEarnerStatuses", "listTerminations", "listTimeOffActivities", "listTimeOffPolicies",
			"listTimeOffRequests", "listTimeSheets", "listUnprocessedTerminationPayPeriods", "listWorkAddresses",
		}
		table.sort(READS)
		assert(table.concat(names, ",") == table.concat(READS, ","), "wrong read-only surface: " .. table.concat(names, ","))
		assert(#requests == 0, "initialization reached Gusto")

		payload = '{"scope":"companies:read employees:read","resource":{"type":"Company","uuid":"' .. COMPANY .. '"},"resource_owner":{"type":"CompanyAdmin","uuid":"a1"}}'
		assert(gusto.getTokenInfo().resource.uuid == COMPANY)
		assert(last().method == "GET" and last().url == API .. "/token_info" and last().body == nil)
		assert(last().headers.Accept[1] == "application/json" and last().headers["X-Gusto-API-Version"][1] == "2026-06-15")
		assert(last().headers.Authorization == nil)

		payload = '[{"uuid":"e1","first_name":"Ada","date_of_birth":null,"jobs":[]},{"uuid":"e2","first_name":"Grace","jobs":[]}]'
		responseHeaders = {["x-page"] = {"2"}, ["x-per-page"] = {"2"}, ["x-total-count"] = {"5"}, ["x-total-pages"] = {"3"}}
		local opts = {company_id = COMPANY, search_term = "a b&c", terminated = false, include = {"custom_fields", "all_compensations"}, page = 2, per = 2}
		local page = gusto.listEmployees(opts)
		assert(last().url == API .. "/companies/" .. COMPANY .. "/employees?search_term=a%20b%26c&include=custom_fields,all_compensations&terminated=false&page=2&per=2", last().url)
		assert(opts.page == 2 and opts.include[2] == "all_compensations", "caller options were modified")
		assert(#page.items == 2 and page.items[2].first_name == "Grace" and page.items[1].date_of_birth == json.decode("null"))
		assert(page.page == 2 and page.per == 2 and page.total_count == 5 and page.total_pages == 3)

		payload = "[]"
		responseHeaders = {}
		local empty = gusto.listDepartments({company_id = COMPANY})
		assert(last().url == API .. "/companies/" .. COMPANY .. "/departments" and json.encode(empty.items) == "[]" and empty.total_pages == nil)

		payload = '{"uuid":"p1","processed":true,"employee_compensations":[],"totals":{"gross_pay":"1250.00"}}'
		local payroll = gusto.getPayroll({company_id = COMPANY, payroll_id = "p1", include = {"taxes", "totals"}})
		assert(last().url == API .. "/companies/" .. COMPANY .. "/payrolls/p1?include=taxes,totals")
		assert(payroll.totals.gross_pay == "1250.00" and json.encode(payroll.employee_compensations) == "[]")
		gusto.listPayrolls({company_id = COMPANY, processing_statuses = {"processed"}, start_date = "2026-01-01", end_date = "2026-06-30", page = 1, per = 100})
		assert(last().url == API .. "/companies/" .. COMPANY .. "/payrolls?processing_statuses=processed&start_date=2026-01-01&end_date=2026-06-30&page=1&per=100", last().url)
		gusto.listContractorPayments({company_id = COMPANY, start_date = "2026-01-01", end_date = "2026-03-31"})
		assert(last().url == API .. "/companies/" .. COMPANY .. "/contractor_payments?start_date=2026-01-01&end_date=2026-03-31")
		gusto.getBenefit({benefit_id = 5})
		assert(last().url == API .. "/benefits/5")
		gusto.getSection603HighEarnerStatus({employee_id = "e1", effective_year = 2026})
		assert(last().url == API .. "/employees/e1/section603_high_earner_statuses/2026")
		gusto.listTimeOffActivities({employee_id = "e1", time_off_type = "vacation"})
		assert(last().url == API .. "/employees/e1/time_off_activities?time_off_type=vacation")

		payload = '{"request_uuid":"r1","status":"pending"}'
		local report = gusto.createGeneralLedgerReport({payroll_uuid = "p1", aggregation = "department"})
		assert(last().method == "POST" and last().url == API .. "/payrolls/p1/reports/general_ledger" and last().headers["Content-Type"][1] == "application/json")
		local body = json.decode(last().body)
		assert(body.aggregation == "department" and body.payroll_uuid == nil, "path field leaked into the body")
		assert(report.request_uuid == "r1")
		payload = ""
		local blank, blankErr = pcall(function() gusto.createGeneralLedgerReport({payroll_uuid = "p1", aggregation = "default"}) end)
		assert(not blank and string.find(tostring(blankErr), "invalid JSON", 1, true), "an empty read is not a success")
		payload = '{"accruing_time_off_hours":[]}'
		gusto.calculateAccruingTimeOffHours({payroll_id = "p1", employee_id = "e1", regular_hours_worked = 40})
		assert(last().method == "POST" and last().url == API .. "/payrolls/p1/employees/e1/calculate_accruing_time_off_hours" and last().body == '{"regular_hours_worked":40}')
		status, payload = 204, ""
		assert(gusto.getRehire({employee_id = "e1"}) == nil and last().url == API .. "/employees/e1/rehire", "a 204 read is not nil")
		status = 200
		local count = #requests

		rejected(function() gusto.getEmployee() end, "employee_id must be a Gusto ID")
		rejected(function() gusto.getEmployee({employee_id = "../token_info"}) end, "employee_id must be a Gusto ID")
		rejected(function() gusto.getEmployee({employee_id = "e1/jobs"}) end, "employee_id must be a Gusto ID")
		rejected(function() gusto.getEmployee({employee_id = "e1?x=1"}) end, "employee_id must be a Gusto ID")
		rejected(function() gusto.getEmployee({employee_id = ""}) end, "employee_id must be a Gusto ID")
		rejected(function() gusto.getBenefit({benefit_id = 1.5}) end, "benefit_id must be a Gusto ID")
		rejected(function() gusto.getBenefit({benefit_id = -1}) end, "benefit_id must be a Gusto ID")
		rejected(function() gusto.getEmployee({employee_id = string.rep("a", 65)}) end, "employee_id must be a Gusto ID")
		rejected(function() gusto.listContractorPayments({company_id = COMPANY, start_date = "2026-01-01"}) end, "end_date is required")
		rejected(function() gusto.listTimeOffActivities({employee_id = "e1"}) end, "time_off_type is required")
		rejected(function() gusto.listEmployees({company_id = COMPANY, limit = 10}) end, "listEmployees has no option limit")
		rejected(function() gusto.listEmployees({company_id = COMPANY, uuids = json.decode("[]")}) end, "uuids must not be an empty array")
		rejected(function() gusto.listEmployees({company_id = COMPANY, include = {a = "x"}}) end, "array, not an object")
		rejected(function() gusto.listEmployees("all") end, "opts must be an object")
		rejected(function() gusto.calculateAccruingTimeOffHours({payroll_id = "p1", employee_id = "e1", _method = "PUT"}) end, "calculateAccruingTimeOffHours has no option _method")
		rejected(function() gusto.createGeneralLedgerReport({payroll_uuid = "p1", aggregation = "job", payroll_id = "p2"}) end, "createGeneralLedgerReport has no option payroll_id")
		assert(#requests == count)
	end,
}
