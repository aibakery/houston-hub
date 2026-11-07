-- Google Cloud REST APIs: Resource Manager v3, Cloud Run v1/v2, Logging v2, Storage v1, Monitoring
-- v1/v3, Compute Engine v1, Cloud Billing v1, Service Usage v1, Artifact Registry v1 and Cloud Build v1.
-- Arguments and results keep Google's native field names.
type Options = {[string]: any}
type Spec = {query: {string}?, body: {string}?, list: string?, defaults: Options?, redact: boolean?}

local PROJECTS = "https://cloudresourcemanager.googleapis.com/v3"
local RUN = "https://run.googleapis.com"
local LOGGING = "https://logging.googleapis.com/v2"
local STORAGE = "https://storage.googleapis.com"
local MONITORING = "https://monitoring.googleapis.com"
local COMPUTE = "https://compute.googleapis.com/compute/v1"
local BILLING = "https://cloudbilling.googleapis.com/v1"
local SERVICES = "https://serviceusage.googleapis.com/v1"
local ARTIFACTS = "https://artifactregistry.googleapis.com/v1"
local BUILD = "https://cloudbuild.googleapis.com/v1"
-- Storage bills, and Compute charges quota to, the resource's own project. The other APIs charge
-- a user's calls to the OAuth client's project unless x-goog-user-project names another.
local RESOURCE_BILLED = {["storage.googleapis.com"] = true, ["compute.googleapis.com"] = true}
local REDACTED = "redacted"
local MAX_UPLOAD = 250 * 1024 * 1024
local NONE: {string} = table.freeze({})

local function text(value: any, field: string): string
	assert(type(value) == "string" and value ~= "", field .. " must be a nonempty string")
	return value
end

local function options(value: any): Options
	if value == nil then return {} end
	assert(type(value) == "table", "opts must be an object")
	for key in value do assert(type(key) == "string", "opts must have named fields") end
	return table.clone(value)
end

local function done(name: string, args: Options)
	local unknown = next(args)
	assert(unknown == nil, name .. " received an unknown option " .. tostring(unknown))
end

