return {
	scenario = {publisher = {}, config = {access = "read-only", client_id = "fixture-client", client_secret = "fixture-secret"},
		auth_method = "oauth", auth_config = {}},
	configure = function()
		requests = {}
		http = {request = function(req)
			table.insert(requests, req)
			return fixture.operation({statusCode = 200, headers = {}, body = fixture.reader('{"name":"Design","projects":[]}')})
		end}
	end,
	run = function(figma)
		for _, name in {"postComment", "deleteComment", "addCommentReaction", "removeCommentReaction"} do
			assert(figma[name] == nil, "read-only leaked " .. name)
		end
		local projects = figma.listTeamProjects({team_id = "1234567890"})
		assert(#requests == 1 and requests[1].method == "GET" and requests[1].url == "https://api.figma.com/v1/teams/1234567890/projects")
		assert(requests[1].headers.Authorization == nil and json.encode(projects.projects) == "[]")
	end,
}
