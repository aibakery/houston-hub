local API = "https://app.assessfirst.com/betty-V2"
local C = "dad17c50ff5d44e7a5b772fe636291a0"
local PM = "ae5d8fe1546e45569a6364455e9f8bbb"
local G = "786a70ccd1454e83bfae271ffa721c0d"
local W = "f4128a0183594722a58f9ccb96e7633d"
return {
	scenario = {publisher = {}, config = {access = "read-write"}, auth_method = "token", auth_config = {token = "fixture-private-assessfirst-token"}},
	configure = function()
		calls = 0
		status = 200
		payload = "{}"
		http = {request = function(req)
			calls += 1
			request = req
			return fixture.operation({statusCode = status, headers = {}, body = fixture.reader(payload)})
		end}
	end,
	run = function(af)
		local names = {}
		for name in af do table.insert(names, name) end
		assert(#names == 27, "wrong read-write surface")

		-- Sends method and URL, and the JSON body exactly when expected.
		local function write(name, args, method, url, body, code, response)
			status, payload = code or 200, response or "{}"
			local result = af[name](args)
			assert(request.method == method and request.url == url, name .. " requested " .. request.method .. " " .. request.url)
			assert(request.headers.Authorization == nil and request.headers["AF-Token"] == nil, "connector set credentials")
			if body then
				assert(request.headers["Content-Type"][1] == "application/json")
				local sent = json.decode(request.body)
				for key, value in body do assert(json.encode(sent[key]) == json.encode(value), name .. " sent " .. key .. "=" .. json.encode(sent[key])) end
				for key in sent do assert(body[key] ~= nil, name .. " sent unexpected " .. key) end
			else
				assert(request.body == nil and request.headers["Content-Type"] == nil, name .. " sent a body")
			end
			return result
		end

		local invited = write("sendInvitation", {email = "ana@example.com", first_name = "Ana", last_name = "Silva", gender = "f",
			recruiter_email = "rh@example.com", message = "Bonjour Ana", predictive_model_uuid = PM, locale = "fr-FR"},
			"POST", API .. "/candidate/send-invitation?locale=fr-FR",
			{email = "ana@example.com", first_name = "Ana", last_name = "Silva", gender = "f", recruiter_email = "rh@example.com", message = "Bonjour Ana", predictive_model_uuid = PM},
			200, '{"uuid":"' .. C .. '","last_invited_at":"2025-05-16T09:15:43.000000Z","status":"invitation_sent"}')
		assert(invited.uuid == C and invited.status == "invitation_sent")
		local again = write("sendInvitation", {email = "ana@example.com", first_name = json.decode("null")}, "POST", API .. "/candidate/send-invitation", {email = "ana@example.com"},
			200, '{"uuid":"' .. C .. '","status":"user_already_invited_24_hours_ago"}')
		assert(again.status == "user_already_invited_24_hours_ago")
		local added = write("createCandidate", {email = "ana@example.com", gender = "n"}, "POST", API .. "/candidate", {email = "ana@example.com", gender = "n"},
			201, '{"uuid":"' .. C .. '","status":"added_to_network"}')
		assert(added.status == "added_to_network")
		write("startVoiceAssessment", {candidate_uuid = C, pm_uuid = PM}, "POST", API .. "/candidate/" .. C .. "/init-voice/" .. PM, nil,
			201, '{"uuid":"33a9d4f816df4718818a28f04f8e23ef","candidate_uuid":"' .. C .. '","predictive_model_uuid":"' .. PM .. '"}')
		local hook = write("createWebhook", {name = "ATS", url = "https://hooks.example.com/af", actions = {"assessment.finished", "user.linked"}},
			"POST", API .. "/webhooks", {name = "ATS", url = "https://hooks.example.com/af", actions = {"assessment.finished", "user.linked"}},
			201, '{"uuid":"' .. W .. '","name":"ATS","actions":["assessment.finished","user.linked"]}')
		assert(hook.uuid == W and hook.actions[2] == "user.linked")
		assert(json.encode(write("deleteWebhook", {webhook_uuid = W}, "DELETE", API .. "/webhooks/" .. W, nil, 200, "{}")) == "{}")
		local group = write("createGroup", {label = "Finalists", color = "#FF0088"}, "POST", API .. "/groups", {label = "Finalists", color = "#FF0088"},
			201, '{"uuid":"' .. G .. '","label":"Finalists","color":"#FF0088","id":38679}')
		assert(group.uuid == G)
		local member = write("addGroupUser", {group_uuid = G, user_uuid = C}, "POST", API .. "/groups/" .. G .. "/user/" .. C, nil, 201,
			'{"user":{"uuid":"' .. C .. '","iframe_candidate_token":"secret-iframe-token","profile_url":"https://app.assessfirst.com/recruiter/profile/' .. C .. '?sso=6db2e7"},"group":{"uuid":"' .. G .. '"}}')
		assert(member.user.uuid == C and member.group.uuid == G)
		assert(member.user.iframe_candidate_token == nil and member.user.profile_url == "https://app.assessfirst.com/recruiter/profile/" .. C, "nested secrets exposed")
		assert(json.encode(write("removeGroupUser", {group_uuid = G, user_uuid = C}, "DELETE", API .. "/groups/" .. G .. "/user/" .. C, nil, 204, "")) == "{}")
		assert(json.encode(write("deleteGroup", {group_uuid = G}, "DELETE", API .. "/groups/" .. G, nil, 204, "")) == "{}")
		assert(json.encode(write("startVoiceAssessment", {candidate_uuid = C, pm_uuid = PM}, "POST", API .. "/candidate/" .. C .. "/init-voice/" .. PM, nil, 204, "")) == "{}")
		assert(calls == 11)

		local function rejected(fn, expected)
			local before = calls
			local ok, err = pcall(fn)
			assert(not ok and string.find(tostring(err), expected, 1, true), "wrong validation error: " .. tostring(err))
			assert(calls == before, "invalid input reached AssessFirst")
		end
		rejected(function() af.sendInvitation({first_name = "Ana"}) end, "email is required")
		rejected(function() af.sendInvitation({email = json.decode("null")}) end, "email is required")
		rejected(function() af.sendInvitation({email = "ana@example.com", gender = "female"}) end, "gender must be 'f', 'n' or 'm'")
		rejected(function() af.sendInvitation({email = "ana@example.com", predictive_model_uuid = "web designer"}) end, "predictive_model_uuid")
		rejected(function() af.sendInvitation({email = "ana@example.com", first_name = 7}) end, "first_name must be a nonempty string")
		rejected(function() af.createCandidate({email = "ana@example.com", message = "Hi"}) end, "createCandidate has no option message")
		rejected(function() af.createWebhook({name = "ATS", url = "https://hooks.example.com/af"}) end, "actions is required")
		rejected(function() af.createWebhook({name = "ATS", url = "https://hooks.example.com/af", actions = {"user.deleted", "user.created"}}) end, "actions must contain only")
		rejected(function() af.createWebhook({name = "ATS", url = "https://hooks.example.com/af", actions = {one = "user.linked"}}) end, "actions must be a nonempty array")
		rejected(function() af.createGroup({color = "#000000"}) end, "label is required")
		-- Laravel reads _method from the query or body; the allow-lists never send it.
		rejected(function() af.sendInvitation({email = "ana@example.com", _method = "DELETE"}) end, "sendInvitation has no option _method")
		rejected(function() af.addGroupUser({group_uuid = G, user_uuid = C, _method = "DELETE"}) end, "addGroupUser has no option _method")
		rejected(function() af.addGroupUser({group_uuid = G}) end, "user_uuid must be an AssessFirst UUID")
		rejected(function() af.deleteGroup({group_uuid = G .. "/user/" .. C}) end, "group_uuid")
		rejected(function() af.deleteWebhook({webhook_uuid = "%2e%2e"}) end, "webhook_uuid")
	end,
}
