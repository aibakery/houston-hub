return {
	scenario = {publisher = {client_id = "fixture-client", client_secret = "fixture-private-secret"}, config = {}, auth_method = "oauth", auth_config = {}},
	config = {access = "read-write"},
	configure = function()
		requests, responses = {}, {}
		fs = fixture.files()
		http = {request = function(req)
			assert(req.headers == nil or req.headers.Authorization == nil, "the proxy injects Authorization")
			table.insert(requests, req)
			assert(#responses > 0, "unexpected request: " .. req.url)
			local response = table.remove(responses, 1)
			return fixture.operation({statusCode = response.status or 200, headers = response.headers or {}, body = fixture.reader(response.body or "{}")})
		end}
	end,
	run = function(c)
		local function fails(expected: {string}, fn: (...any) -> any, ...: any): number
			local before = #requests
			local ok, err = pcall(fn, ...)
			assert(not ok, "call succeeded")
			for _, text in expected do assert(string.find(tostring(err), text, 1, true), "missing " .. text .. " in " .. tostring(err)) end
			return #requests - before
		end
		local function last(method: string, href: string, project: string?): any
			local req = requests[#requests]
			assert(req.method == method and req.url == href, req.method .. " " .. req.url)
			local sent = req.headers and req.headers["x-goog-user-project"]
			assert((sent and sent[1]) == project, "x-goog-user-project " .. tostring(sent and sent[1]) .. " for " .. href)
			return req
		end
		local P = "my-project-123"
		local RUN = "https://run.googleapis.com/v2/projects/my-project-123/locations/us-central1"
		local COMPUTE = "https://compute.googleapis.com/compute/v1/projects/my-project-123/zones/us-central1-a"
		local BUILD = "https://cloudbuild.googleapis.com/v1/projects/my-project-123/locations/global"

		local names = {}
		for name in c do table.insert(names, name) end
		table.sort(names)
		assert(table.concat(names, ",") == "cancelBuild,cancelRunExecution,deleteObject,downloadObject,getBucket,getBuild,getInstance,getObject,getProject,getProjectBillingInfo,getRunExecution,getRunJob,getRunOperation,getRunRevision,getRunService,getZoneOperation,listAlertPolicies,listBillingAccounts,listBuckets,listBuildTriggers,listBuilds,listDockerImages,listEnabledServices,listInstances,listLogEntries,listLogs,listObjects,listRepositories,listRunExecutions,listRunJobs,listRunLocations,listRunRevisions,listRunServices,listRunTasks,listTimeSeries,listUptimeChecks,queryPrometheus,queryPrometheusRange,resetInstance,retryBuild,runJob,searchProjects,startInstance,stopInstance,updateRunServiceImage,updateRunServiceTraffic,uploadObject",
			"read-write got " .. table.concat(names, ","))

		-- An image update replaces containers whole, so it starts from the unredacted service: the real
		-- environment value goes back to Google and never reaches the caller.
		local service = '{"name":"projects/p/locations/us-central1/services/api","etag":"\\"e1\\"","template":{"containers":[{"name":"app","image":"old","env":[{"name":"DB_PASSWORD","value":"hunter2"}]},{"name":"sidecar","image":"proxy:1"}]}}'
		local operation = '{"name":"projects/my-project-123/locations/us-central1/operations/op-1","metadata":{"template":{"containers":[{"env":[{"name":"DB_PASSWORD","value":"hunter2"}]}]}}}'
		responses = {{body = service}, {body = operation}}
		local result = c.updateRunServiceImage({project = P, location = "us-central1", service = "api", container = "app", image = "us-docker.pkg.dev/p/c/api:v42"})
		assert(requests[1].method == "GET" and requests[1].url == RUN .. "/services/api")
		local req = last("PATCH", RUN .. "/services/api?updateMask=template.containers", P)
		local body = json.decode(req.body)
		assert(body.etag == '"e1"' and #body.template.containers == 2, req.body)
		assert(body.template.containers[1].image == "us-docker.pkg.dev/p/c/api:v42" and body.template.containers[1].env[1].value == "hunter2" and body.template.containers[2].image == "proxy:1", req.body)
		assert(result.name == "projects/my-project-123/locations/us-central1/operations/op-1" and not string.find(json.encode(result), "hunter2", 1, true))
		-- With one container, container may be omitted; with several it is required and must exist.
		responses = {{body = '{"template":{"containers":[{"image":"old"}]}}'}, {body = "{}"}}
		c.updateRunServiceImage({project = P, location = "us-central1", service = "api", image = "new"})
		assert(json.decode(last("PATCH", RUN .. "/services/api?updateMask=template.containers", P).body).template.containers[1].image == "new")
		responses = {{body = '{"template":{"containers":[{"image":"app:1"},{"name":"sidecar","image":"proxy:1"}]}}'}}
		assert(fails({"the service has several containers: pass container"}, c.updateRunServiceImage, {project = P, location = "us-central1", service = "api", image = "new"}) == 1)
		responses = {{body = service}}
		assert(fails({"the service has no container named db"}, c.updateRunServiceImage, {project = P, location = "us-central1", service = "api", container = "db", image = "new"}) == 1)
		assert(fails({"image must be a nonempty string"}, c.updateRunServiceImage, {project = P, location = "us-central1", service = "api"}) == 0)
		assert(fails({"received an unknown option"}, c.updateRunServiceImage, {project = P, location = "us-central1", service = "api", image = "x", updateMask = "*"}) == 0)

		local traffic = {{type = "TRAFFIC_TARGET_ALLOCATION_TYPE_REVISION", revision = "api-00041-abc", percent = 100}}
		responses = {{body = operation}, {body = operation}, {body = "{}"}, {body = '{"done":true,"response":{"template":{"containers":[{"env":[{"name":"K","value":"v-secret"}]}]}}}'}}
		c.updateRunServiceTraffic({project = P, location = "us-central1", service = "api", traffic = traffic})
		req = last("PATCH", RUN .. "/services/api?updateMask=traffic", P)
		assert(json.decode(req.body).traffic[1].revision == "api-00041-abc" and json.decode(req.body).template == nil, req.body)
		c.runJob({project = P, location = "us-central1", job = "export", overrides = {taskCount = 2}})
		assert(json.decode(last("POST", RUN .. "/jobs/export:run", P).body).overrides.taskCount == 2)
		c.cancelRunExecution({project = P, location = "us-central1", job = "export", execution = "export-abc12"})
		assert(last("POST", RUN .. "/jobs/export/executions/export-abc12:cancel", P).body == "{}")
		local polled = c.getRunOperation({name = "projects/my-project-123/locations/us-central1/operations/op-1"})
		last("GET", RUN .. "/operations/op-1", P)
		assert(polled.done == true and polled.response.template.containers[1].env[1].value == "redacted")
		assert(fails({"traffic must be a nonempty array"}, c.updateRunServiceTraffic, {project = P, location = "us-central1", service = "api", traffic = {}}) == 0)
		assert(fails({"name must be projects/<project>/locations/<location>/operations/<id>"}, c.getRunOperation, {name = "operations/op-1"}) == 0)
		assert(fails({"received an unknown option"}, c.runJob, {project = P, location = "us-central1", job = "export", validateOnly = true}) == 0)

		-- Compute writes carry requestId and are billed to the instance's project.
		local zoneOperation = '{"name":"operation-1","status":"RUNNING"}'
		responses = {{body = zoneOperation}, {body = zoneOperation}, {body = zoneOperation}, {body = '{"name":"operation-1","status":"DONE"}'}}
		c.startInstance({project = P, zone = "us-central1-a", instance = "worker-1", requestId = "5f0c6b7e-3d1a-4a9b-8c2d-0e1f2a3b4c5d"})
		assert(last("POST", COMPUTE .. "/instances/worker-1/start?requestId=5f0c6b7e-3d1a-4a9b-8c2d-0e1f2a3b4c5d", nil).body == "")
		c.stopInstance({project = P, zone = "us-central1-a", instance = "worker-1"})
		last("POST", COMPUTE .. "/instances/worker-1/stop", nil)
		c.resetInstance({project = P, zone = "us-central1-a", instance = "worker-1"})
		last("POST", COMPUTE .. "/instances/worker-1/reset", nil)
		assert(c.getZoneOperation({project = P, zone = "us-central1-a", operation = "operation-1"}).status == "DONE")
		last("GET", COMPUTE .. "/operations/operation-1", nil)

		-- Storage writes: uploads stream a session file; names keep their slashes.
		local file = fs.open("report.csv", "w")
		file:write("a,b\n")
		await(file:close())
		responses = {{body = '{"name":"reports/2026-11.csv","generation":"1"}'}, {status = 204, body = ""}}
		assert(c.uploadObject({bucket = "assets", name = "reports/2026-11.csv", path = "report.csv", contentType = "text/csv", ifGenerationMatch = "0"}).generation == "1")
		req = last("POST", "https://storage.googleapis.com/upload/storage/v1/b/assets/o?uploadType=media&name=reports%2F2026-11.csv&ifGenerationMatch=0", nil)
		assert(req.headers["Content-Type"][1] == "text/csv")
		assert(c.deleteObject({bucket = "assets", object = "reports/2026-10.csv", generation = "7"}).success == true)
		last("DELETE", "https://storage.googleapis.com/storage/v1/b/assets/o/reports%2F2026-10.csv?generation=7", nil)
		responses = {{status = 412, body = '{"error":{"code":412,"message":"At least one of the pre-conditions you specified did not hold.","errors":[{"reason":"conditionNotMet"}]}}'}}
		assert(fails({"Google HTTP 412: At least one of the pre-conditions you specified did not hold. [conditionNotMet]", '"retryable":false'},
			c.uploadObject, {bucket = "assets", name = "reports/2026-11.csv", path = "report.csv", ifGenerationMatch = "0"}) == 1)
		assert(requests[#requests].headers["Content-Type"][1] == "application/octet-stream")
		assert(fails({"uploadObject received an unknown option"}, c.uploadObject, {bucket = "assets", name = "a", path = "report.csv", predefinedAcl = "publicRead"}) == 0)

		-- Cloud Build defaults to the global location and redacts substitutions and step env.
		local build = '{"id":"b-1","status":"FAILURE","substitutions":{"_DB_PASSWORD":"s3cret"},"steps":[{"name":"gcr.io/cloud-builders/docker","env":["TOKEN=abc","MODE=prod"]}]}'
		responses = {{body = '{"builds":[' .. build .. ']}'}, {body = build}, {body = '{"triggers":[{"id":"t-1","substitutions":{"_KEY":"k"}}]}'}, {body = '{"name":"operations/build/p/b-2","metadata":{"build":' .. build .. '}}'}, {body = build},
			{body = '{"builds":[]}'}}
		local builds = c.listBuilds({project = P, filter = 'status="FAILURE"', pageSize = 10})
		last("GET", BUILD .. "/builds?filter=status%3D%22FAILURE%22&pageSize=10", P)
		assert(builds.builds[1].substitutions._DB_PASSWORD == "redacted" and builds.builds[1].steps[1].env[1] == "TOKEN=redacted" and builds.builds[1].steps[1].env[2] == "MODE=redacted")
		assert(not string.find(json.encode(c.getBuild({project = P, build = "b-1"})), "s3cret", 1, true))
		last("GET", BUILD .. "/builds/b-1", P)
		assert(c.listBuildTriggers({project = P}).triggers[1].substitutions._KEY == "redacted")
		last("GET", BUILD .. "/triggers", P)
		assert(c.retryBuild({project = P, build = "b-1"}).metadata.build.substitutions._DB_PASSWORD == "redacted")
		assert(last("POST", BUILD .. "/builds/b-1:retry", P).body == "{}")
		assert(c.cancelBuild({project = P, build = "b-1"}).steps[1].env[1] == "TOKEN=redacted")
		last("POST", BUILD .. "/builds/b-1:cancel", P)
		assert(json.encode(c.listBuilds({project = P, location = "us-central1"}).builds) == "[]")
		last("GET", "https://cloudbuild.googleapis.com/v1/projects/my-project-123/locations/us-central1/builds", P)
	end,
}
