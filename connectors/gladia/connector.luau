-- Gladia API v2 (https://docs.gladia.io/api-reference/v2/): pre-recorded speech-to-text jobs, their
-- results and the audio they used. Arguments and results keep Gladia's native snake_case field names.
type Options = {[string]: any}

local API = "https://api.gladia.io"
local DOCS = "https://docs.gladia.io/api-reference/v2/"
-- Gladia accepts files up to 1000 MB and transcribes at most 135 minutes per job.
local MAX_UPLOAD = 1000 * 1000 * 1000
local MAX_BODY = 8 * 1024 * 1024
local NONE: {string} = table.freeze({})

local function text(value: any, field: string): string
	assert(type(value) == "string" and value ~= "", field .. " must be a nonempty string")
	return value
end

local function options(value: any): Options
	if value == nil then return {} end
	assert(type(value) == "table", "opts must be an object")
	for key in value do assert(type(key) == "string", "opts must have named fields") end
	return table.clone(value)
end

local function done(name: string, args: Options)
	local unknown = next(args)
	assert(unknown == nil, name .. " has no option " .. string.sub(tostring(unknown), 1, 64))
end

-- Gladia job IDs are UUIDs and it answers HTTP 400 for anything else, so validate before the call.
local function jobId(value: any): string
	local id = text(value, "id")
	assert(
		string.match(id, "^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$") ~= nil,
		"id must be a Gladia job UUID, as createTranscription and listTranscriptions return"
	)
	return id
end

-- Moves the named fields from args into a query string; arrays repeat the key.
local function query(args: Options, names: {string}): string
	local parts: {string} = {}
	for _, name in names do
		local value = args[name]
		args[name] = nil
		for key, item in (if type(value) == "table" then value else {value}) do
			assert(
				type(key) == "number" and (type(item) == "string" or type(item) == "number"),
				name .. " must be a string, a number or an array of them"
			)
			table.insert(parts, url.encode(name) .. "=" .. url.encode(item))
		end
	end
	return if #parts > 0 then "?" .. table.concat(parts, "&") else ""
end

local function failStatus(operation: string, response: HttpResponse): never
	local status = response.statusCode
	local message = "Gladia HTTP " .. tostring(status)
	-- An error body that stalls or breaks counts as empty, so the status and retryable survive.
	local read, raw: any = pcall(function() return await(response.body:readPrefix(16 * 1024)) end)
	if not read and type(raw) == "table" and raw.code ~= nil then error(raw, 0) end
	local ok, problem = false, nil
	if read then ok, problem = pcall(json.decode, raw) end
	if ok and type(problem) == "table" then
		if type(problem.message) == "string" and problem.message ~= "" then
			message ..= ": " .. string.sub(problem.message, 1, 600)
		end
		if type(problem.error_code) == "string" then message ..= " (" .. problem.error_code .. ")" end
		if type(problem.validation_errors) == "table" then
			local errors: {string} = {}
			for _, item in problem.validation_errors do
				if type(item) == "string" then table.insert(errors, item) end
			end
			if #errors > 0 then message ..= "; " .. string.sub(table.concat(errors, "; "), 1, 600) end
		end
	end
	local retry = response.headers["retry-after"]
	if retry and retry[1] then message ..= "; Retry-After: " .. string.sub(retry[1], 1, 32) end
	if status == 401 then
		message ..= ". Check that the API key is valid and still belongs to this Gladia account"
	elseif status == 403 then
		message ..= ". Gladia deletes a job only once it is neither queued nor processing"
	elseif status == 429 then
		message ..= ". The Gladia account is at its concurrency or request-rate limit; wait before trying again"
	end
	return houston.fail({
		operation = operation,
		layer = "upstream",
		upstream_status = status,
		retryable = status == 429 or status >= 500,
		message = message,
	})
end

local function send(operation: string, method: string, href: string, headers: HttpHeaders?, body: any?): HttpResponse
	local sent, result: any = pcall(function()
		return await(http.request({method = method, url = href, headers = headers, body = body}))
	end)
	if not sent then
		if type(result) == "table" and result.code == "timeout" then
			houston.fail({
				operation = operation,
				layer = "upstream",
				retryable = true,
				message = "Gladia did not answer in time. An accepted job is not lost: list transcriptions before creating another",
			})
		end
		error(result, 0)
	end
	local response: HttpResponse = result
	if response.statusCode < 200 or response.statusCode >= 300 then failStatus(operation, response) end
	return response
end

-- A successful answer's JSON object, or {success=true} when a write answers without a body. Houston
-- returns at most 8 MiB per call, so an oversized result fails with the limit named.
local function decode(operation: string, response: HttpResponse): any
	local read, raw: any = pcall(function() return await(response.body:readAll(MAX_BODY)) end)
	if not read then
		if type(raw) == "table" and raw.code ~= nil then error(raw, 0) end
		houston.fail({
			operation = operation,
			layer = "upstream",
			upstream_status = response.statusCode,
			retryable = false,
			message = "Gladia's answer exceeds Houston's 8 MiB limit. List the jobs and read a shorter one",
		})
	end
	if string.match(raw, "^%s*$") then return {success = true} end
	local ok, value = pcall(json.decode, raw)
	if not ok or type(value) ~= "table" or not string.match(raw, "^%s*{") then
		houston.fail({
			operation = operation,
			layer = "upstream",
			upstream_status = response.statusCode,
			retryable = false,
			message = "Gladia returned an invalid JSON object",
		})
	end
	return value
end

-- Streams a response body to a session file; the path changes only when the whole body arrived.
local function save(path: string, fetch: () -> HttpResponse): Options
	local output = fs.open(path, "w")
	local ok, err = pcall(function()
		output:write(fetch().body)
		await(output:close())
	end)
	if not ok then
		output:cancel()
		pcall(function() await(output:close()) end)
		error(err, 0)
	end
	return {path = path, url = await(fs.signedGetUrl(path)), size = await(fs.stat(path)).size}
end

-- Gladia reads the media type of an uploaded part; name the common ones and leave the rest generic.
local MEDIA_TYPES: {[string]: string} = {
	["3gp"] = "video/3gpp", aac = "audio/aac", aif = "audio/aiff", aiff = "audio/aiff", amr = "audio/amr",
	caf = "audio/x-caf", flac = "audio/flac", m4a = "audio/mp4", mkv = "video/x-matroska",
	mov = "video/quicktime", mp3 = "audio/mpeg", mp4 = "video/mp4", mpeg = "audio/mpeg", mpg = "audio/mpeg",
	oga = "audio/ogg", ogg = "audio/ogg", opus = "audio/opus", wav = "audio/wav", webm = "audio/webm",
	wma = "audio/x-ms-wma",
}

local function mediaType(filename: string): string
	local extension = string.match(string.lower(filename), "%.([%w]+)$")
	return if extension then MEDIA_TYPES[extension] or "application/octet-stream" else "application/octet-stream"
end

local help: {text: string, functions: {[string]: any}} = {
	text = [[Gladia speech-to-text jobs of the Gladia account that owns this connection's API key. Every function
takes one named options object with Gladia's snake_case fields and returns Gladia's JSON unchanged.
Connector calls return completed values: use them directly, without await.
A job's status is queued, processing, done or error; its result holds the transcript once it is done.
Gladia keeps working on an accepted job for up to 2 hours, so queued and processing are not failures.
Houston cannot pause between calls: to follow a job, call getTranscription again later, spacing the
calls out.
Results keep Gladia's shape: result.transcription.full_transcript, languages and utterances
[{start, end, confidence, channel, speaker?, text, language, words}], plus sentences, subtitles,
translation, summarization, named_entity_recognition, sentiment_analysis, audio_to_llm, diarization
and pii_redaction sections when the job asked for them. Houston returns at most 8 MiB per call, so the
full result of a very long recording can exceed it.
Gladia keeps audio and results for the account's retention period (3 weeks on paid plans, a year on
Free), then answers HTTP 404 with error_code retention_period_expired.
Gladia answers HTTP 429 when the account's concurrency or request rate is exhausted; wait and retry.
Live transcription over WebSocket is not available through this connector.]],
	functions = {},
}
local exports: {[string]: any} = {help = help}

