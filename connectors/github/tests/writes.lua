return {
	scenario = {publisher = {}, config = {access = "read-write"}, auth_method = "token", auth_config = {token = "fixture-token"}},
	configure = function()
		requests = {}
		payload = "{}"
		status = 200
		http = {request = function(req)
			table.insert(requests, req)
			return fixture.operation({statusCode = status, headers = {}, body = fixture.reader(payload)})
		end}
	end,
	run = function(github)
		local API = "https://api.github.com"
		local NULL = json.decode("null")
		local function last() return requests[#requests] end
		local function same(a, b)
			if type(a) ~= "table" or type(b) ~= "table" then return a == b end
			for key, value in a do if not same(value, b[key]) then return false end end
			for key in b do if a[key] == nil then return false end end
			return true
		end
		local function sent(method, url, body)
			local req = last()
			assert(req.method == method and req.url == url, req.method .. " " .. req.url)
			assert(req.headers.Authorization == nil and req.headers["X-GitHub-Api-Version"][1] == "2026-03-10")
			if body == nil then
				assert(req.body == nil and req.headers["Content-Type"] == nil, "unexpected body " .. tostring(req.body))
			else
				assert(req.headers["Content-Type"][1] == "application/json")
				assert(same(json.decode(req.body), json.decode(body)), req.body)
			end
		end
		local function rejected(fn, expected)
			local before = #requests
			local ok, err = pcall(fn)
			assert(not ok and string.find(tostring(err), expected, 1, true), "wrong validation error: " .. tostring(err))
			assert(#requests == before, "invalid input reached GitHub")
		end

		local names = {}
		for name in github do if name ~= "help" then table.insert(names, name) end end
		assert(#names == 144, "wrong read-write surface: " .. #names)

		payload = '{"number":12,"title":"Crash","labels":[{"name":"bug"}]}'
		local issue = github.createIssue({owner = "o", repo = "r", title = "Crash", body = "Steps", labels = {"bug"}})
		sent("POST", API .. "/repos/o/r/issues", '{"title":"Crash","body":"Steps","labels":["bug"]}')
		assert(issue.number == 12 and issue.labels[1].name == "bug")

		github.updateIssue({owner = "o", repo = "r", issue_number = 12, state = "closed", milestone = NULL})
		sent("PATCH", API .. "/repos/o/r/issues/12", '{"state":"closed","milestone":null}')
		assert(string.find(last().body, '"milestone":null', 1, true))

		payload = "[]"
		github.setLabels({owner = "o", repo = "r", issue_number = 12, labels = json.decode("[]")})
		sent("PUT", API .. "/repos/o/r/issues/12/labels", '{"labels":[]}')
		assert(string.find(last().body, '"labels":[]', 1, true))
		github.removeLabel({owner = "o", repo = "r", issue_number = 12, name = "good first issue"})
		sent("DELETE", API .. "/repos/o/r/issues/12/labels/good%20first%20issue")
		github.updateLabel({owner = "o", repo = "r", name = "area/ui", color = "ff0000"})
		sent("PATCH", API .. "/repos/o/r/labels/area%2Fui", '{"color":"ff0000"}')

		payload = '{"number":12,"assignees":[]}'
		github.removeAssignees({owner = "o", repo = "r", issue_number = 12, assignees = {"hubot"}})
		sent("DELETE", API .. "/repos/o/r/issues/12/assignees", '{"assignees":["hubot"]}')

		payload = '{"content":{"path":"docs/a.md","sha":"new"},"commit":{"sha":"c1"}}'
		local commit = github.putFile({owner = "o", repo = "r", path = "docs/a.md", message = "Update", content = "aGk=", sha = "old", branch = "feature/x"})
		sent("PUT", API .. "/repos/o/r/contents/docs%2Fa.md", '{"message":"Update","content":"aGk=","sha":"old","branch":"feature/x"}')
		assert(commit.commit.sha == "c1")
		github.deleteFile({owner = "o", repo = "r", path = "docs/a.md", message = "Remove", sha = "new"})
		sent("DELETE", API .. "/repos/o/r/contents/docs%2Fa.md", '{"message":"Remove","sha":"new"}')

		payload = '{"ref":"refs/heads/feature/x","object":{"sha":"c2"}}'
		github.createRef({owner = "o", repo = "r", ref = "refs/heads/feature/x", sha = "c2"})
		sent("POST", API .. "/repos/o/r/git/refs", '{"ref":"refs/heads/feature/x","sha":"c2"}')
		github.updateRef({owner = "o", repo = "r", ref = "heads/feature/x", sha = "c3", force = false})
		sent("PATCH", API .. "/repos/o/r/git/refs/heads%2Ffeature%2Fx", '{"sha":"c3","force":false}')
		github.renameBranch({owner = "o", repo = "r", branch = "old/name", new_name = "new/name"})
		sent("POST", API .. "/repos/o/r/branches/old%2Fname/rename", '{"new_name":"new/name"}')

		payload = '{"merged":true,"sha":"m1"}'
		assert(github.mergePull({owner = "o", repo = "r", pull_number = 5, merge_method = "squash", sha = "h1"}).merged == true)
		sent("PUT", API .. "/repos/o/r/pulls/5/merge", '{"merge_method":"squash","sha":"h1"}')
		payload = '{"id":9,"state":"APPROVED"}'
		github.createPullReview({owner = "o", repo = "r", pull_number = 5, event = "APPROVE", comments = {{path = "a.go", line = 3, body = "Nice"}}})
		sent("POST", API .. "/repos/o/r/pulls/5/reviews", '{"event":"APPROVE","comments":[{"path":"a.go","line":3,"body":"Nice"}]}')

		status, payload = 202, "{}"
		github.cancelWorkflowRun({owner = "o", repo = "r", run_id = 30433642})
		sent("POST", API .. "/repos/o/r/actions/runs/30433642/cancel", "{}")
		status, payload = 200, '{"workflow_run_id":1,"run_url":"https://api.github.com/repos/o/r/actions/runs/1"}'
		local run = github.dispatchWorkflow({owner = "o", repo = "r", workflow_id = "deploy.yml", ref = "main", inputs = {env = "staging"}})
		sent("POST", API .. "/repos/o/r/actions/workflows/deploy.yml/dispatches", '{"ref":"main","inputs":{"env":"staging"}}')
		assert(run.workflow_run_id == 1)
		status, payload = 204, ""
		assert(github.deleteIssueComment({owner = "o", repo = "r", comment_id = 77}).success == true)
		sent("DELETE", API .. "/repos/o/r/issues/comments/77")
		assert(github.markThreadDone({thread_id = 1}).success == true)
		sent("DELETE", API .. "/notifications/threads/1")
		status, payload = 205, ""
		assert(github.markThreadRead({thread_id = "1"}).success == true)
		sent("PATCH", API .. "/notifications/threads/1", "{}")

		payload = '{"id":3,"files":{"a.md":{"content":"x"}}}'
		github.updateGist({gist_id = "aa5a315d61ae9438b18d", files = {["old.md"] = NULL, ["a.md"] = {content = "x"}}})
		sent("PATCH", API .. "/gists/aa5a315d61ae9438b18d", '{"files":{"old.md":null,"a.md":{"content":"x"}}}')

		rejected(function() github.createIssue({owner = "o", repo = "r", body = "no title"}) end, "title is required")
		rejected(function() github.putFile({owner = "o", repo = "r", path = "a.md", message = "m"}) end, "content is required")
		rejected(function() github.deleteFile({owner = "o", repo = "r", path = "a.md", message = "m"}) end, "sha is required")
		rejected(function() github.updateRef({owner = "o", repo = "r", ref = "heads/../main", sha = "c"}) end, "ref must not contain empty, . or .. segments")
		rejected(function() github.mergeBranch({owner = "o", repo = "r", base = "main"}) end, "head is required")
		rejected(function() github.createPullReviewComment({owner = "o", repo = "r", pull_number = 5, body = "x", path = "a.go"}) end, "commit_id is required")
		payload = '{"number":5}'
		github.removeRequestedReviewers({owner = "o", repo = "r", pull_number = 5, reviewers = {"hubot"}})
		sent("DELETE", API .. "/repos/o/r/pulls/5/requested_reviewers", '{"reviewers":["hubot"]}')
		rejected(function() github.deleteIssueComment({owner = "o", repo = "r", comment_id = 1, body = "x"}) end, "deleteIssueComment has no option body")
	end,
}