-- Project IDs are 6 to 30 lowercase letters, digits and hyphens; numbers name projects too.
local function isProject(id: string): boolean
	return string.match(id, "^%d+$") ~= nil or (#id >= 6 and #id <= 30 and string.match(id, "^[a-z][a-z0-9%-]*[a-z0-9]$") ~= nil)
end

local function projectId(value: any): string
	local id = text(value, "project")
	assert(isProject(id), "project must be a project ID such as my-project-123 or a project number")
	return id
end

-- Moves the named fields from args into a query string; arrays repeat the key.
local function query(args: Options, names: {string}): string
	local parts: {string} = {}
	for _, name in names do
		local value = args[name]
		args[name] = nil
		for key, item in (if type(value) == "table" then value else {value}) do
			assert(type(key) == "number" and (type(item) == "string" or type(item) == "number" or type(item) == "boolean"), name .. " must be a string, number, boolean or an array of them")
			table.insert(parts, url.encode(name) .. "=" .. url.encode(item))
		end
	end
	return if #parts > 0 then "?" .. table.concat(parts, "&") else ""
end

local function hostOf(href: string): string
	return string.match(href, "^https://([^/]+)") or ""
end

-- Builds a URL from route and args. {field} placeholders take URL-encoded path segments: {project}
-- a project ID or number, {object} a Storage object name, slashes included, as the one segment the
-- manifest's opaque object parameter accepts. The named query fields follow. Also returns the
-- project that may be charged the call's quota.
local function target(route: string, args: Options, names: {string}?): (string, string?)
	local host = hostOf(route)
	local project: string? = nil
	local href = (string.gsub(route, "{(%w+)}", function(field: string): string
		local value = if field == "project" then projectId(args.project) else text(args[field], field)
		args[field] = nil
		if field == "project" and not RESOURCE_BILLED[host] then project = value end
		return if field == "object" then url.encode(value) else url.segment(value, field)
	end))
	return href .. query(args, names or NONE), project
end

local function problemOf(response: HttpResponse): any
	local ok, decoded = pcall(json.decode, await(response.body:readPrefix(4096)))
	if not ok or type(decoded) ~= "table" then return {} end
	if type(decoded.error) == "table" then return decoded.error end
	-- Managed Prometheus answers in Prometheus's format: {status='error', errorType, error}.
	if type(decoded.error) == "string" then return {status = decoded.errorType, message = decoded.error} end
	return {}
end

-- Error reasons, most specific first: ErrorInfo details, then the errors[] of older APIs (Storage,
-- Compute), which may name a generic reason such as forbidden alongside them.
local function reasons(problem: any): {any}
	local found = {}
	for _, list in {problem.details, problem.errors} :: {any} do
		if type(list) == "table" then
			for _, item in list do
				if type(item) == "table" and type(item.reason) == "string" then table.insert(found, item) end
			end
		end
	end
	return found
end

local function hasReason(problem: any, reason: string): boolean
	for _, item in reasons(problem) do
		if item.reason == reason then return true end
	end
	return false
end

-- linked=false drops a disabled API's activation link, which then names Houston's own project.
local function failWith(operation: string, response: HttpResponse, problem: any, linked: boolean?): never
	local first = reasons(problem)[1]
	local reason: string? = if first then first.reason else nil
	local message = "Google HTTP " .. tostring(response.statusCode)
	if type(problem.status) == "string" then message ..= " (" .. problem.status .. ")" end
	if type(problem.message) == "string" then message ..= ": " .. string.sub(problem.message, 1, 600) end
	if reason then message ..= " [" .. reason .. "]" end
	if reason == "SERVICE_DISABLED" and linked ~= false and type(first.metadata) == "table" and type(first.metadata.activationUrl) == "string" then
		message ..= "; enable the API at " .. first.metadata.activationUrl
	elseif reason == "USER_PROJECT_DENIED" then
		message ..= "; the account needs the Service Usage Consumer role on the project"
	end
	local retry = response.headers["retry-after"]
	if retry and retry[1] then message ..= "; Retry-After: " .. retry[1] end
	local limited = reason ~= nil and string.find(string.lower(reason), "ratelimitexceeded", 1, true) ~= nil
	return houston.fail({operation = operation, layer = "upstream", upstream_status = response.statusCode,
		retryable = response.statusCode == 429 or response.statusCode >= 500 or limited, message = message})
end

-- API host and project pairs that cannot be charged quota; later calls skip the header.
local unbilled: {[string]: boolean} = {}

-- Sends one request and returns a 2xx response. With project, Google charges the call's quota to
-- that project. An account without serviceusage.services.use there gets USER_PROJECT_DENIED, and a
-- project without the API enabled SERVICE_DISABLED. Unless shared is false, the call then repeats
-- without the header, charging Houston's OAuth client project, whose quota all connections share.
local function send(operation: string, method: string, href: string, body: any?, project: string?, shared: boolean?): HttpResponse
	local host = hostOf(href)
	local key = host .. " " .. (project or "")
	local function attempt(billed: boolean): HttpResponse
		local headers: HttpHeaders = {}
		if body ~= nil then headers["Content-Type"] = {"application/json"} end
		if billed and project then headers["x-goog-user-project"] = {project} end
		return await(http.request({method = method, url = href, headers = headers,
			body = if body ~= nil then json.encode(body) elseif method == "POST" then "" else nil}))
	end
	local billed = project ~= nil and not unbilled[key]
	local response = attempt(billed)
	if response.statusCode >= 200 and response.statusCode < 300 then return response end
	local problem = problemOf(response)
	if billed and shared ~= false and response.statusCode == 403 and (hasReason(problem, "USER_PROJECT_DENIED") or hasReason(problem, "SERVICE_DISABLED")) then
		unbilled[key] = true
		local retried = attempt(false)
		if retried.statusCode >= 200 and retried.statusCode < 300 then return retried end
		local again = problemOf(retried)
		-- A disabled API in the customer's project is the useful error; otherwise it concerns Houston's.
		if hasReason(again, "SERVICE_DISABLED") and hasReason(problem, "SERVICE_DISABLED") then return failWith(operation, response, problem) end
		return failWith(operation, retried, again, false)
	end
	-- Without the header, a client-billed API reports Houston's project as disabled.
	return failWith(operation, response, problem, billed or RESOURCE_BILLED[host] == true)
end

local function decode(operation: string, response: HttpResponse): any
	local raw = await(response.body:readAll())
	if string.match(raw, "^%s*$") then return {success = true} end
	local ok, value = pcall(json.decode, raw)
	if not ok or type(value) ~= "table" or not string.match(raw, "^%s*{") then
		houston.fail({operation = operation, layer = "upstream", upstream_status = response.statusCode,
			retryable = false, message = "Google returned an invalid JSON object"})
	end
	return value
end

-- Replaces secret values in place, at any depth: Cloud Run env and probe httpHeaders {name, value},
-- source-build environmentVariables, Cloud Build env "KEY=VALUE" and substitutions, Compute metadata
-- items, and uptime-check headers, bodies and passwords. Names and secret references (valueSource)
-- stay. Audit log entries echo the same resources, so their protoPayload goes through this too.
local function redact(value: any): any
	if type(value) ~= "table" then return value end
	for key, item in value do
		if type(item) ~= "table" then continue end
		if key == "env" or key == "httpHeaders" then
			for index, entry in item do
				if type(entry) == "table" and entry.value ~= nil then
					entry.value = REDACTED
				elseif type(entry) == "string" then
					item[index] = (string.match(entry, "^[^=]*") or "") .. "=" .. REDACTED
				end
			end
		elseif key == "substitutions" or key == "environmentVariables" or (key == "headers" and item[1] == nil) then
			for name in item do item[name] = REDACTED end
		elseif key == "metadata" and type(item.items) == "table" then
			for _, entry in item.items do
				if type(entry) == "table" and entry.value ~= nil then entry.value = REDACTED end
			end
		else
			if key == "httpCheck" and item.body ~= nil then item.body = REDACTED end
			if key == "authInfo" and item.password ~= nil then item.password = REDACTED end
			redact(item)
		end
	end
	return value
end

-- One request built from args: target() places the path and query fields, body names the JSON body
-- fields. Lists always carry their array, and redact masks secret values before results return.
local function request(name: string, method: string, route: string, input: any, spec: Spec?): any
	local args = options(input)
	local s: Spec = spec or {}
	local defaults: Options = s.defaults or {}
	for key, value in defaults do
		if args[key] == nil then args[key] = value end
	end
	local href, project = target(route, args, s.query)
	local body: Options? = nil
	if s.body then
		local fields: Options = {}
		for _, field in s.body do
			fields[field] = args[field]
			args[field] = nil
		end
		body = if next(fields) == nil then json.decode("{}") else fields
	end
	done(name, args)
	local result = decode(name, send(name, method, href, body, project))
	if s.list and result[s.list] == nil then result[s.list] = json.decode("[]") end
	return if s.redact then redact(result) else result
end

-- Streams fetch()'s response to a session file; the path changes only when the whole body arrived.
local function save(path: string, fetch: () -> HttpResponse): Options
	local output = fs.open(path, "w")
	local ok, err = pcall(function()
		output:write(fetch().body)
		await(output:close())
	end)
	if not ok then
		output:cancel()
		pcall(function() await(output:close()) end)
		error(err, 0)
	end
	return {path = path, url = await(fs.signedGetUrl(path)), size = await(fs.stat(path)).size}
end

local help: {text: string, functions: {[string]: any}, sections: {[string]: string}?} = {
	text = [[Google Cloud for the connected Google account: projects, Cloud Run, Logging, Cloud Storage,
Monitoring, Compute Engine instances, billing metadata, enabled APIs and Artifact Registry images.
Every operation takes one named options object with Google's camelCase fields and returns Google's
JSON unchanged, except that secret values are replaced with 'redacted': Cloud Run and Cloud Build
environment values, probe headers and substitutions, Compute metadata values (startup scripts, ssh
keys) and uptime-check headers, bodies and passwords, also where audit log entries echo them. Names
and Secret Manager references stay; logs that applications write are returned as written. Connector
calls return completed values: use them directly, without await.
project is a project ID (my-project-123) or number; searchProjects finds them. Domain-scoped
projects (example.com:project) are not supported. Google applies the account's own IAM roles on
top of the connection's access level.
Lists return one page: pass nextPageToken back as pageToken, with the same other options, until it
is absent; page tokens expire after about 24 hours. Empty lists are [].
Calls charge API quota to the named project when the API is enabled there and the account may
(serviceusage.services.use, in Editor or Service Usage Consumer), and otherwise to Houston's shared
project. listLogEntries always charges the named project, so it needs that permission.
Errors report the HTTP status, Google's status, message and reason, e.g. 'Google HTTP 403
(PERMISSION_DENIED): ... [IAM_PERMISSION_DENIED]'. [SERVICE_DISABLED] means the API is off in that
project and includes the link to enable it. HTTP 429, 5xx and [rateLimitExceeded] are retryable after
a pause; Logging allows only 60 listLogEntries calls per minute per project. No hidden paging or
retries.]],
	functions = {},
}
local exports: {[string]: any} = {help = help}

-- Schemas and hints shared by several operations.
local ID = {type = "string", minLength = 1}
local PROJECT = {type = "string", minLength = 1, description = "Project ID or number."}
local LOCATION = {type = "string", minLength = 1, description = "Region, such as us-central1."}
local PAGE_SIZE = {type = "integer", minimum = 1}
local PAGE_TOKEN = {type = "string", minLength = 1, description = "nextPageToken from the previous page."}
local FILTER = {type = "string", minLength = 1}
local READ = {readOnlyHint = true, openWorldHint = true}
local WRITE = {readOnlyHint = false, destructiveHint = false, openWorldHint = true}
local DESTRUCTIVE = {readOnlyHint = false, destructiveHint = true, openWorldHint = true}
local PAGED = {"pageSize", "pageToken"}

-- An options object schema with its required names and one complete example.
local function schema(properties: Options, required: {string}, example: Options): Options
	return {type = "object", properties = properties, required = if #required > 0 then required else nil, additionalProperties = false, examples = {example}}
end

-- Projects

help.functions.searchProjects = {
	description = "Projects the account can see: {projects=[{name='projects/123', projectId, displayName, state, parent, labels?, createTime}], nextPageToken?}. query filters, e.g. 'displayName:api*', 'state:ACTIVE' or 'parent:folders/456'; omit it for every active project.",
	inputSchema = schema({query = FILTER, pageSize = PAGE_SIZE, pageToken = PAGE_TOKEN}, NONE, {query = "state:ACTIVE"}),
	annotations = READ,
}
function exports.searchProjects(args: Options?): Options
	return request("searchProjects", "GET", PROJECTS .. "/projects:search", args, {query = {"query", "pageSize", "pageToken"}, list = "projects"})
end

help.functions.getProject = {
	description = "One project: {name, projectId, displayName, state, parent, labels?, createTime, etag}.",
	inputSchema = schema({project = PROJECT}, {"project"}, {project = "my-project-123"}),
	annotations = READ,
}
function exports.getProject(args: Options): Options
	return request("getProject", "GET", PROJECTS .. "/projects/{project}", args)
end

-- Cloud Run

help.functions.listRunLocations = {
	description = "Regions where Cloud Run is available for the project: {locations=[{locationId, name, displayName?}], nextPageToken?}. Cloud Run lists resources per region, so use locationId as location.",
	inputSchema = schema({project = PROJECT, pageSize = PAGE_SIZE, pageToken = PAGE_TOKEN}, {"project"}, {project = "my-project-123"}),
	annotations = READ,
}
function exports.listRunLocations(args: Options): Options
	return request("listRunLocations", "GET", RUN .. "/v1/projects/{project}/locations", args, {query = PAGED, list = "locations"})
end

help.functions.listRunServices = {
	description = "One region's Cloud Run services: {services=[service], nextPageToken?}. A service has name, uri, urls, template={containers=[{image, env, resources, ports}], serviceAccount, scaling}, traffic, trafficStatuses, latestReadyRevision, latestCreatedRevision, conditions, terminalCondition and etag. location cannot be '-': list each region from listRunLocations.",
	inputSchema = schema({project = PROJECT, location = LOCATION, pageSize = PAGE_SIZE, pageToken = PAGE_TOKEN, showDeleted = {type = "boolean"}}, {"project", "location"}, {project = "my-project-123", location = "us-central1"}),
	annotations = READ,
}
function exports.listRunServices(args: Options): Options
	return request("listRunServices", "GET", RUN .. "/v2/projects/{project}/locations/{location}/services", args, {query = {"pageSize", "pageToken", "showDeleted"}, list = "services", redact = true})
end

help.functions.getRunService = {
	description = "One Cloud Run service, as listRunServices returns it. terminalCondition and conditions explain a failed deployment; latestReadyRevision is the revision serving when traffic follows the latest one.",
	inputSchema = schema({project = PROJECT, location = LOCATION, service = ID}, {"project", "location", "service"}, {project = "my-project-123", location = "us-central1", service = "api"}),
	annotations = READ,
}
function exports.getRunService(args: Options): Options
	return request("getRunService", "GET", RUN .. "/v2/projects/{project}/locations/{location}/services/{service}", args, {redact = true})
end

help.functions.listRunRevisions = {
	description = "A Cloud Run service's revisions, newest first: {revisions=[{name, createTime, containers, conditions, scaling, logUri, ...}], nextPageToken?}. conditions show why a revision failed to become ready; logUri opens its logs in the console.",
	inputSchema = schema({project = PROJECT, location = LOCATION, service = ID, pageSize = PAGE_SIZE, pageToken = PAGE_TOKEN, showDeleted = {type = "boolean"}}, {"project", "location", "service"}, {project = "my-project-123", location = "us-central1", service = "api", pageSize = 5}),
	annotations = READ,
}
function exports.listRunRevisions(args: Options): Options
	return request("listRunRevisions", "GET", RUN .. "/v2/projects/{project}/locations/{location}/services/{service}/revisions", args, {query = {"pageSize", "pageToken", "showDeleted"}, list = "revisions", redact = true})
end

help.functions.getRunRevision = {
	description = "One Cloud Run revision; revision is the short name, such as api-00042-xyz.",
	inputSchema = schema({project = PROJECT, location = LOCATION, service = ID, revision = ID}, {"project", "location", "service", "revision"}, {project = "my-project-123", location = "us-central1", service = "api", revision = "api-00042-xyz"}),
	annotations = READ,
}
function exports.getRunRevision(args: Options): Options
	return request("getRunRevision", "GET", RUN .. "/v2/projects/{project}/locations/{location}/services/{service}/revisions/{revision}", args, {redact = true})
end

help.functions.listRunJobs = {
	description = "One region's Cloud Run jobs: {jobs=[{name, template={taskCount, template={containers, maxRetries, timeout}}, latestCreatedExecution, terminalCondition, ...}], nextPageToken?}.",
	inputSchema = schema({project = PROJECT, location = LOCATION, pageSize = PAGE_SIZE, pageToken = PAGE_TOKEN, showDeleted = {type = "boolean"}}, {"project", "location"}, {project = "my-project-123", location = "us-central1"}),
	annotations = READ,
}
function exports.listRunJobs(args: Options): Options
	return request("listRunJobs", "GET", RUN .. "/v2/projects/{project}/locations/{location}/jobs", args, {query = {"pageSize", "pageToken", "showDeleted"}, list = "jobs", redact = true})
end

help.functions.getRunJob = {
	description = "One Cloud Run job, as listRunJobs returns it.",
	inputSchema = schema({project = PROJECT, location = LOCATION, job = ID}, {"project", "location", "job"}, {project = "my-project-123", location = "us-central1", job = "nightly-export"}),
	annotations = READ,
}
function exports.getRunJob(args: Options): Options
	return request("getRunJob", "GET", RUN .. "/v2/projects/{project}/locations/{location}/jobs/{job}", args, {redact = true})
end

help.functions.listRunExecutions = {
	description = "A Cloud Run job's executions, newest first: {executions=[{name, createTime, startTime?, completionTime?, runningCount, succeededCount, failedCount, cancelledCount, conditions, logUri}], nextPageToken?}.",
	inputSchema = schema({project = PROJECT, location = LOCATION, job = ID, pageSize = PAGE_SIZE, pageToken = PAGE_TOKEN, showDeleted = {type = "boolean"}}, {"project", "location", "job"}, {project = "my-project-123", location = "us-central1", job = "nightly-export"}),
	annotations = READ,
}
function exports.listRunExecutions(args: Options): Options
	return request("listRunExecutions", "GET", RUN .. "/v2/projects/{project}/locations/{location}/jobs/{job}/executions", args, {query = {"pageSize", "pageToken", "showDeleted"}, list = "executions", redact = true})
end

help.functions.getRunExecution = {
	description = "One Cloud Run job execution; execution is the short name, such as nightly-export-abc12.",
	inputSchema = schema({project = PROJECT, location = LOCATION, job = ID, execution = ID}, {"project", "location", "job", "execution"}, {project = "my-project-123", location = "us-central1", job = "nightly-export", execution = "nightly-export-abc12"}),
	annotations = READ,
}
function exports.getRunExecution(args: Options): Options
	return request("getRunExecution", "GET", RUN .. "/v2/projects/{project}/locations/{location}/jobs/{job}/executions/{execution}", args, {redact = true})
end

help.functions.listRunTasks = {
	description = "An execution's tasks: {tasks=[{name, index, retried?, lastAttemptResult?={status, exitCode}, conditions, logUri, ...}], nextPageToken?}. lastAttemptResult explains a failed task.",
	inputSchema = schema({project = PROJECT, location = LOCATION, job = ID, execution = ID, pageSize = PAGE_SIZE, pageToken = PAGE_TOKEN, showDeleted = {type = "boolean"}}, {"project", "location", "job", "execution"}, {project = "my-project-123", location = "us-central1", job = "nightly-export", execution = "nightly-export-abc12"}),
	annotations = READ,
}
function exports.listRunTasks(args: Options): Options
	return request("listRunTasks", "GET", RUN .. "/v2/projects/{project}/locations/{location}/jobs/{job}/executions/{execution}/tasks", args, {query = {"pageSize", "pageToken", "showDeleted"}, list = "tasks", redact = true})
end

-- Logging

help.functions.listLogEntries = {
	description = [[Log entries matching a Logging query: {entries=[{logName, resource={type, labels},
timestamp, severity, textPayload? or jsonPayload? or protoPayload?, httpRequest?, labels?, trace?,
insertId}], nextPageToken?}. Pass project (or resourceNames such as {'projects/p', 'folders/1'})
and a filter that bounds timestamp, e.g. 'timestamp>="2026-11-07T00:00:00Z" AND severity>=ERROR AND
resource.type="cloud_run_revision" AND resource.labels.service_name="api"'. Cloud Build logs are
logName="projects/p/logs/cloudbuild" with resource.labels.build_id. orderBy is 'timestamp asc'
(default) or 'timestamp desc'. pageSize defaults to 50 and is at most 1000. Google allows 60 calls
per minute per project, so prefer a narrow filter and bigger pages to many calls.]],
	inputSchema = {
		type = "object",
		properties = {
			project = PROJECT,
			resourceNames = {type = "array", minItems = 1, items = ID},
			filter = {type = "string", minLength = 1, pattern = "timestamp"},
			orderBy = {type = "string", enum = {"timestamp asc", "timestamp desc"}},
			pageSize = {type = "integer", minimum = 1, maximum = 1000, default = 50},
			pageToken = PAGE_TOKEN,
		},
		required = {"filter"},
		oneOf = {{required = {"project"}}, {required = {"resourceNames"}}},
		additionalProperties = false,
		examples = {{project = "my-project-123", filter = 'timestamp>="2026-11-07T00:00:00Z" AND severity>=ERROR', orderBy = "timestamp desc", pageSize = 100}},
	},
	annotations = READ,
}
function exports.listLogEntries(input: any): Options
	local args = options(input)
	local project: string? = nil
	if args.project ~= nil then
		assert(args.resourceNames == nil, "listLogEntries takes project or resourceNames, not both")
		local id = projectId(args.project)
		project = id
		args.resourceNames, args.project = {"projects/" .. id}, nil
	end
	local names = args.resourceNames
	assert(type(names) == "table" and names[1] ~= nil, "listLogEntries requires project or resourceNames")
	for _, resource in names do text(resource, "resourceNames[]") end
	local named = string.match(names[1], "^projects/([^/]+)$")
	if project == nil and named and isProject(named) then project = named end
	assert(string.find(text(args.filter, "filter"), "timestamp", 1, true), 'filter must bound timestamp, e.g. timestamp>="2026-11-07T00:00:00Z"')
	if args.pageSize == nil then args.pageSize = 50 end
	assert(type(args.pageSize) == "number" and args.pageSize >= 1 and args.pageSize <= 1000 and args.pageSize % 1 == 0, "pageSize must be an integer from 1 to 1000")
	local body = {resourceNames = names, filter = args.filter, orderBy = args.orderBy, pageSize = args.pageSize, pageToken = args.pageToken}
	args.resourceNames, args.filter, args.orderBy, args.pageSize, args.pageToken = nil, nil, nil, nil, nil
	done("listLogEntries", args)
	-- Logging allows 60 entries:list calls per minute per quota project, too few to share between connections.
	local result = decode("listLogEntries", send("listLogEntries", "POST", LOGGING .. "/entries:list", body, project, false))
	if result.entries == nil then result.entries = json.decode("[]") end
	for _, entry in result.entries do
		if type(entry) == "table" then redact(entry.protoPayload) end
	end
	return result
end

help.functions.listLogs = {
	description = "Names of the project's logs that have entries: {logNames=['projects/p/logs/run.googleapis.com%2Fstderr', ...], nextPageToken?}. Log IDs are URL-encoded in logNames; filters use them decoded, e.g. logName=\"projects/p/logs/run.googleapis.com/stderr\".",
	inputSchema = schema({project = PROJECT, pageSize = PAGE_SIZE, pageToken = PAGE_TOKEN}, {"project"}, {project = "my-project-123"}),
	annotations = READ,
}
function exports.listLogs(args: Options): Options
	return request("listLogs", "GET", LOGGING .. "/projects/{project}/logs", args, {query = PAGED, list = "logNames"})
end

-- Cloud Storage

help.functions.listBuckets = {
	description = "The project's buckets: {items=[{name, location, storageClass, timeCreated, updated, iamConfiguration, ...}], nextPageToken?}. prefix keeps buckets whose names start with it.",
	inputSchema = schema({project = PROJECT, prefix = ID, maxResults = PAGE_SIZE, pageToken = PAGE_TOKEN}, {"project"}, {project = "my-project-123"}),
	annotations = READ,
}
function exports.listBuckets(args: Options): Options
	local opts = options(args)
	opts.project = projectId(opts.project)
	return request("listBuckets", "GET", STORAGE .. "/storage/v1/b", opts, {query = {"project", "prefix", "maxResults", "pageToken"}, list = "items"})
end

help.functions.getBucket = {
	description = "One bucket's metadata: {name, location, storageClass, versioning?, lifecycle?, iamConfiguration, retentionPolicy?, ...}.",
	inputSchema = schema({bucket = ID}, {"bucket"}, {bucket = "my-project-123-assets"}),
	annotations = READ,
}
function exports.getBucket(args: Options): Options
	return request("getBucket", "GET", STORAGE .. "/storage/v1/b/{bucket}", args)
end

help.functions.listObjects = {
	description = [[One page of a bucket's objects: {items=[{name, size, contentType, updated, generation, md5Hash,
...}], prefixes?=['folder/'], nextPageToken?}. size is a string of bytes. With delimiter='/' the
list stops at folders: prefixes holds the subfolders of prefix. matchGlob filters names, e.g.
'**/*.json'. maxResults is at most 1000.]],
	inputSchema = schema({bucket = ID, prefix = ID, delimiter = ID, matchGlob = ID, startOffset = ID, endOffset = ID, includeTrailingDelimiter = {type = "boolean"}, versions = {type = "boolean"}, maxResults = PAGE_SIZE, pageToken = PAGE_TOKEN}, {"bucket"}, {bucket = "my-project-123-assets", prefix = "reports/", delimiter = "/"}),
	annotations = READ,
}
function exports.listObjects(args: Options): Options
	return request("listObjects", "GET", STORAGE .. "/storage/v1/b/{bucket}/o", args, {query = {"prefix", "delimiter", "matchGlob", "startOffset", "endOffset", "includeTrailingDelimiter", "versions", "maxResults", "pageToken"}, list = "items"})
