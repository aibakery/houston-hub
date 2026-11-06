-- Vercel REST API. Arguments and results keep Vercel's native camelCase field names.
type Options = {[string]: any}
type Endpoint = {method: string, path: string, query: {string}?, extra: {string}?, required: {string}?, write: boolean?, body: (boolean | string)?,
	fields: {string}?, team: boolean?, shape: string?, doc: string, about: string, example: Options}

local PROVIDER = "Vercel"
local API = "https://api.vercel.com"
local DOCS = "https://vercel.com/docs/rest-api/"
local PAGE = {"limit", "since", "until"}

-- Operations in Vercel's public OpenAPI (https://openapi.vercel.sh), checked on 2026-10-27.
-- Path {fields} are required; listed query fields are taken from the options and the other
-- fields form the JSON body. Requests carry the connection's team unless team is false.
local endpoints: {[string]: Endpoint} = {
	getUser = {method = "GET", path = "/v2/user", example = {}, team = false, doc = "user/get-the-user", about = "The token's user, {user}."},
	listTeams = {method = "GET", path = "/v2/teams", example = {limit = 5}, query = PAGE, team = false, doc = "teams/list-all-teams",
		about = "Teams the token can access, {teams, pagination}."},

	listProjects = {method = "GET", path = "/v10/projects", example = {search = "web", limit = 10, from = "NBSWY"}, query = {"search", "repo", "repoId", "repoUrl", "excludeRepos", "limit", "from"},
		shape = "projects", doc = "projects/retrieve-a-list-of-projects",
		about = "Projects, {projects, pagination}; search matches names. Page with from=pagination.next."},
	getProject = {method = "GET", path = "/v9/projects/{idOrName}", example = {idOrName = "web"}, shape = "project", doc = "projects/find-a-project-by-id-or-name",
		about = "A project by id (prj_...) or name, with its git link, crons and latest and production deployments."},
	listProjectDomains = {method = "GET", path = "/v9/projects/{idOrName}/domains", example = {idOrName = "web", production = "true", verified = false},
		query = {"production", "target", "customEnvironmentId", "gitBranch", "redirects", "redirect", "verified", "order", "limit", "since", "until"},
		doc = "projects/retrieve-project-domains-by-project-by-id-or-name",
		about = "A project's domains with their redirects and verification, {domains, pagination}. target: production or preview; limit at most 100."},
	getProjectDomain = {method = "GET", path = "/v9/projects/{idOrName}/domains/{domain}", example = {idOrName = "web", domain = "www.example.com"}, doc = "projects/get-a-project-domain", about = "One domain of a project."},

	listDeployments = {method = "GET", path = "/v7/deployments", example = {projectIds = {"prj_1", "prj_2"}},
		query = {"projectId", "projectIds", "app", "target", "state", "branch", "sha", "users", "rollbackCandidate", "limit", "since", "until"},
		shape = "deployments", doc = "deployments/list-deployments",
		about = "Deployments, newest first, {deployments, pagination}. projectId takes an id or name; target: production or preview; state: BUILDING, ERROR, INITIALIZING, QUEUED, READY, CANCELED or BLOCKED (comma-separated or an array)."},
	getDeployment = {method = "GET", path = "/v13/deployments/{idOrUrl}", example = {idOrUrl = "web-abc123.vercel.app", withGitRepoInfo = "true"}, query = {"withGitRepoInfo"}, shape = "deployment", doc = "deployments/get-a-deployment-by-id-or-url",
		about = "A deployment by id (dpl_...) or hostname, with readyState, target, url, alias, errorMessage and git metadata."},
	listBuildLogs = {method = "GET", path = "/v3/deployments/{idOrUrl}/events", example = {idOrUrl = "dpl_1", limit = -1, direction = "backward"}, query = {"limit", "direction", "since", "until", "name", "statusCode", "builds"},
		shape = "events", doc = "deployments/get-deployment-events",
		about = "A deployment's build events as an array of {type, created, text, level?, info, payload}. limit=-1 returns all, failing past 8 MiB, so prefer a limit for large builds; direction: forward (default) or backward; builds=1 adds build steps."},
	listRuntimeLogs = {method = "GET", path = "/v1/projects/{projectId}/deployments/{deploymentId}/runtime-logs", example = {projectId = "prj_1", deploymentId = "dpl_1"}, extra = {"limit"},
		shape = "stream", doc = "logs/get-logs-for-a-deployment",
		about = "Live request and function logs written while listening for a few seconds, {logs, ended, truncated}: each {timestampInMs, level, message, source, requestMethod, requestPath, responseStatusCode, domain}. limit is 1..1000 lines (default 100)."},
	listPromoteAliases = {method = "GET", path = "/v1/projects/{projectId}/promote/aliases", example = {projectId = "prj_1", failedOnly = true}, query = {"failedOnly", "limit", "since", "until"},
		doc = "projects/gets-a-list-of-aliases-with-status-for-the-current-promote",
		about = "Progress of the project's current promotion, {aliases, pagination}."},

	listDomains = {method = "GET", path = "/v5/domains", example = {limit = 50}, query = PAGE, doc = "domains/list-all-the-domains", about = "Domains, {domains, pagination}."},
	getDomain = {method = "GET", path = "/v5/domains/{domain}", example = {domain = "example.com"}, doc = "domains/get-information-for-a-single-domain",
		about = "A domain with its verification, nameservers and renewal."},
	getDomainConfig = {method = "GET", path = "/v6/domains/{domain}/config", example = {domain = "www.example.com", projectIdOrName = "web"}, query = {"projectIdOrName", "strict"}, doc = "domains/get-a-domain-s-configuration",
		about = "Whether a domain's DNS points at Vercel: misconfigured, configuredBy and the recommended records."},

	redeploy = {method = "POST", path = "/v13/deployments", example = {name = "web", deploymentId = "dpl_1", target = "production", forceNew = 1}, query = {"forceNew"}, required = {"name", "deploymentId"},
		fields = {"name", "deploymentId", "target", "withLatestCommit", "meta"}, shape = "deployment", doc = "deployments/create-a-new-deployment",
		about = "Body {name (project name), deploymentId, target?, withLatestCommit?, meta?} and no other fields. Rebuilds deploymentId's source as a new deployment. target: production, staging or a custom environment id; without it, a preview. forceNew=1 deploys even when an identical deployment exists."},
	promoteDeployment = {method = "POST", path = "/v10/projects/{projectId}/promote/{deploymentId}", example = {projectId = "prj_1", deploymentId = "dpl_2"}, body = false, doc = "projects/point-production-traffic-to-a-given-deployment",
		about = "Serves production traffic from a deployment without rebuilding; follow progress with listPromoteAliases."},
	rollbackDeployment = {method = "POST", path = "/v1/projects/{projectId}/rollback/{deploymentId}", example = {projectId = "prj_1", deploymentId = "dpl_1", description = "Bad release"}, query = {"description"}, body = false,
		doc = "projects/point-production-traffic-to-a-previous-production-deployment-by-id",
		about = "Points production back to an earlier production deployment and pauses automatic promotion until a later promote."},
	cancelDeployment = {method = "PATCH", path = "/v12/deployments/{id}/cancel", example = {id = "dpl_3"}, body = false, shape = "deployment", doc = "deployments/cancel-a-deployment",
		about = "Cancels a queued or building deployment."},

	listEnvVars = {method = "GET", path = "/v10/projects/{idOrName}/env", example = {idOrName = "web", decrypt = "true"}, write = true,
		query = {"decrypt", "gitBranch", "source", "customEnvironmentId", "customEnvironmentSlug"}, doc = "projects/retrieve-the-environment-variables-of-a-project-by-id-or-name",
		about = "A project's environment variables, {envs}: {id, key, type, target, gitBranch?, value?}. Values of plain variables are included; decrypt='true' also decrypts encrypted ones. Sensitive values are never returned."},
	getEnvVar = {method = "GET", path = "/v1/projects/{idOrName}/env/{id}", example = {idOrName = "web", id = "e1"}, write = true,
		doc = "projects/retrieve-the-decrypted-value-of-an-environment-variable-of-a-project-by-id", about = "One variable with its decrypted value."},
	createEnvVar = {method = "POST", path = "/v10/projects/{idOrName}/env", example = {idOrName = "web", upsert = "true", key = "FLAG", value = "on", type = "plain", target = {"production", "preview"}}, query = {"upsert"}, doc = "projects/create-one-or-more-environment-variables",
		about = "Body {key, value, type, target, gitBranch?, comment?, customEnvironmentIds?}. type: plain, encrypted or sensitive; target: an array of production, preview and development. upsert='true' replaces an existing key. Redeploy for running deployments to see changes."},
	updateEnvVar = {method = "PATCH", path = "/v9/projects/{idOrName}/env/{id}", example = {idOrName = "web", id = "e2", value = "off"}, doc = "projects/edit-an-environment-variable",
		about = "Body: the createEnvVar fields to change."},
	deleteEnvVar = {method = "DELETE", path = "/v9/projects/{idOrName}/env/{id}", example = {idOrName = "web", id = "e2"}, query = {"customEnvironmentId"}, doc = "projects/remove-an-environment-variable",
		about = "Deletes a variable."},
}

