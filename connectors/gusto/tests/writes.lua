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

		local count = 0
		for name in gusto do if name ~= "help" then count += 1 end end
		assert(count == 115, "wrong read-write surface: " .. count)
		for _, name in {"submitPayroll", "calculatePayroll", "cancelPayroll", "createContractorPayment", "createWebhookSubscription", "listEvents"} do
			assert(gusto[name] == nil, "unsupported operation exported: " .. name)
		end

		payload = '{"uuid":"e9","first_name":"Ada","last_name":"Lovelace","version":"v1"}'
		local employee = gusto.createEmployee({company_id = COMPANY, first_name = "Ada", last_name = "Lovelace", email = "ada@example.com", self_onboarding = true})
		assert(last().method == "POST" and last().url == API .. "/companies/" .. COMPANY .. "/employees")
		assert(last().headers["Content-Type"][1] == "application/json" and last().headers["X-Gusto-API-Version"][1] == "2026-06-15")
		assert(last().headers.Authorization == nil)
		local body = sent()
		assert(body.first_name == "Ada" and body.self_onboarding == true and body.company_id == nil, "path field leaked into the body")
		assert(employee.uuid == "e9")

		gusto.updateEmployee({employee_id = "e9", version = "v1", preferred_first_name = "Countess", middle_initial = json.decode("null")})
		assert(last().method == "PUT" and last().url == API .. "/employees/e9")
		assert(sent().version == "v1" and sent().preferred_first_name == "Countess" and string.find(last().body, '"middle_initial":null', 1, true), last().body)

		payload = '{"uuid":"p1","version":"pv2","processing_status":"unprocessed","employee_compensations":[]}'
		local draft = gusto.preparePayroll({company_id = COMPANY, payroll_id = "p1", per = 100})
		assert(last().method == "PUT" and last().url == API .. "/companies/" .. COMPANY .. "/payrolls/p1/prepare?per=100" and last().body == nil)
		assert(last().headers["Content-Type"] == nil and draft.version == "pv2")
		gusto.updatePayroll({company_id = COMPANY, payroll_id = "p1", version = draft.version,
			employee_compensations = {{employee_uuid = "e9", fixed_compensations = {{name = "Bonus", amount = "500.00"}}}}})
		assert(last().method == "PUT" and last().url == API .. "/companies/" .. COMPANY .. "/payrolls/p1")
		body = sent()
		assert(body.version == "pv2" and body.employee_compensations[1].fixed_compensations[1].amount == "500.00" and body.payroll_id == nil)

		payload = '{"uuid":"t1","effective_date":"2026-11-30","version":"tv1"}'
		gusto.createTermination({employee_id = "e9", effective_date = "2026-11-30", run_termination_payroll = false})
		assert(last().method == "POST" and last().url == API .. "/employees/e9/terminations" and sent().run_termination_payroll == false)
		gusto.updateSection603HighEarnerStatus({employee_id = "e9", effective_year = 2026, is_high_earner = true})
		assert(last().method == "PATCH" and last().url == API .. "/employees/e9/section603_high_earner_statuses/2026" and sent().is_high_earner == true)

		payload = ""
		status = 204
		local deleted = gusto.deleteTimeSheet({time_sheet_uuid = "ts1", version = "tsv3"})
		assert(last().method == "DELETE" and last().url == API .. "/time_tracking/time_sheets/ts1?version=tsv3" and last().body == nil)
		assert(deleted.success == true)
		assert(gusto.deleteEmployee({employee_id = "e9"}).success == true and last().method == "DELETE" and last().url == API .. "/employees/e9")
		status = 200

		payload = "[]"
		local cleared = gusto.updateCompanyBenefitEmployeeBenefits({company_benefit_id = "cb1", employee_benefits = json.decode("[]")})
		assert(last().method == "PUT" and last().body == '{"employee_benefits":[]}' and json.encode(cleared.items) == "[]")

		local before = #requests
		for _, call in {
			function() gusto.updateEmployee({employee_id = "e9", first_name = "Ada"}) end,
			function() gusto.updatePayroll({company_id = COMPANY, payroll_id = "p1", employee_compensations = json.decode("[]")}) end,
			function() gusto.updatePayroll({company_id = COMPANY, payroll_id = "p1", version = json.decode("null"), employee_compensations = json.decode("[]")}) end,
			function() gusto.deleteTimeSheet({time_sheet_uuid = "ts1"}) end,
			function() gusto.createTermination({employee_id = "e9"}) end,
			function() gusto.preparePayroll({company_id = COMPANY, payroll_id = "p1", version = "x"}) end,
		} do
			assert(not pcall(call), "invalid write was accepted")
		end
		assert(#requests == before, "invalid writes reached Gusto")
	end,
}