local ID = {type = "string", minLength = 1}
local READ = {readOnlyHint = true, openWorldHint = true}
local WRITE = {readOnlyHint = false, destructiveHint = false, openWorldHint = true}
local DESTRUCTIVE = {readOnlyHint = false, destructiveHint = true, openWorldHint = true}

-- An options object schema with its required names and one complete example.
local function schema(properties: Options, required: {string}, example: Options): Options
	return {
		type = "object",
		properties = properties,
		required = if #required > 0 then required else nil,
		additionalProperties = false,
		examples = {example},
	}
end

-- Reads

help.functions.getTranscription = {
	description = [[One pre-recorded job: {id, request_id, version, status (queued, processing, done or error),
created_at, completed_at?, custom_metadata?, error_code?, kind, file, request_params, result}. result
holds the transcript when status is done and is null otherwise. Call it again to follow a running job;
between calls, wait. Polling faster does not finish the job.]],
	inputSchema = schema(
		{id = {type = "string", minLength = 1, description = "Job UUID from createTranscription or listTranscriptions."}},
		{"id"},
		{id = "45463597-20b7-4af7-b3b3-f5fb778203ab"}
	),
	annotations = READ,
}
function exports.getTranscription(input: any): Options
	local args = options(input)
	local id = jobId(args.id)
	done("getTranscription", args)
	local job = decode("getTranscription", send("getTranscription", "GET", API .. "/v2/transcription/" .. id))
	assert(type(job.id) == "string" and type(job.status) == "string", "Gladia returned an invalid job")
	return job
