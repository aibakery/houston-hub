-- A read-only connection: job reads, paging, audio downloads and Gladia's errors.
return {
	scenario = {publisher = {}, config = {}, auth_method = "api_key", auth_config = {token = "gladia-fixture-key"}},
	config = {access = "read-only"},
	configure = function()
		requests, responses = {}, {}
		fs = fixture.files()
		http = {request = function(req)
			assert(req.headers == nil or (req.headers.Authorization == nil and req.headers["x-gladia-key"] == nil), "the proxy injects the key")
			table.insert(requests, req)
			assert(#responses > 0, "unexpected request: " .. req.method .. " " .. req.url)
			local response = table.remove(responses, 1)
			return fixture.operation({statusCode = response.status or 200, headers = response.headers or {}, body = fixture.reader(response.body or "{}")})
		end}
	end,
	run = function(c)
		local API = "https://api.gladia.io/v2/transcription"
		local ID = "45463597-20b7-4af7-b3b3-f5fb778203ab"
		local function last(method: string, href: string)
			local req = requests[#requests]
			assert(req.method == method and req.url == href, req.method .. " " .. req.url)
			return req
		end
		local function fails(expected: {string}, fn: (...any) -> any, ...: any): number
			local before = #requests
			local ok, err = pcall(fn, ...)
			assert(not ok, "call succeeded")
			for _, text in expected do assert(string.find(tostring(err), text, 1, true), "missing " .. text .. " in " .. tostring(err)) end
			return #requests - before
		end

		local names = {}
		for name in c do if name ~= "help" then table.insert(names, name) end end
		table.sort(names)
		assert(table.concat(names, ",") == "downloadAudio,getTranscription,listTranscriptions", "read-only got " .. table.concat(names, ","))

		-- A finished job comes back unchanged, transcript included.
		responses = {{body = '{"id":"' .. ID .. '","request_id":"G-1","version":2,"status":"done","created_at":"2026-11-09T10:00:00Z","completed_at":"2026-11-09T10:01:00Z","kind":"pre-recorded","post_session_metadata":{},"file":{"id":"f1","filename":"call.wav","source":null,"audio_duration":42.5,"number_of_channels":1},"request_params":{"diarization":true},"result":{"metadata":{"audio_duration":42.5,"number_of_distinct_channels":1,"billing_time":42.5,"transcription_time":3.1},"transcription":{"full_transcript":"Hello there.","languages":["en"],"utterances":[{"start":0.1,"end":1.2,"confidence":0.98,"channel":0,"speaker":0,"text":"Hello there.","language":"en","words":[{"word":"Hello","start":0.1,"end":0.5,"confidence":0.99}]}]}}}'}}
		local job = c.getTranscription({id = ID})
		last("GET", API .. "/" .. ID)
		assert(job.status == "done" and job.result.transcription.full_transcript == "Hello there.")
		local utterance = job.result.transcription.utterances[1]
		assert(utterance.speaker == 0 and utterance.words[1].word == "Hello" and job.result.metadata.billing_time == 42.5)

		-- A running job has a null result.
		responses = {{body = '{"id":"' .. ID .. '","status":"processing","result":null}'}}
		local running = c.getTranscription({id = ID})
		assert(running.status == "processing" and running.result == json.decode("null"))

		-- IDs and options are checked before any request.
		assert(fails({"id must be a Gladia job UUID"}, c.getTranscription, {id = "../v1/history"}) == 0)
		assert(fails({"id must be a nonempty string"}, c.getTranscription, {}) == 0)
		assert(fails({"getTranscription has no option job_id"}, c.getTranscription, {id = ID, job_id = ID}) == 0)

		-- Lists keep Gladia's page and repeat array filters; an empty page stays an array.
		responses = {
			{body = '{"first":"' .. API .. '?offset=0&limit=10","current":"' .. API .. '?offset=0&limit=10","next":"' .. API .. '?offset=10&limit=10","items":[{"id":"' .. ID .. '","status":"done","kind":"pre-recorded"}]}'},
			{body = '{"first":"' .. API .. '","current":"' .. API .. '","next":null,"items":[]}'},
		}
		local page = c.listTranscriptions({limit = 10, status = {"done", "error"}, kind = {"pre-recorded"}, after_date = "2026-11-01T00:00:00Z"})
		last("GET", API .. "?limit=10&after_date=2026-11-01T00%3A00%3A00Z&status=done&status=error&kind=pre-recorded")
		assert(page.items[1].id == ID and type(page.next) == "string")
		local empty = c.listTranscriptions()
		last("GET", API)
		assert(json.encode(empty.items) == "[]" and type(empty.next) ~= "string")
		assert(fails({"limit must be an integer from 1 to 100"}, c.listTranscriptions, {limit = 500}) == 0)
		assert(fails({"offset must be an integer of at least 0"}, c.listTranscriptions, {offset = -20}) == 0)
		assert(fails({"listTranscriptions has no option custom_metadata"}, c.listTranscriptions, {custom_metadata = {user = "ana"}}) == 0)
		responses = {{body = '{"items":"none"}'}}
		fails({"Gladia returned an invalid job page"}, c.listTranscriptions)

		-- The audio streams to a session file.
		responses = {{headers = {["content-type"] = {"audio/wav"}}, body = "RIFF....WAVEfmt "}}
		local saved = c.downloadAudio({id = ID, path = "audio/call.wav"})
		last("GET", API .. "/" .. ID .. "/file")
		assert(saved.path == "audio/call.wav" and saved.size == 16 and saved.contentType == "audio/wav" and type(saved.url) == "string")
		assert(await(fs.open("audio/call.wav", "r"):readAll()) == "RIFF....WAVEfmt ")

		-- Expired audio fails with Gladia's error code and leaves no file behind.
		responses = {{status = 404, body = '{"timestamp":"2026-11-09T10:00:00Z","path":"/v2/transcription/x/file","request_id":"G-2","statusCode":404,"message":"Not found","error_code":"retention_period_expired"}'}}
		fails({"Gladia HTTP 404: Not found (retention_period_expired)", '"retryable":false', '"upstream_status":404', '"operation":"downloadAudio"'},
			c.downloadAudio, {id = ID, path = "gone.wav"})
		assert(not await(fs.exists("gone.wav")))

		-- Gladia's errors keep the status and message; rate limits and outages are retryable.
		responses = {{status = 429, headers = {["retry-after"] = {"3"}}, body = '{"statusCode":429,"message":"Too many requests"}'}}
		fails({"Gladia HTTP 429: Too many requests", "Retry-After: 3", "concurrency or request-rate limit", '"retryable":true'}, c.listTranscriptions)
		responses = {{status = 401, body = '{"statusCode":401,"message":"Unauthorized"}'}}
		fails({"Gladia HTTP 401: Unauthorized", "Check that the API key", '"retryable":false'}, c.getTranscription, {id = ID})
		responses = {{status = 503, body = "<html>unavailable</html>"}}
		fails({"Gladia HTTP 503", '"retryable":true'}, c.getTranscription, {id = ID})
		responses = {{body = "not json"}}
		fails({"Gladia returned an invalid JSON object"}, c.getTranscription, {id = ID})
		assert(#responses == 0)
	end,
}
