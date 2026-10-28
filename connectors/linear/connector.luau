-- Linear GraphQL API. Arguments and results keep Linear's native field names.
type Options = {[string]: any}
type Operation = {field: string, args: {string}, select: string, connection: boolean?, page: string?, write: boolean?, about: string}

local API = "https://api.linear.app/graphql"
local DOCS = "https://linear.app/developers/graphql"
local NULL = json.decode("null")
local MAX_PAGE = 250
local MAX_DOCUMENT = 64 * 1024
local MAX_URL = 8 * 1024

-- Read-only connections send queries with GET, which Linear refuses for mutations (HTTP 405),
-- and the manifest allows POST only on read-write connections.
local WRITES = config.access == "read-write"

-- Fields each operation selects; on read-write connections graphql() reaches the others.
local TEAM_REF = "team { id key name }"
local PERSON = "{ id name displayName }"
local USER = "id name displayName email active admin guest url timezone createdAt"
local TEAM = "id key name displayName description icon color timezone cyclesEnabled createdAt updatedAt archivedAt"
local STATE = "id name type color position description " .. TEAM_REF
local LABEL = "id name color description isGroup parent { id name } " .. TEAM_REF .. " createdAt updatedAt archivedAt"
local PROJECT = "id name slugId url description icon color priority priorityLabel progress health startDate targetDate startedAt completedAt "
	.. "canceledAt createdAt updatedAt archivedAt status { id name type } lead " .. PERSON .. " teams(first: 10) { nodes { id key name } }"
local CYCLE = "id number name description startsAt endsAt completedAt isActive isNext isPrevious progress " .. TEAM_REF .. " createdAt updatedAt archivedAt"
local ISSUE = "id identifier number title priority priorityLabel estimate dueDate url branchName createdAt updatedAt startedAt completedAt "
	.. "canceledAt archivedAt state { id name type } " .. TEAM_REF .. " assignee " .. PERSON .. " creator " .. PERSON
	.. " project { id name } cycle { id number name } parent { id identifier title } labels(first: 10) { nodes { id name } }"
local COMMENT = "id body url createdAt updatedAt editedAt resolvedAt parentId user " .. PERSON .. " issue { id identifier title }"

-- Arguments of a Linear connection field, filtered by the given filter type.
local function list(filter: string, ...: string): {string}
	local args = {"filter: " .. filter, "first: Int", "after: String", "last: Int", "before: String", "includeArchived: Boolean", "orderBy: PaginationOrderBy"}
	for _, extra in {...} do table.insert(args, extra) end
	return args
end

-- Query and Mutation fields of Linear's public schema (packages/sdk/src/schema.graphql), checked
-- on 2026-10-27.
local operations: {[string]: Operation} = {
	getViewer = {field = "viewer", args = {}, select = USER .. " organization { id name urlKey }",
		about = "You, with your workspace's id, name and urlKey."},
	listUsers = {field = "users", args = list("UserFilter", "includeDisabled: Boolean"), select = USER, connection = true,
		about = "Workspace members. Filter by name, displayName, email or isMe, as {email={eq='ada@example.com'}}."},
	listTeams = {field = "teams", args = list("TeamFilter"), select = TEAM, connection = true, about = "Teams you can access."},
	getTeam = {field = "team", args = {"id: String!"}, select = TEAM, about = "A team."},
	listWorkflowStates = {field = "workflowStates", args = list("WorkflowStateFilter"), select = STATE, connection = true,
		about = "Issue statuses, as {team={key={eq='ENG'}}}. type: triage, backlog, unstarted, started, completed or canceled."},
	listLabels = {field = "issueLabels", args = list("IssueLabelFilter"), select = LABEL, connection = true,
		about = "Issue labels. Workspace labels have team null; group labels (isGroup) hold child labels."},
	listProjects = {field = "projects", args = list("ProjectFilter"), select = PROJECT, connection = true,
		about = "Projects, as {status={type={eq='started'}}} or {accessibleTeams={some={key={eq='ENG'}}}}."},
	getProject = {field = "project", args = {"id: String!"}, select = PROJECT .. " content", about = "A project by id or slugId, with its content in Markdown."},
	listCycles = {field = "cycles", args = list("CycleFilter"), select = CYCLE, connection = true,
		about = "Cycles, as {team={key={eq='ENG'}}, isActive={eq=true}}."},
	getCycle = {field = "cycle", args = {"id: String!"}, select = CYCLE, about = "A cycle."},
	listIssues = {field = "issues", args = list("IssueFilter"), select = ISSUE, connection = true,
		about = "Issues, without descriptions; see Filters."},
	searchIssues = {field = "searchIssues", args = list("IssueFilter", "term: String!", "teamId: String", "includeComments: Boolean"),
		select = ISSUE, connection = true, page = "totalCount", about = "Full-text search over titles and descriptions (and comments with includeComments), with totalCount."},
	getIssue = {field = "issue", args = {"id: String!"},
		select = ISSUE .. " description children { nodes { id identifier title state { id name type } } }",
		about = "An issue by id or identifier such as ENG-123, with its Markdown description and sub-issues."},
	listComments = {field = "comments", args = list("CommentFilter"), select = COMMENT, connection = true,
		about = "Comments in Markdown, as {issue={id={eq=issue.id}}}. parentId marks a reply."},

	createIssue = {field = "issueCreate", args = {"input: IssueCreateInput!"}, select = "success issue { " .. ISSUE .. " }", write = true,
		about = "input {teamId, title, description?, stateId?, assigneeId?, priority?, labelIds?, projectId?, cycleId?, parentId?, dueDate?, estimate?}. Returns {success, issue}."},
	updateIssue = {field = "issueUpdate", args = {"id: String!", "input: IssueUpdateInput!"}, select = "success issue { " .. ISSUE .. " }", write = true,
		about = "input: the fields to change, such as stateId, assigneeId (null unassigns), priority, labelIds (replaces), addedLabelIds, removedLabelIds, title or description."},
	createComment = {field = "commentCreate", args = {"input: CommentCreateInput!"}, select = "success comment { " .. COMMENT .. " }", write = true,
		about = "input {issueId, body (Markdown), parentId? to reply}. Returns {success, comment}."},
}

