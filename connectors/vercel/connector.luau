-- Vercel REST API. Arguments and results keep Vercel's native camelCase field names.
type Options = {[string]: any}
type Endpoint = {method: string, path: string, query: {string}?, extra: {string}?, required: {string}?, write: boolean?, body: (boolean | string)?,
	fields: {string}?, team: boolean?, shape: string?, doc: string, about: string}

local PROVIDER = "Vercel"
local API = "https://api.vercel.com"
local DOCS = "https://vercel.com/docs/rest-api/"
local PAGE = {"limit", "since", "until"}

-- Operations in Vercel's public OpenAPI (https://openapi.vercel.sh), checked on 2026-10-27.
-- Path {fields} are required; listed query fields are taken from the options and the other
-- fields form the JSON body. Requests carry the connection's team unless team is false.
local endpoints: {[string]: Endpoint} = {
	getUser = {method = "GET", path = "/v2/user", team = false, doc = "user/get-the-user", about = "The token's user, {user}."},
	listTeams = {method = "GET", path = "/v2/teams", query = PAGE, team = false, doc = "teams/list-all-teams",
		about = "Teams the token can access, {teams, pagination}."},

	listProjects = {method = "GET", path = "/v10/projects", query = {"search", "repo", "repoId", "repoUrl", "excludeRepos", "limit", "from"},
		shape = "projects", doc = "projects/retrieve-a-list-of-projects",
		about = "Projects, {projects, pagination}; search matches names. Page with from=pagination.next."},
	getProject = {method = "GET", path = "/v9/projects/{idOrName}", shape = "project", doc = "projects/find-a-project-by-id-or-name",
		about = "A project by id (prj_...) or name, with its git link, crons and latest and production deployments."},
	listProjectDomains = {method = "GET", path = "/v9/projects/{idOrName}/domains",
		query = {"production", "target", "customEnvironmentId", "gitBranch", "redirects", "redirect", "verified", "order", "limit", "since", "until"},
		doc = "projects/retrieve-project-domains-by-project-by-id-or-name",
		about = "A project's domains with their redirects and verification, {domains, pagination}. target: production or preview; limit at most 100."},
	getProjectDomain = {method = "GET", path = "/v9/projects/{idOrName}/domains/{domain}", doc = "projects/get-a-project-domain", about = "One domain of a project."},

	listDeployments = {method = "GET", path = "/v7/deployments",
		query = {"projectId", "projectIds", "app", "target", "state", "branch", "sha", "users", "rollbackCandidate", "limit", "since", "until"},
		shape = "deployments", doc = "deployments/list-deployments",
		about = "Deployments, newest first, {deployments, pagination}. projectId takes an id or name; target: production or preview; state: BUILDING, ERROR, INITIALIZING, QUEUED, READY, CANCELED or BLOCKED (comma-separated or an array)."},
	getDeployment = {method = "GET", path = "/v13/deployments/{idOrUrl}", query = {"withGitRepoInfo"}, shape = "deployment", doc = "deployments/get-a-deployment-by-id-or-url",
		about = "A deployment by id (dpl_...) or hostname, with readyState, target, url, alias, errorMessage and git metadata."},
	listBuildLogs = {method = "GET", path = "/v3/deployments/{idOrUrl}/events", query = {"limit", "direction", "since", "until", "name", "statusCode", "builds"},
		shape = "events", doc = "deployments/get-deployment-events",
		about = "A deployment's build events as an array of {type, created, text, level?, info, payload}. limit=-1 returns all; direction: forward (default) or backward; builds=1 adds build steps."},
	listRuntimeLogs = {method = "GET", path = "/v1/projects/{projectId}/deployments/{deploymentId}/runtime-logs", extra = {"limit"},
		shape = "stream", doc = "logs/get-logs-for-a-deployment",
		about = "Live request and function logs written while listening for a few seconds, {logs, ended}: each {timestampInMs, level, message, source, requestMethod, requestPath, responseStatusCode, domain}. limit is 1..1000 lines (default 100)."},
	listPromoteAliases = {method = "GET", path = "/v1/projects/{projectId}/promote/aliases", query = {"failedOnly", "limit", "since", "until"},
		doc = "projects/gets-a-list-of-aliases-with-status-for-the-current-promote",
		about = "Progress of the project's current promotion, {aliases, pagination}."},

	listDomains = {method = "GET", path = "/v5/domains", query = PAGE, doc = "domains/list-all-the-domains", about = "Domains, {domains, pagination}."},
	getDomain = {method = "GET", path = "/v5/domains/{domain}", doc = "domains/get-information-for-a-single-domain",
		about = "A domain with its verification, nameservers and renewal."},
	getDomainConfig = {method = "GET", path = "/v6/domains/{domain}/config", query = {"projectIdOrName", "strict"}, doc = "domains/get-a-domain-s-configuration",
		about = "Whether a domain's DNS points at Vercel: misconfigured, configuredBy and the recommended records."},

	redeploy = {method = "POST", path = "/v13/deployments", query = {"forceNew"}, required = {"name", "deploymentId"},
		fields = {"name", "deploymentId", "target", "withLatestCommit", "meta"}, shape = "deployment", doc = "deployments/create-a-new-deployment",
		about = "Body {name (project name), deploymentId, target?, withLatestCommit?, meta?}. Rebuilds deploymentId's source as a new deployment. target: production, staging or a custom environment id; without it, a preview. forceNew=1 deploys even when an identical deployment exists."},
	promoteDeployment = {method = "POST", path = "/v10/projects/{projectId}/promote/{deploymentId}", body = false, doc = "projects/point-production-traffic-to-a-given-deployment",
		about = "Serves production traffic from a deployment without rebuilding; follow progress with listPromoteAliases."},
	rollbackDeployment = {method = "POST", path = "/v1/projects/{projectId}/rollback/{deploymentId}", query = {"description"}, body = false,
		doc = "projects/point-production-traffic-to-a-previous-production-deployment-by-id",
		about = "Points production back to an earlier production deployment and pauses automatic promotion until a later promote."},
	cancelDeployment = {method = "PATCH", path = "/v12/deployments/{id}/cancel", body = false, shape = "deployment", doc = "deployments/cancel-a-deployment",
		about = "Cancels a queued or building deployment."},

	listEnvVars = {method = "GET", path = "/v10/projects/{idOrName}/env", write = true,
		query = {"decrypt", "gitBranch", "source", "customEnvironmentId", "customEnvironmentSlug"}, doc = "projects/retrieve-the-environment-variables-of-a-project-by-id-or-name",
		about = "A project's environment variables, {envs}: {id, key, type, target, gitBranch?, value?}. Values of plain variables are included; decrypt='true' also decrypts encrypted ones. Sensitive values are never returned."},
	getEnvVar = {method = "GET", path = "/v1/projects/{idOrName}/env/{id}", write = true,
		doc = "projects/retrieve-the-decrypted-value-of-an-environment-variable-of-a-project-by-id", about = "One variable with its decrypted value."},
	createEnvVar = {method = "POST", path = "/v10/projects/{idOrName}/env", query = {"upsert"}, doc = "projects/create-one-or-more-environment-variables",
		about = "Body {key, value, type, target, gitBranch?, comment?, customEnvironmentIds?}. type: plain, encrypted or sensitive; target: an array of production, preview and development. upsert='true' replaces an existing key. Redeploy for running deployments to see changes."},
	updateEnvVar = {method = "PATCH", path = "/v9/projects/{idOrName}/env/{id}", doc = "projects/edit-an-environment-variable",
		about = "Body: the createEnvVar fields to change."},
	deleteEnvVar = {method = "DELETE", path = "/v9/projects/{idOrName}/env/{id}", query = {"customEnvironmentId"}, doc = "projects/remove-an-environment-variable",
		about = "Deletes a variable."},
}