-- Request layer shared verbatim by the endpoint-table connectors
-- (tools/validate checks they match). It uses each connector's PROVIDER, DOCS and Endpoint type.
local NULL = json.decode("null")
local NONE: {string} = table.freeze({})

local function options(input: Options?): Options
	if input == nil then return {} end
	assert(type(input) == "table", "opts must be an object")
	for key in input do assert(type(key) == "string", "opts must have named fields") end
	return table.clone(input)
end

local function scalar(value: any, field: string): string
	local kind = type(value)
	assert(kind == "string" or kind == "boolean" or kind == "number", field .. " must be a string, boolean, number or array of those")
	return url.encode(value)
end

-- A query value's encoded parts: one for a scalar, one per item of a nonempty array. Each
-- connector joins them as its provider expects, comma-separated or with the key repeated.
local function queryParts(value: any, field: string): {string}
	if type(value) ~= "table" then return {scalar(value, field)} end
	local parts: {string} = {}
	for index, item in value do
		assert(type(index) == "number" and index == #parts + 1, field .. " must be an array, not an object")
		table.insert(parts, scalar(item, field))
	end
	assert(#parts > 0, field .. " must not be an empty array")
	return parts
end

-- Only GET reads unless write says otherwise.
local function writes(endpoint: Endpoint): boolean
	if endpoint.write ~= nil then return endpoint.write end
	return endpoint.method ~= "GET"
end

-- POST, PATCH and PUT send the remaining options as the JSON body unless body is false
-- (no body) or names the one option to send.
local function hasBody(endpoint: Endpoint): boolean
	return endpoint.body ~= false and (endpoint.method == "POST" or endpoint.method == "PATCH" or endpoint.method == "PUT")
end

local function fail(name: string, response: HttpResponse, message: string): never
	return houston.fail({operation = name, layer = "upstream", upstream_status = response.statusCode,
		retryable = response.statusCode == 429 or response.statusCode >= 500, message = message})
end

-- A successful response's JSON object, or nil when a write answers without a body. With arrays,
-- a top-level JSON array is accepted too, and the second result tells which one came back.
local function object(name: string, endpoint: Endpoint, response: HttpResponse, arrays: boolean?): (any, boolean)
	local raw = await(response.body:readAll())
	if endpoint.method ~= "GET" and writes(endpoint) and string.match(raw, "^%s*$") then return nil, false end
	local ok, value = pcall(json.decode, raw)
	local list = arrays == true and string.match(raw, "^%s*%[") ~= nil
	if not ok or type(value) ~= "table" or not (list or string.match(raw, "^%s*{")) then
		fail(name, response, PROVIDER .. " returned an invalid JSON object")
	end
	return value, list
end

-- Export and document exactly the operations enabled for this connection.
local function operations(endpoints: {[string]: Endpoint}, request: (string, Endpoint, Options?) -> any, intro: {string}, documentation: {[string]: any}): {[string]: any}
	local exports: {[string]: any}, docs: {[string]: any} = {}, {}
	for name in documentation do assert(endpoints[name], "documentation without endpoint: " .. name) end
	for name, endpoint in endpoints do
		assert(documentation[name], "missing documentation for " .. name)
		if not writes(endpoint) or config.access == "read-write" then
			exports[name] = function(args: Options?): any return request(name, endpoint, args) end
			local record = table.clone(documentation[name])
			record.description = endpoint.about .. " " .. endpoint.method .. " " .. endpoint.path .. ". Reference: " .. DOCS .. endpoint.doc
				.. (if record.description then "\n\n" .. record.description else "")
			if record.annotations == nil then record.annotations = {readOnlyHint = not writes(endpoint)} end
			docs[name] = record
		end
	end
	exports.help = {text = table.concat(intro, "\n\n"), functions = docs}
	return exports
end
-- End of the shared request layer.

-- The connection's team, by id (team_...) or slug; without one, the token's own scope applies.
-- An invalid team fails each call rather than loading, so help still works.
local TEAM: string? = nil
local TEAM_VALID = true
if type(config.team) == "string" then
	local team = string.match(config.team, "^%s*(.-)%s*$") :: string
	if team ~= "" then
		TEAM_VALID = string.match(team, "^[%w_%-]+$") ~= nil
		TEAM = if string.sub(string.lower(team), 1, 5) == "team_" then "teamId=" .. team else "slug=" .. string.lower(team)
	end
end

-- Deployment meta can name the deploy hook that started a build, and a hook's id completes its
-- unauthenticated trigger URL, so deployments drop hook fields, and anything named like a token,
-- secret or password.
local SECRET_WORDS = {"hook", "token", "secret", "password", "apikey", "accesskey", "privatekey", "credential"}

local function secretKey(key: string): boolean
	local lower = string.lower(key)
	for _, word in SECRET_WORDS do if string.find(lower, word, 1, true) then return true end end
	return false
end

local function deployment(value: any): any
	if type(value) == "table" and type(value.meta) == "table" then
		local meta: Options = {}
		for key, item in value.meta do
			if type(key) ~= "string" or not secretKey(key) then meta[key] = item end
		end
		value.meta = meta
	end
	return value
end

local function deployments(list: any): any
	if type(list) == "table" then
		for _, item in list do deployment(item) end
	end
	return list
end

-- Project responses also carry environment variable values, protection bypass secrets and deploy
-- hook URLs, so they keep only these fields, and link only its repository details.
local PROJECT_FIELDS = {"id", "name", "accountId", "framework", "nodeVersion", "buildCommand", "devCommand", "installCommand", "outputDirectory",
	"rootDirectory", "createdAt", "updatedAt", "live", "paused", "crons", "latestDeployments", "targets", "link"}
local LINK_FIELDS = {"type", "org", "owner", "repo", "repoId", "slug", "projectName", "projectNamespace", "projectUrl", "productionBranch", "createdAt", "updatedAt"}

local function pick(value: any, fields: {string}): any
	if type(value) ~= "table" then return value end
	local kept: Options = {}
	for _, field in fields do kept[field] = value[field] end
	return kept
end

local function project(value: any): any
	local kept = pick(value, PROJECT_FIELDS)
	if type(kept) == "table" then
		kept.link = pick(kept.link, LINK_FIELDS)
		kept.latestDeployments = deployments(kept.latestDeployments)
		-- targets maps environments, such as production, to their current deployment.
		kept.targets = deployments(kept.targets)
	end
	return kept
end

-- Vercel errors are {error: {code, message, ...}}; rate limits add x-ratelimit-reset in epoch seconds.
local function failStatus(name: string, response: HttpResponse): never
	local message = "Vercel HTTP " .. tostring(response.statusCode)
	local ok, value = pcall(json.decode, await(response.body:readPrefix(16 * 1024)))
	local problem = if ok and type(value) == "table" then value.error else nil
	if type(problem) == "table" then
		if type(problem.code) == "string" then message ..= " (" .. string.sub(problem.code, 1, 100) .. ")" end
		if type(problem.message) == "string" then message ..= ": " .. string.sub(problem.message, 1, 600) end
	end
	local reset = response.headers["x-ratelimit-reset"]
	if response.statusCode == 429 and reset and reset[1] then message ..= "; rate limit resets at Unix time " .. reset[1] end
	return fail(name, response, message)
end

-- Runtime logs stream new lines as newline-delimited JSON for minutes, and an invocation lasts at
-- most 30 seconds: read until limit lines, the stream's end, or a moment without new data, at
-- most HEADERS_WAIT + FIRST_WAIT + (MAX_READS - 1) * IDLE_WAIT, about 23 seconds. The header wait
-- leaves room for Houston's two 429 retries (1 and 2 seconds).
local HEADERS_WAIT, FIRST_WAIT, IDLE_WAIT, MAX_READS, MAX_LINE = 8000, 2000, 1000, 14, 256 * 1024

local function timedOut(err: any): boolean
	if type(err) == "table" then return err.code == "timeout" end
	return string.find(tostring(err), "timed out", 1, true) ~= nil
end

local function stream(name: string, response: HttpResponse, limit: number): any
	if response.statusCode ~= 200 then failStatus(name, response) end
	local logs: {any} = json.decode("[]")
	local pending, ended, idle = "", false, false
	for read = 1, MAX_READS do
		local ok, chunk = pcall(function(): any return await(response.body:read(64 * 1024), if read == 1 then FIRST_WAIT else IDLE_WAIT) end)
		if not ok then
			if timedOut(chunk) then
				idle = true
				break
			end
			pcall(function() response.body:close() end)
			return houston.fail({operation = name, layer = "upstream", upstream_status = 200, retryable = true,
				message = "The runtime log stream failed after " .. #logs .. " lines"})
		end
		if chunk.done then
			ended = true
			pending ..= "\n"
		else
			pending ..= chunk.data
		end
		local start = 1
		while #logs < limit do
			local stop = string.find(pending, "\n", start, true)
			if not stop then break end
			local line = string.sub(pending, start, stop - 1)
			start = stop + 1
			if string.find(line, "%S") then
				local decoded, entry = pcall(json.decode, line)
				if not decoded or type(entry) ~= "table" then
					pcall(function() response.body:close() end)
					fail(name, response, "Vercel returned an invalid log line")
				end
				table.insert(logs, entry)
			end
		end
		pending = string.sub(pending, start)
		if ended or #logs >= limit then break end
		if #pending > MAX_LINE then
			pcall(function() response.body:close() end)
			fail(name, response, "Vercel returned a log line over " .. MAX_LINE .. " bytes")
		end
	end
	-- At exactly limit lines, one short read tells whether the stream has ended.
	if #logs >= limit and not ended and not string.find(pending, "%S") then
		local ok, chunk = pcall(function(): any return await(response.body:read(1), IDLE_WAIT) end)
		ended = ok and chunk.done
		idle = not ok and timedOut(chunk)
	end
	pcall(function() response.body:close() end)
	-- More was likely coming when the read budget or limit ran out, or a line was cut off.
	local truncated = (not ended and not idle) or string.find(pending, "%S") ~= nil
	return {logs = logs, ended = ended, truncated = truncated}
end

local function decode(name: string, endpoint: Endpoint, response: HttpResponse): any
	if response.statusCode < 200 or response.statusCode >= 300 then failStatus(name, response) end
	-- Build events, project lists (on older accounts) and deletions can answer with an array.
	local arrays = endpoint.shape == "events" or endpoint.shape == "projects" or endpoint.method == "DELETE"
	local value, list = object(name, endpoint, response, arrays)
	if endpoint.shape == "project" then return project(value) end
	if value == nil then return {success = true} end
	if endpoint.shape == "deployment" then return deployment(value) end
	if endpoint.shape == "deployments" and type(value.deployments) == "table" then deployments(value.deployments) end
	if endpoint.shape == "projects" then
		local projects = if list then value else value.projects
		if type(projects) ~= "table" then fail(name, response, "Vercel returned an invalid project list") end
		for index, item in projects do projects[index] = project(item) end
		if list then return {projects = projects} end
	end
	return value
end

local function request(name: string, endpoint: Endpoint, input: Options?): any
	assert(TEAM_VALID or endpoint.team == false, "The connection's Vercel team must be a team ID or slug")
	local args = options(input)
	local path = string.gsub(endpoint.path, "{([%w_]+)}", function(field: string)
		local value = args[field]
		args[field] = nil
		assert(value ~= nil and value ~= NULL, field .. " is required")
		assert(type(value) == "string", field .. " must be a string")
		local ok, segment = pcall(url.segment, value, field)
		assert(ok, field .. " must be a Vercel ID, name or hostname")
		return segment
	end)
	for _, field in endpoint.required or NONE do
		assert(args[field] ~= nil and args[field] ~= NULL, field .. " is required")
	end
	local query: {string} = {}
	for _, field in endpoint.query or NONE do
		if args[field] ~= nil then
			local parts = queryParts(args[field], field)
			-- projectIds repeats its key; other array filters (state, users) are comma-separated.
			if field == "projectIds" then
				for _, part in parts do table.insert(query, field .. "=" .. part) end
			else
				table.insert(query, field .. "=" .. table.concat(parts, ","))
			end
		end
		args[field] = nil
	end
	-- Build events answer with one JSON array unless followed live.
	if endpoint.shape == "events" then table.insert(query, "follow=0") end
	if TEAM and endpoint.team ~= false then table.insert(query, TEAM) end
	if #query > 0 then path ..= "?" .. table.concat(query, "&") end
	local limit = 100
	if endpoint.shape == "stream" then
		if args.limit ~= nil then
			limit = args.limit
			assert(type(limit) == "number" and limit == math.floor(limit) and limit >= 1 and limit <= 1000, "limit must be an integer from 1 to 1000")
		end
		args.limit = nil
	end
	if endpoint.fields then
		for field in args do assert(table.find(endpoint.fields :: {string}, field), name .. " has no option " .. field) end
	end
	local headers: HttpHeaders = {Accept = {if endpoint.shape == "stream" then "application/stream+json" else "application/json"}}
	local body: string? = nil
	if hasBody(endpoint) then
		headers["Content-Type"] = {"application/json"}
		body = json.encode(args)
		args = {}
	end
	local unknown = next(args)
	assert(unknown == nil, name .. " has no option " .. tostring(unknown))
	local call: HttpRequest = {url = API .. path, method = endpoint.method, headers = headers, body = body}
	if endpoint.shape == "stream" then
		call.timeoutMs = HEADERS_WAIT
		local ok, response = pcall(function(): any return await(http.request(call)) end)
		if not ok then
			if not timedOut(response) then error(response, 0) end
			return houston.fail({operation = name, layer = "upstream", upstream_status = 0, retryable = true,
				message = "Vercel did not start the runtime log stream within " .. HEADERS_WAIT // 1000 .. " seconds"})
		end
		return stream(name, response, limit)
	end
	return decode(name, endpoint, await(http.request(call)))
end

local intro = {
	"Vercel REST API. Every function takes one named options object with Vercel's camelCase names. Results are Vercel's JSON unchanged, except that projects keep only their main fields (id, name, framework, build settings, git link, crons, latest and production deployments) and deployment meta drops keys named like hooks, tokens, secrets, passwords, keys or credentials. Connector calls return completed values: use them directly, without await.",
	"Ids: projects prj_..., deployments dpl_..., teams team_...; idOrName also takes a project name, and idOrUrl and the runtime log deploymentId a deployment hostname such as my-app-abc123.vercel.app. Times are Unix milliseconds."
		.. (if TEAM then " Requests act on the connection's team." else " Requests act on the token's own scope: its team for a team token, else the personal account."),
	"Lists return one page with {pagination={count, next, prev}}; while next is not null, pass it as until for the next page (listProjects: as from), keeping the same filters. limit bounds and defaults depend on the operation. JSON null is truthy in Luau: compare next with json.decode('null') before continuing.",
	"listRuntimeLogs listens to the live stream until a second passes without new lines (at most about 23 seconds, or 14 network reads) and returns the lines written meanwhile; Vercel offers no history through it, so an empty result does not mean the deployment logged nothing. ended=false means the stream was still open; truncated=true means more lines were likely coming, so call again for them. Use listBuildLogs for build output.",
	"Examples: local page = vercel.listDeployments({projectId='my-app', target='production', limit=10}); local d = page.deployments[1]; vercel.getDeployment({idOrUrl=d.uid}); vercel.listBuildLogs({idOrUrl=d.uid, limit=500, direction='backward'}); vercel.listRuntimeLogs({projectId=d.projectId, deploymentId=d.uid, limit=200}).",
	"The token's own permissions and the team's plan still apply. Rate limits are per endpoint group, such as 100 runtime log reads a minute; Houston retries an HTTP 429 twice, then reports when the limit resets. Errors report the HTTP status with Vercel's error code and message.",
}
if config.access == "read-write" then
	table.insert(intro, "Side effects: redeploy builds and, with target='production', serves the result; promoteDeployment and rollbackDeployment switch production traffic at once. Environment variable changes apply to new deployments only. Other failures are not retried: after a timeout or 5xx, list deployments or variables before repeating a write.")
else
	table.insert(intro, "This read-only connection omits writes and environment variables, whose values are secrets.")
end

local text, flag = {type = "string"}, {type = "boolean"}
local nullableText = {type = {"string", "null"}}
local integer = {type = "integer"}
local timestamp = {type = "integer", minimum = 0, description = "Unix time in milliseconds."}
local segment = {type = "string", minLength = 1, pattern = "^[^/?#\\\\\\x00-\\x20]+$", ["not"] = {enum = {".", ".."}},
	description = "A Vercel ID, name or hostname, as one URL path segment. Hostnames omit the scheme."}
local booleanQuery = {enum = {true :: any, false, "true", "false"}, description = "Boolean or its string spelling; sent as a query value."}
local binaryQuery = {enum = {0 :: any, 1, "0", "1"}}
local function choice(values: {string}): any return {type = "string", enum = values} end
local function list(item: any): any return {type = "array", items = item} end
local function record(properties: Options): any return {type = "object", properties = properties, additionalProperties = true} end
local function repeated(item: any): any return {anyOf = {item, {type = "array", minItems = 1, items = item}}} end
local queries: Options = {
	limit = {type = "integer", minimum = 1, description = "Maximum items per page; provider defaults and caps depend on the operation."},
	since = timestamp, ["until"] = timestamp, from = {type = {"string", "integer"}, description = "The previous page's pagination.next timestamp or continuation token."},
	search = {type = "string", maxLength = 100}, repo = text, repoId = {type = {"string", "integer"}}, repoUrl = text, excludeRepos = text,
	production = booleanQuery, target = text, customEnvironmentId = text, gitBranch = {type = "string", maxLength = 250}, redirects = booleanQuery,
	redirect = text, verified = booleanQuery, order = choice({"ASC", "DESC"}), projectId = text,
	projectIds = {anyOf = {text, {type = "array", items = text, minItems = 1, maxItems = 20}}}, app = text,
	state = {anyOf = {{type = "string", pattern = "^(BUILDING|ERROR|INITIALIZING|QUEUED|READY|CANCELED|BLOCKED)(,(BUILDING|ERROR|INITIALIZING|QUEUED|READY|CANCELED|BLOCKED))*$"} :: any,
		{type = "array", minItems = 1, items = choice({"BUILDING", "ERROR", "INITIALIZING", "QUEUED", "READY", "CANCELED", "BLOCKED"})}}},
	branch = text, sha = text, users = repeated(text), rollbackCandidate = booleanQuery, withGitRepoInfo = booleanQuery,
	direction = choice({"forward", "backward"}), name = text, statusCode = {type = {"integer", "string"}, description = "One HTTP status or range such as 5xx."},
	builds = binaryQuery, failedOnly = booleanQuery, projectIdOrName = text, strict = booleanQuery, forceNew = binaryQuery, description = text,
	decrypt = booleanQuery, source = text, customEnvironmentSlug = text, upsert = booleanQuery,
}
local environment: Options = {
	key = {type = "string", description = "Environment variable name."}, value = {type = "string", description = "Value for new deployments. Do not print secret values."},
	type = choice({"system", "encrypted", "plain", "sensitive"}), target = list(choice({"production", "preview", "development"})),
	gitBranch = {type = {"string", "null"}, maxLength = 250, description = "Branch override requires the preview target; null clears it."},
	comment = {type = "string", maxLength = 500}, customEnvironmentIds = list(text),
}
local redeployFields: Options = {name = {type = "string", minLength = 1}, deploymentId = text, target = text, withLatestCommit = flag,
	meta = {type = "object", maxProperties = 100, additionalProperties = {type = "string", maxLength = 65536}, description = "Deployment metadata, string values keyed by name."}}
local deploymentSchema = record({id = text, uid = text, name = text, url = text, readyState = text, state = text, target = nullableText,
	createdAt = timestamp, created = timestamp, errorMessage = nullableText, meta = {type = "object", additionalProperties = true}})
local projectProperties: Options = {}
for _, field in PROJECT_FIELDS do
	projectProperties[field] = if field == "latestDeployments" then list(deploymentSchema)
		elseif field == "targets" then {type = "object", additionalProperties = deploymentSchema}
		elseif field == "link" or field == "crons" then {type = {"object", "null"}}
		elseif field == "createdAt" or field == "updatedAt" then timestamp
		elseif field == "live" or field == "paused" then flag
		else nullableText
end
local projectSchema = {type = "object", properties = projectProperties, additionalProperties = false}
local pagination = record({count = integer, next = {type = {"integer", "string", "null"}}, prev = {type = {"integer", "string", "null"}}})
local envSchema = record({id = text, key = text, value = nullableText, type = text, target = list(text), gitBranch = nullableText, decrypted = flag})
local outputs: Options = {
	getUser = record({user = record({id = text, email = text, name = nullableText, avatar = nullableText})}),
	getProject = projectSchema, listProjects = record({projects = list(projectSchema), pagination = pagination}),
	getDeployment = deploymentSchema, listDeployments = record({deployments = list(deploymentSchema), pagination = pagination}),
	redeploy = deploymentSchema, cancelDeployment = deploymentSchema,
	listRuntimeLogs = {type = "object", properties = {logs = list(record({timestampInMs = timestamp, level = text, message = text,
		source = text, requestMethod = text, requestPath = text, responseStatusCode = integer, domain = text})), ended = flag, truncated = flag},
		required = {"logs", "ended", "truncated"}, additionalProperties = false},
	listEnvVars = record({envs = list(envSchema)}), getEnvVar = envSchema,
	createEnvVar = record({created = envSchema, failed = list(record({key = text, error = record({code = text, message = text})}))}),
	updateEnvVar = envSchema, promoteDeployment = record({success = flag}), rollbackDeployment = record({success = flag}),
	getProjectDomain = record({name = text, apexName = text, verified = flag, redirect = nullableText, gitBranch = nullableText}),
	getDomain = record({domain = record({name = text, verified = flag, nameservers = list(text)})}),
	getDomainConfig = record({misconfigured = flag, configuredBy = nullableText, recommendedCNAME = list(record({rank = integer, value = text})),
		recommendedIPv4 = list(record({rank = integer, value = list(text)}))}),
}
for name, field in ({listTeams = "teams", listProjectDomains = "domains", listDomains = "domains", listPromoteAliases = "aliases"} :: {[string]: string}) do
	outputs[name] = record({[field] = list(record({})), pagination = pagination})
end
local docs: Options = {}
for name, endpoint in endpoints do
	local properties: Options, required: {string} = {}, {}
	for field in string.gmatch(endpoint.path, "{([%w_]+)}") do
		properties[field] = segment
		table.insert(required, field)
	end
	for _, field in endpoint.query or NONE do
		local schema = queries[field]
		assert(schema, "missing query schema for " .. name .. "." .. field)
		if field == "limit" and name == "listBuildLogs" then schema = {type = "integer", minimum = -1, description = "-1 requests all build events; prefer a finite limit to stay under the 8 MiB response bound."}
		elseif field == "limit" and (name == "listProjectDomains" or name == "listPromoteAliases") then schema = {type = "integer", minimum = 1, maximum = 100}
		elseif field == "target" and name == "listProjectDomains" then schema = choice({"production", "preview"}) end
		properties[field] = schema
	end
	local bodyFields = if name == "redeploy" then redeployFields elseif hasBody(endpoint) then environment else nil
	if bodyFields then
		for field, schema in bodyFields do properties[field] = schema end
	end
	for _, field in endpoint.required or NONE do table.insert(required, field) end
	if name == "createEnvVar" then
		for _, field in {"key", "value", "type"} do table.insert(required, field) end
	end
	if endpoint.shape == "stream" then properties.limit = {type = "integer", minimum = 1, maximum = 1000, default = 100} end
	local schema: any = {type = "object", properties = properties, required = if #required > 0 then required else nil,
		additionalProperties = hasBody(endpoint) and endpoint.fields == nil, examples = {endpoint.example}}
	if name == "createEnvVar" then schema.anyOf = {{required = {"target"}}, {required = {"customEnvironmentIds"}}}
	elseif name == "listDeployments" then schema["not"] = {required = {"projectId", "projectIds"}} end
	local description = if name == "listRuntimeLogs" then intro[4] elseif writes(endpoint) then intro[7] else nil
	if name == "listEnvVars" or name == "getEnvVar" then description = "This read requires read-write connection access because the response can contain secret values." end
	docs[name] = {inputSchema = schema, outputSchema = outputs[name], description = description,
		annotations = {readOnlyHint = endpoint.method == "GET", destructiveHint = endpoint.method ~= "GET",
			idempotentHint = endpoint.method == "GET" or name == "deleteEnvVar" or name == "updateEnvVar"}}
end
local exports = operations(endpoints, request, {intro[1], intro[2], intro[7]}, docs)
local help = exports.help
help.sections = {paging = intro[3], logs = intro[4], workflow = intro[5], errors = intro[6]}
exports.help = help
return exports
