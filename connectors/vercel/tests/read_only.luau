return {
	scenario = {publisher = {}, config = {}, auth_method = "token", auth_config = {token = "fixture-token"}},
	configure = function()
		requests = {}
		payload = "{}"
		http = {request = function(req)
			table.insert(requests, req)
			return fixture.operation({statusCode = 200, headers = {}, body = fixture.reader(payload)})
		end}
	end,
	run = function(vercel)
		local API = "https://api.vercel.com"
		local NULL = json.decode("null")
		local function last() return requests[#requests] end
		local function rejected(fn, expected)
			local before = #requests
			local ok, err = pcall(fn)
			assert(not ok and string.find(tostring(err), expected, 1, true), "wrong validation error: " .. tostring(err))
			assert(#requests == before, "invalid input reached Vercel")
		end

		local names = {}
		for name in vercel do table.insert(names, name) end
		table.sort(names)
		assert(table.concat(names, ",") == "getDeployment,getDomain,getDomainConfig,getProject,getProjectDomain,getUser,listBuildLogs,listDeployments,listDomains,listProjectDomains,listProjects,listPromoteAliases,listRuntimeLogs,listTeams",
			"wrong read-only surface: " .. table.concat(names, ","))
		assert(#requests == 0, "initialization reached Vercel")

		payload = '{"user":{"id":"u1","email":"ada@example.com","avatar":null}}'
		local user = vercel.getUser().user
		assert(last().method == "GET" and last().url == API .. "/v2/user" and last().body == nil)
		assert(last().headers.Accept[1] == "application/json" and last().headers.Authorization == nil)
		assert(user.email == "ada@example.com" and user.avatar == NULL)

		-- Projects keep their public fields only: no variables, bypass secrets or deploy hooks.
		local secret = '{"id":"prj_1","name":"web","framework":"nextjs","env":[{"key":"DB_URL","value":"postgres://secret"}],"protectionBypass":{"bypass-secret":{"scope":"automation-bypass"}},'
			.. '"link":{"type":"github","org":"acme","repo":"web","productionBranch":"main","deployHooks":[{"name":"main","url":"https://api.vercel.com/v1/integrations/deploy/prj_1/hook-secret"}],"gitCredentialId":"cred"},'
			.. '"latestDeployments":[{"id":"dpl_1","readyState":"READY","meta":{"deployHookId":"hook-secret"}}],"targets":{"production":{"id":"dpl_1","meta":{"deployHookId":"hook-secret","branch":"main"}}},"crons":null,"passwordProtection":{"deploymentType":"all"}}'
		payload = secret
		local found = vercel.getProject({idOrName = "web"})
		assert(last().url == API .. "/v9/projects/web")
		assert(found.id == "prj_1" and found.framework == "nextjs" and found.latestDeployments[1].id == "dpl_1" and found.crons == NULL)
		assert(found.link.repo == "web" and found.link.productionBranch == "main")
		assert(found.targets.production.meta.branch == "main" and found.latestDeployments[1].readyState == "READY")
		local encoded = json.encode(found)
		for _, leaked in {"secret", "DB_URL", "bypass", "hook", "cred", "passwordProtection"} do
			assert(not string.find(encoded, leaked, 1, true), "project leaked " .. leaked .. ": " .. encoded)
		end

		payload = '{"projects":[' .. secret .. '],"pagination":{"count":1,"next":"MZXW6","prev":null}}'
		local projects = vercel.listProjects({search = "web", limit = 10, from = "NBSWY"})
		assert(last().url == API .. "/v10/projects?search=web&limit=10&from=NBSWY", last().url)
		assert(projects.pagination.next == "MZXW6" and projects.projects[1].name == "web")
		assert(not string.find(json.encode(projects), "secret", 1, true), "project list leaked a secret")
		payload = "[" .. secret .. "]"
		projects = vercel.listProjects()
		assert(projects.projects[1].id == "prj_1" and not string.find(json.encode(projects), "secret", 1, true))
		payload = '{"projects":[],"pagination":{"count":0,"next":null,"prev":null}}'
		assert(json.encode(vercel.listProjects().projects) == "[]")

		payload = '{"deployments":[{"uid":"dpl_1","state":"READY","meta":{}}],"pagination":{"count":1,"next":1793143768000,"prev":null}}'
		local opts = {projectId = "web", target = "production", state = {"READY", "ERROR"}, limit = 20, ["until"] = 1793143768999}
		local page = vercel.listDeployments(opts)
		assert(last().url == API .. "/v7/deployments?projectId=web&target=production&state=READY,ERROR&limit=20&until=1793143768999", last().url)
		assert(opts.state[2] == "ERROR" and opts.limit == 20, "caller options were modified")
		assert(page.pagination.next == 1793143768000 and page.deployments[1].uid == "dpl_1")

		-- Deploy hook ids complete unauthenticated trigger URLs, so deployments drop them.
		payload = '{"deployments":[{"uid":"dpl_1","meta":{"deployHookId":"hook-secret","deployHookName":"main","ciAccessToken":"tok-secret","vercelApiKey":"key-secret","githubCommitRef":"main"}}],"pagination":{"count":1,"next":null,"prev":null}}'
		local hooked = vercel.listDeployments({projectIds = {"prj_1", "prj_2"}})
		assert(last().url == API .. "/v7/deployments?projectIds=prj_1&projectIds=prj_2", last().url)
		assert(hooked.deployments[1].meta.githubCommitRef == "main" and not string.find(json.encode(hooked), "secret", 1, true), json.encode(hooked))
		payload = '{"deployments":[],"pagination":{"count":0,"next":null,"prev":null}}'
		assert(json.encode(vercel.listDeployments().deployments) == "[]")
		payload = '{"id":"dpl_1","readyState":"READY","meta":{"deployHookId":"hook-secret"}}'
		vercel.getDeployment({idOrUrl = "web-abc123.vercel.app", withGitRepoInfo = "true"})
		assert(last().url == API .. "/v13/deployments/web-abc123.vercel.app?withGitRepoInfo=true")
		assert(not string.find(json.encode(vercel.getDeployment({idOrUrl = "dpl_1"})), "hook", 1, true))

		payload = '[{"type":"stdout","created":1,"text":"Building"},{"type":"stderr","created":2,"text":"Warn","level":"warning"}]'
		local events = vercel.listBuildLogs({idOrUrl = "dpl_1", limit = -1, direction = "backward"})
		assert(last().url == API .. "/v3/deployments/dpl_1/events?limit=-1&direction=backward&follow=0", last().url)
		assert(#events == 2 and events[2].level == "warning")
		payload = "[]"
		assert(json.encode(vercel.listBuildLogs({idOrUrl = "dpl_1"})) == "[]")

		payload = '{"level":"info","message":"GET /","timestampInMs":1}\n\n{"level":"error","message":"boom","timestampInMs":2}\n{"level":"info","message":"last"}'
		local logs = vercel.listRuntimeLogs({projectId = "prj_1", deploymentId = "dpl_1"})
		assert(last().url == API .. "/v1/projects/prj_1/deployments/dpl_1/runtime-logs", last().url)
		assert(last().headers.Accept[1] == "application/stream+json")
		-- The stream ended, so its unterminated last line counts too.
		assert(#logs.logs == 3 and logs.logs[2].message == "boom" and logs.ended == true and logs.truncated == false, json.encode(logs))
		logs = vercel.listRuntimeLogs({projectId = "prj_1", deploymentId = "dpl_1", limit = 1})
		assert(#logs.logs == 1 and logs.logs[1].message == "GET /" and logs.ended == false and logs.truncated == true, json.encode(logs))
		payload = '{"message":"a"}\n{"message":"b"}\n'
		logs = vercel.listRuntimeLogs({projectId = "prj_1", deploymentId = "dpl_1", limit = 2})
		assert(#logs.logs == 2 and logs.truncated == false, "a stream that ended at exactly limit lines is complete")
		payload = ""
		logs = vercel.listRuntimeLogs({projectId = "prj_1", deploymentId = "dpl_1"})
		assert(json.encode(logs.logs) == "[]" and logs.ended == true and logs.truncated == false)
		payload = string.rep("x", 300 * 1024)
		local ok, err = pcall(function() vercel.listRuntimeLogs({projectId = "prj_1", deploymentId = "dpl_1"}) end)
		assert(not ok and string.find(tostring(err), "log line over", 1, true), tostring(err))
		payload = '{"level":"info"}\nnot json\n'
		ok, err = pcall(function() vercel.listRuntimeLogs({projectId = "prj_1", deploymentId = "dpl_1"}) end)
		assert(not ok and string.find(tostring(err), "invalid log line", 1, true), tostring(err))

		payload = '{"domains":[],"pagination":{"count":0,"next":null,"prev":null}}'
		assert(json.encode(vercel.listDomains({limit = 50}).domains) == "[]" and last().url == API .. "/v5/domains?limit=50")
		vercel.getDomain({domain = "example.com"})
		assert(last().url == API .. "/v5/domains/example.com")
		vercel.getDomainConfig({domain = "www.example.com", projectIdOrName = "web"})
		assert(last().url == API .. "/v6/domains/www.example.com/config?projectIdOrName=web")
		vercel.listProjectDomains({idOrName = "web", production = "true", verified = false})
		assert(last().url == API .. "/v9/projects/web/domains?production=true&verified=false")
		vercel.getProjectDomain({idOrName = "web", domain = "www.example.com"})
		assert(last().url == API .. "/v9/projects/web/domains/www.example.com")
		vercel.listPromoteAliases({projectId = "prj_1", failedOnly = true})
		assert(last().url == API .. "/v1/projects/prj_1/promote/aliases?failedOnly=true")
		vercel.listTeams({limit = 5})
		assert(last().url == API .. "/v2/teams?limit=5")
		assert(#requests == 25)

		rejected(function() vercel.getProject() end, "idOrName is required")
		rejected(function() vercel.getProject({idOrName = "../v2/user"}) end, "idOrName must be a Vercel ID, name or hostname")
		rejected(function() vercel.getProject({idOrName = "a/b"}) end, "idOrName must be a Vercel ID")
		rejected(function() vercel.getProject({idOrName = 7}) end, "idOrName must be a string")
		rejected(function() vercel.getDeployment({idOrUrl = ".."}) end, "idOrUrl must be a Vercel ID")
		rejected(function() vercel.listRuntimeLogs({projectId = "prj_1"}) end, "deploymentId is required")
		rejected(function() vercel.listRuntimeLogs({projectId = "prj_1", deploymentId = "dpl_1", limit = 1001}) end, "limit must be an integer from 1 to 1000")
		rejected(function() vercel.listRuntimeLogs({projectId = "prj_1", deploymentId = "dpl_1", limit = 0.5}) end, "limit must be an integer")
		rejected(function() vercel.listDeployments({state = json.decode("[]")}) end, "state must not be an empty array")
		rejected(function() vercel.listDeployments({state = {READY = true}}) end, "array, not an object")
		rejected(function() vercel.listDeployments({teamId = "team_other"}) end, "listDeployments has no option teamId")
		rejected(function() vercel.listBuildLogs({idOrUrl = "dpl_1", follow = 1}) end, "listBuildLogs has no option follow")
		rejected(function() vercel.listProjects({decrypt = "true"}) end, "listProjects has no option decrypt")
		rejected(function() vercel.listDeployments("web") end, "opts must be an object")
		rejected(function() vercel.listDeployments({"web"}) end, "named fields")
	end,
}
