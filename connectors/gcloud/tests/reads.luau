return {
	scenario = {publisher = {client_id = "fixture-client", client_secret = "fixture-private-secret"}, config = {}, auth_method = "oauth", auth_config = {}},
	config = {access = "read-only"},
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
		local function fails(expected: {string}, fn: (...any) -> any, ...: any)
			local before = #requests
			local ok, err = pcall(fn, ...)
			assert(not ok, "call succeeded")
			for _, text in expected do assert(string.find(tostring(err), text, 1, true), "missing " .. text .. " in " .. tostring(err)) end
			return #requests - before
		end
		local function last(method: string, href: string, project: string?)
			local req = requests[#requests]
			assert(req.method == method and req.url == href, req.method .. " " .. req.url)
			local sent = req.headers and req.headers["x-goog-user-project"]
			assert((sent and sent[1]) == project, "x-goog-user-project " .. tostring(sent and sent[1]) .. " for " .. href)
			return req
		end
		local P = "my-project-123"
		local RUN = "https://run.googleapis.com/v2/projects/my-project-123/locations/us-central1"

		local names = {}
		for name in c do table.insert(names, name) end
		table.sort(names)
		assert(table.concat(names, ",") == "downloadObject,getBucket,getInstance,getObject,getProject,getProjectBillingInfo,getRunExecution,getRunJob,getRunRevision,getRunService,listAlertPolicies,listBillingAccounts,listBuckets,listDockerImages,listEnabledServices,listInstances,listLogEntries,listLogs,listObjects,listRepositories,listRunExecutions,listRunJobs,listRunLocations,listRunRevisions,listRunServices,listRunTasks,listTimeSeries,listUptimeChecks,queryPrometheus,queryPrometheusRange,searchProjects",
			"read-only got " .. table.concat(names, ","))

		-- Projects: lists always carry their array; quota goes to the named project.
		responses = {{body = '{"projects":[{"projectId":"my-project-123"}],"nextPageToken":"t2"}'}, {body = "{}"}, {body = '{"projectId":"my-project-123"}'}}
		local page = c.searchProjects({query = "state:ACTIVE", pageSize = 10})
		last("GET", "https://cloudresourcemanager.googleapis.com/v3/projects:search?query=state%3AACTIVE&pageSize=10", nil)
		assert(page.projects[1].projectId == P and page.nextPageToken == "t2")
		local empty = c.searchProjects()
		assert(json.encode(empty.projects) == "[]")
		last("GET", "https://cloudresourcemanager.googleapis.com/v3/projects:search", nil)
		assert(c.getProject({project = P}).projectId == P)
		last("GET", "https://cloudresourcemanager.googleapis.com/v3/projects/my-project-123", P)

		-- Cloud Run results never carry environment values, at any depth.
		local service = '{"name":"projects/p/locations/us-central1/services/api","template":{"containers":[{"image":"img","env":[{"name":"DB_PASSWORD","value":"hunter2"},{"name":"API_KEY","valueSource":{"secretKeyRef":{"secret":"api-key","version":"latest"}}}],"startupProbe":{"httpGet":{"path":"/ready","httpHeaders":[{"name":"Authorization","value":"Bearer probe-secret"}]}}}]},"buildConfig":{"environmentVariables":{"NPM_TOKEN":"npm-secret"}}}'
		responses = {{body = '{"locations":[{"locationId":"us-central1"}]}'}, {body = '{"services":[' .. service .. ']}'}, {body = service}}
		assert(c.listRunLocations({project = P}).locations[1].locationId == "us-central1")
		last("GET", "https://run.googleapis.com/v1/projects/my-project-123/locations", P)
		local listed = c.listRunServices({project = P, location = "us-central1", pageSize = 20})
		last("GET", RUN .. "/services?pageSize=20", P)
		local env = listed.services[1].template.containers[1].env
		assert(env[1].name == "DB_PASSWORD" and env[1].value == "redacted" and env[2].valueSource.secretKeyRef.secret == "api-key" and env[2].value == nil)
		local probe = listed.services[1].template.containers[1].startupProbe.httpGet
		assert(probe.path == "/ready" and probe.httpHeaders[1].name == "Authorization" and probe.httpHeaders[1].value == "redacted")
		assert(listed.services[1].buildConfig.environmentVariables.NPM_TOKEN == "redacted")
		assert(not string.find(json.encode(c.getRunService({project = P, location = "us-central1", service = "api"})), "hunter2", 1, true))
		last("GET", RUN .. "/services/api", P)

		local revision = '{"name":"r","containers":[{"env":[{"name":"TOKEN","value":"secret-token"}]}]}'
		responses = {{body = '{"revisions":[' .. revision .. ']}'}, {body = revision}, {body = '{"jobs":[]}'}, {body = '{"template":{"template":{"containers":[{"env":[{"name":"K","value":"job-secret"}]}]}}}'},
			{body = '{}'}, {body = '{"template":{"containers":[{"env":[{"name":"K","value":"exec-secret"}]}]}}'}, {body = '{"tasks":[{"containers":[{"env":[{"name":"K","value":"task-secret"}]}]}]}'}}
		local revisions = c.listRunRevisions({project = P, location = "us-central1", service = "api", pageSize = 5, pageToken = "t"})
		last("GET", RUN .. "/services/api/revisions?pageSize=5&pageToken=t", P)
		assert(revisions.revisions[1].containers[1].env[1].value == "redacted")
		local one = c.getRunRevision({project = P, location = "us-central1", service = "api", revision = "api-00042-xyz"})
		last("GET", RUN .. "/services/api/revisions/api-00042-xyz", P)
		assert(one.containers[1].env[1].value == "redacted")
		assert(json.encode(c.listRunJobs({project = P, location = "us-central1", showDeleted = true}).jobs) == "[]")
		last("GET", RUN .. "/jobs?showDeleted=true", P)
		assert(c.getRunJob({project = P, location = "us-central1", job = "export"}).template.template.containers[1].env[1].value == "redacted")
		last("GET", RUN .. "/jobs/export", P)
		assert(json.encode(c.listRunExecutions({project = P, location = "us-central1", job = "export"}).executions) == "[]")
		last("GET", RUN .. "/jobs/export/executions", P)
		assert(c.getRunExecution({project = P, location = "us-central1", job = "export", execution = "export-abc12"}).template.containers[1].env[1].value == "redacted")
		last("GET", RUN .. "/jobs/export/executions/export-abc12", P)
		assert(c.listRunTasks({project = P, location = "us-central1", job = "export", execution = "export-abc12"}).tasks[1].containers[1].env[1].value == "redacted")
		last("GET", RUN .. "/jobs/export/executions/export-abc12/tasks", P)

		-- Logging needs a bounded time window and charges the named project.
		responses = {{body = '{"entries":[{"textPayload":"boom"}],"nextPageToken":"n"}'}, {body = "{}"}, {body = '{"logNames":["projects/p/logs/syslog"]}'}}
		local filter = 'timestamp>="2026-11-07T00:00:00Z" AND severity>=ERROR'
		local entries = c.listLogEntries({project = P, filter = filter, orderBy = "timestamp desc"})
		local req = last("POST", "https://logging.googleapis.com/v2/entries:list", P)
		assert(req.headers["Content-Type"][1] == "application/json")
		local body = json.decode(req.body)
		assert(body.resourceNames[1] == "projects/my-project-123" and body.filter == filter and body.orderBy == "timestamp desc" and body.pageSize == 50 and body.pageToken == nil, req.body)
		assert(entries.entries[1].textPayload == "boom")
		assert(json.encode(c.listLogEntries({resourceNames = {"folders/42", "projects/other-project"}, filter = filter, pageSize = 1000, pageToken = "n"}).entries) == "[]")
		body = json.decode(last("POST", "https://logging.googleapis.com/v2/entries:list", "other-project").body)
		assert(#body.resourceNames == 2 and body.pageSize == 1000 and body.pageToken == "n")
		assert(c.listLogs({project = P}).logNames[1] == "projects/p/logs/syslog")
		last("GET", "https://logging.googleapis.com/v2/projects/my-project-123/logs", P)

		-- Storage is billed to the bucket's project: no quota header; object names keep their slashes.
		responses = {{body = '{"items":[{"name":"assets"}]}'}, {body = '{"name":"assets"}'}, {body = '{"prefixes":["reports/"]}'}, {body = '{"name":"reports/2026-10.csv","size":"5"}'}}
		assert(c.listBuckets({project = P, prefix = "as"}).items[1].name == "assets")
		last("GET", "https://storage.googleapis.com/storage/v1/b?project=my-project-123&prefix=as", nil)
		assert(c.getBucket({bucket = "assets"}).name == "assets")
		last("GET", "https://storage.googleapis.com/storage/v1/b/assets", nil)
		local objects = c.listObjects({bucket = "assets", prefix = "reports/", delimiter = "/", matchGlob = "**/*.csv", maxResults = 100})
		last("GET", "https://storage.googleapis.com/storage/v1/b/assets/o?prefix=reports%2F&delimiter=%2F&matchGlob=%2A%2A%2F%2A.csv&maxResults=100", nil)
		assert(objects.prefixes[1] == "reports/" and json.encode(objects.items) == "[]")
		assert(c.getObject({bucket = "assets", object = "reports/2026-10.csv", generation = "17"}).size == "5")
		last("GET", "https://storage.googleapis.com/storage/v1/b/assets/o/reports%2F2026-10.csv?generation=17", nil)
		responses = {{body = "a,b\n1,2\n"}}
		local saved = c.downloadObject({bucket = "assets", object = "reports/2026-10.csv", path = "out/report.csv"})
		last("GET", "https://storage.googleapis.com/storage/v1/b/assets/o/reports%2F2026-10.csv?alt=media", nil)
		assert(saved.path == "out/report.csv" and saved.size == 8 and type(saved.url) == "string")
		assert(await(fs.open("out/report.csv", "r"):readAll()) == "a,b\n1,2\n")
		-- A failed download leaves no file behind.
		responses = {{status = 404, body = '{"error":{"code":404,"message":"No such object: assets/missing","errors":[{"reason":"notFound"}]}}'}}
		fails({"Google HTTP 404: No such object: assets/missing [notFound]"}, c.downloadObject, {bucket = "assets", object = "missing", path = "missing.csv"})
		assert(not await(fs.exists("missing.csv")))

		-- Monitoring flattens interval and aggregation into Google's dotted query names.
		responses = {{body = '{"timeSeries":[{"points":[]}]}'}, {body = '{"status":"success","data":{"resultType":"vector","result":[]}}'}, {body = '{"status":"success"}'}, {body = "{}"}, {body = '{"uptimeCheckConfigs":[{"httpCheck":{"headers":{"X-Api-Key":"k-123"},"authInfo":{"username":"probe","password":"p-456"},"requestMethod":"POST","body":"dXNlcj1hJnBhc3M9Yg=="}}]}'}}
		c.listTimeSeries({project = P, filter = 'metric.type="run.googleapis.com/request_count"', interval = {startTime = "2026-11-07T00:00:00Z", endTime = "2026-11-07T06:00:00Z"},
			aggregation = {alignmentPeriod = "300s", perSeriesAligner = "ALIGN_RATE", crossSeriesReducer = "REDUCE_SUM", groupByFields = {"resource.labels.service_name", "metric.labels.response_code_class"}}, view = "FULL"})
		last("GET", "https://monitoring.googleapis.com/v3/projects/my-project-123/timeSeries?filter=metric.type%3D%22run.googleapis.com%2Frequest_count%22&interval.startTime=2026-11-07T00%3A00%3A00Z&interval.endTime=2026-11-07T06%3A00%3A00Z&aggregation.alignmentPeriod=300s&aggregation.perSeriesAligner=ALIGN_RATE&aggregation.crossSeriesReducer=REDUCE_SUM&aggregation.groupByFields=resource.labels.service_name&aggregation.groupByFields=metric.labels.response_code_class&view=FULL", P)
		assert(c.queryPrometheus({project = P, query = "up"}).data.resultType == "vector")
		req = last("POST", "https://monitoring.googleapis.com/v1/projects/my-project-123/location/global/prometheus/api/v1/query", P)
		assert(req.body == '{"query":"up"}', req.body)
		c.queryPrometheusRange({project = P, query = "up", start = "2026-11-07T00:00:00Z", ["end"] = "2026-11-07T06:00:00Z", step = "300s"})
		body = json.decode(last("POST", "https://monitoring.googleapis.com/v1/projects/my-project-123/location/global/prometheus/api/v1/query_range", P).body)
		assert(body.query == "up" and body.start == "2026-11-07T00:00:00Z" and body["end"] == "2026-11-07T06:00:00Z" and body.step == "300s")
		assert(json.encode(c.listAlertPolicies({project = P, filter = "enabled=true"}).alertPolicies) == "[]")
		last("GET", "https://monitoring.googleapis.com/v3/projects/my-project-123/alertPolicies?filter=enabled%3Dtrue", P)
		local check = c.listUptimeChecks({project = P}).uptimeCheckConfigs[1].httpCheck
		last("GET", "https://monitoring.googleapis.com/v3/projects/my-project-123/uptimeCheckConfigs", P)
		assert(check.headers["X-Api-Key"] == "redacted" and check.authInfo.username == "probe" and check.authInfo.password == "redacted" and check.body == "redacted" and check.requestMethod == "POST")

		-- Compute is billed to the instance's project; metadata values never leave the connector.
		local instance = '{"name":"worker-1","metadata":{"items":[{"key":"startup-script","value":"export TOKEN=abc"},{"key":"ssh-keys","value":"ana:ssh-ed25519 AAAA"}]}}'
		responses = {{body = '{"items":{"zones/us-central1-a":{"instances":[' .. instance .. ']},"zones/europe-west1-b":{"warning":{"code":"NO_RESULTS_ON_PAGE"}}}}'}, {body = instance}}
		local all = c.listInstances({project = P, filter = "status = RUNNING", maxResults = 50})
		last("GET", "https://compute.googleapis.com/compute/v1/projects/my-project-123/aggregated/instances?filter=status%20%3D%20RUNNING&maxResults=50&returnPartialSuccess=true", nil)
		local items = all.items["zones/us-central1-a"].instances[1].metadata.items
		assert(items[1].key == "startup-script" and items[1].value == "redacted" and items[2].value == "redacted")
		assert(not string.find(json.encode(c.getInstance({project = P, zone = "us-central1-a", instance = "worker-1"})), "TOKEN=abc", 1, true))
		last("GET", "https://compute.googleapis.com/compute/v1/projects/my-project-123/zones/us-central1-a/instances/worker-1", nil)

		-- Billing, APIs and Artifact Registry.
		responses = {{body = '{"billingAccounts":[{"name":"billingAccounts/0X0X0X-0X0X0X-0X0X0X"}]}'}, {body = '{"billingEnabled":true}'}, {body = '{"services":[{"name":"projects/1/services/run.googleapis.com"}]}'}, {body = '{"services":[]}'}, {body = "{}"}, {body = '{"dockerImages":[{"uri":"u"}]}'}}
		assert(c.listBillingAccounts().billingAccounts[1].name == "billingAccounts/0X0X0X-0X0X0X-0X0X0X")
		last("GET", "https://cloudbilling.googleapis.com/v1/billingAccounts", nil)
		assert(c.getProjectBillingInfo({project = P}).billingEnabled == true)
		last("GET", "https://cloudbilling.googleapis.com/v1/projects/my-project-123/billingInfo", P)
		assert(#c.listEnabledServices({project = P, pageSize = 200}).services == 1)
		last("GET", "https://serviceusage.googleapis.com/v1/projects/my-project-123/services?filter=state%3AENABLED&pageSize=200", P)
		c.listEnabledServices({project = P, filter = "state:DISABLED"})
		last("GET", "https://serviceusage.googleapis.com/v1/projects/my-project-123/services?filter=state%3ADISABLED", P)
		assert(json.encode(c.listRepositories({project = P, location = "us"}).repositories) == "[]")
		last("GET", "https://artifactregistry.googleapis.com/v1/projects/my-project-123/locations/us/repositories", P)
		assert(c.listDockerImages({project = P, location = "us-central1", repository = "containers", orderBy = "update_time desc"}).dockerImages[1].uri == "u")
		last("GET", "https://artifactregistry.googleapis.com/v1/projects/my-project-123/locations/us-central1/repositories/containers/dockerImages?orderBy=update_time%20desc", P)

		-- Without serviceusage.services.use on the project, the same call repeats once without the header.
		responses = {
			{status = 403, body = '{"error":{"code":403,"status":"PERMISSION_DENIED","message":"Caller does not have required permission to use project my-project-123.","details":[{"@type":"type.googleapis.com/google.rpc.ErrorInfo","reason":"USER_PROJECT_DENIED"}]}}'},
			{body = '{"projectId":"my-project-123"}'},
		}
		local before = #requests
		assert(c.getProject({project = P}).projectId == P)
		assert(#requests == before + 2 and requests[before + 1].headers["x-goog-user-project"][1] == P)
		last("GET", "https://cloudresourcemanager.googleapis.com/v3/projects/my-project-123", nil)

		-- An older API may put a generic reason in errors[] beside the ErrorInfo detail.
		local denied = '{"error":{"code":403,"message":"Caller does not have required permission to use project other-project.","errors":[{"reason":"forbidden"}],"details":[{"@type":"type.googleapis.com/google.rpc.ErrorInfo","reason":"USER_PROJECT_DENIED"}]}}'
		responses = {{status = 403, body = denied}, {body = "{}"}}
		c.listRepositories({project = "other-project", location = "us"})
		last("GET", "https://artifactregistry.googleapis.com/v1/projects/other-project/locations/us/repositories", nil)
		-- After the retry without the header, a disabled API is Houston's project's: no activation link.
		responses = {{status = 403, body = denied}, {status = 403, body = '{"error":{"code":403,"status":"PERMISSION_DENIED","message":"Cloud Billing API has not been used in project 999 before or it is disabled.","details":[{"@type":"type.googleapis.com/google.rpc.ErrorInfo","reason":"SERVICE_DISABLED","metadata":{"activationUrl":"https://console.developers.google.com/apis/api/cloudbilling.googleapis.com/overview?project=999"}}]}}'}}
		local ok, err = pcall(c.getProjectBillingInfo, {project = "other-project"})
		assert(not ok and string.find(tostring(err), "[SERVICE_DISABLED]", 1, true) and not string.find(tostring(err), "project=999", 1, true), tostring(err))
		-- Logging never falls back: its 60 calls a minute per project are too few to share.
		before = #requests
		responses = {{status = 403, body = denied}}
		assert(fails({"[USER_PROJECT_DENIED]; the account needs the Service Usage Consumer role on the project"}, c.listLogEntries, {project = "other-project", filter = filter}) == 1)
		-- A project ID in resourceNames is always charged, never Houston's shared quota.
		for _, names in {{"organizations/1"}, {"projects/example.com:legacy", "folders/42"}} do
			assert(fails({"resourceNames must include a project ID"}, c.listLogEntries, {resourceNames = names, filter = filter}) == 0)
		end
		-- Audit entries echo whole resources, IAM policies and request headers: they keep only who did
		-- what to which resource, and how it ended. Other payloads keep their content with secret fields
		-- masked, and application logs are returned as written.
		local AUDIT = "type.googleapis.com/google.cloud.audit.AuditLog"
		local caller = {callerIp = "203.0.113.7", callerSuppliedUserAgent = "google-cloud-sdk gcloud/540.0.0"}
		responses = {{body = json.encode({entries = {
			{timestamp = "2026-11-07T01:02:03Z", protoPayload = {["@type"] = AUDIT, serviceName = "run.googleapis.com", methodName = "google.cloud.run.v2.Services.UpdateService",
				resourceName = "projects/my-project-123/locations/us-central1/services/api", resourceLocation = {currentLocations = {"us-central1"}},
				status = {code = 9, message = "Revision is not ready", details = {{["@type"] = "type.googleapis.com/google.rpc.DebugInfo", detail = "DB_PASSWORD=hunter2"}}},
				authenticationInfo = {principalEmail = "ana@example.com", thirdPartyPrincipal = {claims = {token = "hunter2"}}},
				authorizationInfo = {{resource = "namespaces/my-project-123/services/api", permission = "run.services.update", granted = true, resourceAttributes = {annotations = {k = "hunter2"}}}},
				requestMetadata = {callerIp = caller.callerIp, callerSuppliedUserAgent = caller.callerSuppliedUserAgent, requestAttributes = {headers = {authorization = "Bearer hunter2"}}},
				request = {service = {template = {containers = {{env = {{name = "DB_PASSWORD", value = "hunter2"}}}}}}},
				response = {spec = {template = {spec = {containers = {{env = {{name = "DB_PASSWORD", value = "hunter2"}}}}}}}},
				resourceOriginalState = {template = {containers = {{args = {"--password=hunter2"}}}}}, metadata = {k = "hunter2"}}},
			{protoPayload = {["@type"] = AUDIT, serviceName = "k8s.io", methodName = "io.k8s.apps.v1.deployments.create", resourceName = "apps/v1/namespaces/default/deployments/api",
				request = {metadata = {annotations = {["kubectl.kubernetes.io/last-applied-configuration"] = '{"spec":{"template":{"spec":{"containers":[{"env":[{"name":"DB_PASSWORD","value":"hunter2"}]}]}}}}'}}}}},
			{protoPayload = {["@type"] = AUDIT, serviceName = "cloudresourcemanager.googleapis.com", methodName = "SetIamPolicy", resourceName = "projects/my-project-123",
				response = {bindings = {{role = "roles/owner", members = {"user:ana@example.com"}}}}, serviceData = {policyDelta = {bindingDeltas = {{action = "ADD", role = "roles/owner"}}}}}},
			{protoPayload = {["@type"] = AUDIT, serviceName = "compute.googleapis.com", methodName = "v1.compute.projects.setCommonInstanceMetadata",
				request = {["@type"] = "type.googleapis.com/compute.projects.setCommonInstanceMetadata", items = {{key = "ssh-keys", value = "ana:ssh-ed25519 TOKEN=abc"}}}}},
			{protoPayload = {["@type"] = "type.googleapis.com/google.appengine.logging.v1.RequestLog", line = {{logMessage = "app-logged"}}, env = {DB_PASSWORD = "map-secret"}}},
			{jsonPayload = {env = {{name = "APP", value = "app-logged"}}}},
		}})}}
		local logged = c.listLogEntries({project = P, filter = filter}).entries
		assert(logged[1].timestamp == "2026-11-07T01:02:03Z" and json.encode(logged[1].protoPayload) == json.encode({["@type"] = AUDIT, serviceName = "run.googleapis.com",
			methodName = "google.cloud.run.v2.Services.UpdateService", resourceName = "projects/my-project-123/locations/us-central1/services/api",
			resourceLocation = {currentLocations = {"us-central1"}}, status = {code = 9, message = "Revision is not ready"}, authenticationInfo = {principalEmail = "ana@example.com"},
			authorizationInfo = {{resource = "namespaces/my-project-123/services/api", permission = "run.services.update", granted = true}}, requestMetadata = caller}), json.encode(logged[1]))
		assert(logged[3].protoPayload.methodName == "SetIamPolicy" and logged[3].protoPayload.response == nil and logged[3].protoPayload.serviceData == nil)
		assert(logged[5].protoPayload.line[1].logMessage == "app-logged" and logged[5].protoPayload.env.DB_PASSWORD == "redacted")
		assert(logged[6].jsonPayload.env[1].value == "app-logged")
		local audited = json.encode(logged)
		assert(not string.find(audited, "hunter2", 1, true) and not string.find(audited, "TOKEN=abc", 1, true) and not string.find(audited, "map-secret", 1, true), audited)

		-- Errors keep Google's status, message and reason; a disabled API links to its activation page.
		-- The retry without the header reports a disabled API that the project itself needs.
		local disabled = '{"error":{"code":403,"status":"PERMISSION_DENIED","message":"Cloud Run Admin API has not been used in project 123 before or it is disabled.","details":[{"@type":"type.googleapis.com/google.rpc.ErrorInfo","reason":"SERVICE_DISABLED","metadata":{"activationUrl":"https://console.developers.google.com/apis/api/run.googleapis.com/overview?project=123"}}]}}'
		responses = {{status = 403, body = disabled}, {status = 403, body = disabled}}
		assert(fails({"Google HTTP 403 (PERMISSION_DENIED): Cloud Run Admin API has not been used in project 123 before or it is disabled. [SERVICE_DISABLED]; enable the API at https://console.developers.google.com/apis/api/run.googleapis.com/overview?project=123", '"retryable":false', '"upstream_status":403'},
			c.listRunJobs, {project = P, location = "us-central1"}) == 2)
		last("GET", "https://run.googleapis.com/v2/projects/my-project-123/locations/us-central1/jobs", nil)
		-- Storage and Compute never send the header, so they never repeat.
		responses = {{status = 403, body = disabled}}
		assert(fails({"[SERVICE_DISABLED]"}, c.getInstance, {project = P, zone = "us-central1-a", instance = "worker-1"}) == 1)
		responses = {{status = 429, headers = {["retry-after"] = {"30"}}, body = '{"error":{"code":429,"status":"RESOURCE_EXHAUSTED","message":"Quota exceeded"}}'}}
		fails({"Google HTTP 429 (RESOURCE_EXHAUSTED): Quota exceeded; Retry-After: 30", '"retryable":true'}, c.listLogEntries, {project = P, filter = filter})
		responses = {{status = 403, body = '{"error":{"code":403,"message":"Rate Limit Exceeded","errors":[{"reason":"rateLimitExceeded"}]}}'}}
		fails({"Google HTTP 403: Rate Limit Exceeded [rateLimitExceeded]", '"retryable":true'}, c.getBucket, {bucket = "assets"})
		-- ErrorInfo spells it RATE_LIMIT_EXCEEDED, ahead of errors[].
		responses = {{status = 403, body = '{"error":{"code":403,"message":"Rate Limit Exceeded","errors":[{"reason":"forbidden"}],"details":[{"@type":"type.googleapis.com/google.rpc.ErrorInfo","reason":"RATE_LIMIT_EXCEEDED"}]}}'}}
		fails({"[RATE_LIMIT_EXCEEDED]", '"retryable":true'}, c.getInstance, {project = P, zone = "us-central1-a", instance = "worker-1"})
		-- Error bodies past a few KiB keep their reason and link.
		responses = {{status = 403, body = '{"error":{"code":403,"message":"' .. string.rep("x", 8000) .. '","details":[{"reason":"SERVICE_DISABLED","metadata":{"activationUrl":"https://console.developers.google.com/apis/api/storage.googleapis.com/overview?project=123"}}]}}'}}
		fails({"[SERVICE_DISABLED]; enable the API at https://console.developers.google.com/apis/api/storage.googleapis.com/overview?project=123"}, c.getBucket, {bucket = "assets"})
		responses = {{status = 503, body = "<html>unavailable</html>"}}
		fails({"Google HTTP 503", '"retryable":true'}, c.listLogs, {project = P})
		responses = {{status = 400, body = '{"status":"error","errorType":"bad_data","error":"invalid parameter \\"query\\": 1:1: parse error"}'}}
		fails({"Google HTTP 400 (bad_data): invalid parameter"}, c.queryPrometheus, {project = P, query = "("})
		responses = {{body = "[1]"}}
		fails({"Google returned an invalid JSON object"}, c.getProject, {project = P})

		-- Invalid input never reaches the network.
		for _, case in {
			{{"project must be a project ID"}, c.getProject, {project = "Bad_Project"}},
			{{"project must be a project ID"}, c.getProject, {project = "example.com:project"}},
			{{"project must be a nonempty string"}, c.listRunServices, {location = "us-central1"}},
			{{"location must be a nonempty string"}, c.listRunServices, {project = P}},
			{{"received an unknown option"}, c.getRunService, {project = P, location = "us-central1", service = "api", fields = "*"}},
			{{"received an unknown option"}, c.searchProjects, {["$httpMethod"] = "DELETE"}},
			{{"filter must bound timestamp"}, c.listLogEntries, {project = P, filter = "severity>=ERROR"}},
			{{"takes project or resourceNames, not both"}, c.listLogEntries, {project = P, resourceNames = {"projects/x"}, filter = filter}},
			{{"requires project or resourceNames"}, c.listLogEntries, {filter = filter}},
			{{"pageSize must be an integer from 1 to 1000"}, c.listLogEntries, {project = P, filter = filter, pageSize = 5000}},
			{{"interval.endTime must be a nonempty string"}, c.listTimeSeries, {project = P, filter = "x", interval = {startTime = "2026-11-07T00:00:00Z"}}},
			{{"received an unknown option interval.step"}, c.listTimeSeries, {project = P, filter = "x", interval = {endTime = "2026-11-07T00:00:00Z", step = "1"}}},
			{{"aggregation must be an object"}, c.listTimeSeries, {project = P, filter = "x", interval = {endTime = "t"}, aggregation = {"300s"}}},
			{{"opts must be an object"}, c.getBucket, "assets"},
			{{"path must be a nonempty string"}, c.downloadObject, {bucket = "assets", object = "a"}},
		} do
			assert(fails(case[1], case[2], case[3]) == 0, "invalid input reached the network")
		end
	end,
}