local function fail(name: string, status: number, retryable: boolean, message: string): never
	return houston.fail({operation = name, layer = "upstream", upstream_status = status, retryable = retryable, message = message})
end

-- Linear errors are {errors: [{message, extensions: {code, userPresentableMessage?}}]}, with HTTP
-- 400 for invalid queries, 401 for credentials and 429 (code RATELIMITED) with Retry-After and
-- the hourly windows' reset times in Unix milliseconds.
local RESETS = {"retry-after", "x-ratelimit-requests-reset", "x-ratelimit-complexity-reset"}

local function failed(name: string, response: HttpResponse, body: any, raw: string): never
	local status = response.statusCode
	local retryable = status == 429 or status >= 500
	local messages: {string} = {}
	if type(body) == "table" and type(body.errors) == "table" then
		for index, item in body.errors do
			if type(index) ~= "number" or index > 3 or type(item) ~= "table" then continue end
			local extensions = if type(item.extensions) == "table" then item.extensions else {}
			local code = if type(extensions.code) == "string" then extensions.code .. ": " else ""
			local text = if type(extensions.userPresentableMessage) == "string" then extensions.userPresentableMessage else item.message
			if code == "RATELIMITED: " then retryable = true end
			table.insert(messages, code .. string.sub(if type(text) == "string" then text else "error", 1, 600))
		end
	end
	local message = "Linear HTTP " .. tostring(status) .. ": "
		.. (if #messages > 0 then table.concat(messages, "; ") else string.sub(raw, 1, 600))
	if retryable then
		for _, header in RESETS do
			local values = response.headers[header]
			if values and values[1] then message ..= "; " .. header .. " " .. string.sub(values[1], 1, 100) end
		end
	end
	return fail(name, status, retryable, message)
end

-- Linear's whole response, {data, errors?}. GraphQL can answer data with errors, such as for
-- nested items the caller cannot see; errors without data fail.
local function execute(name: string, document: string, variables: Options, operationName: string?): any
	local headers: HttpHeaders = {Accept = {"application/json"}}
	local call: HttpRequest
	if WRITES then
		headers["Content-Type"] = {"application/json"}
		call = {method = "POST", url = API, headers = headers, body = json.encode({query = document, variables = variables, operationName = operationName})}
	else
		-- Linear's CSRF protection needs this header on GET requests.
		headers["apollo-require-preflight"] = {"true"}
		local query = "?query=" .. url.encode(document)
		if next(variables) ~= nil then query ..= "&variables=" .. url.encode(json.encode(variables)) end
		assert(#API + #query <= MAX_URL, "The query is too large for a read-only connection, which sends it in the URL; narrow the filter")
		call = {method = "GET", url = API .. query, headers = headers}
	end
	local response = await(http.request(call))
	local success = response.statusCode >= 200 and response.statusCode < 300
	local raw = await(if success then response.body:readAll() else response.body:readPrefix(16 * 1024))
	local ok, body = pcall(json.decode, raw)
	if not ok then body = nil end
	if not success then failed(name, response, body, raw) end
	if type(body) ~= "table" or type(body.data) ~= "table" then
		if type(body) == "table" and type(body.errors) == "table" and #body.errors > 0 then failed(name, response, body, raw) end
		fail(name, response.statusCode, false, "Linear returned an invalid GraphQL response")
	end
	return body
end

local function options(input: Options?): Options
	if input == nil then return {} end
	assert(type(input) == "table", "opts must be an object")
	for key in input do assert(type(key) == "string", "opts must have named fields") end
	return table.clone(input)
end

local function object(value: any, field: string)
	assert(type(value) == "table", field .. " must be an object")
	local key = next(value)
	assert(key == nil or type(key) == "string", field .. " must be an object, not an array")
end

-- The GraphQL variable an argument receives, checked against its declared base type.
local function variable(value: any, field: string, base: string)
	if base == "Int" then
		assert(type(value) == "number" and value == math.floor(value) and value >= 1 and value <= MAX_PAGE,
			field .. " must be an integer from 1 to " .. MAX_PAGE)
	elseif base == "String" then
		assert(type(value) == "string" and value ~= "", field .. " must be a nonempty string")
	elseif base == "Boolean" then
		assert(type(value) == "boolean", field .. " must be true or false")
	elseif base == "PaginationOrderBy" then
		assert(value == "createdAt" or value == "updatedAt", field .. " must be 'createdAt' or 'updatedAt'")
	else
		object(value, field)
	end
end

-- Argument declarations such as "first: Int" or "id: String!", parsed once per operation.
type Parameter = {field: string, kind: string, base: string, required: boolean}

local function parameters(operation: Operation): {Parameter}
	local parsed: {Parameter} = {}
	for _, arg in operation.args do
		local field, kind = string.match(arg, "^(%w+): (.+)$")
		assert(field and kind, "invalid argument declaration " .. arg)
		table.insert(parsed, {field = field, kind = kind, base = (string.gsub(kind, "!$", "")), required = string.sub(kind, -1) == "!"})
	end
	return parsed
end

local function document(name: string, operation: Operation, params: {Parameter}): string
	local definitions: {string}, uses: {string} = {}, {}
	for _, param in params do
		table.insert(definitions, "$" .. param.field .. ": " .. param.kind)
		table.insert(uses, param.field .. ": $" .. param.field)
	end
	local selection = operation.select
	if operation.connection then
		selection = "nodes { " .. selection .. " } pageInfo { hasNextPage endCursor }" .. (if operation.page then " " .. operation.page else "")
	end
	local head = (if operation.write then "mutation " else "query ") .. name
	if #definitions > 0 then head ..= "(" .. table.concat(definitions, ", ") .. ")" end
	local field = operation.field
	if #uses > 0 then field ..= "(" .. table.concat(uses, ", ") .. ")" end
	return head .. " { " .. field .. " { " .. selection .. " } }"
end

local function signature(params: {Parameter}): string
	local fields: {string} = {}
	for _, param in params do table.insert(fields, if param.required then param.field else param.field .. "?") end
	return if #fields == 0 then "()" else "({" .. table.concat(fields, ", ") .. "})"
end

local function run(name: string, operation: Operation, params: {Parameter}, source: string, input: Options?): any
	local args = options(input)
	local variables: Options = {}
	for _, param in params do
		local value = args[param.field]
		args[param.field] = nil
		if value == nil or value == NULL then
			assert(not param.required, param.field .. " is required")
		else
			variable(value, param.field, param.base)
			variables[param.field] = value
		end
	end
	local unknown = next(args)
	assert(unknown == nil, name .. " has no option " .. tostring(unknown))
	local body = execute(name, source, variables)
	local result = body.data[operation.field]
	if type(body.errors) == "table" and #body.errors > 0 then
		-- Keep a partial result, such as a created issue with an unreadable nested field.
		if type(result) ~= "table" then
			return fail(name, 200, false, "Linear answered " .. operation.field .. " with errors: " .. string.sub(json.encode(body.errors), 1, 600))
		end
		result.errors = body.errors
	end
	return result
end

local exports: {[string]: any} = {}
local signatures: {[string]: string} = {}
for name, operation in operations do
	if not operation.write or WRITES then
		local params = parameters(operation)
		local source = document(name, operation, params)
		signatures[name] = signature(params)
		exports[name] = function(input: Options?): any return run(name, operation, params, source, input) end
	end
end

local function graphql(input: Options?): any
	local args = options(input)
	local source, variables, operationName = args.query, args.variables, args.operationName
	args.query, args.variables, args.operationName = nil, nil, nil
	local unknown = next(args)
	assert(unknown == nil, "graphql has no option " .. tostring(unknown))
	assert(type(source) == "string" and string.find(source, "%S") ~= nil, "query must be a GraphQL document")
	assert(#source <= MAX_DOCUMENT, "query must be at most " .. MAX_DOCUMENT .. " bytes")
	if variables == nil or variables == NULL then variables = {} else object(variables, "variables") end
	assert(operationName == nil or (type(operationName) == "string" and string.match(operationName, "^[_%a][_%w]*$")), "operationName must be a GraphQL name")
	return execute("graphql", source, variables, operationName)
end

-- Arbitrary documents can read webhook signing secrets and SSO settings, so they need read-write.
if WRITES then exports.graphql = graphql end

exports.help = function(): string
	local names: {string} = {}
	for name in operations do if exports[name] then table.insert(names, name) end end
	table.sort(names)
	local lines = {
		"Linear GraphQL API (" .. DOCS .. "). Every function takes one named options object with Linear's field names; ? marks optional fields. Results are Linear's JSON for the queried field, without the data wrapper; when Linear also reports errors, such as for nested items you cannot see, the result carries them as errors. In arguments, pass json.decode('null') to clear a field (such as assigneeId) and json.decode('[]') for an empty list: nil omits the field and {} is an object. Connector calls return completed values: use them directly, without await.",
		"Lists return one page {nodes, pageInfo={hasNextPage, endCursor}}: first is 1.." .. MAX_PAGE .. " (default 50); pass pageInfo.endCursor as after while hasNextPage. orderBy: createdAt (default) or updatedAt. includeArchived=true adds archived items.",
		"Filters use Linear's comparators: eq, neq, in, nin, lt, lte, gt, gte, null, contains, containsIgnoreCase, startsWith; and and/or arrays. Write the Luau keywords in, and, or as ['in'], ['and'], ['or']. Relations nest: {team={key={eq='ENG'}}, state={type={['in']={'unstarted', 'started'}}}, assignee={isMe={eq=true}}, labels={some={name={eq='Bug'}}}, priority={lte=2}}. Dates take ISO 8601 or durations relative to now, as {updatedAt={gt='-P2W'}}.",
		"ids are UUIDs; getIssue and updateIssue also take identifiers such as ENG-123 and getProject a slugId. Issues show their first 10 labels and projects their first 10 teams. priority: 0 none, 1 urgent, 2 high, 3 medium, 4 low. Descriptions and comment bodies are Markdown.",
	}
	for _, name in names do
		local operation = operations[name]
		table.insert(lines, name .. signatures[name] .. ": " .. operation.about)
	end
	table.insert(lines, "Examples: local me = linear.getViewer(); local page = linear.listIssues({filter={assignee={isMe={eq=true}}, state={type={nin={'completed', 'canceled'}}}}, first=50}); linear.getIssue({id='ENG-123'}); linear.listComments({filter={issue={id={eq=issue.id}}}}).")
	if WRITES then
		table.insert(lines, "graphql({query, variables?, operationName?}): any Linear query or mutation document, returning Linear's response {data, errors?}, for fields and operations not listed above, such as attachments, project updates, issue relations or archiving. Schema: https://studio.apollographql.com/public/Linear-API. Example: linear.graphql({query='query($id: String!) { issue(id: $id) { attachments { nodes { title url } } } }', variables={id='ENG-123'}}).")
		table.insert(lines, "Writes: find teamId with listTeams, stateId with listWorkflowStates, label ids with listLabels and user ids with listUsers. Linear notifies subscribers of new issues, assignments and comments. There are no automatic retries: after any failed write, read the issue again before repeating it, since Linear may have applied it.")
	else
		table.insert(lines, "This read-only connection sends queries with GET, which Linear refuses for mutations.")
	end
	table.insert(lines, "Errors report the HTTP status with Linear's error codes and messages; RATELIMITED (HTTP 429) is retryable and reports Retry-After and the reset times of the hourly windows. Linear limits API keys to 2,500 requests and 3,000,000 complexity points an hour per user (OAuth apps 5,000 and 2,000,000). A single query may cost at most 10,000 points, counting each list at its first value, so lower first when results nest lists. Your Linear permissions, team access and the API key's or app's permissions still apply.")
	return table.concat(lines, "\n")
end

return exports