end

help.functions.listTranscriptions = {
	description = [[A page of jobs, newest first: {first, current, next, items}. offset starts at 0 and limit
defaults to 20 (at most 100 here). date, before_date and after_date (ISO 8601, UTC) bound creation time;
status keeps queued, processing, done or error, and kind keeps pre-recorded or live. next is null on
the last page, else the URL of the following one: call again with offset increased by limit. Items carry
their whole job, results included, so keep limit small. Live jobs listed here have no transcript to
read through this connector.]],
	inputSchema = schema({
		offset = {type = "integer", minimum = 0, description = "Number of jobs to skip; starts at 0."},
		limit = {type = "integer", minimum = 1, maximum = 100, description = "Jobs per page; Gladia defaults to 20."},
		date = {type = "string", minLength = 1, description = "Keep jobs created on this day, such as 2026-11-09."},
		before_date = {type = "string", minLength = 1, description = "Keep jobs created before this ISO 8601 time."},
		after_date = {type = "string", minLength = 1, description = "Keep jobs created after this ISO 8601 time."},
		status = {type = "array", items = {type = "string"}, description = "queued, processing, done, error."},
		kind = {type = "array", items = {type = "string"}, description = "pre-recorded or live."},
	}, NONE, {status = {"done"}, limit = 10}),
	annotations = READ,
}
function exports.listTranscriptions(input: any): Options
	local args = options(input)
	local offset, limit = args.offset, args.limit
	if offset ~= nil then
		assert(type(offset) == "number" and offset == math.floor(offset) and offset >= 0, "offset must be an integer of at least 0")
	end
	if limit ~= nil then
		assert(type(limit) == "number" and limit == math.floor(limit) and limit >= 1 and limit <= 100, "limit must be an integer from 1 to 100")
	end
	local href = API .. "/v2/transcription" .. query(args, {"offset", "limit", "date", "before_date", "after_date", "status", "kind"})
	done("listTranscriptions", args)
	local page = decode("listTranscriptions", send("listTranscriptions", "GET", href))
	assert(type(page.items) == "table", "Gladia returned an invalid job page")
	return page
end