end

help.functions.getObject = {
	description = "One object's metadata, without its content: {name, bucket, size, contentType, updated, generation, md5Hash, crc32c, metadata?}. object is the full name, slashes included.",
	inputSchema = schema({bucket = ID, object = ID, generation = ID}, {"bucket", "object"}, {bucket = "my-project-123-assets", object = "reports/2026-10.csv"}),
	annotations = READ,
}
function exports.getObject(args: Options): Options
	return request("getObject", "GET", STORAGE .. "/storage/v1/b/{bucket}/o/{object}", args, {query = {"generation"}})
end

help.functions.downloadObject = {
	description = "Saves an object's content to a session file and returns {path, url, size}; url is a signed Houston link. Read the file with fs, never inline it. generation selects an older version of a versioned object.",
	inputSchema = schema({bucket = ID, object = ID, path = ID, generation = ID}, {"bucket", "object", "path"}, {bucket = "my-project-123-assets", object = "reports/2026-10.csv", path = "2026-10.csv"}),
	annotations = READ,
}
function exports.downloadObject(input: any): Options
	local args = options(input)
	local path = text(args.path, "path")
	args.path, args.alt = nil, "media"
	local href = target(STORAGE .. "/storage/v1/b/{bucket}/o/{object}", args, {"alt", "generation"})
	done("downloadObject", args)
	return save(path, function(): HttpResponse return send("downloadObject", "GET", href) end)
