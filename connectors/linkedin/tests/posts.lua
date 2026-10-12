return {
	scenario = {config = {client_id = "fixture-client", client_secret = "fixture-private-secret"}, auth_method = "oauth", auth_config = {}},
	config = {access = "read-write"},
	configure = function()
		requests, responses = {}, {}
		fs = fixture.files()
		http = {request = function(req)
			table.insert(requests, req)
			if req.body ~= nil and type(req.body) ~= "string" then
				req.wire = await(req.body:readAll())
				await(req.body:close())
			end
			assert(#responses > 0, "unexpected request: " .. req.url)
			return fixture.operation(table.remove(responses, 1))
		end}
		function respond(status, body, headers)
			table.insert(responses, {statusCode = status, headers = headers or {}, body = fixture.reader(body)})
		end
		function created(id)
			respond(201, "", {["x-restli-id"] = {id}})
		end
		PROFILE = '{"sub":"abc123","name":"Jane Doe"}'
	end,
	run = function(c)
		assert(c.getProfile and c.createPost and c.deletePost)

		-- Text post: every little-text reserved character except # is escaped, so hashtags still link.
		respond(200, PROFILE)
		created("urn:li:share:6844785523593134080")
		local post = c.createPost({text = "(a) [b] {c} <d> @e #f g_h *i* ~j~ k|l m\\n", visibility = "CONNECTIONS"})
		assert(post.id == "urn:li:share:6844785523593134080")
		assert(post.url == "https://www.linkedin.com/feed/update/urn:li:share:6844785523593134080/")
		local req = requests[2]
		assert(req.method == "POST" and req.url == "https://api.linkedin.com/rest/posts")
		assert(req.headers["LinkedIn-Version"][1] == "202609" and req.headers["X-Restli-Protocol-Version"][1] == "2.0.0")
		assert(req.headers["Content-Type"][1] == "application/json" and req.headers.Authorization == nil)
		local body = json.decode(req.body)
		assert(body.author == "urn:li:person:abc123" and body.visibility == "CONNECTIONS" and body.lifecycleState == "PUBLISHED")
		assert(body.commentary == "\\(a\\) \\[b\\] \\{c\\} \\<d\\> \\@e #f g\\_h \\*i\\* \\~j\\~ k\\|l m\\\\n")
		assert(body.distribution.feedDistribution == "MAIN_FEED" and json.encode(body.distribution.targetEntities) == "[]")
		assert(string.find(req.body, '"thirdPartyDistributionChannels":[]', 1, true))
		assert(body.content == nil and body.isReshareDisabledByAuthor == false)

		-- Article post: LinkedIn does not scrape links, so title is sent explicitly.
		respond(200, PROFILE)
		created("urn:li:ugcPost:42")
		assert(c.createPost({text = "Read this", article = {url = "https://example.com/post", title = "Our launch"}}).id == "urn:li:ugcPost:42")
		body = json.decode(requests[4].body)
		assert(body.visibility == "PUBLIC")
		assert(body.content.article.source == "https://example.com/post" and body.content.article.title == "Our launch")
		assert(body.content.article.description == nil)

		-- Image post: register the image, stream the session file, then publish.
		local bytes = string.char(137, 80, 78, 71, 0, 255) .. "image bytes"
		local file = fs.open("photos/team.png", "w")
		file:write(bytes)
		await(file:close())
		local uploadUrl = "https://www.linkedin.com/dms-uploads/C4E10AQ/uploaded-image/0?ca=vector_feedshare&ut=signed"
		respond(200, PROFILE)
		respond(200, json.encode({value = {uploadUrlExpiresAt = 1650567510704, uploadUrl = uploadUrl, image = "urn:li:image:C4E10AQ"}}))
		respond(201, "")
		created("urn:li:share:7")
		c.createPost({text = "Team", image = {path = "photos/team.png", altText = "Our team"}})
		local init = requests[6]
		assert(init.method == "POST" and init.url == "https://api.linkedin.com/rest/images?action=initializeUpload")
		assert(json.decode(init.body).initializeUploadRequest.owner == "urn:li:person:abc123")
		local upload = requests[7]
		assert(upload.method == "PUT" and upload.url == uploadUrl and upload.wire == bytes)
		body = json.decode(requests[8].body)
		assert(body.content.media.id == "urn:li:image:C4E10AQ" and body.content.media.altText == "Our team")

		-- A failed upload stops before publishing.
		respond(200, PROFILE)
		respond(200, json.encode({value = {uploadUrl = uploadUrl, image = "urn:li:image:C4E10AQ"}}))
		respond(500, "")
		assert(not pcall(c.createPost, {text = "Team", image = {path = "photos/team.png"}}))
		assert(#requests == 11 and #responses == 0)

		-- Delete encodes the URN as one path segment.
		respond(204, "")
		assert(c.deletePost("urn:li:share:7").id == "urn:li:share:7")
		assert(requests[12].method == "DELETE" and requests[12].url == "https://api.linkedin.com/rest/posts/urn%3Ali%3Ashare%3A7")
		assert(requests[12].body == nil)

		-- Invalid input fails before reaching LinkedIn.
		local before = #requests
		for _, call in {
			function() c.createPost() end,
			function() c.createPost({}) end,
			function() c.createPost({text = ""}) end,
			function() c.createPost({text = "x", visibility = "LOGGED_IN"}) end,
			function() c.createPost({text = "x", title = "unknown option"}) end,
			function() c.createPost({text = "x", image = {path = "photos/team.png"}, article = {url = "https://e.com", title = "t"}}) end,
			function() c.createPost({text = "x", image = {path = "missing.png"}}) end,
			function() c.createPost({text = "x", image = {path = "photos/team.png", alt = "typo"}}) end,
			function() c.createPost({text = "x", article = {url = "javascript:alert(1)", title = "t"}}) end,
			function() c.createPost({text = "x", article = {url = "https://e.com"}}) end,
			function() c.deletePost("123") end,
			function() c.deletePost({id = "urn:li:share:7"}) end,
			function() c.deletePost("urn:li:share:7/../1") end,
		} do
			assert(not pcall(call), "invalid input accepted")
		end
		assert(#requests == before, "invalid input reached LinkedIn")

		-- Missing confirmations and provider errors are reported, never retried.
		respond(200, PROFILE)
		respond(201, "")
		local ok, err = pcall(c.createPost, {text = "x"})
		assert(not ok and string.find(tostring(err), "did not confirm the post ID", 1, true))
		respond(200, PROFILE)
		respond(403, '{"status":403,"serviceErrorCode":100,"code":"ACCESS_DENIED","message":"Not enough permissions to access: partnerApiPostsExternal.CREATE"}')
		ok, err = pcall(c.createPost, {text = "x"})
		assert(not ok and string.find(tostring(err), "LinkedIn HTTP 403 (ACCESS_DENIED): Not enough permissions", 1, true))
		assert(#requests == before + 4 and #responses == 0)
	end,
}
