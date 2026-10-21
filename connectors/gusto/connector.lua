-- Gusto App Integrations API, X-Gusto-API-Version 2026-06-15. Arguments and results keep Gusto's native snake_case field names.
type Options = {[string]: any}
type Endpoint = {method: string, path: string, query: {string}?, required: {string}?, write: boolean?, body: boolean?, about: string}

local API = if auth.method == "demo" then "https://api.gusto-demo.com" else "https://api.gusto.com"
local VERSION = "2026-06-15"
local PAGE = {"page", "per"}

-- The company-token operations of Gusto's App Integrations reference
-- (https://docs.gusto.com/app-integrations/reference), checked on 2026-10-21.
-- Path {fields} are required; listed query fields are taken from the options and the other
-- fields form the JSON body of POST, PUT and PATCH requests. Webhooks, events and salary
-- estimate occupations need an app-level system token, and running payroll or paying
-- contractors are Gusto Embedded features, so they are absent.
local endpoints: {[string]: Endpoint} = {
	getTokenInfo = {method = "GET", path = "/v1/token_info",
		about = "{scope, resource={type='Company', uuid}, resource_owner={type, uuid}}; resource.uuid is the connected company's company_id."},

	getCompany = {method = "GET", path = "/v1/companies/{company_id}", about = "Name, EIN, entity type, locations and compensation settings."},
	listCompanyAdmins = {method = "GET", path = "/v1/companies/{company_id}/admins", query = PAGE, about = ""},
	listCompanyCustomFields = {method = "GET", path = "/v1/companies/{company_id}/custom_fields", query = PAGE, about = ""},
	listLocations = {method = "GET", path = "/v1/companies/{company_id}/locations", query = PAGE, about = ""},
	createLocation = {method = "POST", path = "/v1/companies/{company_id}/locations", required = {"street_1", "city", "state", "zip", "phone_number"},
		about = "Also street_2, country, mailing_address, filing_address."},
	getLocation = {method = "GET", path = "/v1/locations/{location_id}", about = ""},
	updateLocation = {method = "PUT", path = "/v1/locations/{location_id}", required = {"version"}, about = ""},
	listMinimumWages = {method = "GET", path = "/v1/locations/{location_id}/minimum_wages", query = {"effective_date"}, about = ""},

	listDepartments = {method = "GET", path = "/v1/companies/{company_id}/departments", about = "With their employees and contractors."},
	createDepartment = {method = "POST", path = "/v1/companies/{company_id}/departments", required = {"title"}, about = ""},
	getDepartment = {method = "GET", path = "/v1/departments/{department_uuid}", about = ""},
	updateDepartment = {method = "PUT", path = "/v1/departments/{department_uuid}", required = {"title", "version"}, about = ""},
	deleteDepartment = {method = "DELETE", path = "/v1/departments/{department_uuid}", about = "Only an empty department."},
	addDepartmentPeople = {method = "PUT", path = "/v1/departments/{department_uuid}/add", required = {"version"},
		about = "Also employees={{uuid}}, contractors={{uuid}}."},
	removeDepartmentPeople = {method = "PUT", path = "/v1/departments/{department_uuid}/remove", required = {"version"},
		about = "Also employees={{uuid}}, contractors={{uuid}}."},

	listEmployees = {method = "GET", path = "/v1/companies/{company_id}/employees",
		query = {"search_term", "sort_by", "include", "location_uuid", "payroll_uuid", "onboarded", "onboarded_active", "terminated", "terminated_today", "uuids", "page", "per"},
		about = "include: all_compensations, all_home_addresses, custom_fields, portal_invitations or current_home_address."},
	createEmployee = {method = "POST", path = "/v1/companies/{company_id}/employees", required = {"first_name", "last_name"},
		about = "Also middle_initial, preferred_first_name, email, date_of_birth, ssn, self_onboarding. Starts onboarding."},
	getEmployee = {method = "GET", path = "/v1/employees/{employee_id}", query = {"include"}, about = "With jobs; pay rates need the compensations scope."},
	updateEmployee = {method = "PUT", path = "/v1/employees/{employee_id}", required = {"version"}, about = ""},
	deleteEmployee = {method = "DELETE", path = "/v1/employees/{employee_id}", about = "Only an employee who hasn't finished onboarding; terminate the others."},
	listEmployeeCustomFields = {method = "GET", path = "/v1/employees/{employee_id}/custom_fields", query = PAGE, about = ""},
	getEmploymentHistory = {method = "GET", path = "/v1/employees/{employee_id}/employment_history", about = "Hire and termination dates."},
	listTerminations = {method = "GET", path = "/v1/employees/{employee_id}/terminations", about = ""},
	createTermination = {method = "POST", path = "/v1/employees/{employee_id}/terminations", required = {"effective_date"},
		about = "Also run_termination_payroll. Ends the employment on that date."},
	updateTermination = {method = "PUT", path = "/v1/terminations/{employee_id}", required = {"effective_date", "version"}, about = ""},
	deleteTermination = {method = "DELETE", path = "/v1/employees/{employee_id}/terminations", about = "Cancels a termination that hasn't taken effect."},
	getRehire = {method = "GET", path = "/v1/employees/{employee_id}/rehire", about = ""},
	createRehire = {method = "POST", path = "/v1/employees/{employee_id}/rehire", required = {"effective_date", "file_new_hire_report", "work_location_uuid"}, about = ""},
	updateRehire = {method = "PUT", path = "/v1/employees/{employee_id}/rehire", required = {"effective_date", "file_new_hire_report", "work_location_uuid", "version"}, about = ""},
	deleteRehire = {method = "DELETE", path = "/v1/employees/{employee_id}/rehire", about = "Cancels a rehire that hasn't taken effect."},
	listHomeAddresses = {method = "GET", path = "/v1/employees/{employee_id}/home_addresses", about = ""},
	createHomeAddress = {method = "POST", path = "/v1/employees/{employee_id}/home_addresses",
		about = "Body {street_1, street_2?, city, state, zip, effective_date?, courtesy_withholding?}."},
	getHomeAddress = {method = "GET", path = "/v1/home_addresses/{home_address_uuid}", about = ""},
	updateHomeAddress = {method = "PUT", path = "/v1/home_addresses/{home_address_uuid}", required = {"version"}, about = ""},
	deleteHomeAddress = {method = "DELETE", path = "/v1/home_addresses/{home_address_uuid}", about = ""},
	listWorkAddresses = {method = "GET", path = "/v1/employees/{employee_id}/work_addresses", about = ""},
	createWorkAddress = {method = "POST", path = "/v1/employees/{employee_id}/work_addresses",
		about = "Body {location_uuid, effective_date?}."},
	getWorkAddress = {method = "GET", path = "/v1/work_addresses/{work_address_uuid}", about = ""},
	updateWorkAddress = {method = "PUT", path = "/v1/work_addresses/{work_address_uuid}", required = {"version"}, about = ""},
	deleteWorkAddress = {method = "DELETE", path = "/v1/work_addresses/{work_address_uuid}", about = ""},

	listCompensations = {method = "GET", path = "/v1/jobs/{job_id}/compensations", query = {"include", "page", "per"},
		about = "job_id comes from an employee's jobs; include='all_compensations' adds past and future rates."},
	createCompensation = {method = "POST", path = "/v1/jobs/{job_id}/compensations", required = {"rate", "payment_unit", "flsa_status"},
		about = "rate is a string; payment_unit Hour, Week, Month, Year or Paycheck. Also effective_date, adjust_for_minimum_wage."},
	getCompensation = {method = "GET", path = "/v1/compensations/{compensation_id}", about = ""},
	updateCompensation = {method = "PUT", path = "/v1/compensations/{compensation_id}", required = {"version"}, about = ""},
	deleteCompensation = {method = "DELETE", path = "/v1/compensations/{compensation_id}", about = "Only a future-dated compensation."},

	listContractors = {method = "GET", path = "/v1/companies/{company_id}/contractors",
		query = {"search_term", "sort_by", "include", "onboarded", "onboarded_active", "terminated", "terminated_today", "page", "per"}, about = ""},
	createContractor = {method = "POST", path = "/v1/companies/{company_id}/contractors", required = {"type", "wage_type", "start_date"},
		about = "type Individual or Business; wage_type Fixed or Hourly. Also first_name, last_name, business_name, email, hourly_rate, self_onboarding."},
	getContractor = {method = "GET", path = "/v1/contractors/{contractor_uuid}", query = {"include"}, about = ""},
	updateContractor = {method = "PUT", path = "/v1/contractors/{contractor_uuid}", required = {"version"}, about = ""},

	listPaySchedules = {method = "GET", path = "/v1/companies/{company_id}/pay_schedules", query = PAGE, about = ""},
	getPaySchedule = {method = "GET", path = "/v1/companies/{company_id}/pay_schedules/{pay_schedule_id}", about = ""},
	getPayScheduleAssignments = {method = "GET", path = "/v1/companies/{company_id}/pay_schedules/assignments",
		about = "Which pay schedule each employee follows."},
	listPayPeriods = {method = "GET", path = "/v1/companies/{company_id}/pay_periods", query = {"start_date", "end_date", "payroll_types"},
		about = "start_date defaults to 6 months ago; end_date at most 3 months ahead. Each period names its payroll's payroll_uuid."},
	listUnprocessedTerminationPayPeriods = {method = "GET", path = "/v1/companies/{company_id}/pay_periods/unprocessed_termination_pay_periods", about = ""},

	listPayrolls = {method = "GET", path = "/v1/companies/{company_id}/payrolls",
		query = {"processing_statuses", "payroll_types", "processed", "include_off_cycle", "include", "start_date", "end_date", "date_filter_by", "sort_order", "page", "per"},
		about = "Always paged (per up to 100). processing_statuses: processed, unprocessed; payroll_types: regular, off_cycle, external; include: totals, payroll_status_meta, risk_blockers, reversals."},
	getPayroll = {method = "GET", path = "/v1/companies/{company_id}/payrolls/{payroll_id}", query = {"include", "sort_by", "page", "per"},
		about = "Gross and net pay, taxes and deductions per employee; page and per page employee_compensations (up to 100). include: benefits, deductions, taxes, payroll_status_meta, totals, risk_blockers, reversals."},
	preparePayroll = {method = "PUT", path = "/v1/companies/{company_id}/payrolls/{payroll_id}/prepare", query = {"sort_by", "page", "per"}, body = false,
		about = "Readies an unprocessed payroll for editing and returns it with the version updatePayroll needs. Clears any earlier calculation."},
	updatePayroll = {method = "PUT", path = "/v1/companies/{company_id}/payrolls/{payroll_id}", required = {"version", "employee_compensations"},
		about = "employee_compensations={{employee_uuid, fixed_compensations?, hourly_compensations?, paid_time_off?, excluded?, memo?}}, up to 100. Changes the draft only; omitted entries stay."},
	calculateAccruingTimeOffHours = {method = "POST", path = "/v1/payrolls/{payroll_id}/employees/{employee_id}/calculate_accruing_time_off_hours", write = false,
		about = "Body {regular_hours_worked?, overtime_hours_worked?, ...}; computes only."},
	listContractorPayments = {method = "GET", path = "/v1/companies/{company_id}/contractor_payments", query = {"start_date", "end_date", "contractor_uuid", "group_by_date", "page", "per"},
		required = {"start_date", "end_date"}, about = "Totals and payments in the date range."},
	getContractorPayment = {method = "GET", path = "/v1/companies/{company_id}/contractor_payments/{contractor_payment_id}", about = ""},
	listEarningTypes = {method = "GET", path = "/v1/companies/{company_id}/earning_types", about = "{default, custom}."},
	createEarningType = {method = "POST", path = "/v1/companies/{company_id}/earning_types", required = {"name"},
		about = "A custom earning type for payroll fixed compensations."},
	updateEarningType = {method = "PUT", path = "/v1/companies/{company_id}/earning_types/{earning_type_uuid}",
		about = "Body {name}."},
	deleteEarningType = {method = "DELETE", path = "/v1/companies/{company_id}/earning_types/{earning_type_uuid}",
		about = "Deactivates a custom earning type."},
	createGeneralLedgerReport = {method = "POST", path = "/v1/payrolls/{payroll_uuid}/reports/general_ledger", required = {"aggregation"}, write = false,
		about = "aggregation default, job or department; also integration_type. Returns {request_uuid}; poll getReport until its status is Succeeded."},
	getReport = {method = "GET", path = "/v1/reports/{request_uuid}",
		about = "{status, report_urls}: temporary download links; treat them as secrets."},

	listTimeOffPolicies = {method = "GET", path = "/v1/companies/{company_id}/time_off_policies", about = ""},
	getTimeOffPolicy = {method = "GET", path = "/v1/time_off_policies/{time_off_policy_uuid}", about = "With employee balances."},
	addTimeOffPolicyEmployees = {method = "PUT", path = "/v1/time_off_policies/{time_off_policy_uuid}/add_employees", required = {"employees"},
		about = "employees={{uuid, balance?}}."},
	listTimeOffRequests = {method = "GET", path = "/v1/companies/{company_id}/time_off_requests", query = {"start_date", "end_date"}, about = ""},
	listTimeOffActivities = {method = "GET", path = "/v1/employees/{employee_id}/time_off_activities", query = {"time_off_type"}, required = {"time_off_type"},
		about = "time_off_type such as 'vacation' or 'sick'."},

	listBenefits = {method = "GET", path = "/v1/benefits", about = "Benefit types Gusto supports; benefit_id is a number."},
	getBenefit = {method = "GET", path = "/v1/benefits/{benefit_id}", about = ""},
	getBenefitRequirements = {method = "GET", path = "/v1/benefits/{benefit_id}/requirements", about = ""},
	listCompanyBenefits = {method = "GET", path = "/v1/companies/{company_id}/company_benefits", query = {"active", "enrollment_count", "benefit_type"},
		about = "benefit_type takes benefit type numbers."},
	createCompanyBenefit = {method = "POST", path = "/v1/companies/{company_id}/company_benefits", required = {"description"},
		about = "Also benefit_type, active, responsible_for_employer_taxes, responsible_for_employee_w2."},
	getCompanyBenefit = {method = "GET", path = "/v1/company_benefits/{company_benefit_id}", query = {"with_employee_benefits", "include"}, about = ""},
	updateCompanyBenefit = {method = "PUT", path = "/v1/company_benefits/{company_benefit_id}", required = {"version"}, about = ""},
	deleteCompanyBenefit = {method = "DELETE", path = "/v1/company_benefits/{company_benefit_id}",
		about = "Only a benefit without employee enrollments or payroll history; otherwise set active=false."},
	getCompanyBenefitSummary = {method = "GET", path = "/v1/company_benefits/{company_benefit_id}/summary", query = {"start_date", "end_date", "detailed"},
		about = "Employee deductions and company contributions over the range."},
	getContributionExclusions = {method = "GET", path = "/v1/company_benefits/{company_benefit_id}/contribution_exclusions", about = ""},
	updateContributionExclusions = {method = "PUT", path = "/v1/company_benefits/{company_benefit_id}/contribution_exclusions", required = {"contribution_exclusions"}, about = ""},
	listCompanyBenefitEmployeeBenefits = {method = "GET", path = "/v1/company_benefits/{company_benefit_id}/employee_benefits", query = {"include", "page", "per"},
		about = "Enrollments in one company benefit."},
	updateCompanyBenefitEmployeeBenefits = {method = "PUT", path = "/v1/company_benefits/{company_benefit_id}/employee_benefits", required = {"employee_benefits"},
		about = "employee_benefits={{employee_uuid, ...}} creates or updates many enrollments."},
	listEmployeeBenefits = {method = "GET", path = "/v1/employees/{employee_id}/employee_benefits", query = {"include", "page", "per"}, about = ""},
	createEmployeeBenefit = {method = "POST", path = "/v1/employees/{employee_id}/employee_benefits", required = {"company_benefit_uuid"},
		about = "Also active, employee_deduction, company_contribution, deduct_as_percentage, effective_date and more. Enrolls the employee."},
	getEmployeeBenefit = {method = "GET", path = "/v1/employee_benefits/{employee_benefit_id}", about = ""},
	updateEmployeeBenefit = {method = "PUT", path = "/v1/employee_benefits/{employee_benefit_id}", required = {"version"}, about = ""},
	deleteEmployeeBenefit = {method = "DELETE", path = "/v1/employee_benefits/{employee_benefit_id}", about = "Ends the enrollment."},
	getYtdBenefitAmountsFromDifferentCompany = {method = "GET", path = "/v1/employees/{employee_id}/ytd_benefit_amounts_from_different_company", query = {"tax_year"},
		about = "Contributions made at a previous employer this year."},
	createYtdBenefitAmountsFromDifferentCompany = {method = "POST", path = "/v1/employees/{employee_id}/ytd_benefit_amounts_from_different_company",
		required = {"benefit_type", "tax_year", "ytd_employee_deduction_amount", "ytd_company_contribution_amount"}, about = ""},
	listSection603HighEarnerStatuses = {method = "GET", path = "/v1/employees/{employee_id}/section603_high_earner_statuses",
		about = "Whether catch-up contributions must be Roth, per year."},
	getSection603HighEarnerStatus = {method = "GET", path = "/v1/employees/{employee_id}/section603_high_earner_statuses/{effective_year}", about = ""},
	createSection603HighEarnerStatus = {method = "POST", path = "/v1/employees/{employee_id}/section603_high_earner_statuses", required = {"effective_year", "is_high_earner"}, about = ""},
	updateSection603HighEarnerStatus = {method = "PATCH", path = "/v1/employees/{employee_id}/section603_high_earner_statuses/{effective_year}", required = {"is_high_earner"}, about = ""},

	listGarnishments = {method = "GET", path = "/v1/employees/{employee_id}/garnishments", query = PAGE, about = "Court-ordered and voluntary deductions."},
	createGarnishment = {method = "POST", path = "/v1/employees/{employee_id}/garnishments", required = {"amount", "court_ordered"},
		about = "Also description, garnishment_type, recurring, deduct_as_percentage, annual_maximum and more."},
	getGarnishment = {method = "GET", path = "/v1/garnishments/{garnishment_id}", about = ""},
	updateGarnishment = {method = "PUT", path = "/v1/garnishments/{garnishment_id}", required = {"version"}, about = ""},
	getChildSupportData = {method = "GET", path = "/v1/garnishments/child_support", about = "Child support agencies and their required fields per state."},
	listRecurringReimbursements = {method = "GET", path = "/v1/employees/{employee_id}/recurring_reimbursements", query = PAGE, about = ""},
	createRecurringReimbursement = {method = "POST", path = "/v1/employees/{employee_id}/recurring_reimbursements", required = {"description", "amount"},
		about = "amount is a string. Paid on every regular payroll."},
	getRecurringReimbursement = {method = "GET", path = "/v1/recurring_reimbursements/{id}", about = ""},
	updateRecurringReimbursement = {method = "PUT", path = "/v1/recurring_reimbursements/{id}", required = {"version"}, about = ""},
	deleteRecurringReimbursement = {method = "DELETE", path = "/v1/recurring_reimbursements/{id}", about = ""},

	listTimeSheets = {method = "GET", path = "/v1/companies/{company_id}/time_tracking/time_sheets",
		query = {"entity_type", "entity_uuids", "status", "after", "before", "sort_by", "sort_order", "page", "per"},
		about = "entity_type Employee or Contractor; status pending, approved or rejected; after/before filter created_at (ISO 8601)."},
	createTimeSheet = {method = "POST", path = "/v1/companies/{company_id}/time_tracking/time_sheets", required = {"entity_type", "entity_uuid", "shift_started_at", "time_zone"},
		about = "Also shift_ended_at, job_uuid, entries, status."},
	getTimeSheet = {method = "GET", path = "/v1/time_tracking/time_sheets/{time_sheet_uuid}", about = ""},
	updateTimeSheet = {method = "PUT", path = "/v1/time_tracking/time_sheets/{time_sheet_uuid}", required = {"version"}, about = ""},
	deleteTimeSheet = {method = "DELETE", path = "/v1/time_tracking/time_sheets/{time_sheet_uuid}", query = {"version"}, required = {"version"}, about = ""},
	createPayrollSync = {method = "POST", path = "/v1/companies/{company_id}/time_tracking/payroll_syncs", required = {"kind", "pay_schedule_uuid", "pay_period_start_date", "pay_period_end_date"},
		about = "Copies approved time sheets into that pay period's unprocessed payroll."},
	getPayrollSync = {method = "GET", path = "/v1/time_tracking/payroll_syncs/{payroll_sync_uuid}", about = ""},

	listNotifications = {method = "GET", path = "/v1/companies/{company_id}/notifications", query = {"status", "page", "per"},
		about = "Actions Gusto asks the company to take; status open, resolved or expired."},
}

local NULL = json.decode("null")
local NONE: {string} = table.freeze({})

local function options(input: Options?): Options
	if input == nil then return {} end
	assert(type(input) == "table", "opts must be an object")
	for key in input do assert(type(key) == "string", "opts must have named fields") end
	return table.clone(input)
end

-- Only GET reads unless write says otherwise.
local function writes(endpoint: Endpoint): boolean
	if endpoint.write ~= nil then return endpoint.write end
	return endpoint.method ~= "GET"
end

-- Gusto IDs are UUIDs; benefit types and years are numbers.
local function identifier(value: any, field: string): string
	if type(value) == "number" then
		assert(value >= 0 and value % 1 == 0 and value <= 9007199254740991, field .. " must be a Gusto ID")
		return string.format("%d", value)
	end
	assert(type(value) == "string" and string.match(value, "^[%w_%-]+$") and #value <= 64, field .. " must be a Gusto ID")
	return value
end

local function scalar(value: any, field: string): string
	local kind = type(value)
	assert(kind == "string" or kind == "boolean" or kind == "number", field .. " must be a string, boolean, number or array of those")
	return url.encode(value)
end

-- Gusto reads list filters (include, uuids, payroll_types) as comma-separated values.
local function queryValue(value: any, field: string): string
	if type(value) ~= "table" then return scalar(value, field) end
	local parts: {string} = {}
	for index, item in value do
		assert(type(index) == "number" and index == #parts + 1, field .. " must be an array, not an object")
		table.insert(parts, scalar(item, field))
	end
	assert(#parts > 0, field .. " must not be an empty array")
	return table.concat(parts, ",")
end

local function fail(name: string, response: HttpResponse, message: string): never
	return houston.fail({operation = name, layer = "upstream", upstream_status = response.statusCode,
		retryable = response.statusCode == 429 or response.statusCode >= 500, message = message})
end

local function header(response: HttpResponse, name: string): string?
	local values = response.headers[name]
	return if values then values[1] else nil
end

-- Gusto errors are {errors={{error_key, category, message}}}; a rejected token answers with an
-- empty body and the reason in WWW-Authenticate.
local function failStatus(name: string, response: HttpResponse): never
	local message = "Gusto HTTP " .. tostring(response.statusCode)
	local ok, value = pcall(json.decode, await(response.body:readPrefix(16 * 1024)))
	local details: {string} = {}
	if ok and type(value) == "table" and type(value.errors) == "table" then
		for _, item in value.errors do
			if type(item) == "table" and #details < 5 then
				local parts: {string} = {}
				for _, field in {"category", "error_key", "message"} do
					if type(item[field]) == "string" and item[field] ~= "" then table.insert(parts, string.sub(item[field], 1, 300)) end
				end
				if #parts > 0 then table.insert(details, table.concat(parts, " ")) end
			end
		end
	end
	local reason = header(response, "www-authenticate")
	if #details == 0 and reason then
		local description = string.match(reason, 'error_description="([^"]*)"')
		if description then table.insert(details, string.sub(description, 1, 300)) end
	end
	if #details > 0 then message ..= ": " .. table.concat(details, "; ") end
	local retry = header(response, "retry-after")
	if response.statusCode == 429 and retry and string.match(retry, "^%d+$") then message ..= "; retry after " .. retry .. "s" end
	return fail(name, response, message)
end

-- Objects return unchanged; arrays become {items, page?, per?, total_count?, total_pages?}, keeping
-- Gusto's paging headers; a write answered without a body returns {success=true}.
local function decode(name: string, endpoint: Endpoint, response: HttpResponse): any
	local raw = await(response.body:readAll())
	if writes(endpoint) and string.match(raw, "^%s*$") then return {success = true} end
	local ok, value = pcall(json.decode, raw)
	if not ok or type(value) ~= "table" or not string.match(raw, "^%s*[%[{]") then
		fail(name, response, "Gusto returned invalid JSON")
	end
	if string.match(raw, "^%s*%[") then
		return {items = value, page = tonumber(header(response, "x-page")), per = tonumber(header(response, "x-per-page")),
			total_count = tonumber(header(response, "x-total-count")), total_pages = tonumber(header(response, "x-total-pages"))}
	end
	return value
end

local function request(name: string, endpoint: Endpoint, input: Options?): any
	local args = options(input)
	local path = string.gsub(endpoint.path, "{([%w_]+)}", function(field: string)
		local id = identifier(args[field], field)
		args[field] = nil
		return id
	end)
	for _, field in endpoint.required or NONE do
		assert(args[field] ~= nil and args[field] ~= NULL, field .. " is required")
	end
	local query: {string} = {}
	for _, field in endpoint.query or NONE do
		if args[field] ~= nil then table.insert(query, field .. "=" .. queryValue(args[field], field)) end
		args[field] = nil
	end
	if #query > 0 then path ..= "?" .. table.concat(query, "&") end
	local headers: HttpHeaders = {Accept = {"application/json"}, ["X-Gusto-API-Version"] = {VERSION}}
	local body: string? = nil
	if endpoint.method ~= "GET" and endpoint.method ~= "DELETE" and endpoint.body ~= false then
		headers["Content-Type"] = {"application/json"}
		body = json.encode(args)
		args = {}
	end
	local unknown = next(args)
	assert(unknown == nil, name .. " has no option " .. tostring(unknown))
	local response = await(http.request({method = endpoint.method, url = API .. path, headers = headers, body = body}))
	if response.statusCode < 200 or response.statusCode >= 300 then failStatus(name, response) end
	return decode(name, endpoint, response)
end

-- name({path fields, query fields?, required body fields, ...body}) built from the endpoint itself.
local function signature(endpoint: Endpoint): string
	local fields: {string} = {}
	for field in string.gmatch(endpoint.path, "{([%w_]+)}") do table.insert(fields, field) end
	for _, field in endpoint.query or NONE do
		table.insert(fields, if table.find(endpoint.required or NONE, field) then field else field .. "?")
	end
	if endpoint.method ~= "GET" and endpoint.method ~= "DELETE" and endpoint.body ~= false then
		for _, field in endpoint.required or NONE do
			if not table.find(endpoint.query or NONE, field) then table.insert(fields, field) end
		end
		table.insert(fields, "...body")
	end
	return "({" .. table.concat(fields, ", ") .. "})"
end

local exports: {[string]: any} = {}
for name, endpoint in endpoints do
	if not writes(endpoint) or config.access == "read-write" then
		exports[name] = function(args: Options?): any return request(name, endpoint, args) end
	end
end

local INTRO = {
	"Gusto App Integrations API (version " .. VERSION .. ")" .. (if auth.method == "demo" then " on Gusto's demo environment (sample data)" else "") .. ". Every function takes one named options object with Gusto's snake_case names; ? marks optional fields, required body fields follow the path and query fields, and ...body stands for the other JSON body fields. Objects return unchanged; JSON arrays return {items, page?, per?, total_count?, total_pages?}; a write answered without a body returns {success=true}. Connector calls return completed values: use them directly, without await.",
	"A connection reaches one company. Start with local company_id = gusto.getTokenInfo().resource.uuid, then getCompany({company_id=company_id}), listEmployees({company_id=company_id}), listPayrolls(...). Employee jobs (getEmployee().jobs) give the job_id for compensations. IDs are UUID strings, except benefit_id (a number).",
	"Lists without page return every record, except listPayrolls, which always pages; pass page (1-based) and per (default 25, often at most 100) and continue while page < total_pages. Dates are YYYY-MM-DD; money amounts are decimal strings such as '1250.00'. Array filters (include, uuids, payroll_types) are sent comma-separated.",
	"Examples: local company_id = gusto.getTokenInfo().resource.uuid; gusto.listEmployees({company_id=company_id, terminated=false, include={'custom_fields'}, page=1, per=100}); gusto.listPayrolls({company_id=company_id, start_date='2026-01-01', end_date='2026-06-30', include={'totals'}}); gusto.getPayroll({company_id=company_id, payroll_id=id, include={'taxes', 'deductions'}}).",
	"Responses include personal and pay data (birth dates, home addresses, pay rates, garnishments); share only what the task needs. Gusto's scopes for the app decide what is visible: pay rates need the compensations scope, and a missing scope fails with 403 missing_oauth_scopes.",
	"Read-only connections omit writes. Updates take the object's current version, read just before: a stale version fails with 409 invalid_resource_version, so read again and reapply. Payroll changes stay drafts: call preparePayroll, then updatePayroll with its version; payrolls are submitted in Gusto, not here. Creates are not idempotent: after a timeout or 5xx, list or read before repeating one. Gusto allows 200 requests per minute per connection.",
	"Errors report the HTTP status and Gusto's category, error_key and message (for example 422 invalid_attribute_value or 404 not_found).",
}

exports.help = function(): string
	local names: {string} = {}
	for name in exports do if name ~= "help" then table.insert(names, name) end end
	table.sort(names)
	local lines = table.clone(INTRO)
	for _, name in names do
		local endpoint = endpoints[name]
		local about = if endpoint.about == "" then "" else endpoint.about .. " "
		table.insert(lines, name .. signature(endpoint) .. ": " .. about .. endpoint.method .. " " .. endpoint.path)
	end
	return table.concat(lines, "\n")
end

return exports
