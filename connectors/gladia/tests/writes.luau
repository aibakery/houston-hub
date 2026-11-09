-- A read-write connection: uploads, job creation and deletion.
return {
	scenario = {publisher = {}, config = {access = "read-write"}, auth_method = "api_key", auth_config = {token = "gladia-fixture-key"}},
	configure = function()
		requests, responses = {}, {}
		fs = fixture.files()
		local multipart = http.multipart
		http = {multipart = multipart, request = function(req)
			if req.body ~= nil and type(req.body) ~= "string" then req.body = await(req.body:readAll()) end
			table.insert(requests, req)
			assert(#responses > 0, "unexpected request: " .. req.method .. " " .. req.url)
			local response = table.remove(responses, 1)
			return fixture.operation({statusCode = response.status or 200, headers = response.headers or {}, body = fixture.reader(response.body or "{}")})
		end}
	end,
	run = function(c)
		local API = "https://api.gladia.io"
		local ID = "45463597-20b7-4af7-b3b3-f5fb778203ab"
		local AUDIO = "https://api.gladia.io/file/6c09400e-23d2-4bd2-be55-96a5ececfa3b"
		local function last(method: string, href: string)
			local req = requests[#requests]
			assert(req.method == method and req.url == href, req.method .. " " .. req.url)
			assert(req.headers == nil or (req.headers.Authorization == nil and req.headers["x-gladia-key"] == nil), "the proxy injects the key")
			return req
		end
		local function fails(expected: {string}, fn: (...any) -> any, ...: any): number
			local before = #requests
			local ok, err = pcall(fn, ...)
			assert(not ok, "call succeeded")
			for _, text in expected do assert(string.find(tostring(err), text, 1, true), "missing " .. text .. " in " .. tostring(err)) end
			return #requests - before
		end
		local function write(path: string, bytes: string)
			local file = fs.open(path, "w")
			if bytes ~= "" then file:write(bytes) end
			await(file:close())
		end

		local names = {}
		for name in c do if name ~= "help" then table.insert(names, name) end end
		table.sort(names)
		assert(table.concat(names, ",") == "createTranscription,deleteTranscription,downloadAudio,getTranscription,listTranscriptions,uploadAudio",
			"read-write got " .. table.concat(names, ","))

		-- uploadAudio streams the session file as the multipart audio part, with its media type.
		write("calls/meeting.m4a", "fake-m4a-bytes")
		responses = {{body = '{"audio_url":"' .. AUDIO .. '","audio_metadata":{"id":"6c09400e-23d2-4bd2-be55-96a5ececfa3b","filename":"meeting.m4a","source":null,"extension":"m4a","size":14,"audio_duration":1.5,"number_of_channels":1}}'}}
		local uploaded = c.uploadAudio({path = "calls/meeting.m4a"})
		local req = last("POST", API .. "/v2/upload")
		local contentType = req.headers["Content-Type"][1]
		assert(string.match(contentType, "^multipart/form%-data; boundary=") ~= nil, contentType)
		for _, part in {'name="audio"', 'filename="meeting.m4a"', "audio/mp4", "fake-m4a-bytes"} do
			assert(string.find(req.body, part, 1, true), "upload body lacks " .. part)
		end
		assert(uploaded.audio_url == AUDIO and uploaded.audio_metadata.audio_duration == 1.5)

		-- Unknown extensions upload as generic bytes; missing and empty files never reach Gladia.
		write("voice.xyz", "x")
		responses = {{body = '{"audio_url":"' .. AUDIO .. '","audio_metadata":{}}'}}
		c.uploadAudio({path = "voice.xyz"})
		assert(string.find(last("POST", API .. "/v2/upload").body, "application/octet-stream", 1, true))
		assert(fails({"path missing.wav is not a session file"}, c.uploadAudio, {path = "missing.wav"}) == 0)
		write("empty.wav", "")
		assert(fails({"path empty.wav is empty"}, c.uploadAudio, {path = "empty.wav"}) == 0)
		responses = {{body = '{"audio_metadata":{}}'}}
		fails({"Gladia returned no audio_url"}, c.uploadAudio, {path = "voice.xyz"})

		-- createTranscription sends Gladia's own request fields as JSON, and only those given.
		responses = {{status = 201, body = '{"id":"' .. ID .. '","result_url":"' .. API .. '/v2/transcription/' .. ID .. '"}'}}
		local created = c.createTranscription({
			audio_url = uploaded.audio_url,
			language_config = {languages = {"fr"}, code_switching = false},
			diarization = true,
			diarization_config = {min_speakers = 2, max_speakers = 3},
			summarization = true,
			summarization_config = {type = "bullet_points"},
			custom_metadata = {meeting = "weekly"},
		})
		req = last("POST", API .. "/v2/transcription")
		assert(req.headers["Content-Type"][1] == "application/json")
		local body = json.decode(req.body)
		assert(body.audio_url == AUDIO and body.language_config.languages[1] == "fr" and body.language_config.code_switching == false)
		assert(body.diarization == true and body.diarization_config.max_speakers == 3 and body.summarization_config.type == "bullet_points")
		assert(body.custom_metadata.meeting == "weekly" and body.model == nil and body.translation == nil)
		assert(created.id == ID and created.result_url == API .. "/v2/transcription/" .. ID)

		-- Gladia's documentation also answers 200 on acceptance.
		responses = {{body = '{"id":"' .. ID .. '","result_url":"' .. API .. '/v2/transcription/' .. ID .. '"}'}}
		assert(c.createTranscription({audio_url = "https://example.com/podcast.mp3", model = "solaria-1"}).id == ID)
		assert(json.decode(last("POST", API .. "/v2/transcription").body).model == "solaria-1")

		-- Invalid requests never reach Gladia; Gladia's validation errors are reported.
		assert(fails({"audio_url is required"}, c.createTranscription, {diarization = true}) == 0)
		assert(fails({"audio_url must be an http or https URL"}, c.createTranscription, {audio_url = "file:///etc/passwd"}) == 0)
		assert(fails({"createTranscription has no option callback_url"}, c.createTranscription,
			{audio_url = "https://example.com/a.wav", callback_url = "https://example.com/hook"}) == 0)
		assert(fails({"model must be a nonempty string"}, c.createTranscription, {audio_url = "https://example.com/a.wav", model = ""}) == 0)
		responses = {{status = 422, body = '{"statusCode":422,"message":"Unprocessable","validation_errors":["Field language must be a string"]}'}}
		fails({"Gladia HTTP 422: Unprocessable; Field language must be a string", '"retryable":false'}, c.createTranscription, {audio_url = "https://example.com/a.wav"})
		responses = {{status = 201, body = '{"result_url":"x"}'}}
		fails({"Gladia returned no job id"}, c.createTranscription, {audio_url = "https://example.com/a.wav"})

		-- deleteTranscription answers 202 without a body.
		responses = {{status = 202, body = ""}}
		assert(c.deleteTranscription({id = ID}).success == true)
		last("DELETE", API .. "/v2/transcription/" .. ID)
		responses = {{status = 403, body = '{"statusCode":403,"message":"Forbidden"}'}}
		fails({"Gladia HTTP 403: Forbidden", "neither queued nor processing", '"retryable":false'}, c.deleteTranscription, {id = ID})
		assert(fails({"id must be a Gladia job UUID"}, c.deleteTranscription, {id = "all"}) == 0)
		assert(#responses == 0)
	end,
}
