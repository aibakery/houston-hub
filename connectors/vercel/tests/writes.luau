return {
	scenario = {publisher = {}, config = {access = "read-write", team = "team_Fixture1"}, auth_method = "token", auth_config = {token = "fixture-token"}},
	configure = function()
		requests = {}
		status = 200
		payload = "{}"
		http = {request = function(req)
			table.insert(requests, req)
			return fixture.operation({statusCode = status, headers = {}, body = fixture.reader(payload)})
		end}
	end,
	run = function(vercel)
		local API = "https://api.vercel.com"
		local TEAM = "teamId=team_Fixture1"
		local function last() return requests[#requests] end
		local function sent() return json.decode(last().body) end
		local function rejected(fn, expected)
			local before = #requests
			local ok, err = pcall(fn)
			assert(not ok and string.find(tostring(err), expected, 1, true), "wrong validation error: " .. tostring(err))
			assert(#requests == before, "invalid input reached Vercel")
		end

		local names = {}
		for name in vercel do table.insert(names, name) end
		table.sort(names)
		assert(table.concat(names, ",") == "cancelDeployment,createEnvVar,deleteEnvVar,getDeployment,getDomain,getDomainConfig,getEnvVar,getProject,getProjectDomain,getUser,listBuildLogs,listDeployments,listDomains,listEnvVars,listProjectDomains,listProjects,listPromoteAliases,listRuntimeLogs,listTeams,promoteDeployment,redeploy,rollbackDeployment,updateEnvVar",
			"wrong read-write surface: " .. table.concat(names, ","))

		-- The connection's team goes with every request except the user and team lists.
		vercel.getUser()
		assert(last().url == API .. "/v2/user")
		vercel.listTeams()
		assert(last().url == API .. "/v2/teams")
		vercel.listDeployments({projectId = "web"})
		assert(last().url == API .. "/v7/deployments?projectId=web&" .. TEAM, last().url)
		vercel.listBuildLogs({idOrUrl = "dpl_1"})
		assert(last().url == API .. "/v3/deployments/dpl_1/events?follow=0&" .. TEAM, last().url)

		payload = '{"id":"dpl_2","readyState":"QUEUED","target":"production"}'
		local deployment = vercel.redeploy({name = "web", deploymentId = "dpl_1", target = "production", forceNew = 1})
		assert(last().method == "POST" and last().url == API .. "/v13/deployments?forceNew=1&" .. TEAM, last().url)
		assert(last().headers["Content-Type"][1] == "application/json" and last().headers.Authorization == nil)
		local body = sent()
		assert(body.name == "web" and body.deploymentId == "dpl_1" and body.target == "production" and body.forceNew == nil)
		assert(deployment.id == "dpl_2")

		payload = ""
		status = 201
		assert(vercel.promoteDeployment({projectId = "prj_1", deploymentId = "dpl_2"}).success == true)
		assert(last().method == "POST" and last().url == API .. "/v10/projects/prj_1/promote/dpl_2?" .. TEAM and last().body == nil)
		vercel.rollbackDeployment({projectId = "prj_1", deploymentId = "dpl_1", description = "Bad release"})
		assert(last().url == API .. "/v1/projects/prj_1/rollback/dpl_1?description=Bad%20release&" .. TEAM and last().body == nil, last().url)
		status = 200
		payload = '{"id":"dpl_3","readyState":"CANCELED"}'
		assert(vercel.cancelDeployment({id = "dpl_3"}).readyState == "CANCELED")
		assert(last().method == "PATCH" and last().url == API .. "/v12/deployments/dpl_3/cancel?" .. TEAM and last().body == nil)

		payload = '{"envs":[{"id":"e1","key":"API_URL","type":"plain","value":"https://example.com","target":["production"]}]}'
		local envs = vercel.listEnvVars({idOrName = "web", decrypt = "true"})
		assert(last().method == "GET" and last().url == API .. "/v10/projects/web/env?decrypt=true&" .. TEAM, last().url)
		assert(envs.envs[1].value == "https://example.com")
		payload = '{"envs":[]}'
		assert(json.encode(vercel.listEnvVars({idOrName = "web"}).envs) == "[]")
		payload = '{"id":"e1","key":"API_URL","value":"https://example.com","decrypted":true}'
		assert(vercel.getEnvVar({idOrName = "web", id = "e1"}).decrypted == true)
		assert(last().url == API .. "/v1/projects/web/env/e1?" .. TEAM)

		payload = '{"created":{"id":"e2","key":"FLAG"},"failed":[]}'
		local created = vercel.createEnvVar({idOrName = "web", upsert = "true", key = "FLAG", value = "on", type = "plain", target = {"production", "preview"}})
		assert(last().method == "POST" and last().url == API .. "/v10/projects/web/env?upsert=true&" .. TEAM)
		body = sent()
		assert(body.key == "FLAG" and body.value == "on" and json.encode(body.target) == '["production","preview"]' and body.upsert == nil)
		assert(created.created.id == "e2" and json.encode(created.failed) == "[]")
		vercel.updateEnvVar({idOrName = "web", id = "e2", value = "off"})
		assert(last().method == "PATCH" and last().url == API .. "/v9/projects/web/env/e2?" .. TEAM and last().body == '{"value":"off"}')
		payload = ""
		assert(vercel.deleteEnvVar({idOrName = "web", id = "e2"}).success == true)
		assert(last().method == "DELETE" and last().url == API .. "/v9/projects/web/env/e2?" .. TEAM and last().body == nil)
		payload = '[{"id":"e2","key":"FLAG"}]'
		local deleted = vercel.deleteEnvVar({idOrName = "web", id = "e2"})
		assert(deleted[1].id == "e2", "deletions may answer with an array")
		payload, status = "", 202
		assert(vercel.promoteDeployment({projectId = "prj_1", deploymentId = "dpl_3"}).success == true, "a background promotion answers 202")
		status = 200
		assert(#requests == 16)

		rejected(function() vercel.redeploy({name = "web"}) end, "deploymentId is required")
		rejected(function() vercel.redeploy({deploymentId = "dpl_1"}) end, "name is required")
		rejected(function() vercel.redeploy({name = "web", deploymentId = "dpl_1", files = {}}) end, "redeploy has no option files")
		rejected(function() vercel.redeploy({name = "web", deploymentId = "dpl_1", gitSource = {ref = "main"}}) end, "redeploy has no option gitSource")
		rejected(function() vercel.promoteDeployment({projectId = "prj_1", deploymentId = "dpl_1", target = "production"}) end, "promoteDeployment has no option target")
		rejected(function() vercel.deleteEnvVar({idOrName = "web"}) end, "id is required")
	end,
}
