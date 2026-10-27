return {
	scenario = {publisher = {}, config = {access = "read-only", client_id = "fixture-client", client_secret = "fixture-secret"},
		auth_method = "oauth", auth_config = {}},
	configure = function()
		requests = {}
		http = {request = function(req)
			table.insert(requests, req)
			return fixture.operation({statusCode = 200, headers = {},
				body = fixture.reader('{"data":{"workflowStates":{"nodes":[{"id":"s1","type":"started"}],"pageInfo":{"hasNextPage":false,"endCursor":"c1"}}}}')})
		end}
	end,
	run = function(linear)
		for _, name in {"createIssue", "updateIssue", "createComment", "graphql"} do
			assert(linear[name] == nil, "read-only leaked " .. name)
		end
		local states = linear.listWorkflowStates({filter = {team = {key = {eq = "ENG"}}}})
		local request = requests[1]
		assert(#requests == 1 and request.method == "GET" and request.body == nil and request.headers.Authorization == nil)
		assert(string.find(request.url, "^https://api%.linear%.app/graphql%?query=query%%20listWorkflowStates%%28"), request.url)
		assert(string.find(request.url, "&variables=%7B%22filter%22%3A%7B%22team%22%3A%7B%22key%22%3A%7B%22eq%22%3A%22ENG%22%7D%7D%7D%7D", 1, true), request.url)
		assert(states.nodes[1].type == "started")
	end,
}