-- Request layer shared verbatim by the Cal.com, Calendly, Carta, Carta CRM, Gusto, Resend and Vercel connectors
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

-- name({path fields, query fields?, extra fields?, required body fields, ...body}) built from the
-- endpoint itself.
-- Extra fields are options the connector's own request consumes, such as a request header.
local function signature(endpoint: Endpoint): string
	local fields: {string} = {}
	for field in string.gmatch(endpoint.path, "{([%w_]+)}") do table.insert(fields, field) end
	for _, group in {endpoint.query or NONE, endpoint.extra or NONE} do
		for _, field in group do
			table.insert(fields, if table.find(endpoint.required or NONE, field) then field else field .. "?")
		end
	end
	if type(endpoint.body) == "string" then
		table.insert(fields, endpoint.body)
	elseif hasBody(endpoint) then
		for _, field in endpoint.required or NONE do
			if not table.find(fields, field) then table.insert(fields, field) end
		end
		table.insert(fields, "...body")
	end
	return "({" .. table.concat(fields, ", ") .. "})"
end

-- A function for each endpoint the connection's access allows, and help listing them after intro.
local function operations(endpoints: {[string]: Endpoint}, request: (string, Endpoint, Options?) -> any, intro: {string}): {[string]: any}
	local exports: {[string]: any} = {}
	for name, endpoint in endpoints do
		if not writes(endpoint) or config.access == "read-write" then
			exports[name] = function(args: Options?): any return request(name, endpoint, args) end
		end
	end
	exports.help = function(): string
		local names: {string} = {}
		for name in exports do if name ~= "help" then table.insert(names, name) end end
		table.sort(names)
		local lines = table.clone(intro)
		table.insert(lines, "Each function below names its route and reference page, " .. DOCS .. "<page>.")
		for _, name in names do
			local endpoint = endpoints[name]
			table.insert(lines, name .. signature(endpoint) .. ": " .. endpoint.about .. " " .. endpoint.method .. " " .. endpoint.path .. " (" .. endpoint.doc .. ")")
		end
		return table.concat(lines, "\n")
	end
	return exports
