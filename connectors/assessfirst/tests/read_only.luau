local API = "https://app.assessfirst.com/betty-V2"
return {
	scenario = {publisher = {}, config = {}, auth_method = "token", auth_config = {token = "fixture-private-assessfirst-token"}},
	configure = function()
		calls = 0
		responses = {}
		http = {request = function(req)
			calls += 1
			assert(req.method == "GET" and req.body == nil, "read-only sent " .. req.method)
			assert(req.headers.Authorization == nil and req.headers["AF-Token"] == nil, "connector set credentials")
			assert(req.headers.Accept[1] == "application/json")
			local body = responses[req.url]
			assert(body, "unexpected URL " .. req.url)
			return fixture.operation({statusCode = 200, headers = {["content-type"] = {"application/json"}}, body = fixture.reader(body)})
		end}
	end,
	run = function(af)
		local names = {}
		for name in af do table.insert(names, name) end
		table.sort(names)
		assert(table.concat(names, ",") == "downloadCandidateReport,getCandidate,getCandidateAdequacies,getCandidateCompletion,getCandidateOnePager,"
			.. "getCandidateScores,getCandidateSynthesis,getCandidateTopCareers,getVoiceStatus,listBenchmarks,listCandidateReports,listCandidates,"
			.. "listGroupUsers,listGroups,listLocales,listPredictiveModels,listRecruiters,listWebhooks", "wrong read-only surface: " .. table.concat(names, ","))

		responses[API .. "/locales"] = "[]"
		assert(json.encode(af.listLocales()) == "[]", "empty locale array lost")
		responses[API .. "/locales"] = '[{"name":"language_french","iso_code_639":"fr-FR","flag":"fr"}]'
		assert(af.listLocales()[1].iso_code_639 == "fr-FR")

		local uuid = "ab4699c9169d469c81082accfbe91584"
		responses[API .. "/candidates?email=ana%2Bjob%40example.com&page=2&per_page=50&locale=fr-FR"] =
			'{"data":[{"uuid":"' .. uuid .. '","first_name":"Ana","email":"ana+job@example.com","iframe_candidate_token":"secret-iframe-token"}],"meta":{"total":51,"current_page":2,"per_page":50,"previous_page":1,"next_page":null,"last_page":2}}'
		local page = af.listCandidates({email = "ana+job@example.com", page = 2, per_page = 50, locale = "fr-FR"})
		assert(page.data[1].uuid == uuid and page.meta.last_page == 2 and page.meta.next_page == json.decode("null"))
		assert(page.data[1].iframe_candidate_token == nil, "listed candidate iframe token exposed")
		responses[API .. "/candidates"] = '{"data":[],"meta":{"total":0,"current_page":1,"per_page":50,"previous_page":null,"next_page":1,"last_page":1}}'
		assert(json.encode(af.listCandidates().data) == "[]", "empty candidate array lost")

		responses[API .. "/candidate/" .. uuid] = '{"uuid":"' .. uuid .. '","status":"ENABLED","aplayer_score":16,"iframe_candidate_token":"secret-iframe-token",'
			.. '"candidate_url":"https://my.assessfirst.com/recruiter/profile/' .. uuid .. '/synthesis","assessments":[{"id":8,"name":"Shape","status":"finish"}]}'
		local candidate = af.getCandidate({candidate_uuid = uuid})
		assert(candidate.iframe_candidate_token == nil, "candidate iframe token exposed")
		assert(candidate.aplayer_score == 16 and candidate.assessments[1].status == "finish" and string.find(candidate.candidate_url, uuid, 1, true))

		responses[API .. "/candidate/" .. uuid .. "/scores"] = "[]"
		assert(json.encode(af.getCandidateScores({candidate_uuid = uuid})) == "[]", "empty score array lost")
		responses[API .. "/candidate/" .. uuid .. "/scores"] = '[{"id":1,"label":"lead","name":"Assertive with others","score":3,"min":1,"max":10}]'
		assert(af.getCandidateScores({candidate_uuid = uuid})[1].label == "lead")

		responses[API .. "/webhooks?actions%5B%5D=user.linked&actions%5B%5D=assessment.finished"] = '{"data":[{"uuid":"d21e1601bd6c498aba228e0f54438f7d","url":"https://hooks.example.com/af","actions":["user.linked"]}],"meta":{}}'
		assert(af.listWebhooks({actions = {"user.linked", "assessment.finished"}}).data[1].actions[1] == "user.linked")
		local ok, err = pcall(af.listCandidates, {_method = "DELETE"})
		assert(not ok and string.find(tostring(err), "listCandidates has no option _method", 1, true), tostring(err))
		assert(calls == 8)
	end,
}