end

-- Monitoring

help.functions.listTimeSeries = {
	description = [[Metric data: {timeSeries=[{metric={type, labels}, resource={type, labels}, metricKind, valueType,
points=[{interval={startTime, endTime}, value={doubleValue? or int64Value? or distributionValue?}}]}],
nextPageToken?}. filter names one metric type, e.g. 'metric.type="run.googleapis.com/request_count"
AND resource.labels.service_name="api"'. interval={startTime, endTime} in RFC 3339; endTime is
required. aggregation={alignmentPeriod='300s', perSeriesAligner='ALIGN_RATE', crossSeriesReducer=
'REDUCE_SUM', groupByFields={'metric.labels.response_code_class'}} reduces the data; without it every
raw point returns, so set it for anything longer than an hour. view='HEADERS' omits points.]],
	inputSchema = {
		type = "object",
		properties = {
			project = PROJECT,
			filter = FILTER,
			interval = {type = "object", properties = {startTime = ID, endTime = ID}, required = {"endTime"}, additionalProperties = false},
			aggregation = {["$ref"] = "#/$defs/aggregation"},
			secondaryAggregation = {["$ref"] = "#/$defs/aggregation"},
			orderBy = ID,
			view = {type = "string", enum = {"FULL", "HEADERS"}},
			pageSize = PAGE_SIZE,
			pageToken = PAGE_TOKEN,
		},
		required = {"project", "filter", "interval"},
		additionalProperties = false,
		["$defs"] = {aggregation = {type = "object", properties = {
			alignmentPeriod = ID, perSeriesAligner = ID, crossSeriesReducer = ID, groupByFields = {type = "array", items = ID},
		}, additionalProperties = false}},
		examples = {{project = "my-project-123", filter = 'metric.type="run.googleapis.com/request_count"', interval = {startTime = "2026-11-07T00:00:00Z", endTime = "2026-11-07T06:00:00Z"}, aggregation = {alignmentPeriod = "300s", perSeriesAligner = "ALIGN_RATE", crossSeriesReducer = "REDUCE_SUM", groupByFields = {"resource.labels.service_name"}}}},
	},
	annotations = READ,
}
function exports.listTimeSeries(input: any): Options
	local args = options(input)
	for _, group in {"interval", "aggregation", "secondaryAggregation"} do
		local value = args[group]
		if value ~= nil then
			assert(type(value) == "table" and value[1] == nil, group .. " must be an object")
			for key, item in value do
				assert(type(key) == "string", group .. " must have named fields")
				args[group .. "." .. key] = item
			end
			args[group] = nil
		end
	end
	text(args.filter, "filter")
	text(args["interval.endTime"], "interval.endTime")
	return request("listTimeSeries", "GET", MONITORING .. "/v3/projects/{project}/timeSeries", args, {list = "timeSeries", query = {
		"filter", "interval.startTime", "interval.endTime",
		"aggregation.alignmentPeriod", "aggregation.perSeriesAligner", "aggregation.crossSeriesReducer", "aggregation.groupByFields",
		"secondaryAggregation.alignmentPeriod", "secondaryAggregation.perSeriesAligner", "secondaryAggregation.crossSeriesReducer", "secondaryAggregation.groupByFields",
		"orderBy", "view", "pageSize", "pageToken",
	}})
