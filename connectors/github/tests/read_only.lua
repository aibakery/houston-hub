return {
	scenario = {publisher = {}, config = {}, auth_method = "token", auth_config = {token = "fixture-token"}},
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
		local function rejected(fn, expected)
			local before = #requests
			local ok, err = pcall(fn)
			assert(not ok and string.find(tostring(err), expected, 1, true), "wrong validation error: " .. tostring(err))
			assert(#requests == before, "invalid input reached GitHub")
		end

		local names = {}
		for name in github do if name ~= "help" then table.insert(names, name) end end
		assert(#names == 86, "wrong read-only surface: " .. #names)
		for _, name in {"createIssue", "updateIssue", "createIssueComment", "createPull", "mergePull", "putFile", "deleteFile", "createRef",
			"deleteRef", "createRelease", "uploadReleaseAsset", "dispatchWorkflow", "cancelWorkflowRun", "createGist", "markThreadDone", "graphql",
			"generateReleaseNotes", "removeAssignees"} do
			assert(github[name] == nil, "read-only leaked " .. name)
		end
		assert(github.listNotifications ~= nil, "token connections list notifications")
		assert(#requests == 0, "initialization reached GitHub")

		payload = '{"login":"octocat","id":1,"name":null}'
		local me = github.getAuthenticatedUser()
		local req = last()
		assert(req.method == "GET" and req.url == API .. "/user" and req.body == nil)
		assert(req.headers.Accept[1] == "application/vnd.github+json" and req.headers["X-GitHub-Api-Version"][1] == "2026-03-10")
		assert(req.headers["User-Agent"][1] == "Houston" and req.headers.Authorization == nil, "the proxy injects credentials")
		assert(me.login == "octocat" and me.name == NULL)

		payload = '[{"number":7,"title":"Bug","labels":[],"pull_request":{"url":"x"}}]'
		local opts = {owner = "octo-org", repo = "app.js", state = "all", labels = "bug,ui", per_page = 50, page = 2}
		local issues = github.listIssues(opts)
		assert(last().url == API .. "/repos/octo-org/app.js/issues?state=all&labels=bug%2Cui&per_page=50&page=2", last().url)
		assert(opts.owner == "octo-org" and opts.per_page == 50, "caller options were modified")
		assert(#issues == 1 and issues[1].number == 7 and json.encode(issues[1].labels) == "[]")

		payload = "[]"
		local empty = github.listPulls({owner = "o", repo = "r"})
		assert(last().url == API .. "/repos/o/r/pulls" and json.encode(empty) == "[]")

		payload = '{"total_count":1,"incomplete_results":false,"items":[{"number":1}]}'
		local found = github.searchIssues({q = "repo:o/r is:pr is:open review-requested:@me"})
		assert(last().url == API .. "/search/issues?q=repo%3Ao%2Fr%20is%3Apr%20is%3Aopen%20review-requested%3A%40me", last().url)
		assert(found.total_count == 1 and found.items[1].number == 1)
		payload = '{"total_count":0,"incomplete_results":false,"items":[]}'
		assert(json.encode(github.searchCode({q = "fetchUser"}).items) == "[]")

		payload = '{"name":"feature/x"}'
		github.getBranch({owner = "o", repo = "r", branch = "feature/x"})
		assert(last().url == API .. "/repos/o/r/branches/feature%2Fx", last().url)
		github.getContent({owner = "o", repo = "r", path = "src/main file.go", ref = "release/1.0"})
		assert(last().url == API .. "/repos/o/r/contents/src%2Fmain%20file.go?ref=release%2F1.0", last().url)
		github.getRef({owner = "o", repo = "r", ref = "heads/feature/x"})
		assert(last().url == API .. "/repos/o/r/git/ref/heads%2Ffeature%2Fx")
		github.getCombinedStatus({owner = "o", repo = "r", ref = "feature/x"})
		assert(last().url == API .. "/repos/o/r/commits/feature%2Fx/status")
		github.compareCommits({owner = "o", repo = "r", basehead = "main...feature/x"})
		assert(last().url == API .. "/repos/o/r/compare/main...feature%2Fx")
		github.getReleaseByTag({owner = "o", repo = "r", tag = "app/v1.2"})
		assert(last().url == API .. "/repos/o/r/releases/tags/app%2Fv1.2")
		github.getIssue({owner = "o", repo = "r", issue_number = "42"})
		assert(last().url == API .. "/repos/o/r/issues/42")
		github.getWorkflow({owner = "o", repo = "r", workflow_id = "ci.yml"})
		assert(last().url == API .. "/repos/o/r/actions/workflows/ci.yml")
		github.listRunsForWorkflow({owner = "o", repo = "r", workflow_id = 161335, status = "failure"})
		assert(last().url == API .. "/repos/o/r/actions/workflows/161335/runs?status=failure", last().url)
		github.getTree({owner = "o", repo = "r", tree_sha = "main", recursive = true})
		assert(last().url == API .. "/repos/o/r/git/trees/main?recursive=true")
		github.listNotifications({all = true})
		assert(last().url == API .. "/notifications?all=true")

		payload = "diff --git a/x b/x\n+line\n"
		local diff = github.getPull({owner = "o", repo = "r", pull_number = 3, format = "diff"})
		assert(diff == payload and last().headers.Accept[1] == "application/vnd.github.diff")
		assert(last().url == API .. "/repos/o/r/pulls/3")
		github.getCommit({owner = "o", repo = "r", ref = "abc123", format = "patch"})
		assert(last().headers.Accept[1] == "application/vnd.github.patch")

		payload = "<html>oops</html>"
		local ok, err = pcall(function() github.getRepo({owner = "o", repo = "r"}) end)
		assert(not ok and string.find(tostring(err), "invalid JSON", 1, true), tostring(err))

		rejected(function() github.getRepo({owner = "o"}) end, "repo must be a GitHub name or SHA")
		rejected(function() github.getRepo({owner = "o", repo = ".."}) end, "repo must be a GitHub name or SHA")
		rejected(function() github.getRepo({owner = "a/b", repo = "r"}) end, "owner must be a GitHub name or SHA")
		rejected(function() github.getWorkflow({owner = "o", repo = "r", workflow_id = 1.5}) end, "workflow_id must be a GitHub name or SHA")
		rejected(function() github.getIssue({owner = "o", repo = "r", issue_number = 1.5}) end, "issue_number must be a positive integer")
		rejected(function() github.getIssue({owner = "o", repo = "r", issue_number = "1/../2"}) end, "issue_number must be a positive integer")
		rejected(function() github.getIssue({owner = "o", repo = "r", issue_number = 0}) end, "issue_number must be a positive integer")
		rejected(function() github.getContent({owner = "o", repo = "r", path = "../secrets"}) end, "path must not contain empty, . or .. segments")
		rejected(function() github.getContent({owner = "o", repo = "r", path = "a//b"}) end, "path must not contain empty")
		rejected(function() github.getContent({owner = "o", repo = "r", path = "/etc"}) end, "path must not contain empty")
		rejected(function() github.getContent({owner = "o", repo = "r", path = ""}) end, "path must be a nonempty string")
		rejected(function() github.getBranch({owner = "o", repo = "r", branch = "a\nb"}) end, "branch must be a nonempty string without control characters")
		rejected(function() github.searchIssues({}) end, "q is required")
		rejected(function() github.searchIssues({q = NULL}) end, "q is required")
		rejected(function() github.listIssues({owner = "o", repo = "r", stat = "open"}) end, "listIssues has no option stat")
		rejected(function() github.listIssues({owner = "o", repo = "r", labels = {"bug"}}) end, "labels must be a string, boolean or number")
		rejected(function() github.getPull({owner = "o", repo = "r", pull_number = 1, format = "html"}) end, "format must be 'diff' or 'patch'")
		rejected(function() github.getRepo({owner = "o", repo = "r", format = "diff"}) end, "getRepo has no option format")
		rejected(function() github.getRepo("o/r") end, "opts must be an object")
	end,
}
