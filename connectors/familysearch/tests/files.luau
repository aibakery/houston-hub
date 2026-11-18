return {
	scenario = {config = {environment = "production"}, access = {data = "write"}, auth_method = "token", auth_config = {token = "fixture-token"}},
	configure = function()
		requests, responses = {}, {}
		fs = fixture.files()
		http = {request = function(req)
			table.insert(requests, req)
			if req.body ~= nil and type(req.body) ~= "string" then req.streamed = true; req.body = await(req.body:readAll()) end
			local response = table.remove(responses, 1)
			assert(response, "unexpected request")
			return fixture.operation({statusCode = response.status or 200, headers = response.headers or {}, body = fixture.reader(response.body or "")})
		end}
	end,
	run = function(c)
		local bytes = string.char(0, 255, 13, 10) .. "image payload"
		responses = {{body = bytes, headers = {["content-type"] = {"image/jpeg"}}}}
		local saved = c.memories.artifacts.downloadMemoryArtifact({mid = "ARXX-MMM", path = "downloads/memory.jpg", variant = "thumbnail"})
		assert(saved.statusCode == 200 and saved.path == "downloads/memory.jpg" and saved.size == #bytes and saved.url == "https://houston.test/downloads/memory.jpg")
		assert(requests[#requests].url == "https://api.familysearch.org/platform/memories/artifacts/ARXX-MMM?thumbnail")
		local file = fs.open(saved.path, "r")
		assert(await(file:readAll()) == bytes)
		await(file:close())
		responses = {{status = 307, headers = {location = {"https://images.familysearch.org/example.jpg"}}}}
		local redirect = c.memories.artifacts.downloadMemoryArtifact({mid = "ARXX-MMM", path = "downloads/redirect.jpg"})
		assert(redirect.statusCode == 307 and redirect.path == nil and redirect.headers.location[1] == "https://images.familysearch.org/example.jpg")

		responses = {{status = 201, headers = {location = {"https://api.familysearch.org/platform/memories/memories/new"}}}, {status = 201, headers = {["x-entity-id"] = {"new-person-memory"}}}}
		local created = c.memories.createMemories({path = saved.path, contentType = "image/jpeg", title = "Family photograph", filename = "family.jpg", type = "Photo"})
		assert(created.statusCode == 201 and requests[#requests].streamed and requests[#requests].body == bytes)
		assert(requests[#requests].headers["Content-Type"][1] == "image/jpeg" and string.find(requests[#requests].url, "title=Family%20photograph", 1, true))
		c.tree.memories.createPersonMemory({pid = "P1", path = saved.path, contentType = "image/jpeg"})
		assert(requests[#requests].url == "https://api.familysearch.org/platform/tree/persons/P1/memories")
		responses = {{status = 201}}
		local ok, err = pcall(c.memories.createMemories, {path = saved.path, contentType = "image/jpeg"})
		assert(not ok and string.find(tostring(err), '"retryable":false', 1, true) and string.find(tostring(err), "may have been created", 1, true))

		local story = fs.open("uploads/story.txt", "w")
		story:write("My ancestor's story")
		await(story:close())
		responses = {{status = 204}}
		assert(c.memories.artifacts.updateMemoryArtifact({mid = "M1", aid = "0", path = "uploads/story.txt", contentType = "text/plain"}).statusCode == 204)
		assert(requests[#requests].streamed and requests[#requests].body == "My ancestor's story")

		local audio = fs.open("uploads/interview.mp3", "w")
		audio:write(bytes)
		await(audio:close())
		responses = {{status = 201, headers = {location = {"https://api.familysearch.org/platform/memories/memories/audio"}}}}
		c.memories.createMemories({path = "uploads/interview.mp3", contentType = "audio/mpeg", multipart = true, title = "Family interview"})
		local sentAudio = requests[#requests]
		assert(sentAudio.streamed and string.find(sentAudio.headers["Content-Type"][1], "multipart/form-data; boundary=", 1, true) == 1)
		assert(string.find(sentAudio.body, 'name="artifact"; filename="interview.mp3"', 1, true))
		assert(string.find(sentAudio.body, "Content-Type: audio/mpeg", 1, true) and string.find(sentAudio.body, bytes, 1, true))
		local count = #requests
		assert(not pcall(c.memories.createMemories, {path = "uploads/interview.mp3", contentType = "audio/mpeg"}), "audio requires multipart")
		assert(#requests == count)

		responses = {{body = "<html><p>A story</p></html>", headers = {["content-type"] = {"text/html"}}}, {status = 201, headers = {location = {"https://api.familysearch.org/platform/genealogies/media/2:3:54321"}}}, {status = 204}}
		local html = c.genealogies.media.readGenealogiesMedia({mid = "2:3:54321", path = "downloads/story.html"})
		assert(html.size == 27 and requests[#requests].headers.Accept[1] == "text/html")
		assert(c.genealogies.media.createGenealogiesMedia({tid = "2:3:12345", path = html.path, contentType = "text/html"}).statusCode == 201)
		assert(c.genealogies.media.updateGenealogiesMedia({mid = "2:3:54321", path = html.path, contentType = "text/html"}).statusCode == 204)
		assert(requests[#requests].streamed and requests[#requests].headers["Content-Type"][1] == "text/html")
		assert(#responses == 0)
	end,
}
