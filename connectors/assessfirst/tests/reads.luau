local API = "https://app.assessfirst.com/betty-V2"
local C = "ab4699c9169d469c81082accfbe91584"
local PM = "1d9c92277e264fe49a4ce330e51e6ac7"
local G = "786a70ccd1454e83bfae271ffa721c0d"
return {
	scenario = {publisher = {}, config = {access = "read-write"}, auth_method = "token", auth_config = {token = "fixture-private-assessfirst-token"}},
	configure = function()
		calls = 0
		status = 200
		payload = "{}"
		contentType = "application/json"
		fs = fixture.files()
		http = {request = function(req)
			calls += 1
			request = req
			return fixture.operation({statusCode = status, headers = {["content-type"] = {contentType}}, body = fixture.reader(payload)})
		end}
	end,
	run = function(af)
		local function get(name, args, url, body)
			payload = body or "{}"
			local result = af[name](args)
			assert(request.method == "GET" and request.url == url, name .. " requested " .. request.method .. " " .. request.url)
			assert(request.body == nil and request.headers.Authorization == nil and request.headers["AF-Token"] == nil)
			return result
		end
		get("listRecruiters", {uuid = C, email = "rh@example.com", page = 1, per_page = 1}, API .. "/recruiters?uuid=" .. C .. "&email=rh%40example.com&page=1&per_page=1")
		assert(json.encode(get("listCandidateReports", {candidate_uuid = C}, API .. "/candidate/" .. C .. "/reports", "[]")) == "[]", "empty report array lost")
		local reports = get("listCandidateReports", {candidate_uuid = C}, API .. "/candidate/" .. C .. "/reports",
			'[{"id":20,"name":"Summary of findings","assessment":"All assessments","web_link":"https://report.assessfirst.com/report/summary_report/' .. C .. '?from=api"}]')
		assert(reports[1].id == 20 and string.find(reports[1].web_link, "?from=api", 1, true))
		-- The sso parameter may sign whoever opens the link in to AssessFirst.
		local profile = "https://app.assessfirst.com/recruiter/profile/" .. C .. "/predict/" .. PM
		for _, link in {{profile .. "?sso=6db2e7", profile}, {profile .. "?sso=6db2e7&tab=voice", profile .. "?tab=voice"},
			{profile .. "?tab=voice&sso=6db2e7", profile .. "?tab=voice"}, {profile .. "?tab=voice&sso=6db2e7#top", profile .. "?tab=voice#top"},
			{profile .. "?sso=a&sso=b", profile}, {profile .. "?a=1&sso=a&sso=b&c=2", profile .. "?a=1&c=2"}, {"Why use sso=1? Is it safe?", "Why use sso=1? Is it safe?"}} do
			local fit = get("getCandidateAdequacies", {candidate_uuid = C, pm_uuid = PM, locale = "en-GB"}, API .. "/candidate/" .. C .. "/adequacies/" .. PM .. "?locale=en-GB",
				json.encode({adequacies = {global_adequacy = 14.29}, predict_success_url = link[1]}))
			assert(fit.predict_success_url == link[2] and fit.adequacies.global_adequacy == 14.29, "kept " .. fit.predict_success_url)
		end
		get("getCandidateCompletion", {candidate_uuid = C}, API .. "/candidate/" .. C .. "/completion")
		get("getCandidateCompletion", {candidate_uuid = C, pm_uuid = json.decode("null")}, API .. "/candidate/" .. C .. "/completion")
		local completion = get("getCandidateCompletion", {candidate_uuid = C, pm_uuid = PM}, API .. "/candidate/" .. C .. "/completion?pm_uuid=" .. PM,
			'{"assessments":{"swipe":"finish","voice":"todo"},"is_completed":false}')
		assert(completion.assessments.voice == "todo" and completion.is_completed == false)
		get("getCandidateSynthesis", {candidate_uuid = C}, API .. "/candidate/" .. C .. "/synthesis")
		-- PHP answers an empty object as [], which object endpoints pass through.
		assert(json.encode(get("getCandidateSynthesis", {candidate_uuid = C}, API .. "/candidate/" .. C .. "/synthesis", "[]")) == "[]")
		get("getCandidateTopCareers", {candidate_uuid = C, type = "full"}, API .. "/candidate/" .. C .. "/career/top?type=full")
		get("getCandidateOnePager", {candidate_uuid = C, pm_uuid = PM}, API .. "/onepager/candidate/" .. C .. "/results?pm_uuid=" .. PM)
		get("getVoiceStatus", {candidate_uuid = C, pm_uuid = PM}, API .. "/candidate/" .. C .. "/init-voice/" .. PM)
		get("listPredictiveModels", {name = "Sales & Ops", is_public = true}, API .. "/predictive-models?name=Sales%20%26%20Ops&is_public=1")
		get("listPredictiveModels", {is_public = false, page = 3}, API .. "/predictive-models?is_public=0&page=3")
		get("listBenchmarks", {name = "Director"}, API .. "/benchmarks?name=Director")
		get("listWebhooks", {name = "ATS", url = "https://hooks.example.com/af?x=1"}, API .. "/webhooks?name=ATS&url=https%3A%2F%2Fhooks.example.com%2Faf%3Fx%3D1")
		get("listGroups", {per_page = 10}, API .. "/groups?per_page=10")
		get("listGroupUsers", {group_uuid = G}, API .. "/groups/" .. G .. "/users")

		contentType = "application/pdf"
		payload = "%PDF-1.7 report"
		local report = af.downloadCandidateReport({candidate_uuid = C, report_id = 20, path = "reports/ana.pdf", locale = "fr-FR"})
		assert(request.url == API .. "/candidate/" .. C .. "/report/20?locale=fr-FR" and request.headers.Accept == nil)
		assert(report.path == "reports/ana.pdf" and report.size == #payload and report.contentType == "application/pdf" and type(report.url) == "string")
		local file = fs.open("reports/ana.pdf", "r")
		assert(await(file:readAll()) == payload)
		await(file:close())
		af.downloadCandidateReport({candidate_uuid = C, report_id = 17, pm_uuid = PM, path = "fit.pdf"})
		assert(request.url == API .. "/candidate/" .. C .. "/report/17?pm_uuid=" .. PM)

		contentType = "application/json; charset=utf-8"
		payload = '{"code":0,"message":"report_not_available","data":[],"status":200}'
		local ok, err = pcall(af.downloadCandidateReport, {candidate_uuid = C, report_id = 8, path = "brain.pdf"})
		assert(not ok and string.find(tostring(err), "HTTP 200: report_not_available", 1, true), tostring(err))
		assert(not await(fs.exists("brain.pdf")), "JSON explanation saved as a PDF")
		for _, kind in {"text/html; charset=UTF-8", "text/plain", "", "application/xhtml+xml", "image/png"} do
			contentType = kind
			payload = "<html>Sign in to AssessFirst</html>"
			local ok, err = pcall(af.downloadCandidateReport, {candidate_uuid = C, report_id = 10, path = "login.pdf"})
			assert(not ok and string.find(tostring(err), "instead of a PDF", 1, true) and string.find(tostring(err), '"retryable":false', 1, true), tostring(err))
			assert(not await(fs.exists("login.pdf")), kind .. " page saved as a PDF")
		end
		payload = "%PDF-1.7 binary"
		for _, kind in {"application/octet-stream", "application/x-pdf", "application/force-download"} do
			contentType = kind
			assert(af.downloadCandidateReport({candidate_uuid = C, report_id = 10, path = "brain.pdf"}).size == #payload, kind)
		end

		local function rejected(fn, expected)
			local before = calls
			local ok, err = pcall(fn)
			assert(not ok and string.find(tostring(err), expected, 1, true), "wrong validation error: " .. tostring(err))
			assert(calls == before, "invalid input reached AssessFirst")
		end
		rejected(function() af.getCandidate() end, "candidate_uuid must be an AssessFirst UUID")
		rejected(function() af.getCandidate({candidate_uuid = "../recruiters"}) end, "candidate_uuid must be an AssessFirst UUID")
		rejected(function() af.getCandidate({candidate_uuid = C .. "/reports"}) end, "candidate_uuid")
		rejected(function() af.getCandidate({candidate_uuid = 42}) end, "candidate_uuid")
		rejected(function() af.getCandidate({candidate_uuid = C, extra = true}) end, "getCandidate has no option extra")
		rejected(function() af.getCandidate("ab4699c9") end, "opts must be an object")
		rejected(function() af.getCandidateCompletion({candidate_uuid = C, pm_uuid = "web designer"}) end, "pm_uuid")
		for _, size in {0, 51, 1.5, "10"} do
			rejected(function() af.listCandidates({per_page = size}) end, "per_page must be an integer from 1 to 50")
		end
		rejected(function() af.listCandidates({page = 0}) end, "page must be an integer")
		rejected(function() af.listCandidates({page = 1e15}) end, "page must be an integer from 1 to 1000000000")
		rejected(function() af.listCandidates({email = ""}) end, "email must be a nonempty string")
		rejected(function() af.listPredictiveModels({is_public = 1}) end, "is_public must be a boolean")
		rejected(function() af.listWebhooks({actions = "user.linked"}) end, "actions must be a nonempty array")
		rejected(function() af.listWebhooks({actions = json.decode("[]")}) end, "actions must be a nonempty array")
		rejected(function() af.listWebhooks({actions = {"user.created"}}) end, "actions must contain only")
		rejected(function() af.listLocales({locale = "fr-FR&page=2"}) end, "locale must be a locale")
		rejected(function() af.downloadCandidateReport({candidate_uuid = C, report_id = 20}) end, "path must be a nonempty string")
		rejected(function() af.downloadCandidateReport({candidate_uuid = C, report_id = 18, path = "fit.pdf"}) end, "report_id 18 requires pm_uuid")
		rejected(function() af.downloadCandidateReport({candidate_uuid = C, report_id = 17, pm_uuid = json.decode("null"), path = "fit.pdf"}) end, "report_id 17 requires pm_uuid")
		rejected(function() af.downloadCandidateReport({candidate_uuid = C, report_id = "20", path = "x.pdf"}) end, "report_id must be an integer")
		rejected(function() af.downloadCandidateReport({candidate_uuid = C, report_id = 0, path = "x.pdf"}) end, "report_id must be an integer")
	end,
}
