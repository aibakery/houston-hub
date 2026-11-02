return {
	scenario = {publisher = {}, config = {site_host = "blog.example.com", access = "read-write"}, auth_method = "application_password",
		auth_config = {username = "editor", password = "abcd efgh ijkl mnop qrst uvwx"}},
	configure = function()
		calls = 0
		status = 200
		payload = "{}"
		responseHeaders = {}
		fs = fixture.files()
		http = {request = function(req)
			calls += 1
			return fixture.operation({statusCode = status, headers = responseHeaders, body = fixture.reader(payload)})
		end}
	end,
	run = function(wp)
		local function rejected(fn, expected)
			local before = calls
			local ok, err = pcall(fn)
			assert(not ok and string.find(tostring(err), expected, 1, true), "wrong validation error: " .. tostring(err))
			assert(calls == before, "invalid input reached WordPress")
		end
		rejected(function() wp.getPost() end, "id must be")
		rejected(function() wp.getPost({id = "../users"}) end, "id must be")
		rejected(function() wp.getPost({id = -1}) end, "nonnegative integer")
		rejected(function() wp.getPost({id = 1.5}) end, "nonnegative integer")
		rejected(function() wp.getPost({id = ""}) end, "id must be")
		rejected(function() wp.getPostRevision({id = 2}) end, "parent must be")
		rejected(function() wp.listPosts("draft") end, "opts must be an object")
		rejected(function() wp.listPosts({"draft"}) end, "named fields")
		rejected(function() wp.listPosts({status = {draft = true}}) end, "array, not an object")
		rejected(function() wp.listPosts({after = json.decode("null")}) end, "after must be")
		rejected(function() wp.listPosts({include = json.decode("[]")}) end, "must not be an empty array")
		-- WordPress would let these change the request's method or route.
		for _, key in {"_method", "rest_route", "rest.route", "rest route", "_envelope", "_jsonp", "status[0]"} do
			rejected(function() wp.getPost({id = 1, [key] = "DELETE"}) end, "not a WordPress query parameter")
		end
		rejected(function() wp.deletePost({id = 1, _method = "GET"}) end, "not a WordPress query parameter")

		local photo = fs.open("photo.jpg", "w")
		photo:write("jpeg")
		await(photo:close())
		rejected(function() wp.uploadMedia({content_type = "image/jpeg"}) end, "path must name a session file")
		rejected(function() wp.uploadMedia({path = "photo.jpg"}) end, "content_type must be")
		rejected(function() wp.uploadMedia({path = "photo.jpg", content_type = "image/jpeg\r\nX-Evil: 1"}) end, "content_type must be")
		-- PHP parses form bodies into $_POST, where rest_route would reroute the upload.
		for _, contentType in {"application/x-www-form-urlencoded", "Application/X-WWW-Form-Urlencoded", "multipart/form-data"} do
			rejected(function() wp.uploadMedia({path = "photo.jpg", content_type = contentType}) end, "not a form type")
		end
		rejected(function() wp.uploadMedia({path = "photo.jpg", content_type = "image/jpeg", url = "https://example.com/a.jpg"}) end, "url is not supported")
		local accented = fs.open("Café.jpg", "w")
		accented:write("jpeg")
		await(accented:close())
		rejected(function() wp.uploadMedia({path = "Café.jpg", content_type = "image/jpeg"}) end, "pass filename")
		for _, filename in {"photo", 'a".jpg', "a/b.jpg", "a;b.jpg", "a\r\n.jpg", "é.jpg", 7} do
			rejected(function() wp.uploadMedia({path = "photo.jpg", content_type = "image/jpeg", filename = filename}) end, "filename must be")
		end
		rejected(function() wp.uploadMedia({path = "photo.jpg", content_type = "image/jpeg", rest_route = "/wp/v2/users"}) end, "not a WordPress query parameter")

		local function upstream(code, body, headers, expected)
			status, payload, responseHeaders = code, body, headers
			local before = calls
			local ok, err = pcall(function() wp.updatePost({id = 1, status = "publish"}) end)
			for _, text in expected do
				assert(not ok and string.find(tostring(err), text, 1, true), "missing " .. text .. " in " .. tostring(err))
			end
			assert(calls == before + 1, "failed write was retried")
		end
		upstream(401, '{"code":"incorrect_password","message":"The provided password is an invalid application password.","data":{"status":401}}', {},
			{"WordPress HTTP 401", "incorrect_password", "invalid application password", '"retryable":false'})
		upstream(403, '{"code":"rest_cannot_edit","message":"Sorry, you are not allowed to edit this post.","data":{"status":403}}', {},
			{"HTTP 403", "rest_cannot_edit", "not allowed to edit"})
		upstream(400, '{"code":"rest_invalid_param","message":"Invalid parameter(s): status","data":{"status":400,"params":{"status":"status is not one of publish, future."}}}', {},
			{"HTTP 400", "rest_invalid_param", "status is not one of"})
		upstream(400, json.encode({code = "rest_invalid_param", message = string.rep("x", 5000), data = {params = {date = "Invalid date."}}}), {},
			{"rest_invalid_param", "Invalid date."})
		upstream(429, "Too many requests", {["retry-after"] = {"30"}}, {"HTTP 429: Too many requests", "Retry-After: 30", '"retryable":true'})
		-- Host firewalls answer with an HTML page that names the blocking layer.
		upstream(429, "<!doctype html><html><head><title>429</title><style>\nbody { color: red }</style></head><body>\n<!-- blocked by firewall -->\n<h1>Too many\n requests</h1></body></html>",
			{server = {"host-firewall"}}, {"HTTP 429: 429 blocked by firewall Too many requests", "Server: host-firewall"})
		upstream(500, "<html>Fatal error</html>", {}, {"HTTP 500: Fatal error", '"retryable":true'})
		upstream(301, "", {location = {"https://www.blog.example.com/wp-json/wp/v2/posts/1"}},
			{"HTTP 301", "redirected to https://www.blog.example.com/", "connection's domain"})
		upstream(200, "<!doctype html><title>Maintenance</title>", {}, {"not JSON", "/wp-json"})
		upstream(200, '"ok"', {}, {"not JSON"})
	end,
}
