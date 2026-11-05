local API = "https://app.assessfirst.com/betty-V2"
local C = "ab4699c9169d469c81082accfbe91584"
local PM = "1d9c92277e264fe49a4ce330e51e6ac7"
local G = "786a70ccd1454e83bfae271ffa721c0d"
local META = '"meta":{"total":1,"current_page":1,"per_page":50,"previous_page":null,"next_page":1,"last_page":1}}'
return {
	-- Completion status only has no writes, even for a caller granted write access.
	scenario = {publisher = {}, config = {access = "custom"}, auth_method = "token", auth_config = {token = "fixture-private-assessfirst-token"}, caller_access = "read-write"},
	configure = function()
		calls = 0
		payload = "{}"
		http = {request = function(req)
			calls += 1
			request = req
			assert(req.method == "GET" and req.body == nil, "completion only sent " .. req.method)
			assert(req.headers.Authorization == nil and req.headers["AF-Token"] == nil, "connector set credentials")
			return fixture.operation({statusCode = 200, headers = {["content-type"] = {"application/json"}}, body = fixture.reader(payload)})
		end}
	end,
	run = function(af)
		local names = {}
		for name in af do table.insert(names, name) end
		table.sort(names)
		assert(table.concat(names, ",") == "getCandidateCompletion,listCandidates,listGroupUsers,listGroups,listPredictiveModels",
			"wrong completion-only surface: " .. table.concat(names, ","))

		local function get(name, args, url, body)
			payload = body
			local result = af[name](args)
			assert(request.url == url, name .. " requested " .. request.url)
			return result
		end
		-- Following a group: its candidates, then each one's completion against a predictive model.
		local group = get("listGroups", nil, API .. "/groups", '{"data":[{"uuid":"' .. G .. '","label":"Sales 2026","color":"#000000"}],' .. META).data[1]
		local member = get("listGroupUsers", {group_uuid = group.uuid}, API .. "/groups/" .. G .. "/users",
			'{"data":[{"uuid":"' .. C .. '","first_name":"Ana","last_name":"Silva","email":"ana@example.com"}],' .. META).data[1]
		local model = get("listPredictiveModels", {name = "Sales"}, API .. "/predictive-models?name=Sales",
			'{"data":[{"uuid":"' .. PM .. '","name":"Sales","assessments":{"swipe":true,"drive":true,"brain":false,"voice":true}}],' .. META).data[1]
		local completion = get("getCandidateCompletion", {candidate_uuid = member.uuid, pm_uuid = model.uuid}, API .. "/candidate/" .. C .. "/completion?pm_uuid=" .. PM,
			'{"assessments":{"swipe":"finish","drive":"finish","voice":"todo"},"is_completed":true,"scores":[{"label":"lead","score":3}]}')
		assert(member.email == "ana@example.com" and completion.is_completed and completion.assessments.voice == "todo")
		assert(completion.scores == nil, "completion kept a field outside its list")

		local page = get("listCandidates", {email = "ana@example.com"}, API .. "/candidates?email=ana%40example.com",
			'{"data":[{"uuid":"' .. C .. '","first_name":"Ana","email":"ana@example.com","aplayer_score":16,"iframe_candidate_token":"secret-iframe-token"}],"scores":[],' .. META)
		-- Only the listed fields of each record come back, so a result AssessFirst adds later stays out.
		assert(page.data[1].uuid == C and page.data[1].email == "ana@example.com" and page.meta.last_page == 1)
		assert(page.data[1].aplayer_score == nil and page.data[1].iframe_candidate_token == nil and page.scores == nil, "candidate list kept a field outside its list")
		assert(json.encode(get("listCandidates", nil, API .. "/candidates", '{"data":[],' .. META).data) == "[]", "empty candidate array lost")
		assert(calls == 6)
	end,
}
