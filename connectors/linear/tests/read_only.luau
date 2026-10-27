return {
	scenario = {publisher = {}, config = {}, auth_method = "token", auth_config = {token = "fixture-key"}},
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
		local function sent(): (string, any)
			local query = string.match(last().url, "^https://api%.linear%.app/graphql%?query=([^&]+)")
			assert(query, "not a GET query: " .. last().url)
			local variables = string.match(last().url, "&variables=(.+)$")
			local function decode(value: string): string
				return (string.gsub(value, "%%(%x%x)", function(hex: string) return string.char(tonumber(hex, 16) :: number) end))
			end
			return decode(query), if variables then json.decode(decode(variables)) else nil
		end
		local function same(a: any, b: any): boolean
			if type(a) ~= "table" or type(b) ~= "table" then return a == b end
			for key, value in a do if not same(value, b[key]) then return false end end
			for key in b do if a[key] == nil then return false end end
			return true
		end
		local function rejected(fn, expected)
			local before = #requests
			local ok, err = pcall(fn)
			assert(not ok and string.find(tostring(err), expected, 1, true), "wrong validation error: " .. tostring(err))
			assert(#requests == before, "invalid input reached Linear")
		end

		local names = {}
		for name in linear do table.insert(names, name) end
		table.sort(names)
		assert(table.concat(names, ",") == "getCycle,getIssue,getProject,getTeam,getViewer,listComments,listCycles,listIssues,listLabels,listProjects,listTeams,listUsers,listWorkflowStates,searchIssues",
			"wrong read-only surface: " .. table.concat(names, ","))
		assert(#requests == 0, "initialization reached Linear")

		payload = '{"data":{"viewer":{"id":"u1","name":"Ada","email":"ada@example.com","organization":{"id":"o1","urlKey":"acme"},"timezone":null}}}'
		local me = linear.getViewer()
		local query, variables = sent()
		assert(last().method == "GET" and last().body == nil)
		assert(last().headers.Accept[1] == "application/json" and last().headers["apollo-require-preflight"][1] == "true")
		assert(last().headers.Authorization == nil and last().headers["Content-Type"] == nil)
		assert(string.find(query, "^query getViewer { viewer { id name displayName email ") and variables == nil, query)
		assert(me.email == "ada@example.com" and me.organization.urlKey == "acme" and me.timezone == NULL)

		payload = '{"data":{"issues":{"nodes":[{"id":"i1","identifier":"ENG-1","labels":{"nodes":[]}}],"pageInfo":{"hasNextPage":true,"endCursor":"c2"}}}}'
		local filter = {assignee = {isMe = {eq = true}}, state = {type = {nin = {"completed", "canceled"}}}}
		local page = linear.listIssues({filter = filter, first = 50, after = "c1", orderBy = "updatedAt"})
		query, variables = sent()
		assert(string.find(query, "^query listIssues%(%$filter: IssueFilter, %$first: Int, %$after: String, %$last: Int, %$before: String, %$includeArchived: Boolean, %$orderBy: PaginationOrderBy%) { issues%(filter: %$filter, first: %$first, after: %$after, last: %$last, before: %$before, includeArchived: %$includeArchived, orderBy: %$orderBy%) { nodes { id identifier "), query)
		assert(string.find(query, " } pageInfo { hasNextPage endCursor } } }$", 1, false), query)
		assert(not string.find(query, "description", 1, true), "lists leave out descriptions")
		assert(variables.first == 50 and variables.after == "c1" and variables.orderBy == "updatedAt")
		assert(json.encode(variables.filter.state.type.nin) == '["completed","canceled"]' and variables.filter.assignee.isMe.eq == true)
		assert(page.pageInfo.endCursor == "c2" and page.nodes[1].identifier == "ENG-1")
		assert(json.encode(page.nodes[1].labels.nodes) == "[]")

		payload = '{"data":{"comments":{"nodes":[],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}'
		local empty = linear.listComments({filter = {issue = {id = {eq = "i1"}}}})
		query, variables = sent()
		assert(string.find(query, "comments(filter: $filter", 1, true) and variables.filter.issue.id.eq == "i1")
		assert(json.encode(empty.nodes) == "[]" and empty.pageInfo.endCursor == NULL)

		payload = '{"data":{"issue":{"id":"i1","identifier":"ENG-123","description":"# Hi","children":{"nodes":[]}}}}'
		local issue = linear.getIssue({id = "ENG-123"})
		query, variables = sent()
		assert(string.find(query, "^query getIssue%(%$id: String!%) { issue%(id: %$id%) { id identifier ") and string.find(query, " description children { ", 1, true))
		assert(variables.id == "ENG-123" and issue.description == "# Hi")

		payload = '{"data":{"searchIssues":{"nodes":[],"pageInfo":{"hasNextPage":false,"endCursor":null},"totalCount":0}}}'
		local found = linear.searchIssues({term = "login & crash", teamId = "t1", includeComments = true})
		query, variables = sent()
		assert(string.find(query, "searchIssues(filter: $filter, first: $first, after: $after, last: $last, before: $before, includeArchived: $includeArchived, orderBy: $orderBy, term: $term, teamId: $teamId, includeComments: $includeComments)", 1, true), query)
		assert(string.find(query, "pageInfo { hasNextPage endCursor } totalCount } }", 1, true))
		assert(string.find(last().url, "&variables=", 1, true) and not string.find(last().url, "&", string.find(last().url, "&variables=", 1, true) + 1, true),
			"variables must be encoded")
		assert(variables.term == "login & crash" and variables.teamId == "t1" and variables.includeComments == true and found.totalCount == 0)

		linear.listTeams()
		assert(select(2, sent()) == nil, "no variables are sent without options")
		linear.getProject({id = "launch-2a1b"})
		query = sent()
		assert(string.find(query, " content } }$"), query)
		for _, case in {
			{function() return linear.listUsers({includeDisabled = true, first = 250}) end, "users", "includeDisabled: $includeDisabled", {first = 250, includeDisabled = true}},
			{function() return linear.listWorkflowStates({filter = {team = {key = {eq = "ENG"}}}}) end, "workflowStates", "filter: $filter", json.decode('{"filter":{"team":{"key":{"eq":"ENG"}}}}')},
			{function() return linear.listLabels({includeArchived = true}) end, "issueLabels", "includeArchived: $includeArchived", {includeArchived = true}},
			{function() return linear.listProjects({filter = {status = {type = {eq = "started"}}}}) end, "projects", "filter: $filter", json.decode('{"filter":{"status":{"type":{"eq":"started"}}}}')},
			{function() return linear.listCycles({filter = {isActive = {eq = true}}}) end, "cycles", "filter: $filter", json.decode('{"filter":{"isActive":{"eq":true}}}')},
			{function() return linear.getCycle({id = "c1"}) end, "cycle", "id: $id", {id = "c1"}},
			{function() return linear.getTeam({id = "t1"}) end, "team", "id: $id", {id = "t1"}},
		} do
			local call, field, use, expected = case[1], case[2], case[3], case[4]
			payload = json.encode({data = {[field] = {id = "x1"}}})
			assert(call().id == "x1", field)
			query, variables = sent()
			assert(string.find(query, " { " .. field .. "(", 1, true) and string.find(query, use, 1, true), query)
			assert(same(variables, expected), field .. " variables " .. json.encode(variables))
		end
		assert(#requests == 14)

		payload = '{"data":null}'
		local ok, err = pcall(function() linear.getTeam({id = "t1"}) end)
		assert(not ok and string.find(tostring(err), "invalid GraphQL response", 1, true), tostring(err))
		payload = "<html>"
		ok, err = pcall(function() linear.getTeam({id = "t1"}) end)
		assert(not ok and string.find(tostring(err), "invalid GraphQL response", 1, true), tostring(err))

		rejected(function() linear.getIssue() end, "id is required")
		rejected(function() linear.getIssue({id = NULL}) end, "id is required")
		rejected(function() linear.getIssue({id = ""}) end, "id must be a nonempty string")
		rejected(function() linear.getIssue({id = 7}) end, "id must be a nonempty string")
		rejected(function() linear.searchIssues({}) end, "term is required")
		rejected(function() linear.listIssues({first = 251}) end, "first must be an integer from 1 to 250")
		rejected(function() linear.listIssues({first = 0}) end, "first must be an integer from 1 to 250")
		rejected(function() linear.listIssues({first = 2.5}) end, "first must be an integer")
		rejected(function() linear.listIssues({orderBy = "priority"}) end, "orderBy must be 'createdAt' or 'updatedAt'")
		rejected(function() linear.listIssues({includeArchived = "yes"}) end, "includeArchived must be true or false")
		rejected(function() linear.listIssues({filter = "state = started"}) end, "filter must be an object")
		rejected(function() linear.listIssues({filter = {"started"}}) end, "filter must be an object, not an array")
		rejected(function() linear.listIssues({fitler = {}}) end, "listIssues has no option fitler")
		local many = {}
		for index = 1, 600 do many[index] = string.format("00000000-0000-4000-8000-%012d", index) end
		rejected(function() linear.listIssues({filter = {id = {["in"] = many}}}) end, "too large for a read-only connection")
		rejected(function() linear.listIssues("ENG") end, "opts must be an object")
		rejected(function() linear.listIssues({"ENG"}) end, "named fields")
	end,
}