end
-- End of the shared request layer.

-- The connection's team, by id (team_...) or slug; without one, the token's own scope applies.
local TEAM: string? = nil
if type(config.team) == "string" and config.team ~= "" then
	local team = string.lower(config.team)
	assert(string.match(team, "^[%w_%-]+$"), "The Vercel team must be a team ID or slug")
	TEAM = if string.sub(team, 1, 5) == "team_" then "teamId=" .. config.team else "slug=" .. team
end

-- Deployment meta can name the deploy hook that started a build, and a hook's id completes its
-- unauthenticated trigger URL, so deployments drop those fields.
local function deployment(value: any): any
	if type(value) == "table" and type(value.meta) == "table" then
		local meta: Options = {}
		for key, item in value.meta do
			if type(key) ~= "string" or string.find(string.lower(key), "deployhook", 1, true) == nil then meta[key] = item end
		end
		value.meta = meta
	end
	return value
end

local function deployments(list: any): any
	if type(list) == "table" then
		for index, item in list do list[index] = deployment(item) end
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
		if type(kept.targets) == "table" then
			for target, item in kept.targets do kept.targets[target] = deployment(item) end
		end
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
-- most HEADERS_WAIT + FIRST_WAIT + (MAX_READS - 1) * IDLE_WAIT, about 23 seconds.
local HEADERS_WAIT, FIRST_WAIT, IDLE_WAIT, MAX_READS, MAX_LINE = 5000, 3000, 250, 60, 256 * 1024

local function timedOut(err: any): boolean
	if type(err) == "table" then return err.code == "timeout" end
	return string.find(tostring(err), "timed out", 1, true) ~= nil
end

