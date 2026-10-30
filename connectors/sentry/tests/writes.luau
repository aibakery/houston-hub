return {
	scenario = {publisher = {}, config = {access = "read-write", region = "de.sentry.io", organization = "acme"}, auth_method = "token", auth_config = {token = "fixture-token"}},
	configure = function()
		requests = {}
		status = 200
		payload = "{}"
		http = {request = function(req)
			table.insert(requests, req)
			return fixture.operation({statusCode = status, headers = {}, body = fixture.reader(payload)})
		end}
	end,
	run = function(sentry)
		local ISSUE = "https://de.sentry.io/api/0/organizations/acme/issues/1001/"
		local NULL = json.decode("null")
		local function last() return requests[#requests] end
		local function sent(method, target, body)
			local req = last()
			assert(req.method == method and req.url == target, req.method .. " " .. req.url)
			assert(req.headers.Authorization == nil and req.headers["Content-Type"][1] == "application/json" and req.headers.Accept[1] == "application/json")
			assert(json.encode(json.decode(req.body)) == json.encode(body), req.body)
		end
		local function rejected(fn, expected)
			local before = #requests
			local ok, err = pcall(fn)
			assert(not ok and string.find(tostring(err), expected, 1, true), "wrong validation error: " .. tostring(err))
			assert(#requests == before, "invalid input reached Sentry")
		end

		local names = {}
		for name in sentry do table.insert(names, name) end
		table.sort(names)
		assert(table.concat(names, ",") == "addIssueComment,getEvent,getIssue,getIssueEvent,getIssueTag,getOrganization,getProject,getRelease,getSessions,listIssueComments,listIssueEvents,listIssues,listMembers,listOrganizations,listProjects,listReleases,listTeams,updateIssue",
			"wrong read-write surface: " .. table.concat(names, ","))

		payload = '{"id":"1001","status":"resolved","statusDetails":{"inNextRelease":true},"assignedTo":null}'
		local issue = sentry.updateIssue({issue_id = "1001", status = "resolved", statusDetails = {inNextRelease = true}})
		sent("PUT", ISSUE, {status = "resolved", statusDetails = {inNextRelease = true}})
		assert(issue.status == "resolved" and issue.assignedTo == NULL)

		payload = '{"id":"1001","status":"ignored","substatus":"archived_until_condition_met"}'
		sentry.updateIssue({issue_id = "1001", status = "ignored", substatus = "archived_until_condition_met", statusDetails = {ignoreCount = 100, ignoreWindow = 60}})
		sent("PUT", ISSUE, {status = "ignored", substatus = "archived_until_condition_met", statusDetails = {ignoreCount = 100, ignoreWindow = 60}})

		payload = '{"id":"1001","assignedTo":{"type":"team","id":"7","name":"backend"}}'
		assert(sentry.updateIssue({issue_id = "1001", assignedTo = "team:7"}).assignedTo.name == "backend")
		sent("PUT", ISSUE, {assignedTo = "team:7"})
		sentry.updateIssue({issue_id = "WEB-1A", assignedTo = ""})
		sent("PUT", "https://de.sentry.io/api/0/organizations/acme/issues/WEB-1A/", {assignedTo = ""})

		status, payload = 201, '{"id":"5","type":"note","data":{"text":"Fixed in #42"},"dateCreated":"2026-10-30T08:00:00Z"}'
		local comment = sentry.addIssueComment({issue_id = "1001", text = "Fixed in #42"})
		sent("POST", ISSUE .. "comments/", {text = "Fixed in #42"})
		assert(comment.id == "5" and comment.data.text == "Fixed in #42")
		assert(#requests == 5)

		-- Publishing, merging and discarding issues are not exposed.
		rejected(function() sentry.updateIssue({issue_id = "1001", isPublic = true}) end, "updateIssue has no option isPublic")
		rejected(function() sentry.updateIssue({issue_id = "1001", discard = true}) end, "updateIssue has no option discard")
		rejected(function() sentry.updateIssue({status = "resolved"}) end, "issue_id is required")
		rejected(function() sentry.addIssueComment({issue_id = "1001"}) end, "text is required")
		rejected(function() sentry.addIssueComment({issue_id = "1001", text = "hi", mentions = {}}) end, "addIssueComment has no option mentions")
	end,
}