help.functions.downloadAudio = {
	description = [[Saves the audio or video file a job used to path, a session file, and returns
{path, url, size, contentType}. url is a signed session link that expires. Gladia keeps the file for the
account's retention period and then answers HTTP 404 with error_code retention_period_expired.]],
	inputSchema = schema(
		{id = {type = "string", minLength = 1, description = "Job UUID."}, path = {type = "string", minLength = 1, description = "Session file to write."}},
		{"id", "path"},
		{id = "45463597-20b7-4af7-b3b3-f5fb778203ab", path = "meeting.m4a"}
	),
	annotations = READ,
}
function exports.downloadAudio(input: any): Options
	local args = options(input)
	local id = jobId(args.id)
	local path = text(args.path, "path")
	done("downloadAudio", args)
	local contentType: string? = nil
	local saved = save(path, function()
		local response = send("downloadAudio", "GET", API .. "/v2/transcription/" .. id .. "/file")
		local kind = response.headers["content-type"]
		contentType = if kind then kind[1] else nil
		return response
	end)
	if contentType then saved.contentType = contentType end
	return saved
end

if config.access ~= "read-write" then
	help.text ..= [[

This connection is read-only: it lists and reads jobs and saves their audio, but cannot upload files,
start transcriptions or delete jobs.
Example: local page = gladia.listTranscriptions({status={'done'}, limit=10}); for _, job in page.items
do print(job.id, job.created_at) end; local t = gladia.getTranscription({id=page.items[1].id}).]]
end

if config.access == "read-write" then
	help.text ..= [[

To transcribe, pass a public audio or video URL as audio_url to createTranscription, or first upload a
session file with uploadAudio and pass the audio_url it returns. Gladia fetches external URLs itself,
so they must be reachable without credentials; signed links work. Limits: 1000 MB and 135 minutes per
job (4h15 on enterprise plans) and at most 2 channels; splitting near 60 minutes transcribes better.
createTranscription returns {id, result_url} once Gladia accepts the job. Gladia does not deduplicate:
every accepted call is a new, separately billed job, so never resubmit an accepted one. After a
timeout or an HTTP 5xx, list recent jobs before trying again. deleteTranscription removes a finished
job with its audio and result.
Example: local up = gladia.uploadAudio({path='call.m4a'}); local job = gladia.createTranscription({
audio_url=up.audio_url, diarization=true}); later, local t = gladia.getTranscription({id=job.id}); if
t.status == 'done' then print(t.result.transcription.full_transcript) end.]]

	-- Writes

	help.functions.uploadAudio = {
		description = [[Uploads a session file, up to 1000 MB, and returns {audio_url, audio_metadata={id, filename,
source, extension, size, audio_duration, number_of_channels}}. Pass audio_url to createTranscription.
The whole upload must finish within Houston's call deadline, so for a large recording pass a public URL
to createTranscription instead. Gladia keeps the file for the account's retention period.]],
		inputSchema = schema(
			{path = {type = "string", minLength = 1, description = "Session file holding the audio or video."}},
			{"path"},
			{path = "meeting.m4a"}
		),
		annotations = WRITE,
	}
	function exports.uploadAudio(input: any): Options
		local args = options(input)
		local path = text(args.path, "path")
		done("uploadAudio", args)
		assert(await(fs.exists(path)), "path " .. path .. " is not a session file")
		local size = await(fs.stat(path)).size
		assert(size > 0, "path " .. path .. " is empty")
		assert(size <= MAX_UPLOAD, "Gladia accepts files up to 1000 MB; split or shorten this one")
		local filename = string.match(path, "[^/]+$") or path
		local body, contentType = http.multipart({
			{name = "audio", filename = filename, contentType = mediaType(filename), body = fs.open(path, "r")},
		})
		local value = decode(
			"uploadAudio",
			send("uploadAudio", "POST", API .. "/v2/upload", {["Content-Type"] = {contentType}}, body)
		)
		assert(type(value.audio_url) == "string" and value.audio_url ~= "", "Gladia returned no audio_url")
		return value
	end

	-- The documented InitTranscriptionRequest fields, minus the deprecated callback_url. Nested
	-- configuration objects are passed through as Gladia documents them.
	local REQUEST_FIELDS = {
		"audio_url", "model", "language_config", "sentences", "punctuation_enhanced", "diarization",
		"diarization_config", "translation", "translation_config", "summarization", "summarization_config",
		"named_entity_recognition", "custom_spelling", "custom_spelling_config", "sentiment_analysis",
		"audio_to_llm", "audio_to_llm_config", "pii_redaction", "pii_redaction_config", "custom_vocabulary",
		"custom_vocabulary_config", "subtitles", "subtitles_config", "callback", "callback_config",
		"custom_metadata",
	}

	help.functions.createTranscription = {
		description = [[Starts a pre-recorded job and returns {id, result_url}. audio_url is required: the audio_url
uploadAudio returned, or a public URL Gladia can fetch without credentials. Optional fields are Gladia's
own: model (solaria-1 by default, also solaria-3 and solaria-fusion), language_config
{languages=[...], code_switching?} (Gladia detects the language when languages is empty), sentences,
punctuation_enhanced, diarization with diarization_config {min_speakers?, max_speakers?},
translation with translation_config {target_languages=[...], ...}, summarization with
summarization_config {type (general, bullet_points or concise)}, named_entity_recognition,
custom_spelling with custom_spelling_config, custom_vocabulary with custom_vocabulary_config
{vocabulary=[...], ...}, sentiment_analysis, audio_to_llm with audio_to_llm_config {prompts=[...]},
pii_redaction with pii_redaction_config, subtitles with subtitles_config {formats=[...], ...},
callback with callback_config {url, method?} to have Gladia post the result, and custom_metadata to tag
the job. Read getTranscription for the result; each accepted job is billed.]],
		inputSchema = schema({
			audio_url = {type = "string", minLength = 1, description = "Gladia audio_url or public audio or video URL."},
			model = {type = "string", minLength = 1, description = "solaria-1 (default), solaria-3 or solaria-fusion."},
			language_config = {type = "object", description = "{languages=[...], code_switching?}."},
			sentences = {type = "boolean"},
			punctuation_enhanced = {type = "boolean"},
			diarization = {type = "boolean"},
			diarization_config = {type = "object", description = "{min_speakers?, max_speakers?}."},
			translation = {type = "boolean"},
			translation_config = {type = "object", description = "{target_languages=[...], ...}."},
			summarization = {type = "boolean"},
			summarization_config = {type = "object", description = "{type}."},
			named_entity_recognition = {type = "boolean"},
			custom_spelling = {type = "boolean"},
			custom_spelling_config = {type = "object"},
			custom_vocabulary = {type = "boolean"},
			custom_vocabulary_config = {type = "object"},
			sentiment_analysis = {type = "boolean"},
			audio_to_llm = {type = "boolean"},
			audio_to_llm_config = {type = "object", description = "{prompts=[...]}."},
			pii_redaction = {type = "boolean"},
			pii_redaction_config = {type = "object"},
			subtitles = {type = "boolean"},
			subtitles_config = {type = "object", description = "{formats, ...}."},
			callback = {type = "boolean"},
			callback_config = {type = "object", description = "{url, method?}."},
			custom_metadata = {type = "object", description = "Tags attached to the job."},
		}, {"audio_url"}, {
			audio_url = "https://files.gladia.io/example/audio-transcription/split_infinity.wav",
			language_config = {languages = {"en"}},
			diarization = true,
			diarization_config = {min_speakers = 1, max_speakers = 4},
		}),
		annotations = WRITE,
	}
	function exports.createTranscription(input: any): Options
		local args = options(input)
		assert(args.audio_url ~= nil, "audio_url is required")
		local audio = text(args.audio_url, "audio_url")
		assert(string.match(audio, "^https?://") ~= nil, "audio_url must be an http or https URL")
		local body: Options = {}
		for _, field in REQUEST_FIELDS do
			local value = args[field]
			args[field] = nil
			if value ~= nil then body[field] = value end
		end
		if body.model ~= nil then text(body.model, "model") end
		done("createTranscription", args)
		local value = decode(
			"createTranscription",
			send("createTranscription", "POST", API .. "/v2/transcription", {["Content-Type"] = {"application/json"}}, json.encode(body))
		)
		assert(type(value.id) == "string" and value.id ~= "", "Gladia returned no job id")
		return value
	end

	help.functions.deleteTranscription = {
		description = [[Deletes a job with its audio and result, and returns {success=true}. Gladia answers HTTP 403
while the job is still queued or processing: wait for it to finish, or read it instead. Deleting is
permanent and the job cannot be transcribed again without uploading or fetching the audio once more.]],
		inputSchema = schema(
			{id = {type = "string", minLength = 1, description = "Job UUID."}},
			{"id"},
			{id = "45463597-20b7-4af7-b3b3-f5fb778203ab"}
		),
		annotations = DESTRUCTIVE,
	}
	function exports.deleteTranscription(input: any): Options
		local args = options(input)
		local id = jobId(args.id)
		done("deleteTranscription", args)
		return decode("deleteTranscription", send("deleteTranscription", "DELETE", API .. "/v2/transcription/" .. id))
	end
end

return exports