end

help.functions.queryPrometheus = {
	description = "A PromQL instant query over the project's metrics, in Prometheus's response format: {status, data={resultType, result}}. Google metrics use names such as run_googleapis_com:request_count; time is RFC 3339 or a Unix timestamp and defaults to now.",
	inputSchema = schema({project = PROJECT, query = ID, time = ID, timeout = ID}, {"project", "query"}, {project = "my-project-123", query = "sum(rate(run_googleapis_com:request_count[5m]))"}),
	annotations = READ,
}
function exports.queryPrometheus(args: Options): Options
	return request("queryPrometheus", "POST", MONITORING .. "/v1/projects/{project}/location/global/prometheus/api/v1/query", args, {body = {"query", "time", "timeout"}})
end

help.functions.queryPrometheusRange = {
	description = "A PromQL range query: {status, data={resultType='matrix', result=[{metric, values=[[time, value]]}]}}. start and end are RFC 3339 or Unix timestamps; step is a duration such as '60s'. Keep (end - start) / step under 11,000 points.",
	inputSchema = schema({project = PROJECT, query = ID, start = ID, ["end"] = ID, step = ID, timeout = ID}, {"project", "query", "start", "end", "step"}, {project = "my-project-123", query = "sum by (service_name) (rate(run_googleapis_com:request_count[5m]))", start = "2026-11-07T00:00:00Z", ["end"] = "2026-11-07T06:00:00Z", step = "300s"}),
	annotations = READ,
}
function exports.queryPrometheusRange(args: Options): Options
	return request("queryPrometheusRange", "POST", MONITORING .. "/v1/projects/{project}/location/global/prometheus/api/v1/query_range", args, {body = {"query", "start", "end", "step", "timeout"}})
end

help.functions.listAlertPolicies = {
	description = "The project's alerting policies: {alertPolicies=[{name, displayName, enabled, conditions, notificationChannels, documentation?, severity?}], nextPageToken?}.",
	inputSchema = schema({project = PROJECT, filter = FILTER, orderBy = ID, pageSize = PAGE_SIZE, pageToken = PAGE_TOKEN}, {"project"}, {project = "my-project-123"}),
	annotations = READ,
}
function exports.listAlertPolicies(args: Options): Options
	return request("listAlertPolicies", "GET", MONITORING .. "/v3/projects/{project}/alertPolicies", args, {query = {"filter", "orderBy", "pageSize", "pageToken"}, list = "alertPolicies"})
