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
	run = function(figma)
		local API = "https://api.figma.com"
		local KEY = "aBcDeFgHiJkLmNoPqRsTuV12"
		local function last() return requests[#requests] end
		local function rejected(fn, expected)
			local before = #requests
			local ok, err = pcall(fn)
			assert(not ok and string.find(tostring(err), expected, 1, true), "wrong validation error: " .. tostring(err))
			assert(#requests == before, "invalid input reached Figma")
		end

		local count = 0
		for _ in figma do count += 1 end
		assert(count == 24, "wrong read-write surface: " .. count)
		for _, name in {"postComment", "deleteComment", "addCommentReaction", "removeCommentReaction"} do
			assert(type(figma[name]) == "function", "missing " .. name)
		end

		payload = '{"id":"8","message":"Looks good","parent_id":"7","client_meta":null}'
		local link = "https://www.figma.com/design/" .. KEY .. "/App"
		local opts = {file_key = link, message = "Looks good", comment_id = "7"}
		local reply = figma.postComment(opts)
		assert(last().method == "POST" and last().url == API .. "/v1/files/" .. KEY .. "/comments")
		assert(last().headers["Content-Type"][1] == "application/json" and last().headers.Authorization == nil and last().headers["X-Figma-Token"] == nil)
		local body = json.decode(last().body)
		assert(body.message == "Looks good" and body.comment_id == "7" and body.file_key == nil)
		assert(reply.parent_id == "7" and opts.file_key == link, "caller options were modified")

		figma.postComment({file_key = KEY, message = "Pinned", client_meta = {node_id = "1-2", node_offset = {x = 10, y = 20}}})
		body = json.decode(last().body)
		assert(body.client_meta.node_id == "1:2" and body.client_meta.node_offset.y == 20)

		payload = ""
		assert(figma.deleteComment({file_key = KEY, comment_id = "8"}).success == true)
		assert(last().method == "DELETE" and last().url == API .. "/v1/files/" .. KEY .. "/comments/8" and last().body == nil)
		payload = '{"status":200,"error":false}'
		figma.addCommentReaction({file_key = KEY, comment_id = "7", emoji = ":+1:"})
		assert(last().method == "POST" and last().url == API .. "/v1/files/" .. KEY .. "/comments/7/reactions" and last().body == '{"emoji":":+1:"}')
		figma.removeCommentReaction({file_key = KEY, comment_id = "7", emoji = ":+1:"})
		assert(last().method == "DELETE" and last().url == API .. "/v1/files/" .. KEY .. "/comments/7/reactions?emoji=%3A%2B1%3A" and last().body == nil, last().url)
		figma.getMe()
		assert(last().method == "GET" and last().url == API .. "/v1/me")
		assert(#requests == 6)

		rejected(function() figma.postComment({file_key = KEY}) end, "message is required")
		rejected(function() figma.addCommentReaction({file_key = KEY, comment_id = "7"}) end, "emoji is required")
		rejected(function() figma.removeCommentReaction({file_key = KEY, comment_id = "7"}) end, "emoji is required")
		rejected(function() figma.deleteComment({file_key = KEY, comment_id = "abc"}) end, "comment_id must be a numeric id string")
	end,
}
