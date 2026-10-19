return {
	scenario = {publisher = {}, config = {access = "read-write"}, auth_method = "token", auth_config = {token = "fixture-page-token"}},
	configure = function()
		requests, responses = {}, {}
		fs = fixture.files()
		local multipart = http.multipart
		http = {multipart = multipart, request = function(req)
			if req.body ~= nil and type(req.body) ~= "string" then req.body = await(req.body:readAll()) end
			table.insert(requests, req)
			assert(#responses > 0, "unexpected request: " .. req.url)
			return fixture.operation(table.remove(responses, 1))
		end}
		function respond(body)
			table.insert(responses, {statusCode = 200, headers = {}, body = fixture.reader(body)})
		end
		function rejected(call, expected)
			local before = #requests
			local ok, err = pcall(call)
			local text = if type(err) == "table" then json.encode(err) else tostring(err)
			assert(not ok and string.find(text, expected, 1, true), "expected " .. expected .. ", got " .. text)
			assert(#requests == before, "invalid input reached Meta")
		end
		function sent(index, method, url)
			local req = requests[index]
			assert(req.method == method and req.url == url, req.method .. " " .. req.url)
			assert(req.headers.Authorization == nil)
			return req
		end
	end,
	run = function(meta)
		for _, name in {"createComment", "createInstagramContainer", "createInstagramReply", "createPost", "deleteObject",
			"publishInstagramMedia", "sendMessage", "sendInstagramPrivateReply", "getInstagramPublishingLimit", "updateComment", "updateInstagramMedia", "updatePost", "uploadPhoto", "uploadVideo",
			"getPage", "listFeed"} do
			assert(meta[name], "missing " .. name)
		end

		-- Writes send the remaining options as JSON, with nested objects and arrays intact.
		respond('{"id":"101_9"}')
		assert(meta.createPost({message = "Fresh bread", published = false, scheduled_publish_time = 1760003600,
			attached_media = {{media_fbid = "201"}, {media_fbid = "202"}}}).id == "101_9")
		local req = sent(1, "POST", "https://graph.facebook.com/v26.0/me/feed")
		assert(req.headers["Content-Type"][1] == "application/json")
		local body = json.decode(req.body)
		assert(body.message == "Fresh bread" and body.published == false and body.scheduled_publish_time == 1760003600)
		assert(body.attached_media[2].media_fbid == "202")

		respond('{"recipient_id":"2400000000000001","message_id":"m_ABC"}')
		meta.sendMessage({recipient = {id = "2400000000000001"}, messaging_type = "RESPONSE", message = {text = "Thanks!"}})
		body = json.decode(sent(2, "POST", "https://graph.facebook.com/v26.0/me/messages").body)
		assert(body.recipient.id == "2400000000000001" and body.message.text == "Thanks!" and body.messaging_type == "RESPONSE")

		respond('{"success":true}')
		assert(meta.updateComment({comment = "101_9_3", is_hidden = true}).success == true)
		req = sent(3, "POST", "https://graph.facebook.com/v26.0/101_9_3")
		assert(req.body == '{"is_hidden":true}' and req.headers.Accept[1] == "application/json", req.body)
		respond('{"success":true}')
		meta.deleteObject({id = "101_9"})
		req = sent(4, "DELETE", "https://graph.facebook.com/v26.0/101_9")
		assert(req.body == nil)

		-- Instagram publishing: a container, then its publication.
		respond('{"id":"17890000000000009"}')
		local container = meta.createInstagramContainer({ig_user = "17841400000000001", image_url = "https://example.com/bread.jpg", caption = "Fresh #bread"})
		body = json.decode(sent(5, "POST", "https://graph.facebook.com/v26.0/17841400000000001/media").body)
		assert(body.image_url == "https://example.com/bread.jpg" and body.caption == "Fresh #bread" and body.ig_user == nil)
		respond('{"id":"17900000000000010"}')
		meta.publishInstagramMedia({ig_user = "17841400000000001", creation_id = container.id})
		assert(json.decode(sent(6, "POST", "https://graph.facebook.com/v26.0/17841400000000001/media_publish").body).creation_id == "17890000000000009")
		respond('{"id":"17870000000000011"}')
		meta.createInstagramReply({comment = "17860000000000001", message = "Thank you!"})
		assert(json.decode(sent(7, "POST", "https://graph.facebook.com/v26.0/17860000000000001/replies").body).message == "Thank you!")
		respond('{"success":true}')
		meta.updateInstagramMedia({media = "17900000000000010", comment_enabled = false})
		assert(json.decode(sent(8, "POST", "https://graph.facebook.com/v26.0/17900000000000010").body).comment_enabled == false)

		-- A public URL is sent as JSON; a session file streams as multipart with the other fields.
		respond('{"id":"201","post_id":"101_10"}')
		meta.uploadPhoto({url = "https://example.com/bread.jpg", caption = "Bread", published = false})
		body = json.decode(sent(9, "POST", "https://graph.facebook.com/v26.0/me/photos").body)
		assert(body.url == "https://example.com/bread.jpg" and body.published == false)
		local bytes = string.char(255, 216, 255, 0) .. "jpeg bytes"
		local file = fs.open("photos/bread.jpg", "w")
		file:write(bytes)
		await(file:close())
		respond('{"id":"202","post_id":"101_11"}')
		assert(meta.uploadPhoto({path = "photos/bread.jpg", caption = "Bread", published = false, scheduled_publish_time = 1760003600}).id == "202")
		req = sent(10, "POST", "https://graph.facebook.com/v26.0/me/photos")
		assert(string.find(req.headers["Content-Type"][1], "multipart/form-data", 1, true))
		for _, part in {'name="source"; filename="bread.jpg"', bytes, 'name="caption"\r\n\r\nBread', 'name="published"\r\n\r\nfalse',
			'name="scheduled_publish_time"\r\n\r\n1760003600'} do
			assert(string.find(req.body, part, 1, true), "missing multipart field " .. part)
		end
		assert(not string.find(req.body, 'name="path"', 1, true))
		respond('{"id":"301"}')
		meta.uploadVideo({path = "photos/bread.jpg", title = "Baking", description = "How we bake"})
		req = sent(11, "POST", "https://graph-video.facebook.com/v26.0/me/videos")
		assert(string.find(req.body, 'name="title"\r\n\r\nBaking', 1, true) and string.find(req.body, bytes, 1, true))
		respond('{"id":"302"}')
		meta.uploadVideo({file_url = "https://example.com/baking.mp4"})
		assert(json.decode(sent(12, "POST", "https://graph-video.facebook.com/v26.0/me/videos").body).file_url == "https://example.com/baking.mp4")

		-- Instagram private replies go through the account; the quota needs the publishing permission.
		respond('{"recipient_id":"17840000000000002","message_id":"aWdGMTIz"}')
		meta.sendInstagramPrivateReply({ig_user = "17841400000000001", recipient = {comment_id = "17860000000000001"}, message = {text = "Sent you the details"}})
		assert(sent(13, "POST", "https://graph.facebook.com/v26.0/17841400000000001/messages").body
			== json.encode({recipient = {comment_id = "17860000000000001"}, message = {text = "Sent you the details"}}))
		respond('{"data":[{"quota_usage":2,"config":{"quota_total":50,"quota_duration":86400}}]}')
		assert(meta.getInstagramPublishingLimit({ig_user = "17841400000000001"}).data[1].config.quota_total == 50)
		sent(14, "GET", "https://graph.facebook.com/v26.0/17841400000000001/content_publishing_limit?fields=config%2Cquota_usage")

		-- Graph reads method, batch and fields from bodies too: batch could fetch a token and
		-- fields reads the written object back, its access_token included.
		rejected(function() meta.updatePost({post = "101_9", message = "x", method = "delete"}) end, "cannot send method")
		rejected(function() meta.createPost({message = "x", batch = "[]"}) end, "cannot send batch")
		rejected(function() meta.updatePost({post = "me", about = "x", fields = "access_token"}) end, "cannot send fields")
		rejected(function() meta.createComment({object = "101_9", message = "x", access_token = "EAAOTHER"}) end, "cannot send access_token")
		rejected(function() meta.uploadPhoto({path = "photos/bread.jpg", callback = "f"}) end, "cannot send callback")
		rejected(function() meta.uploadPhoto({path = "photos/bread.jpg", caption = json.decode("null")}) end, "cannot send null")
		-- PHP-style parsers trim names, map . and spaces to _ and read name[] as arrays.
		for _, key in {" method", "Method", "fields[]", "batch[0]", "suppress.http.code", "access token", "method "} do
			rejected(function() meta.createPost({message = "x", [key] = "delete"}) end, "cannot send")
			rejected(function() meta.uploadPhoto({path = "photos/bread.jpg", [key] = "get"}) end, "cannot send")
		end
		rejected(function() meta.deleteObject({id = "101_9", method = "get"}) end, "has no option method")
		rejected(function() meta.sendMessage({message = {text = "hi"}}) end, "recipient is required")
		rejected(function() meta.publishInstagramMedia({ig_user = "17841400000000001"}) end, "creation_id is required")
		rejected(function() meta.deleteObject({id = "101/feed"}) end, "one Meta ID")
		rejected(function() meta.uploadPhoto({path = "missing.jpg"}) end, '"code":"not_found"')
		assert(#responses == 0)
	end,
}