end

help.functions.listUptimeChecks = {
	description = "The project's uptime checks: {uptimeCheckConfigs=[{name, displayName, monitoredResource?, httpCheck?, tcpCheck?, period, timeout, checkerType}], nextPageToken?}. Header values and passwords are redacted.",
	inputSchema = schema({project = PROJECT, filter = FILTER, pageSize = PAGE_SIZE, pageToken = PAGE_TOKEN}, {"project"}, {project = "my-project-123"}),
	annotations = READ,
}
function exports.listUptimeChecks(args: Options): Options
	return request("listUptimeChecks", "GET", MONITORING .. "/v3/projects/{project}/uptimeCheckConfigs", args, {query = {"filter", "pageSize", "pageToken"}, list = "uptimeCheckConfigs", redact = true})
end

-- Compute Engine

help.functions.listInstances = {
	description = [[VM instances in every zone: {items={['zones/us-central1-a']={instances=[instance]} or
{warning}}, nextPageToken?}. An instance has name, zone, status (RUNNING, TERMINATED, ...),
machineType, networkInterfaces, disks, labels and metadata, whose values are redacted. filter uses
Compute syntax, e.g. 'status = RUNNING' or 'labels.env = prod'. maxResults is at most 500.]],
	inputSchema = schema({project = PROJECT, filter = FILTER, orderBy = ID, maxResults = PAGE_SIZE, pageToken = PAGE_TOKEN}, {"project"}, {project = "my-project-123", filter = "status = RUNNING"}),
	annotations = READ,
}
function exports.listInstances(args: Options): Options
	return request("listInstances", "GET", COMPUTE .. "/projects/{project}/aggregated/instances", args, {query = {"filter", "orderBy", "maxResults", "pageToken", "returnPartialSuccess"}, defaults = {returnPartialSuccess = true}, redact = true})
end

help.functions.getInstance = {
	description = "One VM instance, as listInstances returns it; zone is short, such as us-central1-a.",
	inputSchema = schema({project = PROJECT, zone = ID, instance = ID}, {"project", "zone", "instance"}, {project = "my-project-123", zone = "us-central1-a", instance = "worker-1"}),
	annotations = READ,
}
function exports.getInstance(args: Options): Options
	return request("getInstance", "GET", COMPUTE .. "/projects/{project}/zones/{zone}/instances/{instance}", args, {redact = true})
end

-- Billing and APIs

help.functions.listBillingAccounts = {
	description = "Billing accounts the account can see: {billingAccounts=[{name='billingAccounts/0X0X0X-...', displayName, open, masterBillingAccount?}], nextPageToken?}. Google offers no API for actual costs: use the Cloud console or a BigQuery billing export.",
	inputSchema = schema({filter = FILTER, pageSize = PAGE_SIZE, pageToken = PAGE_TOKEN}, NONE, {pageSize = 50}),
	annotations = READ,
}
function exports.listBillingAccounts(args: Options?): Options
	return request("listBillingAccounts", "GET", BILLING .. "/billingAccounts", args, {query = {"filter", "pageSize", "pageToken"}, list = "billingAccounts"})
end

help.functions.getProjectBillingInfo = {
	description = "A project's billing link: {name, projectId, billingAccountName, billingEnabled}. billingEnabled=false explains APIs refusing calls with [BILLING_DISABLED].",
	inputSchema = schema({project = PROJECT}, {"project"}, {project = "my-project-123"}),
	annotations = READ,
}
function exports.getProjectBillingInfo(args: Options): Options
	return request("getProjectBillingInfo", "GET", BILLING .. "/projects/{project}/billingInfo", args)
end

help.functions.listEnabledServices = {
	description = "APIs enabled in the project: {services=[{name='projects/123/services/run.googleapis.com', config={name, title}, state}], nextPageToken?}. Explains [SERVICE_DISABLED] errors. pageSize is at most 200.",
	inputSchema = schema({project = PROJECT, pageSize = PAGE_SIZE, pageToken = PAGE_TOKEN}, {"project"}, {project = "my-project-123", pageSize = 200}),
	annotations = READ,
}
function exports.listEnabledServices(args: Options): Options
	return request("listEnabledServices", "GET", SERVICES .. "/projects/{project}/services", args, {query = {"filter", "pageSize", "pageToken"}, defaults = {filter = "state:ENABLED"}, list = "services"})
end

-- Artifact Registry

help.functions.listRepositories = {
	description = "One region's Artifact Registry repositories: {repositories=[{name, format (DOCKER, NPM, ...), mode, sizeBytes?, createTime, updateTime}], nextPageToken?}. location is a region or multi-region such as us.",
	inputSchema = schema({project = PROJECT, location = LOCATION, filter = FILTER, orderBy = ID, pageSize = PAGE_SIZE, pageToken = PAGE_TOKEN}, {"project", "location"}, {project = "my-project-123", location = "us-central1"}),
	annotations = READ,
}
function exports.listRepositories(args: Options): Options
	return request("listRepositories", "GET", ARTIFACTS .. "/projects/{project}/locations/{location}/repositories", args, {query = {"filter", "orderBy", "pageSize", "pageToken"}, list = "repositories"})
end

help.functions.listDockerImages = {
	description = "A Docker repository's images: {dockerImages=[{name, uri, tags?, imageSizeBytes, uploadTime, updateTime, buildTime?}], nextPageToken?}. orderBy='update_time desc' lists the newest first.",
	inputSchema = schema({project = PROJECT, location = LOCATION, repository = ID, orderBy = ID, pageSize = PAGE_SIZE, pageToken = PAGE_TOKEN}, {"project", "location", "repository"}, {project = "my-project-123", location = "us-central1", repository = "containers", orderBy = "update_time desc"}),
	annotations = READ,
}
function exports.listDockerImages(args: Options): Options
	return request("listDockerImages", "GET", ARTIFACTS .. "/projects/{project}/locations/{location}/repositories/{repository}/dockerImages", args, {query = {"orderBy", "pageSize", "pageToken"}, list = "dockerImages"})
end

if config.access ~= "read-write" then
	help.sections = {builds = "Cloud Build's API needs read-write access. To see why a build failed, read its logs: listLogEntries with filter 'logName=\"projects/p/logs/cloudbuild\" AND timestamp>=\"...\"', optionally with resource.labels.build_id=\"<id>\"."}
end

