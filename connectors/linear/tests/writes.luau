return {
	scenario = {publisher = {}, config = {access = "read-write", client_id = "fixture-client", client_secret = "fixture-secret"},
		auth_method = "oauth", auth_config = {}},
	configure = function()
		requests = {}
		payload = "{}"
		http = {request = function(req)
			table.insert(requests, req)
			return fixture.operation({statusCode = 200, headers = {}, body = fixture.reader(payload)})
		end}
	end,
	run = function(linear)
		local API = "https://api.linear.app/graphql"
		local NULL = json.decode("null")
		local function last() return requests[#requests] end
		local function sent() return json.decode(last().body) end
		local function rejected(fn, expected)
			local before = #requests
			local ok, err = pcall(fn)
			assert(not ok and string.find(tostring(err), expected, 1, true), "wrong validation error: " .. tostring(err))
			assert(#requests == before, "invalid input reached Linear")
		end

		local names = {}
		for name in linear do table.insert(names, name) end
		table.sort(names)
		assert(table.concat(names, ",") == "createComment,createIssue,getCycle,getIssue,getProject,getTeam,getViewer,graphql,listComments,listCycles,listIssues,listLabels,listProjects,listTeams,listUsers,listWorkflowStates,searchIssues,updateIssue",
			"wrong read-write surface: " .. table.concat(names, ","))

		-- Read-write connections send queries with POST too.
		payload = '{"data":{"teams":{"nodes":[{"id":"t1","key":"ENG"}],"pageInfo":{"hasNextPage":false,"endCursor":"c1"}}}}'
		local teams = linear.listTeams({first = 10})
		assert(last().method == "POST" and last().url == API and last().headers.Authorization == nil)
		assert(last().headers["Content-Type"][1] == "application/json" and last().headers["apollo-require-preflight"] == nil)
		assert(string.find(sent().query, "^query listTeams%(") and sent().variables.first == 10 and teams.nodes[1].key == "ENG")
		linear.getViewer()
		assert(last().body == json.encode({query = sent().query, variables = {}}) and string.find(last().body, '"variables":{}', 1, true),
			"variables are an object even when empty")

		payload = '{"data":{"issueCreate":{"success":true,"issue":{"id":"i9","identifier":"ENG-9","labels":{"nodes":[]}}}}}'
		local input = {teamId = "t1", title = "Crash on login", description = "Steps:\n1. Sign in", priority = 2, labelIds = {"l1"}}
		local opts = {input = input}
		local created = linear.createIssue(opts)
		local body = sent()
		assert(string.find(body.query, "^mutation createIssue%(%$input: IssueCreateInput!%) { issueCreate%(input: %$input%) { success issue { id identifier "), body.query)
		assert(body.variables.input.title == "Crash on login" and body.variables.input.priority == 2 and json.encode(body.variables.input.labelIds) == '["l1"]')
		assert(created.success == true and created.issue.identifier == "ENG-9")
		assert(opts.input == input, "caller options were modified")

		-- A write that succeeded keeps its result when a nested field errors.
		payload = '{"data":{"issueCreate":{"success":true,"issue":{"id":"i10","project":null}}},"errors":[{"message":"Entity not found: Project","path":["issueCreate","issue","project"]}]}'
		local partial = linear.createIssue({input = {teamId = "t1", title = "Partial"}})
		assert(partial.success == true and partial.issue.id == "i10" and partial.errors[1].path[3] == "project")
		payload = '{"data":{"issueUpdate":{"success":true,"issue":{"id":"i9","assignee":null}}}}'
		local updated = linear.updateIssue({id = "ENG-9", input = {stateId = "s2", assigneeId = NULL, addedLabelIds = {"l2"}}})
		body = sent()
		assert(string.find(body.query, "^mutation updateIssue%(%$id: String!, %$input: IssueUpdateInput!%) { issueUpdate%(id: %$id, input: %$input%) { success issue { "), body.query)
		assert(body.variables.id == "ENG-9" and body.variables.input.stateId == "s2" and body.variables.input.assigneeId == NULL)
		assert(string.find(last().body, '"assigneeId":null', 1, true), "null unassigns")
		assert(updated.issue.assignee == NULL)

		payload = '{"data":{"commentCreate":{"success":true,"comment":{"id":"c1","body":"Fixed in #42","parentId":null}}}}'
		local comment = linear.createComment({input = {issueId = "ENG-9", body = "Fixed in #42", parentId = "c0"}})
		body = sent()
		assert(string.find(body.query, "^mutation createComment%(%$input: CommentCreateInput!%) { commentCreate%(input: %$input%) { success comment { id body "), body.query)
		assert(body.variables.input.parentId == "c0" and comment.comment.id == "c1")

		payload = '{"data":{"issue":{"attachments":{"nodes":[]}}}}'
		local document = "query($id: String!) { issue(id: $id) { attachments { nodes { title url } } } }"
		local response = linear.graphql({query = document, variables = {id = "ENG-9"}})
		assert(last().method == "POST" and last().body == json.encode({query = document, variables = {id = "ENG-9"}}))
		assert(json.encode(response.data.issue.attachments.nodes) == "[]" and response.errors == nil)
		linear.graphql({query = "query A { viewer { id } } query B { teams { nodes { id } } }", operationName = "B"})
		assert(json.decode(last().body).operationName == "B")
		linear.graphql({query = "{ viewer { id } }"})
		assert(string.find(last().body, '"variables":{}', 1, true))
		linear.graphql({query = "{ viewer { id } }", variables = NULL})
		assert(string.find(last().body, '"variables":{}', 1, true), "null variables are omitted")
		assert(#requests == 10)

		rejected(function() linear.createIssue({}) end, "input is required")
		rejected(function() linear.createIssue({input = {"t1"}}) end, "input must be an object, not an array")
		rejected(function() linear.createIssue({input = {teamId = "t1"}, teamId = "t1"}) end, "createIssue has no option teamId")
		rejected(function() linear.updateIssue({input = {stateId = "s2"}}) end, "id is required")
		rejected(function() linear.createComment({input = "Fixed"}) end, "input must be an object")
		rejected(function() linear.graphql({}) end, "query must be a GraphQL document")
		rejected(function() linear.graphql({query = "  \n"}) end, "query must be a GraphQL document")
		rejected(function() linear.graphql({query = string.rep(" ", 64 * 1024) .. "{ viewer { id } }"}) end, "query must be at most")
		rejected(function() linear.graphql({query = "{ viewer { id } }", variables = {"x"}}) end, "variables must be an object, not an array")
		rejected(function() linear.graphql({query = "{ viewer { id } }", operationName = "B C"}) end, "operationName must be a GraphQL name")
		rejected(function() linear.graphql({query = "{ viewer { id } }", operation = "B"}) end, "graphql has no option operation")
	end,
}
