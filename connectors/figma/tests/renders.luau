return {
	scenario = {publisher = {}, config = {}, auth_method = "token", auth_config = {token = "figd_fixture"}},
	configure = function()
		requests = {}
		responses = {}
		fs = fixture.files()
		http = {request = function(req)
			table.insert(requests, req)
			local next = table.remove(responses, 1)
			return fixture.operation({statusCode = next.statusCode, headers = {}, body = fixture.reader(next.body)})
		end}
	end,
	run = function(figma)
		local KEY = "aBcDeFgHiJkLmNoPqRsTuV12"
		local BUCKET = "https://figma-alpha-api.s3.us-west-2.amazonaws.com/images/"
		local NULL = json.decode("null")
		local function respond(statusCode, body) table.insert(responses, {statusCode = statusCode, body = body}) end
		local function contents(path)
			local file = fs.open(path, "r")
			local chunk = await(file:read(1024 * 1024))
			await(file:close())
			return if chunk.done then "" else chunk.data
		end

		respond(200, '{"err":null,"images":{"1:2":"' .. BUCKET .. 'u1","I3:4;5:6":"' .. BUCKET .. 'u2","7:8":null}}')
		respond(200, "png-one")
		respond(200, "png-two")
		local saved = figma.renderImages({file_key = KEY, ids = {"1:2", "I3:4;5:6", "7:8"}, scale = 2, save_to = "renders/"})
		assert(#requests == 3 and requests[1].url == "https://api.figma.com/v1/images/" .. KEY .. "?ids=1%3A2,I3%3A4%3B5%3A6,7%3A8&scale=2", requests[1].url)
		-- Downloads go to the render bucket in sorted id order, without credentials.
		assert(requests[2].method == "GET" and requests[2].url == BUCKET .. "u1" and requests[2].headers == nil)
		assert(requests[3].url == BUCKET .. "u2")
		local one, two = saved.images["1:2"], saved.images["I3:4;5:6"]
		assert(one.path == "renders/1-2.png" and one.size == 7 and type(one.url) == "string" and contents("renders/1-2.png") == "png-one")
		assert(two.path == "renders/I3-4-5-6.png" and contents(two.path) == "png-two")
		assert(saved.images["7:8"] == NULL and saved.err == NULL)

		respond(200, '{"err":null,"images":{"1:2":"https://evil.example/images/u1"}}')
		local ok, err = pcall(function() figma.renderImages({file_key = KEY, ids = "1:2", format = "jpg", save_to = "renders"}) end)
		assert(not ok and string.find(tostring(err), "unexpected host", 1, true) and #requests == 4, tostring(err))

		respond(200, '{"err":null,"images":{"1:2":"' .. BUCKET .. 'gone"}}')
		respond(403, "<Error>AccessDenied</Error>")
		ok, err = pcall(function() figma.renderImages({file_key = KEY, ids = "1:2", format = "jpg", save_to = "renders"}) end)
		assert(not ok and string.find(tostring(err), "Downloading the render of 1:2 failed with HTTP 403", 1, true)
			and string.find(tostring(err), '"retryable":true', 1, true), tostring(err))

		respond(400, '{"status":400,"err":"Invalid parameter: scale"}')
		ok, err = pcall(function() figma.renderImages({file_key = KEY, ids = "1:2", scale = 9, save_to = "renders"}) end)
		assert(not ok and string.find(tostring(err), "Figma HTTP 400: Invalid parameter: scale", 1, true), tostring(err))
		respond(200, '{"err":"Render timeout","images":null}')
		ok, err = pcall(function() figma.renderImages({file_key = KEY, ids = "1:2", save_to = "renders"}) end)
		assert(not ok and string.find(tostring(err), "Figma rendered no images: Render timeout", 1, true), tostring(err))
		assert(#requests == 8)

		local many = {}
		for index = 1, 11 do many[index] = "1:" .. index end
		ok, err = pcall(function() figma.renderImages({file_key = KEY, ids = many, save_to = "renders"}) end)
		assert(not ok and string.find(tostring(err), "save_to saves at most 10 ids", 1, true) and #requests == 8, tostring(err))
		ok, err = pcall(function() figma.renderImages({file_key = KEY, ids = "1:2", save_to = ""}) end)
		assert(not ok and string.find(tostring(err), "save_to must be a session folder path", 1, true) and #requests == 8, tostring(err))
	end,
}
