-- Gusto App Integrations API, X-Gusto-API-Version 2026-06-15. Arguments and results keep Gusto's native snake_case field names.
type Options = {[string]: any}
type Endpoint = {
	method: string, path: string, query: {string}?, extra: {string}?, required: {string}?, allow: {string}?,
	write: boolean?, body: (boolean | string)?, doc: string, about: string,
}

local PROVIDER = "Gusto"
local API = if auth.method == "demo" then "https://api.gusto-demo.com" else "https://api.gusto.com"
local VERSION = "2026-06-15"
local DOCS = "https://docs.gusto.com/app-integrations/reference/"
local PAGE = {"page", "per"}

-- The company-token operations of Gusto's App Integrations reference
-- (https://docs.gusto.com/app-integrations/reference), checked on 2026-10-21.
-- Path {fields} are required; listed query fields are taken from the options and the other
-- fields form the JSON body of POST, PUT and PATCH requests, limited to allow when it is listed.
-- Webhooks, events and salary estimate occupations need an app-level system token, so the
-- salary estimates built on those occupations are absent too; running payroll and paying
-- contractors are Gusto Embedded features. The company's contractor-only flag and the
-- duplicate GET /v1/terminations/{employee_id} are left out.
local endpoints: {[string]: Endpoint} = {
	getTokenInfo = {method = "GET", path = "/v1/token_info",
		doc = "get-v1-token-info", about = "{scope, resource={type='Company', uuid}, resource_owner={type, uuid}}; resource.uuid is the connected company's company_id."},

	getCompany = {method = "GET", path = "/v1/companies/{company_id}", doc = "get-v1-companies", about = "Name, EIN, entity type, locations and compensation settings."},
	listCompanyAdmins = {method = "GET", path = "/v1/companies/{company_id}/admins", query = PAGE, doc = "get-v1-companies-company_id-admins", about = ""},
	listCompanyCustomFields = {method = "GET", path = "/v1/companies/{company_id}/custom_fields", query = PAGE, doc = "get-v1-companies-company_id-custom_fields", about = ""},
	listLocations = {method = "GET", path = "/v1/companies/{company_id}/locations", query = PAGE, doc = "get-v1-companies-company_id-locations", about = ""},
	createLocation = {method = "POST", path = "/v1/companies/{company_id}/locations", required = {"street_1", "city", "state", "zip", "phone_number"},
		doc = "post-v1-companies-company_id-locations", about = "Also street_2, country, mailing_address, filing_address."},
	getLocation = {method = "GET", path = "/v1/locations/{location_id}", doc = "get-v1-locations-location_id", about = ""},
	updateLocation = {method = "PUT", path = "/v1/locations/{location_id}", required = {"version"}, doc = "put-v1-locations-location_id", about = ""},
	listMinimumWages = {method = "GET", path = "/v1/locations/{location_id}/minimum_wages", query = {"effective_date"}, doc = "get-v1-locations-location_uuid-minimum_wages", about = ""},

	listDepartments = {method = "GET", path = "/v1/companies/{company_id}/departments", doc = "get-companies-departments", about = "With their employees and contractors."},
	createDepartment = {method = "POST", path = "/v1/companies/{company_id}/departments", required = {"title"}, doc = "post-departments", about = ""},
	getDepartment = {method = "GET", path = "/v1/departments/{department_uuid}", doc = "get-department", about = ""},
	updateDepartment = {method = "PUT", path = "/v1/departments/{department_uuid}", required = {"title", "version"}, doc = "put-departments", about = ""},
	deleteDepartment = {method = "DELETE", path = "/v1/departments/{department_uuid}", doc = "delete-department", about = "Only an empty department."},
	addDepartmentPeople = {method = "PUT", path = "/v1/departments/{department_uuid}/add", required = {"version"},
		doc = "put-add-people-to-department", about = "Also employees={{uuid}}, contractors={{uuid}}."},
	removeDepartmentPeople = {method = "PUT", path = "/v1/departments/{department_uuid}/remove", required = {"version"},
		doc = "put-remove-people-from-department", about = "Also employees={{uuid}}, contractors={{uuid}}."},

	listEmployees = {method = "GET", path = "/v1/companies/{company_id}/employees",
		query = {"search_term", "sort_by", "include", "location_uuid", "payroll_uuid", "onboarded", "onboarded_active", "terminated", "terminated_today", "uuids", "page", "per"},
		doc = "get-v1-companies-company_id-employees", about = "include: all_compensations, all_home_addresses, company_name, current_home_address, custom_fields or portal_invitations."},
	createEmployee = {method = "POST", path = "/v1/companies/{company_id}/employees", required = {"first_name", "last_name"},
		doc = "post-v1-employees", about = "Also middle_initial, preferred_first_name, email, date_of_birth, ssn, self_onboarding. Starts onboarding."},
	getEmployee = {method = "GET", path = "/v1/employees/{employee_id}", query = {"include"}, doc = "get-v1-employees", about = "With jobs; pay rates need the compensations scope."},
	updateEmployee = {method = "PUT", path = "/v1/employees/{employee_id}", required = {"version"}, doc = "put-v1-employees", about = ""},
	deleteEmployee = {method = "DELETE", path = "/v1/employees/{employee_id}", doc = "delete-v1-employee", about = "Only an employee who hasn't finished onboarding; terminate the others."},
	listEmployeeCustomFields = {method = "GET", path = "/v1/employees/{employee_id}/custom_fields", query = PAGE, doc = "get-v1-employees-employee_id-custom_fields", about = ""},
	getEmploymentHistory = {method = "GET", path = "/v1/employees/{employee_id}/employment_history", doc = "get-v1-employees-employee_id-employment_history", about = "Hire and termination dates."},
	listTerminations = {method = "GET", path = "/v1/employees/{employee_id}/terminations", doc = "get-v1-employees-employee_id-terminations", about = ""},
	createTermination = {method = "POST", path = "/v1/employees/{employee_id}/terminations", required = {"effective_date"},
		doc = "post-v1-employees-employee_id-terminations", about = "Also run_termination_payroll. Ends the employment on that date."},
	updateTermination = {method = "PUT", path = "/v1/terminations/{employee_id}", required = {"effective_date", "version"}, doc = "put-v1-terminations-employee_id", about = ""},
	deleteTermination = {method = "DELETE", path = "/v1/employees/{employee_id}/terminations", doc = "delete-v1-employees-employee_id-terminations", about = "Cancels a termination that hasn't taken effect."},
	getRehire = {method = "GET", path = "/v1/employees/{employee_id}/rehire", doc = "get-v1-employees-employee_id-rehire", about = "nil when no rehire is scheduled."},
	createRehire = {method = "POST", path = "/v1/employees/{employee_id}/rehire", required = {"effective_date", "file_new_hire_report", "work_location_uuid"}, doc = "post-v1-employees-employee_id-rehire", about = ""},
	updateRehire = {method = "PUT", path = "/v1/employees/{employee_id}/rehire", required = {"effective_date", "file_new_hire_report", "work_location_uuid", "version"}, doc = "put-v1-employees-employee_id-rehire", about = ""},
	deleteRehire = {method = "DELETE", path = "/v1/employees/{employee_id}/rehire", doc = "delete-v1-employees-employee_id-rehire", about = "Cancels a rehire that hasn't taken effect."},
	listHomeAddresses = {method = "GET", path = "/v1/employees/{employee_id}/home_addresses", doc = "get-v1-employees-employee_id-home_addresses", about = ""},
	createHomeAddress = {method = "POST", path = "/v1/employees/{employee_id}/home_addresses",
		doc = "post-v1-employees-employee_id-home_addresses", about = "Body {street_1, street_2?, city, state, zip, effective_date?, courtesy_withholding?}."},
	getHomeAddress = {method = "GET", path = "/v1/home_addresses/{home_address_uuid}", doc = "get-v1-home_addresses-home_address_uuid", about = ""},
	updateHomeAddress = {method = "PUT", path = "/v1/home_addresses/{home_address_uuid}", required = {"version"}, doc = "put-v1-home_addresses-home_address_uuid", about = ""},
	deleteHomeAddress = {method = "DELETE", path = "/v1/home_addresses/{home_address_uuid}", doc = "delete-v1-home_addresses-home_address_uuid", about = ""},
	listWorkAddresses = {method = "GET", path = "/v1/employees/{employee_id}/work_addresses", doc = "get-v1-employees-employee_id-work_addresses", about = ""},
	createWorkAddress = {method = "POST", path = "/v1/employees/{employee_id}/work_addresses",
		doc = "post-v1-employees-employee_id-work_addresses", about = "Body {location_uuid, effective_date?}."},
	getWorkAddress = {method = "GET", path = "/v1/work_addresses/{work_address_uuid}", doc = "get-v1-work_addresses-work_address_uuid", about = ""},
	updateWorkAddress = {method = "PUT", path = "/v1/work_addresses/{work_address_uuid}", required = {"version"}, doc = "put-v1-work_addresses-work_address_uuid", about = ""},
	deleteWorkAddress = {method = "DELETE", path = "/v1/work_addresses/{work_address_uuid}", doc = "delete-v1-work_addresses-work_address_uuid", about = ""},

	listCompensations = {method = "GET", path = "/v1/jobs/{job_id}/compensations", query = {"include", "page", "per"},
		doc = "get-v1-jobs-job_id-compensations", about = "job_id comes from an employee's jobs; include='all_compensations' adds past and future rates."},
	createCompensation = {method = "POST", path = "/v1/jobs/{job_id}/compensations", required = {"rate", "payment_unit", "flsa_status"},
		doc = "post-v1-compensations-compensation_id", about = "rate is a string; payment_unit Hour, Week, Month, Year or Paycheck. Also effective_date, adjust_for_minimum_wage."},
	getCompensation = {method = "GET", path = "/v1/compensations/{compensation_id}", doc = "get-v1-compensations-compensation_id", about = ""},
	updateCompensation = {method = "PUT", path = "/v1/compensations/{compensation_id}", required = {"version"}, doc = "put-v1-compensations-compensation_id", about = ""},
	deleteCompensation = {method = "DELETE", path = "/v1/compensations/{compensation_id}", doc = "delete-v1-compensations-compensation_id", about = "Only a compensation not yet paid on a payroll."},

	listContractors = {method = "GET", path = "/v1/companies/{company_id}/contractors",
		query = {"search_term", "sort_by", "include", "onboarded", "onboarded_active", "terminated", "terminated_today", "page", "per"}, doc = "get-v1-companies-company_uuid-contractors", about = ""},
	createContractor = {method = "POST", path = "/v1/companies/{company_id}/contractors", required = {"type", "wage_type", "start_date"},
		doc = "post-v1-companies-company_uuid-contractors", about = "type Individual or Business; wage_type Fixed or Hourly. Also first_name, last_name, business_name, email, hourly_rate, self_onboarding."},
	getContractor = {method = "GET", path = "/v1/contractors/{contractor_uuid}", query = {"include"}, doc = "get-v1-contractors-contractor_uuid", about = ""},
	updateContractor = {method = "PUT", path = "/v1/contractors/{contractor_uuid}", required = {"version"}, doc = "put-v1-contractors-contractor_uuid", about = ""},

	listPaySchedules = {method = "GET", path = "/v1/companies/{company_id}/pay_schedules", query = PAGE, doc = "get-v1-companies-company_id-pay_schedules", about = ""},
	getPaySchedule = {method = "GET", path = "/v1/companies/{company_id}/pay_schedules/{pay_schedule_id}", doc = "get-v1-companies-company_id-pay_schedules-pay_schedule_id", about = ""},
	getPayScheduleAssignments = {method = "GET", path = "/v1/companies/{company_id}/pay_schedules/assignments",
		doc = "get-v1-companies-company_id-pay_schedules-assignments", about = "Which pay schedule each employee follows."},
	listPayPeriods = {method = "GET", path = "/v1/companies/{company_id}/pay_periods", query = {"start_date", "end_date", "payroll_types"},
		doc = "get-v1-companies-company_id-pay_periods", about = "start_date defaults to 6 months ago; end_date at most 3 months ahead. Each period names its payroll's payroll_uuid."},
	listUnprocessedTerminationPayPeriods = {method = "GET", path = "/v1/companies/{company_id}/pay_periods/unprocessed_termination_pay_periods", doc = "get-v1-companies-company_id-unprocessed_termination_pay_periods", about = ""},

	listPayrolls = {method = "GET", path = "/v1/companies/{company_id}/payrolls",
		query = {"processing_statuses", "payroll_types", "processed", "include_off_cycle", "include", "start_date", "end_date", "date_filter_by", "sort_order", "page", "per"},
		doc = "get-v1-companies-company_id-payrolls", about = "Always paged (per up to 100). Defaults to processed regular payrolls of the past 6 months: pass processing_statuses={'unprocessed'} for drafts and payroll_types={'regular', 'off_cycle'} for off-cycle ones (also external). start_date and end_date span at most a year, ending at most 3 months ahead. include: totals, taxes, payroll_status_meta, risk_blockers, reversals."},
	getPayroll = {method = "GET", path = "/v1/companies/{company_id}/payrolls/{payroll_id}", query = {"include", "sort_by", "page", "per"},
		doc = "get-v1-companies-company_id-payrolls-payroll_id", about = "Gross and net pay, taxes and deductions per employee. Always pages employee_compensations (per default 25, up to 100) without totals: request the next page until fewer than per come back. include: benefits, deductions, taxes, payroll_taxes, payroll_status_meta, totals, risk_blockers, reversals."},
	preparePayroll = {method = "PUT", path = "/v1/companies/{company_id}/payrolls/{payroll_id}/prepare", query = {"sort_by", "page", "per"},
		doc = "put-v1-companies-company_id-payrolls-payroll_id-prepare", about = "Readies an unprocessed payroll for editing and returns it with each employee_compensations entry's version, paged like getPayroll. Also employee_uuids (up to 100) to prepare only those employees, or add up to 25 to a Bonus, Correction or Adhoc off-cycle payroll. Clears any earlier calculation."},
	updatePayroll = {method = "PUT", path = "/v1/companies/{company_id}/payrolls/{payroll_id}", required = {"employee_compensations"},
		doc = "put-v1-companies-company_id-payrolls", about = "employee_compensations={{employee_uuid, version, fixed_compensations?, hourly_compensations?, paid_time_off?, excluded?, memo?}}, up to 100, each version from preparePayroll. Also withholding_pay_period, skip_regular_deductions, fixed_withholding_rate. Changes the draft only; omitted entries stay."},
	calculateAccruingTimeOffHours = {method = "POST", path = "/v1/payrolls/{payroll_id}/employees/{employee_id}/calculate_accruing_time_off_hours", write = false,
		allow = {"regular_hours_worked", "overtime_hours_worked", "double_overtime_hours_worked", "pto_hours_used", "sick_hours_used"},
		doc = "post-v1-payrolls-payroll_id-calculate_accruing_time_off_hours", about = "Computes only; body fields regular_hours_worked, overtime_hours_worked, double_overtime_hours_worked, pto_hours_used and sick_hours_used."},
	listContractorPayments = {method = "GET", path = "/v1/companies/{company_id}/contractor_payments", query = {"start_date", "end_date", "contractor_uuid", "group_by_date", "page", "per"},
		required = {"start_date", "end_date"}, doc = "get-v1-companies-company_id-contractor_payments", about = "Totals and payments in the date range."},
	getContractorPayment = {method = "GET", path = "/v1/companies/{company_id}/contractor_payments/{contractor_payment_id}", doc = "get-v1-companies-company_id-contractor_payment-contractor-payment", about = ""},
	listEarningTypes = {method = "GET", path = "/v1/companies/{company_id}/earning_types", doc = "get-v1-companies-company_id-earning_types", about = "{default, custom}."},
	createEarningType = {method = "POST", path = "/v1/companies/{company_id}/earning_types", required = {"name"},
		doc = "post-v1-companies-company_id-earning_types", about = "A custom earning type for payroll fixed compensations."},
	updateEarningType = {method = "PUT", path = "/v1/companies/{company_id}/earning_types/{earning_type_uuid}",
		doc = "put-v1-companies-company_id-earning_types-earning_type_uuid", about = "Body {name}."},
	deleteEarningType = {method = "DELETE", path = "/v1/companies/{company_id}/earning_types/{earning_type_uuid}",
		doc = "delete-v1-companies-company_id-earning_types-earning_type_uuid", about = "Deactivates a custom earning type."},
	createGeneralLedgerReport = {method = "POST", path = "/v1/payrolls/{payroll_uuid}/reports/general_ledger", required = {"aggregation"}, allow = {"aggregation", "integration_type"}, write = false,
		doc = "post-payrolls-payroll_uuid-reports-general_ledger", about = "aggregation default, job, department or integration, with integration_type (such as xero or qbo) for integration. Returns {request_uuid}; poll getReport until its status is succeeded or failed."},
	getReport = {method = "GET", path = "/v1/reports/{request_uuid}",
		doc = "get-reports-request_uuid", about = "{status, report_urls}: temporary download links; treat them as secrets."},

	listTimeOffPolicies = {method = "GET", path = "/v1/companies/{company_id}/time_off_policies", doc = "get-v1-companies-company_uuid-time_off_policies", about = ""},
	getTimeOffPolicy = {method = "GET", path = "/v1/time_off_policies/{time_off_policy_uuid}", doc = "get-v1-time_off_policies-time_off_policy_uuid", about = "With employee balances."},
	addTimeOffPolicyEmployees = {method = "PUT", path = "/v1/time_off_policies/{time_off_policy_uuid}/add_employees", required = {"employees"},
		doc = "put-v1-time_off_policies-time_off_policy_uuid-add_employees", about = "employees={{uuid, balance?}}."},
	listTimeOffRequests = {method = "GET", path = "/v1/companies/{company_id}/time_off_requests", query = {"start_date", "end_date"}, doc = "get-v1-companies-company_id-time_off_requests", about = ""},
	listTimeOffActivities = {method = "GET", path = "/v1/employees/{employee_id}/time_off_activities", query = {"time_off_type"}, required = {"time_off_type"},
		doc = "get-version-employees-time_off_activities", about = "time_off_type such as 'vacation' or 'sick'."},

	listBenefits = {method = "GET", path = "/v1/benefits", doc = "get-v1-benefits", about = "Benefit types Gusto supports; benefit_id is a number."},
	getBenefit = {method = "GET", path = "/v1/benefits/{benefit_id}", doc = "get-v1-benefits-benefit_id", about = ""},
	getBenefitRequirements = {method = "GET", path = "/v1/benefits/{benefit_id}/requirements", doc = "get-v1-benefits-benefits_id-requirements", about = ""},
	listCompanyBenefits = {method = "GET", path = "/v1/companies/{company_id}/company_benefits", query = {"active", "enrollment_count", "benefit_type"},
		doc = "get-v1-companies-company_id-company_benefits", about = "benefit_type takes benefit type numbers."},
	createCompanyBenefit = {method = "POST", path = "/v1/companies/{company_id}/company_benefits", required = {"description"},
		doc = "post-v1-companies-company_id-company_benefits", about = "Also benefit_type, active, responsible_for_employer_taxes, responsible_for_employee_w2."},
	getCompanyBenefit = {method = "GET", path = "/v1/company_benefits/{company_benefit_id}", query = {"with_employee_benefits", "include"}, doc = "get-v1-company_benefits-company_benefit_id", about = ""},
	updateCompanyBenefit = {method = "PUT", path = "/v1/company_benefits/{company_benefit_id}", required = {"version"}, doc = "put-v1-company_benefits-company_benefit_id", about = ""},
	deleteCompanyBenefit = {method = "DELETE", path = "/v1/company_benefits/{company_benefit_id}",
		doc = "delete-v1-company_benefits-company_benefit_id", about = "Only a benefit without employee enrollments or payroll history; otherwise set active=false."},
	getCompanyBenefitSummary = {method = "GET", path = "/v1/company_benefits/{company_benefit_id}/summary", query = {"start_date", "end_date", "detailed"},
		doc = "get-v1-benefits-company_benefit_id-summary", about = "Employee deductions and company contributions over the range."},
	getContributionExclusions = {method = "GET", path = "/v1/company_benefits/{company_benefit_id}/contribution_exclusions", doc = "get-v1-company_benefits-company_benefit_id-contribution_exclusions", about = ""},
	updateContributionExclusions = {method = "PUT", path = "/v1/company_benefits/{company_benefit_id}/contribution_exclusions", required = {"contribution_exclusions"}, doc = "put-v1-company_benefits-company_benefit_id-contribution_exclusions", about = ""},
	listCompanyBenefitEmployeeBenefits = {method = "GET", path = "/v1/company_benefits/{company_benefit_id}/employee_benefits", query = {"include", "page", "per"},
		doc = "get-v1-company_benefits-company_benefit_id-employee_benefits", about = "Enrollments in one company benefit."},
	updateCompanyBenefitEmployeeBenefits = {method = "PUT", path = "/v1/company_benefits/{company_benefit_id}/employee_benefits", required = {"employee_benefits"},
		doc = "put-v1-company_benefits-company_benefit_id-employee_benefits", about = "employee_benefits={{employee_uuid, ...}} creates or updates many enrollments."},
	listEmployeeBenefits = {method = "GET", path = "/v1/employees/{employee_id}/employee_benefits", query = {"include", "page", "per"}, doc = "get-v1-employees-employee_id-employee_benefits", about = ""},
	createEmployeeBenefit = {method = "POST", path = "/v1/employees/{employee_id}/employee_benefits", required = {"company_benefit_uuid"},
		doc = "post-v1-employees-employee_id-employee_benefits", about = "Also active, employee_deduction, company_contribution, deduct_as_percentage, effective_date and more. Enrolls the employee."},
	getEmployeeBenefit = {method = "GET", path = "/v1/employee_benefits/{employee_benefit_id}", doc = "get-v1-employee_benefits-employee_benefit_id", about = ""},
	updateEmployeeBenefit = {method = "PUT", path = "/v1/employee_benefits/{employee_benefit_id}", required = {"version"}, doc = "put-v1-employee_benefits-employee_benefit_id", about = ""},
	deleteEmployeeBenefit = {method = "DELETE", path = "/v1/employee_benefits/{employee_benefit_id}", doc = "delete-v1-employee_benefits-employee_benefit_id", about = "Ends the enrollment."},
	getYtdBenefitAmountsFromDifferentCompany = {method = "GET", path = "/v1/employees/{employee_id}/ytd_benefit_amounts_from_different_company", query = {"tax_year"},
		doc = "get-employee-ytd-benefit-amounts-from-different-company", about = "Contributions made at a previous employer this year."},
	createYtdBenefitAmountsFromDifferentCompany = {method = "POST", path = "/v1/employees/{employee_id}/ytd_benefit_amounts_from_different_company",
		required = {"benefit_type", "tax_year", "ytd_employee_deduction_amount", "ytd_company_contribution_amount"}, doc = "post-employee-ytd-benefit-amounts-from-different-company", about = ""},
	listSection603HighEarnerStatuses = {method = "GET", path = "/v1/employees/{employee_id}/section603_high_earner_statuses",
		doc = "get-v1-employees-employee_uuid-section603_high_earner_statuses", about = "Whether catch-up contributions must be Roth, per year."},
	getSection603HighEarnerStatus = {method = "GET", path = "/v1/employees/{employee_id}/section603_high_earner_statuses/{effective_year}", doc = "get-v1-employees-employee_uuid-section603_high_earner_statuses-effective_year", about = ""},
	createSection603HighEarnerStatus = {method = "POST", path = "/v1/employees/{employee_id}/section603_high_earner_statuses", required = {"effective_year", "is_high_earner"}, doc = "post-v1-employees-employee_uuid-section603_high_earner_statuses", about = ""},
	updateSection603HighEarnerStatus = {method = "PATCH", path = "/v1/employees/{employee_id}/section603_high_earner_statuses/{effective_year}", required = {"is_high_earner"}, doc = "patch-v1-employees-employee_uuid-section603_high_earner_statuses-effective_year", about = ""},

	listGarnishments = {method = "GET", path = "/v1/employees/{employee_id}/garnishments", query = PAGE, doc = "get-v1-employees-employee_id-garnishments", about = "Court-ordered and voluntary deductions."},
	createGarnishment = {method = "POST", path = "/v1/employees/{employee_id}/garnishments", required = {"amount", "court_ordered"},
		doc = "post-v1-employees-employee_id-garnishments", about = "Also description, garnishment_type, recurring, deduct_as_percentage, annual_maximum and more."},
	getGarnishment = {method = "GET", path = "/v1/garnishments/{garnishment_id}", doc = "get-v1-garnishments-garnishment_id", about = ""},
	updateGarnishment = {method = "PUT", path = "/v1/garnishments/{garnishment_id}", required = {"version"}, doc = "put-v1-garnishments-garnishment_id", about = ""},
	getChildSupportData = {method = "GET", path = "/v1/garnishments/child_support", doc = "get-v1-garnishments-child_support", about = "Child support agencies and their required fields per state."},
	listRecurringReimbursements = {method = "GET", path = "/v1/employees/{employee_id}/recurring_reimbursements", query = PAGE, doc = "get-v1-employees-employee_id-recurring_reimbursements", about = ""},
	createRecurringReimbursement = {method = "POST", path = "/v1/employees/{employee_id}/recurring_reimbursements", required = {"description", "amount"},
		doc = "post-v1-employees-employee_id-recurring_reimbursements", about = "amount is a number. Paid on every regular payroll."},
	getRecurringReimbursement = {method = "GET", path = "/v1/recurring_reimbursements/{id}", doc = "get-v1-recurring_reimbursements", about = ""},
	updateRecurringReimbursement = {method = "PUT", path = "/v1/recurring_reimbursements/{id}", required = {"version"}, doc = "put-v1-recurring_reimbursements", about = ""},
	deleteRecurringReimbursement = {method = "DELETE", path = "/v1/recurring_reimbursements/{id}", doc = "delete-v1-recurring_reimbursements", about = ""},

	listTimeSheets = {method = "GET", path = "/v1/companies/{company_id}/time_tracking/time_sheets",
		query = {"entity_type", "entity_uuids", "status", "after", "before", "sort_by", "sort_order", "page", "per"},
		doc = "get-companies-company_uuid-time_tracking-time_sheets", about = "entity_type Employee or Contractor; status pending, approved or rejected; after/before filter created_at (ISO 8601)."},
	createTimeSheet = {method = "POST", path = "/v1/companies/{company_id}/time_tracking/time_sheets", required = {"entity_type", "entity_uuid", "shift_started_at", "time_zone"},
		doc = "post-companies-company_uuid-time_tracking-time_sheets", about = "Also shift_ended_at, job_uuid, metadata, entries."},
	getTimeSheet = {method = "GET", path = "/v1/time_tracking/time_sheets/{time_sheet_uuid}", doc = "get-time_tracking-time_sheets-time_sheet_uuid", about = ""},
	updateTimeSheet = {method = "PUT", path = "/v1/time_tracking/time_sheets/{time_sheet_uuid}", required = {"version"}, doc = "put-time_tracking-time_sheets-time_sheet_uuid", about = ""},
	deleteTimeSheet = {method = "DELETE", path = "/v1/time_tracking/time_sheets/{time_sheet_uuid}", query = {"version"}, required = {"version"}, doc = "delete-time_tracking-time_sheets-time_sheet_uuid", about = ""},
	createPayrollSync = {method = "POST", path = "/v1/companies/{company_id}/time_tracking/payroll_syncs", required = {"kind", "pay_schedule_uuid", "pay_period_start_date", "pay_period_end_date"},
		doc = "post-companies-company_uuid-time_tracking-payroll_syncs", about = "Copies approved time sheets into that pay period's unprocessed payroll."},
	getPayrollSync = {method = "GET", path = "/v1/time_tracking/payroll_syncs/{payroll_sync_uuid}", doc = "get-time_tracking-payroll_syncs-payroll_sync_uuid", about = ""},

	listNotifications = {method = "GET", path = "/v1/companies/{company_id}/notifications", query = {"status", "page", "per"},
		doc = "get-company-notifications", about = "Actions Gusto asks the company to take; status open, resolved or expired."},
}

-- Request layer shared verbatim by the Cal.com, Calendly, Carta, Carta CRM, Gusto, Resend and Vercel connectors
-- (tools/validate checks they match). It uses each connector's PROVIDER, DOCS and Endpoint type.
local NULL = json.decode("null")
local NONE: {string} = table.freeze({})

local function options(input: Options?): Options
	if input == nil then return {} end
	assert(type(input) == "table", "opts must be an object")
	for key in input do assert(type(key) == "string", "opts must have named fields") end
	return table.clone(input)
end

local function scalar(value: any, field: string): string
	local kind = type(value)
	assert(kind == "string" or kind == "boolean" or kind == "number", field .. " must be a string, boolean, number or array of those")
	return url.encode(value)
end

-- A query value's encoded parts: one for a scalar, one per item of a nonempty array. Each
-- connector joins them as its provider expects, comma-separated or with the key repeated.
local function queryParts(value: any, field: string): {string}
	if type(value) ~= "table" then return {scalar(value, field)} end
	local parts: {string} = {}
	for index, item in value do
		assert(type(index) == "number" and index == #parts + 1, field .. " must be an array, not an object")
		table.insert(parts, scalar(item, field))
	end
	assert(#parts > 0, field .. " must not be an empty array")
	return parts
end

-- Only GET reads unless write says otherwise.
local function writes(endpoint: Endpoint): boolean
	if endpoint.write ~= nil then return endpoint.write end
	return endpoint.method ~= "GET"
end

-- POST, PATCH and PUT send the remaining options as the JSON body unless body is false
-- (no body) or names the one option to send.
local function hasBody(endpoint: Endpoint): boolean
	return endpoint.body ~= false and (endpoint.method == "POST" or endpoint.method == "PATCH" or endpoint.method == "PUT")
end

local function fail(name: string, response: HttpResponse, message: string): never
	return houston.fail({operation = name, layer = "upstream", upstream_status = response.statusCode,
		retryable = response.statusCode == 429 or response.statusCode >= 500, message = message})
end

-- A successful response's JSON object, or nil when a write answers without a body. With arrays,
-- a top-level JSON array is accepted too, and the second result tells which one came back.
local function object(name: string, endpoint: Endpoint, response: HttpResponse, arrays: boolean?): (any, boolean)
	local raw = await(response.body:readAll())
	if endpoint.method ~= "GET" and writes(endpoint) and string.match(raw, "^%s*$") then return nil, false end
	local ok, value = pcall(json.decode, raw)
	local list = arrays == true and string.match(raw, "^%s*%[") ~= nil
	if not ok or type(value) ~= "table" or not (list or string.match(raw, "^%s*{")) then
		fail(name, response, PROVIDER .. " returned an invalid JSON object")
	end
	return value, list
end

-- name({path fields, query fields?, extra fields?, required body fields, ...body}) built from the
-- endpoint itself.
-- Extra fields are options the connector's own request consumes, such as a request header.
local function signature(endpoint: Endpoint): string
	local fields: {string} = {}
	for field in string.gmatch(endpoint.path, "{([%w_]+)}") do table.insert(fields, field) end
	for _, group in {endpoint.query or NONE, endpoint.extra or NONE} do
		for _, field in group do
			table.insert(fields, if table.find(endpoint.required or NONE, field) then field else field .. "?")
		end
	end
	if type(endpoint.body) == "string" then
		table.insert(fields, endpoint.body)
	elseif hasBody(endpoint) then
		for _, field in endpoint.required or NONE do
			if not table.find(fields, field) then table.insert(fields, field) end
		end
		table.insert(fields, "...body")
	end
	return "({" .. table.concat(fields, ", ") .. "})"
end

-- A function for each endpoint the connection's access allows, and help listing them after intro.
local function operations(endpoints: {[string]: Endpoint}, request: (string, Endpoint, Options?) -> any, intro: {string}): {[string]: any}
	local exports: {[string]: any} = {}
	for name, endpoint in endpoints do
		if not writes(endpoint) or config.access == "read-write" then
			exports[name] = function(args: Options?): any return request(name, endpoint, args) end
		end
	end
	exports.help = function(): string
		local names: {string} = {}
		for name in exports do if name ~= "help" then table.insert(names, name) end end
		table.sort(names)
		local lines = table.clone(intro)
		table.insert(lines, "Each function below names its route and reference page, " .. DOCS .. "<page>.")
		for _, name in names do
			local endpoint = endpoints[name]
			table.insert(lines, name .. signature(endpoint) .. ": " .. endpoint.about .. " " .. endpoint.method .. " " .. endpoint.path .. " (" .. endpoint.doc .. ")")
		end
		return table.concat(lines, "\n")
	end
	return exports
end
-- End of the shared request layer.

-- Gusto IDs are UUIDs; benefit types and years are numbers.
local function identifier(value: any, field: string): string
	if type(value) == "number" then
		assert(value >= 0 and value % 1 == 0 and value <= 9007199254740991, field .. " must be a Gusto ID")
		return string.format("%d", value)
	end
	assert(type(value) == "string" and string.match(value, "^[%w_%-]+$") and #value <= 64, field .. " must be a Gusto ID")
	return value
end

local function header(response: HttpResponse, name: string): string?
	local values = response.headers[name]
	return if values then values[1] else nil
end

-- Gusto errors are {errors={{error_key, category, message, errors?}}}, where nested_errors
-- carry per-item errors further down with metadata such as employee_uuid; a rejected token
-- answers with an empty body and the reason in WWW-Authenticate. A create that failed with a
-- 5xx may have been stored, so only throttling makes it retryable.
local function failStatus(name: string, endpoint: Endpoint, response: HttpResponse): never
	local message = "Gusto HTTP " .. tostring(response.statusCode)
	local ok, value = pcall(json.decode, await(response.body:readPrefix(16 * 1024)))
	local details: {string} = {}
	local function collect(errors: any)
		if type(errors) ~= "table" then return end
		for _, item in errors do
			if type(item) == "table" and #details < 5 then
				local parts: {string} = {}
				for _, field in {"category", "error_key", "message"} do
					if type(item[field]) == "string" and item[field] ~= "" then table.insert(parts, string.sub(item[field], 1, 300)) end
				end
				if type(item.metadata) == "table" then
					local keys: {string} = {}
					for key, field in item.metadata do
						if type(key) == "string" and (type(field) == "string" or type(field) == "number") then table.insert(keys, key) end
					end
					table.sort(keys)
					for _, key in keys do table.insert(parts, "(" .. string.sub(key .. "=" .. tostring(item.metadata[key]), 1, 100) .. ")") end
				end
				if #parts > 0 then table.insert(details, table.concat(parts, " ")) end
				collect(item.errors)
			end
		end
	end
	if ok and type(value) == "table" then collect(value.errors) end
	local reason = header(response, "www-authenticate")
	if #details == 0 and reason then
		local description = string.match(reason, 'error_description="([^"]*)"')
		if description then table.insert(details, string.sub(description, 1, 300)) end
	end
	if #details > 0 then message ..= ": " .. table.concat(details, "; ") end
	local retry = header(response, "retry-after")
	if response.statusCode == 429 and retry and string.match(retry, "^%d+$") then message ..= "; retry after " .. retry .. "s" end
	local creates = endpoint.method == "POST" and writes(endpoint)
	return houston.fail({operation = name, layer = "upstream", upstream_status = response.statusCode,
		retryable = response.statusCode == 429 or (response.statusCode >= 500 and not creates), message = message})
end

-- Objects return unchanged; arrays become {items, page?, per?, total_count?, total_pages?}, keeping
-- Gusto's paging headers; a write answered without a body returns {success=true} and a read
-- answered 204 No Content returns nil.
local function decode(name: string, endpoint: Endpoint, response: HttpResponse): any
	if response.statusCode == 204 and not writes(endpoint) then
		response.body:close()
		return nil
	end
	local value, list = object(name, endpoint, response, true)
	if value == nil then return {success = true} end
	if not list then return value end
	return {items = value, page = tonumber(header(response, "x-page")), per = tonumber(header(response, "x-per-page")),
		total_count = tonumber(header(response, "x-total-count")), total_pages = tonumber(header(response, "x-total-pages"))}
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
	-- Gusto reads list filters (include, uuids, payroll_types) as comma-separated values.
	for _, field in endpoint.query or NONE do
		if args[field] ~= nil then table.insert(query, field .. "=" .. table.concat(queryParts(args[field], field), ",")) end
		args[field] = nil
	end
	if #query > 0 then path ..= "?" .. table.concat(query, "&") end
	local headers: HttpHeaders = {Accept = {"application/json"}, ["X-Gusto-API-Version"] = {VERSION}}
	local body: string? = nil
	if hasBody(endpoint) then
		for field in args do
			assert(endpoint.allow == nil or table.find(endpoint.allow, field), name .. " has no option " .. field)
		end
		headers["Content-Type"] = {"application/json"}
		body = json.encode(args)
		args = {}
	end
	local unknown = next(args)
	assert(unknown == nil, name .. " has no option " .. tostring(unknown))
	local response = await(http.request({method = endpoint.method, url = API .. path, headers = headers, body = body}))
	if response.statusCode < 200 or response.statusCode >= 300 then failStatus(name, endpoint, response) end
	return decode(name, endpoint, response)
end

local WRITES = "Updates whose signature lists version take the object's current version, read just before: a stale version fails with 409 invalid_resource_version, so read again and reapply. Payrolls are never submitted here: call preparePayroll, then updatePayroll with each employee compensation's version. Changes to pay, reimbursements and draft payrolls are paid by the next payroll, including one Gusto runs automatically for companies on Payroll on AutoPilot. Creates are not idempotent: after a timeout or 5xx, which is reported as not retryable, list or read before repeating one."

return operations(endpoints, request, {
	"Gusto App Integrations API (version " .. VERSION .. ")" .. (if auth.method == "demo" then " on Gusto's demo environment (sample data)" else "") .. ". Every function takes one named options object with Gusto's snake_case names; ? marks optional fields, required body fields follow the path and query fields, and ...body stands for the other JSON body fields. Objects return unchanged; JSON arrays return {items, page?, per?, total_count?, total_pages?}; a write answered without a body returns {success=true}. Connector calls return completed values: use them directly, without await.",
	"A connection reaches one company. Start with local company_id = gusto.getTokenInfo().resource.uuid, then getCompany({company_id=company_id}), listEmployees({company_id=company_id}), listPayrolls(...). Employee jobs (getEmployee().jobs) give the job_id for compensations. IDs are UUID strings, except benefit_id (a number).",
	"Pass page (1-based) and per (default 25, often at most 100) to any list and continue while total_pages is set and page < total_pages, or else while a full page came back; without page, most lists return every record, but listPayrolls always pages, and getPayroll and preparePayroll page their employee_compensations. Dates are YYYY-MM-DD; payroll amounts are decimal strings such as '1250.00'. Array filters (include, uuids, payroll_types) are sent comma-separated. A read answered 204 No Content returns nil.",
	"Examples: local company_id = gusto.getTokenInfo().resource.uuid; gusto.listEmployees({company_id=company_id, terminated=false, include={'custom_fields'}, page=1, per=100}); gusto.listPayrolls({company_id=company_id, start_date='2026-01-01', end_date='2026-06-30', include={'totals'}}); gusto.getPayroll({company_id=company_id, payroll_id=id, include={'taxes', 'deductions'}}).",
	"Responses include personal and pay data (birth dates, home addresses, pay rates, garnishments); share only what the task needs. Gusto's scopes for the app decide what is visible: pay rates need the compensations scope, and a missing scope fails with 403 missing_oauth_scopes.",
	"Errors report the HTTP status and Gusto's category, error_key and message, with per-item nested errors (for example 422 invalid_attribute_value or 404 not_found). Gusto allows 200 requests per minute per connection.",
	if config.access == "read-write" then WRITES else "Read-only connections omit writes.",
})
