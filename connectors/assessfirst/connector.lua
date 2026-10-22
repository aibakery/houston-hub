-- AssessFirst API v2 (open beta). Arguments and results keep AssessFirst's native snake_case field names.
type Options = {[string]: any}
type Endpoint = {method: string, path: string, query: {string}?, body: {string}?, required: {string}?, array: boolean?, pdf: boolean?, about: string}

local API = "https://app.assessfirst.com/betty-V2"
local DOCS = "https://documenter.getpostman.com/view/12154847/2sB2qWGjNX"
local NULL = json.decode("null")
local NONE: {string} = table.freeze({})
local EVENTS = {"assessment.finished", "user.linked", "user.completed", "user.deleted"}
local PREDICTIVE_REPORTS = {17, 18, 35}
local PAGE = {"page", "per_page"}
local CANDIDATE = {"email", "first_name", "last_name", "gender", "recruiter_email"}

local function list(...: {string}): {string}
	local fields: {string} = {}
	for _, group in {...} do table.move(group, 1, #group, #fields + 1, fields) end
	return fields
end

-- Paths are relative to API. Only GET reads; path {fields}, query and body fields come from one options object.
local endpoints: {[string]: Endpoint} = {
	listLocales = {method = "GET", path = "/locales", array = true, about = "Languages the API speaks: {{name, iso_code_639, flag}}. Pass iso_code_639 as locale."},
	listRecruiters = {method = "GET", path = "/recruiters", query = list({"uuid", "email"}, PAGE),
		about = "Recruiters of your company: {data={{uuid, first_name, last_name, email, created_at}}, meta}. email matches partially."},
	listCandidates = {method = "GET", path = "/candidates", query = list({"uuid", "email"}, PAGE),
		about = "Candidates available to your company: {data={{uuid, first_name, last_name, email, created_at}}, meta}. email matches partially: pick the entry whose email equals the address."},
	getCandidate = {method = "GET", path = "/candidate/{candidate_uuid}",
		about = "A candidate: {uuid, email, first_name, last_name, locale, status, aplayer_score, remote_score, candidate_url, assessments={{id, name, status, end_date}}}. Assessment ids are not report_ids."},
	listCandidateReports = {method = "GET", path = "/candidate/{candidate_uuid}/reports", array = true,
		about = "Reports available for the candidate: {{id, name, assessment, web_link}}; web_link opens the report on AssessFirst's report site."},
	downloadCandidateReport = {method = "GET", path = "/candidate/{candidate_uuid}/report/{report_id}", query = {"pm_uuid"}, pdf = true,
		about = "Saves a report PDF to the session file path and returns {path, size, url, contentType}; url is Houston's signed download link. report_id: 1, 2, 3 personality (Swipe) in-depth, summary, key behaviors; 13, 15 motivations (Drive) in-depth, summary; 8, 10 reasoning (Brain) in-depth, summary; 20 complete summary; 50 HR report; 51 report for recruiters and managers; 17, 18 fit with a predictive model, full and short; 35 voice. 17, 18 and 35 require pm_uuid."},
	getCandidateAdequacies = {method = "GET", path = "/candidate/{candidate_uuid}/adequacies/{pm_uuid}",
		about = "Fit with a predictive model: {adequacies={global_adequacy, success_adequacy, fulfillment_adequacy, adequacy_shape, adequacy_drive, adequacy_brain} (percentages), reports={{id, name, web_link}}, voice={{score, status, skill_label, skill_definition, skill_type, skill_level, user_level, web_link}}, predict_success_url}. predict_success_url opens the fit in AssessFirst for signed-in recruiters."},
	getCandidateCompletion = {method = "GET", path = "/candidate/{candidate_uuid}/completion", query = {"pm_uuid"},
		about = "Which assessments are done: {assessments={swipe='finish', drive='finish', voice='todo', ...}, is_completed}. Checked against pm_uuid's assessments, or your company's default set without it. Check each assessment's status: is_completed can be true while voice is still todo."},
	getCandidateScores = {method = "GET", path = "/candidate/{candidate_uuid}/scores", array = true,
		about = "Scores for every AssessFirst dimension: {{id, label, name, score, min, max}}. Scales differ by dimension (1..10, 0..100, -4..4, ...), so read each item's min and max; name can be null and scores decimal."},
	getCandidateSynthesis = {method = "GET", path = "/candidate/{candidate_uuid}/synthesis",
		about = "Written synthesis of the Swipe (as shape), Drive and Brain results: categories and behaviours with labels, descriptions, scores, success and fulfillment tips. Large."},
	getCandidateTopCareers = {method = "GET", path = "/candidate/{candidate_uuid}/career/top", query = {"type"},
		about = "The 10 jobs that best match the candidate. type='full' is the only documented value."},
	getCandidateOnePager = {method = "GET", path = "/onepager/candidate/{candidate_uuid}/results", query = {"pm_uuid"},
		about = "A OnePager library link whose token, valid for 15 minutes, lets anyone who has it open all the candidate's reports without signing in; share it only with people entitled to see them. AssessFirst enables OnePager per company."},
	getVoiceStatus = {method = "GET", path = "/candidate/{candidate_uuid}/init-voice/{pm_uuid}",
		about = "The candidate's voice assessment for a voice predictive model: {uuid, candidate_uuid, predictive_model_uuid}. Needs AssessFirst's Voice option."},
	listPredictiveModels = {method = "GET", path = "/predictive-models", query = list({"name", "uuid", "is_public"}, PAGE),
		about = "Your predictive models, the job profiles candidates are matched against: {data={{uuid, name, assessments={swipe, drive, brain, voice}, is_public, created_at}}, meta}. name matches partially. Create and edit them in AssessFirst."},
	listBenchmarks = {method = "GET", path = "/benchmarks", query = {"name"},
		about = "AssessFirst's library of benchmark predictive models by job title: {data={{uuid, name, assessments, created_at}}}. name matches partially."},
	listWebhooks = {method = "GET", path = "/webhooks", query = list({"name", "url", "actions"}, PAGE),
		about = "Your webhooks: {data={{uuid, name, url, actions, created_at}}, meta}. name and url match partially; actions filters by an array of events."},
	listGroups = {method = "GET", path = "/groups", query = PAGE,
		about = "Candidate groups: {data={{uuid, label, color, created_at}}, meta}. Paging here is undocumented: stop if meta.current_page is not the page you asked for."},
	listGroupUsers = {method = "GET", path = "/groups/{group_uuid}/users", query = PAGE,
		about = "Candidates in a group: {data={{uuid, first_name, last_name, email}}, meta}. Paging here is undocumented: stop if meta.current_page is not the page you asked for."},

	sendInvitation = {method = "POST", path = "/candidate/send-invitation", body = list(CANDIDATE, {"message", "predictive_model_uuid"}), required = {"email"},
		about = "AssessFirst emails the candidate an invitation to take the assessments, or to share existing results with your company. gender is 'f', 'n' (default) or 'm'; recruiter_email defaults to your company's ATS recruiter; message is added to the email; predictive_model_uuid (recommended) picks the assessments and starts voice when the model has it. Returns {uuid, last_invited_at, status}: invitation_sent, ask_share, reminder_sent, assessment_reminder, already_completed, added_to_network, or user_already_invited_24_hours_ago (one invitation per email address a day)."},
	createCandidate = {method = "POST", path = "/candidate", body = CANDIDATE, required = {"email"},
		about = "Adds a candidate to your company without asking them; you are responsible for their GDPR consent. Returns {uuid, status}: added_to_network or already_in_sharepool."},
	startVoiceAssessment = {method = "POST", path = "/candidate/{candidate_uuid}/init-voice/{pm_uuid}",
		about = "Creates the candidate's voice assessment for a voice predictive model; sendInvitation with predictive_model_uuid already does this. Returns {uuid, candidate_uuid, predictive_model_uuid}."},
	createWebhook = {method = "POST", path = "/webhooks", body = {"name", "url", "actions"}, required = {"name", "url", "actions"},
		about = "actions is an array of assessment.finished, user.linked, user.completed and user.deleted. AssessFirst then POSTs {data={user={uuid, email, assessment?}}, webhook={uuid, name, action}} to url, a receiver you control. AssessFirst documents no payload signature, so the receiver should read the candidate again rather than trust the payload. AssessFirst recommends assessment.finished and user.linked, then getCandidateCompletion on each event; candidates who were already_completed or added_to_network send none. Returns {uuid, name, url, actions}."},
	deleteWebhook = {method = "DELETE", path = "/webhooks/{webhook_uuid}", about = "Deletes a webhook."},
	createGroup = {method = "POST", path = "/groups", body = {"label", "color"}, required = {"label"},
		about = "Creates a candidate group; color is hex such as '#000000'. Returns the group with its uuid."},
	deleteGroup = {method = "DELETE", path = "/groups/{group_uuid}", about = "Deletes a group."},
	addGroupUser = {method = "POST", path = "/groups/{group_uuid}/user/{user_uuid}", about = "Adds a candidate to a group. Returns {user, group}."},
	removeGroupUser = {method = "DELETE", path = "/groups/{group_uuid}/user/{user_uuid}", about = "Removes a candidate from a group."},
}

local function options(input: Options?): Options
	if input == nil then return {} end
	assert(type(input) == "table", "opts must be an object")
	for key in input do assert(type(key) == "string", "opts must have named fields") end
	return table.clone(input)
end

local function text(value: any, field: string): string
	assert(type(value) == "string" and value ~= "", field .. " must be a nonempty string")
	return value
end

-- AssessFirst UUIDs are hexadecimal, usually 32 characters without dashes.
local function uuid(value: any, field: string): string
	assert(type(value) == "string" and #value <= 64 and string.match(value, "^[%x%-]+$"), field .. " must be an AssessFirst UUID")
	return value
end

local function integer(value: any, field: string, maximum: number): number
	assert(type(value) == "number" and value % 1 == 0 and value >= 1 and value <= maximum, field .. " must be an integer from 1 to " .. tostring(maximum))
	return value
end

local function events(value: any, field: string): {string}
	assert(type(value) == "table" and #value > 0, field .. " must be a nonempty array of events")
	local count = 0
	for _, event in value do
		count += 1
		assert(table.find(EVENTS, event), field .. " must contain only " .. table.concat(EVENTS, ", "))
	end
	assert(count == #value, field .. " must be an array, not an object")
	return value
end

-- Each query or body value as AssessFirst expects it; other fields are nonempty strings.
local FIELDS: {[string]: (any, string) -> any} = {
	uuid = uuid, pm_uuid = uuid, predictive_model_uuid = uuid, actions = events,
	page = function(value: any, field: string): any return integer(value, field, 9007199254740991) end,
	per_page = function(value: any, field: string): any return integer(value, field, 50) end,
	is_public = function(value: any, field: string): any
		assert(type(value) == "boolean", field .. " must be a boolean")
		return if value then 1 else 0
	end,
	gender = function(value: any, field: string): any
		assert(value == "f" or value == "n" or value == "m", field .. " must be 'f', 'n' or 'm'")
		return value
	end,
	locale = function(value: any, field: string): any
		assert(type(value) == "string" and #value <= 16 and string.match(value, "^%a%a[%w%-]*$"), field .. " must be a locale such as 'fr-FR'")
		return value
	end,
}

local function check(field: string, value: any): any
	local validate = FIELDS[field]
	if validate then return validate(value, field) end
	return text(value, field)
end

local function fail(name: string, response: HttpResponse, message: string, retryable: boolean?): never
	return houston.fail({operation = name, layer = "upstream", upstream_status = response.statusCode,
		retryable = retryable == true, message = message})
end

-- AssessFirst errors are {code, message, data, status}; validation errors may add errors={field={...}}.
local function failStatus(name: string, endpoint: Endpoint, response: HttpResponse): never
	local ok, value = pcall(json.decode, await(response.body:readPrefix(16 * 1024)))
	local message = "AssessFirst HTTP " .. tostring(response.statusCode)
	local revoked = false
	if ok and type(value) == "table" then
		if type(value.message) == "string" then message ..= ": " .. string.sub(value.message, 1, 600) end
		if type(value.errors) == "table" then message ..= " " .. string.sub(json.encode(value.errors), 1, 600) end
		revoked = response.statusCode == 500 and value.message == "an error occured"
		if revoked then message ..= " (AssessFirst also answers this way when the API token is invalid or revoked)" end
	end
	local retry = response.headers["retry-after"]
	if retry and retry[1] then message ..= "; Retry-After: " .. retry[1] end
	-- A throttled request was refused; a failed write may already have applied, and a revoked token stays revoked.
	local retryable = response.statusCode == 429 or (response.statusCode >= 500 and endpoint.method == "GET" and not revoked)
	return fail(name, response, message, retryable)
end

local function download(name: string, endpoint: Endpoint, response: HttpResponse, path: string): Options
	local contentType = (response.headers["content-type"] or NONE)[1] or ""
	local mediaType = string.lower(string.match(contentType, "^%s*([^;%s]*)") or "")
	-- A report that cannot be produced is explained in JSON; anything else but a file is a sign-in or error page.
	if string.find(mediaType, "json", 1, true) then failStatus(name, endpoint, response) end
	if mediaType ~= "application/pdf" and mediaType ~= "application/octet-stream" then
		response.body:close()
		fail(name, response, "AssessFirst returned " .. (if mediaType == "" then "an untyped response" else mediaType) .. " instead of a PDF")
	end
	local file = fs.open(path, "w")
	file:write(response.body)
	await(file:close())
	return {path = path, size = await(fs.stat(path)).size, url = await(fs.signedGetUrl(path)), contentType = contentType}
end

-- Withheld from every response: the iframe token takes assessments as the candidate, and an
-- sso parameter, such as predict_success_url's, signs in whoever opens the link.
local function withhold(value: any)
	if type(value) ~= "table" then return end
	for key, item in value do
		if key == "iframe_candidate_token" then
			value[key] = nil
		elseif type(item) == "string" and string.find(item, "sso=", 1, true) then
			local link = string.gsub(item, "([?&])sso=[^&#]*&?", "%1")
			link = string.gsub(link, "[?&]$", "")
			value[key] = string.gsub(link, "[?&]#", "#")
		else
			withhold(item)
		end
	end
end

local function decode(name: string, endpoint: Endpoint, response: HttpResponse): any
	local raw = await(response.body:readAll())
	if endpoint.method == "DELETE" and string.match(raw, "^%s*$") then return {} end
	local ok, value = pcall(json.decode, raw)
	local array = string.match(raw, "^%s*%[") ~= nil
	-- PHP encodes an empty object as [], so only array endpoints insist on the shape.
	if not ok or type(value) ~= "table" or (endpoint.array and not array) then
		fail(name, response, "AssessFirst returned an invalid JSON " .. (if endpoint.array then "array" else "object"))
	end
	withhold(value)
	return value
end

local function request(name: string, endpoint: Endpoint, input: Options?): any
	local args = options(input)
	if endpoint.pdf and table.find(PREDICTIVE_REPORTS, args.report_id) then
		assert(args.pm_uuid ~= nil, "report_id " .. tostring(args.report_id) .. " requires pm_uuid")
	end
	for _, field in endpoint.required or NONE do
		assert(args[field] ~= nil and args[field] ~= NULL, field .. " is required")
	end
	local path = string.gsub(endpoint.path, "{([%w_]+)}", function(field: string)
		local value = if field == "report_id" then string.format("%d", integer(args[field], field, 9999)) else uuid(args[field], field)
		args[field] = nil
		return value
	end)
	local query: {string} = {}
	for _, field in list(endpoint.query or NONE, {"locale"}) do
		local value = args[field]
		if value ~= nil then
			if field == "actions" then
				for _, event in events(value, field) do table.insert(query, "actions%5B%5D=" .. url.encode(event)) end
			else
				table.insert(query, field .. "=" .. url.encode(check(field, value)))
			end
			args[field] = nil
		end
	end
	if #query > 0 then path ..= "?" .. table.concat(query, "&") end
	local destination: string? = nil
	if endpoint.pdf then
		destination = text(args.path, "path")
		args.path = nil
	end
	-- Like AssessFirst's examples, PDFs are requested with the default Accept; errors are JSON either way.
	local headers: HttpHeaders = if endpoint.pdf then {} else {Accept = {"application/json"}}
	local body: string? = nil
	if endpoint.body then
		local fields: Options = {}
		for _, field in endpoint.body do
			if args[field] ~= nil then fields[field] = check(field, args[field]) end
			args[field] = nil
		end
		headers["Content-Type"] = {"application/json"}
		body = json.encode(fields)
	end
	local unknown = next(args)
	assert(unknown == nil, name .. " has no option " .. tostring(unknown))
	local response = await(http.request({method = endpoint.method, url = API .. path, headers = headers, body = body}))
	if response.statusCode < 200 or response.statusCode >= 300 then failStatus(name, endpoint, response) end
	if destination then return download(name, endpoint, response, destination) end
	return decode(name, endpoint, response)
end

local function signature(endpoint: Endpoint): string
	local fields: {string} = {}
	for field in string.gmatch(endpoint.path, "{([%w_]+)}") do table.insert(fields, field) end
	if endpoint.pdf then table.insert(fields, "path") end
	for _, field in list(endpoint.query or NONE, endpoint.body or NONE) do
		table.insert(fields, if table.find(endpoint.required or NONE, field) then field else field .. "?")
	end
	return "({" .. table.concat(fields, ", ") .. "})"
end

local exports: {[string]: any} = {}
for name, endpoint in endpoints do
	if endpoint.method == "GET" or config.access == "read-write" then
		exports[name] = function(args: Options?): any return request(name, endpoint, args) end
	end
end
exports.help = function(): string
	local names: {string} = {}
	for name in exports do if name ~= "help" then table.insert(names, name) end end
	table.sort(names)
	local lines = {
		"AssessFirst API v2, an open beta AssessFirst may still change (" .. DOCS .. "). Every function takes one named options object with AssessFirst's snake_case names; ? marks optional fields. Every function also takes locale?, such as 'fr-FR' (default en-US, see listLocales), for the language of returned text, reports and emails. Results are AssessFirst's JSON unchanged, except that the connector withholds iframe_candidate_token (it lets anyone take assessments as the candidate) and removes sso single sign-on parameters from links. Connector calls return completed values: use them directly, without await.",
		"Candidates, predictive models (pm_uuid, predictive_model_uuid), groups, users and webhooks have 32-character hexadecimal UUIDs; report_id is a number. Lists date records as 'YYYY-MM-DD hh:mm:ss'; writes may answer with ISO 8601 or Unix seconds. Swipe measures personality, Drive motivations and Brain reasoning; a predictive model scores candidates against a job.",
		"Paging: lists with page (from 1) and per_page (1..50) return {data, meta={total, current_page, per_page, previous_page, next_page, last_page}}, one page per call; continue while meta.current_page < meta.last_page.",
		"To follow a candidate: listCandidates({email='ana@example.com'}) finds their uuid; getCandidateCompletion({candidate_uuid=uuid, pm_uuid=pm}) tells whether they finished; then getCandidateAdequacies({candidate_uuid=uuid, pm_uuid=pm}), getCandidateScores({candidate_uuid=uuid}) or downloadCandidateReport({candidate_uuid=uuid, report_id=20, path='ana-summary.pdf'}). pm is a predictive model uuid from listPredictiveModels({name='Sales'}).",
		"Results are personal data: share them only with people entitled to see them. Predictive models, campaigns, consents and API tokens are managed in the AssessFirst app.",
		"No automatic retries except Houston's for short 429 waits; AssessFirst allows about 100 requests a minute. Errors report the HTTP status and AssessFirst's message, and retryable is true only for 429 and for failed reads. AssessFirst also answers an invalid or revoked API token with HTTP 500 'an error occured': ask an administrator to check the connection's token rather than retrying.",
	}
	if exports.sendInvitation then
		table.insert(lines, "To invite: sendInvitation({email='ana@example.com', first_name='Ana', last_name='Silva', predictive_model_uuid=pm}) emails the candidate. Status ask_share means they already have an AssessFirst account and must accept to share their results with you; wait for that before reading them. createCandidate adds a person without asking them, so collect their consent first. Deletions return {}. After a timeout or 5xx, read the candidate, group or webhook again before repeating a write.")
	else
		table.insert(lines, "This connection is read-only: inviting candidates and managing groups and webhooks need read and write access.")
	end
	for _, name in names do
		local endpoint = endpoints[name]
		table.insert(lines, name .. signature(endpoint) .. ": " .. endpoint.about .. " " .. endpoint.method .. " " .. endpoint.path)
	end
	return table.concat(lines, "\n")
end
return exports