local function stream(name: string, response: HttpResponse, limit: number): any
	if response.statusCode ~= 200 then failStatus(name, response) end
	local logs: {any} = json.decode("[]")
	local pending, ended = "", false
	for read = 1, MAX_READS do
		local ok, chunk = pcall(function(): any return await(response.body:read(64 * 1024), if read == 1 then FIRST_WAIT else IDLE_WAIT) end)
		if not ok then
			if timedOut(chunk) then break end
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
				if not decoded or type(entry) ~= "table" then fail(name, response, "Vercel returned an invalid log line") end
				table.insert(logs, entry)
			end
		end
		pending = string.sub(pending, start)
		if ended or #logs >= limit then break end
		if #pending > MAX_LINE then fail(name, response, "Vercel returned a log line over " .. MAX_LINE .. " bytes") end
	end
	pcall(function() response.body:close() end)
	return {logs = logs, ended = ended}
end

local function decode(name: string, endpoint: Endpoint, response: HttpResponse): any
	if response.statusCode < 200 or response.statusCode >= 300 then failStatus(name, response) end
	-- Build events, project lists (on older accounts) and deletions can answer with an array.
	local arrays = endpoint.shape == "events" or endpoint.shape == "projects" or endpoint.method == "DELETE"
	local value, list = object(name, endpoint, response, arrays)
	if endpoint.shape == "project" then return project(value) end
	if endpoint.shape == "deployment" then return deployment(value) end
	if endpoint.shape == "deployments" and type(value.deployments) == "table" then deployments(value.deployments) end
	if endpoint.shape == "projects" then
		local projects = if list then value else value.projects
		if type(projects) ~= "table" then fail(name, response, "Vercel returned an invalid project list") end
		for index, item in projects do projects[index] = project(item) end
		if list then return {projects = projects} end
	end
	-- Promotions, cancellations and deletions may answer without a body.
	return value or {success = true}
end

local function request(name: string, endpoint: Endpoint, input: Options?): any
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
		return stream(name, await(http.request(call)), limit)
	end
	return decode(name, endpoint, await(http.request(call)))
end

local intro = {
	"Vercel REST API. Every function takes one named options object with Vercel's camelCase names; ? marks optional fields and ...body the JSON body fields. Results are Vercel's JSON unchanged, except that projects omit environment variables and secrets, and deployment meta omits deploy hook ids. Connector calls return completed values: use them directly, without await.",
	"Ids: projects prj_..., deployments dpl_..., teams team_...; idOrName also takes a project name, and idOrUrl and the runtime log deploymentId a deployment hostname such as my-app-abc123.vercel.app. Times are Unix milliseconds."
		.. (if TEAM then " Requests act on the connection's team." else " Requests act on the token's own scope: its team for a team token, else the personal account."),
	"Lists return one page: limit (default 20, at most 100) and {pagination={count, next, prev}}; while next is not null, pass it as until for the next page (listProjects: as from).",
	"listRuntimeLogs listens to the live stream for a few seconds and returns the lines written meanwhile; Vercel offers no history through it, so an empty result does not mean the deployment logged nothing. ended=false means the stream was still open. Use listBuildLogs for build output.",
	"Examples: local page = vercel.listDeployments({projectId='my-app', target='production', limit=10}); local d = page.deployments[1]; vercel.getDeployment({idOrUrl=d.uid}); vercel.listBuildLogs({idOrUrl=d.uid, limit=-1}); vercel.listRuntimeLogs({projectId=d.projectId, deploymentId=d.uid, limit=200}).",
	"The token's own permissions and the team's plan still apply. Rate limits are per endpoint group, such as 100 runtime log reads a minute; Houston retries an HTTP 429 twice, then reports when the limit resets. Errors report the HTTP status with Vercel's error code and message.",
}
if config.access == "read-write" then
	table.insert(intro, "Side effects: redeploy builds and, with target='production', serves the result; promoteDeployment and rollbackDeployment switch production traffic at once. Environment variable changes apply to new deployments only. Other failures are not retried: after a timeout or 5xx, list deployments or variables before repeating a write.")
else
	table.insert(intro, "This read-only connection omits writes and environment variables, whose values are secrets.")
end

return operations(endpoints, request, intro)
