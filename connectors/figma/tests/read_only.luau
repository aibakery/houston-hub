return {
	scenario = {publisher = {}, config = {}, auth_method = "token", auth_config = {token = "figd_fixture"}},
	configure = function()
		requests = {}
		payload = "{}"
		http = {request = function(req)
			table.insert(requests, req)
			return fixture.operation({statusCode = 200, headers = {}, body = fixture.reader(payload)})
		end}
	end,
	run = function(figma)
		local API = "https://api.figma.com"
		local KEY = "aBcDeFgHiJkLmNoPqRsTuV12"
		local NULL = json.decode("null")
		local function last() return requests[#requests] end
		local function rejected(fn, expected)
			local before = #requests
			local ok, err = pcall(fn)
			assert(not ok and string.find(tostring(err), expected, 1, true), "wrong validation error: " .. tostring(err))
			assert(#requests == before, "invalid input reached Figma")
		end

		local names = {}
		for name in figma do table.insert(names, name) end
		table.sort(names)
		assert(table.concat(names, ",") == "getComponent,getComponentSet,getFile,getFileMeta,getFileNodes,getImageFills,getMe,getStyle,listCommentReactions,listComments,listFileComponentSets,listFileComponents,listFileStyles,listFileVersions,listProjectFiles,listTeamComponentSets,listTeamComponents,listTeamProjects,listTeamStyles,renderImages",
			"wrong read-only surface: " .. table.concat(names, ","))
		assert(#requests == 0, "initialization reached Figma")

		payload = '{"id":"1234567890123456789","handle":"Ada","email":"ada@example.com","img_url":"https://s3-alpha.figma.com/profile/x"}'
		local me = fixture.example("getMe")
		assert(last().method == "GET" and last().url == API .. "/v1/me" and last().body == nil)
		assert(last().headers.Accept[1] == "application/json" and last().headers.Authorization == nil and last().headers["X-Figma-Token"] == nil)
		assert(me.id == "1234567890123456789" and me.email == "ada@example.com")

		payload = '{"name":"App","document":{"id":"0:0","children":[{"id":"0:1","type":"CANVAS","children":[]}]},"components":{},"styles":{}}'
		local file = fixture.example("getFile")
		assert(last().url == API .. "/v1/files/" .. KEY .. "?depth=2&branch_data=true", last().url)
		assert(file.document.children[1].type == "CANVAS" and json.encode(file.document.children[1].children) == "[]")

		-- Links work as file keys, branch links name the branch, and URL node ids use dashes.
		for _, link in {"https://www.figma.com/design/" .. KEY .. "/App?node-id=1-2&m=dev", "https://figma.com/file/" .. KEY, KEY} do
			if link == "https://www.figma.com/design/" .. KEY .. "/App?node-id=1-2&m=dev" then fixture.example("getFileMeta") else figma.getFileMeta({file_key = link}) end
			assert(last().url == API .. "/v1/files/" .. KEY .. "/meta", last().url)
		end
		figma.getFileMeta({file_key = "https://www.figma.com/design/" .. KEY .. "/branch/BrAnChKeY123/App"})
		assert(last().url == API .. "/v1/files/BrAnChKeY123/meta", last().url)

		payload = '{"nodes":{"1:2":{"document":{"id":"1:2"}},"9:9":null}}'
		local nodes = fixture.example("getFileNodes")
		assert(last().url == API .. "/v1/files/" .. KEY .. "/nodes?ids=1%3A2,I1%3A2%3B3%3A4,9%3A9&depth=1", last().url)
		assert(nodes.nodes["1:2"].document.id == "1:2" and nodes.nodes["9:9"] == NULL)
		figma.getFileNodes({file_key = KEY, ids = " 1:2, 3-4 "})
		assert(last().url == API .. "/v1/files/" .. KEY .. "/nodes?ids=1%3A2,3%3A4", last().url)
		figma.getFileNodes({file_key = "www.figma.com/design/" .. KEY .. "/App", ids = {"12%3A34", "I1-2%3B3-4"}})
		assert(last().url == API .. "/v1/files/" .. KEY .. "/nodes?ids=12%3A34,I1%3A2%3B3%3A4", last().url)
		figma.getFileMeta({file_key = "http://figma.com/file/" .. KEY})
		assert(last().url == API .. "/v1/files/" .. KEY .. "/meta", last().url)

		payload = '{"err":null,"images":{"1:2":"https://figma-alpha-api.s3.us-west-2.amazonaws.com/images/u1","1:3":null}}'
		local rendered = fixture.example("renderImages")
		assert(last().url == API .. "/v1/images/" .. KEY .. "?ids=1%3A2,1%3A3&scale=2&format=svg&svg_include_id=true", last().url)
		assert(rendered.images["1:3"] == NULL and #requests == 11, "renders are not downloaded without save_to")

		payload = '{"versions":[],"pagination":{}}'
		assert(json.encode(fixture.example("listFileVersions").versions) == "[]")
		assert(last().url == API .. "/v1/files/" .. KEY .. "/versions?page_size=50&before=123")
		payload = '{"meta":{"components":[{"key":"abc123","node_id":"1:2"}],"cursor":{"after":30}}}'
		local components = fixture.example("listTeamComponents")
		assert(last().url == API .. "/v1/teams/1234567890/components?page_size=30&after=0")
		assert(components.meta.cursor.after == 30 and components.meta.components[1].key == "abc123")
		payload = '{"comments":[{"id":"7","message":"**Hi**","parent_id":"","reactions":[]}]}'
		local comments = fixture.example("listComments")
		assert(last().url == API .. "/v1/files/" .. KEY .. "/comments?as_md=true")
		assert(comments.comments[1].message == "**Hi**" and json.encode(comments.comments[1].reactions) == "[]")
		payload = '{"comments":[]}'
		assert(json.encode(figma.listComments({file_key = KEY}).comments) == "[]")

		for _, case in {
			{function() fixture.example("getImageFills") end, "/v1/files/" .. KEY .. "/images"},
			{function() fixture.example("listTeamProjects") end, "/v1/teams/42/projects"},
			{function() fixture.example("listProjectFiles") end, "/v1/projects/77/files?branch_data=true"},
			{function() fixture.example("listTeamComponentSets") end, "/v1/teams/42/component_sets"},
			{function() fixture.example("listTeamStyles") end, "/v1/teams/42/styles?before=10"},
			{function() fixture.example("listFileComponents") end, "/v1/files/" .. KEY .. "/components"},
			{function() fixture.example("listFileComponentSets") end, "/v1/files/" .. KEY .. "/component_sets"},
			{function() fixture.example("listFileStyles") end, "/v1/files/" .. KEY .. "/styles"},
			{function() fixture.example("getComponent") end, "/v1/components/abc123"},
			{function() fixture.example("getComponentSet") end, "/v1/component_sets/def456"},
			{function() fixture.example("getStyle") end, "/v1/styles/0f0f"},
			{function() fixture.example("listCommentReactions") end, "/v1/files/" .. KEY .. "/comments/7/reactions?cursor=c2"},
			{function() figma.listCommentReactions({file_key = KEY, comment_id = "7", cursor = "https://api.figma.com/v1/files/" .. KEY .. "/comments/7/reactions?cursor=YWJj%3D%3D"}) end, "/v1/files/" .. KEY .. "/comments/7/reactions?cursor=YWJj%3D%3D"},
		} do
			case[1]()
			assert(last().method == "GET" and last().url == API .. case[2], last().url)
		end
		assert(#requests == 28)

		rejected(function() figma.getFile() end, "file_key must be a Figma file key or URL")
		rejected(function() figma.getFile({file_key = "../v1/me"}) end, "file_key must be a Figma file key or URL")
		rejected(function() figma.getFile({file_key = "https://evil.example/design/" .. KEY}) end, "file_key must be a Figma file key or URL")
		rejected(function() figma.getFile({file_key = "https://www.figma.com.evil.example/design/" .. KEY}) end, "file_key must be a Figma file key or URL")
		rejected(function() figma.getFile({file_key = "https://www.figma.com/"}) end, "file_key must be a Figma file key or URL")
		rejected(function() figma.getFile({file_key = "https://www.figma.com/files/123/team/456/Design"}) end, "file_key must be a Figma file key or URL")
		rejected(function() figma.getFile({file_key = "https://www.figma.com/community/file/123/Kit"}) end, "file_key must be a Figma file key or URL")
		rejected(function() figma.getFile({file_key = KEY, save_to = "out"}) end, "getFile has no option save_to")
		rejected(function() figma.listCommentReactions({file_key = KEY, comment_id = "7", cursor = "https://api.figma.com/v1/files/x/comments/7/reactions?page=2"}) end, "cursor must be a cursor or pagination.next_page")
		rejected(function() figma.listTeamProjects({team_id = 42}) end, "team_id must be a numeric id string")
		rejected(function() figma.listTeamProjects({team_id = "42/../1"}) end, "team_id must be a numeric id string")
		rejected(function() figma.getComponent({key = "node 1:2"}) end, "key must be a Figma key")
		rejected(function() figma.getFileNodes({file_key = KEY}) end, "ids is required")
		rejected(function() figma.getFileNodes({file_key = KEY, ids = json.decode("[]")}) end, "ids must name at least one node")
		rejected(function() figma.getFileNodes({file_key = KEY, ids = {"1:2&x=y"}}) end, "ids must be node ids such as 1:2")
		rejected(function() figma.getFileNodes({file_key = KEY, ids = {a = "1:2"}}) end, "ids must be a list")
		rejected(function() figma.renderImages({file_key = KEY, ids = {"1:2"}, save_to = "out", format = "gif"}) end, "format must be png, jpg, svg or pdf")
		rejected(function() figma.getFile({file_key = KEY, deep = 1}) end, "getFile has no option deep")
		rejected(function() figma.getFile("key") end, "opts must be an object")
		rejected(function() figma.listCommentReactions({file_key = KEY, comment_id = "7", cursor = {"a", "b"}}) end, "cursor must be one value")
	end,
}