if config.access == "read-write" then
	help.text ..= [[

Writes return Google's long-running operation or resource unchanged (secrets redacted). Cloud Run
writes return {name='projects/p/locations/l/operations/id', done?, error?, response?}: poll
getRunOperation({name}) until done, then check error. Compute writes return {name, status, zone,
error?}: poll getZoneOperation until status is DONE. A failed or timed-out write may already have
succeeded: check before repeating. Compute writes take a requestId (a UUID) that makes a repeated
call with the same requestId run once.]]

	-- Cloud Run writes

	-- The service's own unredacted spec, never returned: writes that replace containers whole start
	-- from it. args must hold only the service's project, location and name.
	local function runService(name: string, args: Options): (string, string?, Options)
		local href, project = target(RUN .. "/v2/projects/{project}/locations/{location}/services/{service}", args)
		done(name, args)
		return href, project, decode(name, send(name, "GET", href, nil, project))
	end

	help.functions.updateRunServiceImage = {
		description = [[Deploys a new image to a Cloud Run service: a new revision with the same settings and
environment, which takes the traffic that follows the latest revision. container names the
container to change when the service has several. Returns the operation; its response is the
updated service. A service whose template names its revision (template.revision) needs a new name,
which this does not set, and fails.]],
		inputSchema = schema({project = PROJECT, location = LOCATION, service = ID, image = ID, container = ID}, {"project", "location", "service", "image"}, {project = "my-project-123", location = "us-central1", service = "api", image = "us-central1-docker.pkg.dev/my-project-123/containers/api:v42"}),
		annotations = WRITE,
	}
	function exports.updateRunServiceImage(input: any): Options
		local args = options(input)
		local image, container = text(args.image, "image"), args.container
		args.image, args.container = nil, nil
		local href, project, service = runService("updateRunServiceImage", args)
		local containers = if type(service.template) == "table" then service.template.containers else nil
		assert(type(containers) == "table" and containers[1] ~= nil, "the service has no containers")
		local chosen: Options? = nil
		for _, entry in containers do
			if (container == nil and #containers == 1) or (container ~= nil and entry.name == container) then chosen = entry end
		end
		assert(chosen, if container == nil then "the service has several containers: pass container" else "the service has no container named " .. tostring(container))
		chosen.image = image
		return redact(decode("updateRunServiceImage", send("updateRunServiceImage", "PATCH", href .. "?updateMask=template.containers",
			{template = {containers = containers}, etag = service.etag}, project)))
	end

	help.functions.updateRunServiceTraffic = {
		description = "Splits a Cloud Run service's traffic, e.g. traffic={{type='TRAFFIC_TARGET_ALLOCATION_TYPE_REVISION', revision='api-00041-abc', percent=100}} to roll back, or {{type='TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST', percent=100}} to follow new revisions. Percents add up to 100; tag gives a revision its own URL. Returns the operation.",
		inputSchema = schema({project = PROJECT, location = LOCATION, service = ID, traffic = {type = "array", minItems = 1, items = {type = "object", properties = {
			type = {type = "string", enum = {"TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST", "TRAFFIC_TARGET_ALLOCATION_TYPE_REVISION"}},
			revision = ID, percent = {type = "integer", minimum = 0, maximum = 100}, tag = ID,
		}, additionalProperties = false}}}, {"project", "location", "service", "traffic"}, {project = "my-project-123", location = "us-central1", service = "api", traffic = {{type = "TRAFFIC_TARGET_ALLOCATION_TYPE_REVISION", revision = "api-00041-abc", percent = 100}}}),
		annotations = WRITE,
	}
	function exports.updateRunServiceTraffic(input: any): Options
		local args = options(input)
		assert(type(args.traffic) == "table" and args.traffic[1] ~= nil, "traffic must be a nonempty array")
		return request("updateRunServiceTraffic", "PATCH", RUN .. "/v2/projects/{project}/locations/{location}/services/{service}?updateMask=traffic", args, {body = {"traffic"}, redact = true})
	end

	help.functions.runJob = {
		description = "Starts a Cloud Run job execution. overrides={containerOverrides={{args?, env?={{name, value}}}}, taskCount?, timeout?} changes this execution only. Returns the operation; its metadata is the execution, whose name listRunTasks takes.",
		inputSchema = schema({project = PROJECT, location = LOCATION, job = ID, overrides = {type = "object"}}, {"project", "location", "job"}, {project = "my-project-123", location = "us-central1", job = "nightly-export"}),
		annotations = WRITE,
	}
	function exports.runJob(args: Options): Options
		return request("runJob", "POST", RUN .. "/v2/projects/{project}/locations/{location}/jobs/{job}:run", args, {body = {"overrides"}, redact = true})
	end

	help.functions.cancelRunExecution = {
		description = "Cancels a running Cloud Run job execution; finished tasks keep their results. Returns the operation.",
		inputSchema = schema({project = PROJECT, location = LOCATION, job = ID, execution = ID}, {"project", "location", "job", "execution"}, {project = "my-project-123", location = "us-central1", job = "nightly-export", execution = "nightly-export-abc12"}),
		annotations = DESTRUCTIVE,
	}
	function exports.cancelRunExecution(args: Options): Options
		return request("cancelRunExecution", "POST", RUN .. "/v2/projects/{project}/locations/{location}/jobs/{job}/executions/{execution}:cancel", args, {body = NONE, redact = true})
	end

	help.functions.getRunOperation = {
		description = "A Cloud Run operation by the name a write returned: {name, done?, error?={code, message}, metadata, response?}. Poll every few seconds until done.",
		inputSchema = schema({name = {type = "string", pattern = "^projects/[^/]+/locations/[^/]+/operations/[^/]+$"}}, {"name"}, {name = "projects/my-project-123/locations/us-central1/operations/abc-123"}),
		annotations = READ,
	}
	function exports.getRunOperation(input: any): Options
		local args = options(input)
		local project, location, operation = string.match(text(args.name, "name"), "^projects/([^/]+)/locations/([^/]+)/operations/([^/]+)$")
		assert(project and location and operation, "name must be projects/<project>/locations/<location>/operations/<id>")
		return request("getRunOperation", "GET", RUN .. "/v2/projects/{project}/locations/{location}/operations/{operation}", {project = project, location = location, operation = operation}, {redact = true})
	end

	-- Compute Engine writes

	local INSTANCE = {project = PROJECT, zone = ID, instance = ID, requestId = {type = "string", minLength = 1, description = "A UUID; a repeated call with the same requestId runs once."}}
	local INSTANCE_REQUIRED = {"project", "zone", "instance"}
	local INSTANCE_EXAMPLE = {project = "my-project-123", zone = "us-central1-a", instance = "worker-1", requestId = "5f0c6b7e-3d1a-4a9b-8c2d-0e1f2a3b4c5d"}

	help.functions.startInstance = {
		description = "Starts a stopped VM instance. Returns the zone operation.",
		inputSchema = schema(INSTANCE, INSTANCE_REQUIRED, INSTANCE_EXAMPLE),
		annotations = WRITE,
	}
	function exports.startInstance(args: Options): Options
		return request("startInstance", "POST", COMPUTE .. "/projects/{project}/zones/{zone}/instances/{instance}/start", args, {query = {"requestId"}})
	end

	help.functions.stopInstance = {
		description = "Stops a VM instance after a graceful shutdown; its disks remain and it stops accruing compute charges. Returns the zone operation.",
		inputSchema = schema(INSTANCE, INSTANCE_REQUIRED, INSTANCE_EXAMPLE),
		annotations = DESTRUCTIVE,
	}
	function exports.stopInstance(args: Options): Options
		return request("stopInstance", "POST", COMPUTE .. "/projects/{project}/zones/{zone}/instances/{instance}/stop", args, {query = {"requestId"}})
	end

	help.functions.resetInstance = {
		description = "Hard-resets a VM instance, like pressing its reset button: memory is lost and no graceful shutdown runs. Returns the zone operation.",
		inputSchema = schema(INSTANCE, INSTANCE_REQUIRED, INSTANCE_EXAMPLE),
		annotations = DESTRUCTIVE,
	}
	function exports.resetInstance(args: Options): Options
		return request("resetInstance", "POST", COMPUTE .. "/projects/{project}/zones/{zone}/instances/{instance}/reset", args, {query = {"requestId"}})
	end

	help.functions.getZoneOperation = {
		description = "A Compute zone operation by the name a write returned: {name, operationType, targetLink, status (PENDING, RUNNING, DONE), progress, error?={errors}}.",
		inputSchema = schema({project = PROJECT, zone = ID, operation = ID}, {"project", "zone", "operation"}, {project = "my-project-123", zone = "us-central1-a", operation = "operation-1730000000000-abc"}),
		annotations = READ,
	}
	function exports.getZoneOperation(args: Options): Options
		return request("getZoneOperation", "GET", COMPUTE .. "/projects/{project}/zones/{zone}/operations/{operation}", args)
	end

	-- Cloud Storage writes

	help.functions.uploadObject = {
		description = "Uploads a session file, up to 250 MB, as a bucket object and returns its metadata. An existing object of that name is replaced unless ifGenerationMatch='0', which only creates. contentType defaults to application/octet-stream.",
		inputSchema = schema({bucket = ID, name = ID, path = ID, contentType = ID, ifGenerationMatch = ID}, {"bucket", "name", "path"}, {bucket = "my-project-123-assets", name = "reports/2026-11.csv", path = "report.csv", contentType = "text/csv"}),
		annotations = DESTRUCTIVE,
	}
	function exports.uploadObject(input: any): Options
		local args = options(input)
		local path = text(args.path, "path")
		local contentType = if args.contentType == nil then "application/octet-stream" else text(args.contentType, "contentType")
		text(args.name, "name")
		args.path, args.contentType, args.uploadType = nil, nil, "media"
		local href = target(STORAGE .. "/upload/storage/v1/b/{bucket}/o", args, {"uploadType", "name", "ifGenerationMatch"})
		done("uploadObject", args)
		assert(await(fs.stat(path)).size <= MAX_UPLOAD, "uploadObject handles files up to 250 MB")
		local response = await(http.request({method = "POST", url = href, headers = {["Content-Type"] = {contentType}}, body = fs.open(path, "r")}))
		if response.statusCode < 200 or response.statusCode >= 300 then failWith("uploadObject", response, problemOf(response)) end
		return decode("uploadObject", response)
	end

	help.functions.deleteObject = {
		description = "Deletes an object, or one generation of a versioned object; returns {success=true}. A bucket with soft delete keeps it restorable for its retention period.",
		inputSchema = schema({bucket = ID, object = ID, generation = ID, ifGenerationMatch = ID}, {"bucket", "object"}, {bucket = "my-project-123-assets", object = "reports/2026-10.csv"}),
		annotations = DESTRUCTIVE,
	}
	function exports.deleteObject(args: Options): Options
		return request("deleteObject", "DELETE", STORAGE .. "/storage/v1/b/{bucket}/o/{object}", args, {query = {"generation", "ifGenerationMatch"}})
	end

	-- Cloud Build

	local GLOBAL = {location = "global"}
	local BUILD_LOCATION = {type = "string", minLength = 1, default = "global", description = "Region of a regional build or trigger; defaults to global."}

	help.functions.listBuilds = {
		description = "Builds, newest first: {builds=[{id, status (SUCCESS, FAILURE, TIMEOUT, ...), statusDetail?, failureInfo?, createTime, startTime, finishTime, source, steps, images, logUrl, logsBucket, buildTriggerId?, substitutions}], nextPageToken?}. filter e.g. 'status=\"FAILURE\"' or 'trigger_id=\"...\"'. Substitution and step env values are redacted.",
		inputSchema = schema({project = PROJECT, location = BUILD_LOCATION, filter = FILTER, pageSize = PAGE_SIZE, pageToken = PAGE_TOKEN}, {"project"}, {project = "my-project-123", filter = 'status="FAILURE"', pageSize = 10}),
		annotations = READ,
	}
	function exports.listBuilds(args: Options): Options
		return request("listBuilds", "GET", BUILD .. "/projects/{project}/locations/{location}/builds", args, {defaults = GLOBAL, query = {"filter", "pageSize", "pageToken"}, list = "builds", redact = true})
	end

	help.functions.getBuild = {
		description = "One build by id, as listBuilds returns it. Its log is in Cloud Logging (listLogEntries with resource.labels.build_id) or logsBucket.",
		inputSchema = schema({project = PROJECT, location = BUILD_LOCATION, build = ID}, {"project", "build"}, {project = "my-project-123", build = "1b2c3d4e-5f60-4718-9a0b-c1d2e3f4a5b6"}),
		annotations = READ,
	}
	function exports.getBuild(args: Options): Options
		return request("getBuild", "GET", BUILD .. "/projects/{project}/locations/{location}/builds/{build}", args, {defaults = GLOBAL, redact = true})
	end

	help.functions.listBuildTriggers = {
		description = "Build triggers: {triggers=[{id, name, description?, github? or repositoryEventConfig?, filename?, build?, substitutions?, disabled?}], nextPageToken?}.",
		inputSchema = schema({project = PROJECT, location = BUILD_LOCATION, pageSize = PAGE_SIZE, pageToken = PAGE_TOKEN}, {"project"}, {project = "my-project-123"}),
		annotations = READ,
	}
	function exports.listBuildTriggers(args: Options): Options
		return request("listBuildTriggers", "GET", BUILD .. "/projects/{project}/locations/{location}/triggers", args, {defaults = GLOBAL, query = PAGED, list = "triggers", redact = true})
	end

	help.functions.retryBuild = {
		description = "Runs a finished build again from the same source revision. Returns the operation; metadata.build is the new build.",
		inputSchema = schema({project = PROJECT, location = BUILD_LOCATION, build = ID}, {"project", "build"}, {project = "my-project-123", build = "1b2c3d4e-5f60-4718-9a0b-c1d2e3f4a5b6"}),
		annotations = WRITE,
	}
	function exports.retryBuild(args: Options): Options
		return request("retryBuild", "POST", BUILD .. "/projects/{project}/locations/{location}/builds/{build}:retry", args, {defaults = GLOBAL, body = NONE, redact = true})
	end

	help.functions.cancelBuild = {
		description = "Cancels a queued or running build and returns it.",
		inputSchema = schema({project = PROJECT, location = BUILD_LOCATION, build = ID}, {"project", "build"}, {project = "my-project-123", build = "1b2c3d4e-5f60-4718-9a0b-c1d2e3f4a5b6"}),
		annotations = DESTRUCTIVE,
	}
	function exports.cancelBuild(args: Options): Options
		return request("cancelBuild", "POST", BUILD .. "/projects/{project}/locations/{location}/builds/{build}:cancel", args, {defaults = GLOBAL, body = NONE, redact = true})
	end
end

return exports
