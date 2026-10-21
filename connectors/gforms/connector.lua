-- Google Forms API v1. Arguments and results keep Google's native field names.
local API = "https://forms.googleapis.com/v1"

-- Request layer shared verbatim by the Google connectors (tools/validate checks they match).
type Options = {[string]: any}
type Endpoint = {method: string, path: string, read: boolean, query: {string}?, body: boolean?, defaults: Options?, list: string?, required: {[string]: string}?, help: string}

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

-- Moves the named fields from args into a query string; arrays repeat the key.
local function query(args: Options, names: {string}): string
	local parts: {string} = {}
	for _, name in names do
		local value = args[name]
		args[name] = nil
		for key, item in (if type(value) == "table" then value else {value}) do
			assert(type(key) == "number" and (type(item) == "string" or type(item) == "number" or type(item) == "boolean"), name .. " must be a string, number, boolean or an array of them")
			table.insert(parts, url.encode(name) .. "=" .. url.encode(item))
		end
	end
	return if #parts > 0 then "?" .. table.concat(parts, "&") else ""
end

local function fail(operation: string, response: HttpResponse): never
	local ok, decoded = pcall(json.decode, await(response.body:readPrefix(4096)))
	local problem = if ok and type(decoded) == "table" and type(decoded.error) == "table" then decoded.error else {}
	-- Older APIs name the reason in errors[], newer ones in an ErrorInfo detail.
	local reasons: {any} = if type(problem.errors) == "table" then problem.errors elseif type(problem.details) == "table" then problem.details else {}
	local reason: string? = nil
	for _, item in reasons do
		if type(item) == "table" and type(item.reason) == "string" then
			reason = item.reason
			break
		end
	end
	local message = "Google HTTP " .. tostring(response.statusCode)
	if type(problem.status) == "string" then message ..= " (" .. problem.status .. ")" end
	if type(problem.message) == "string" then message ..= ": " .. string.sub(problem.message, 1, 600) end
	if reason then message ..= " [" .. reason .. "]" end
	local retry = response.headers["retry-after"]
	if retry and retry[1] then message ..= "; Retry-After: " .. retry[1] end
	local limited = reason ~= nil and string.find((string.gsub(string.lower(reason), "_", "")), "ratelimitexceeded", 1, true) ~= nil
	return houston.fail({operation = operation, layer = "upstream", upstream_status = response.statusCode,
		retryable = response.statusCode == 429 or response.statusCode >= 500 or limited, message = message})
end

local function decode(operation: string, response: HttpResponse): any
	if response.statusCode < 200 or response.statusCode >= 300 then fail(operation, response) end
	local raw = await(response.body:readAll())
	if raw == "" then return {success = true} end
	local ok, value = pcall(json.decode, raw)
	if not ok or type(value) ~= "table" or not string.match(raw, "^%s*{") then
		houston.fail({operation = operation, layer = "upstream", upstream_status = response.statusCode,
			retryable = false, message = "Google returned an invalid JSON object"})
	end
	return value
end

local function call(operation: string, method: string, href: string, body: any?): any
	return decode(operation, await(http.request({method = method, url = href,
		headers = if body ~= nil then {["Content-Type"] = {"application/json"}} else nil,
		body = if body ~= nil then json.encode(body) else nil})))
end

-- Accepts a docs.google.com editor URL in place of its file ID; published and responder links (/d/e/...) carry no ID.
local function docsId(value: any, product: string, field: string): any
	if type(value) ~= "string" then return value end
	local rest = string.match(value, "^https://docs%.google%.com/" .. product .. "/d/(.*)$")
		or string.match(value, "^https://docs%.google%.com/" .. product .. "/u/%d+/d/(.*)$")
		or string.match(value, "^https://docs%.google%.com/a/[^/]+/" .. product .. "/d/(.*)$")
	local id: string = if rest then string.match(rest, "^[^/?#]*") or "" else value
	assert(string.match(id, "^[%w_%-]+$") and id ~= "e", field .. " must be an ID or its https://docs.google.com/" .. product .. "/d/<id> URL")
	return id
end

-- Moves {placeholders} and declared query fields from args into the URL; remaining fields form the JSON body.
local function target(name: string, endpoint: Endpoint, args: Options): string
	local defaults: Options = endpoint.defaults or {}
	for key, value in defaults do
		if args[key] == nil then args[key] = value end
	end
	local required: {[string]: string} = endpoint.required or {}
	for field, kind in required do
		local value = args[field]
		assert(if kind == "array" then type(value) == "table" and value[1] ~= nil elseif kind == "string" then type(value) == "string" and value ~= "" elseif kind == "object" then type(value) == "table" and next(value) ~= nil and value[1] == nil else false,
			name .. " requires " .. field .. " as a nonempty " .. kind)
	end
	local path = string.gsub(endpoint.path, "{(%w+)}", function(field: string)
		local value = url.segment(text(args[field], field), field)
		args[field] = nil
		return value
	end)
	path ..= query(args, endpoint.query or {})
	if not endpoint.body then assert(next(args) == nil, name .. " received an unknown option") end
	return API .. path
end

local function invoke(name: string, endpoint: Endpoint, input: any): any
	local args = options(input)
	local result = call(name, endpoint.method, target(name, endpoint, args), if endpoint.body then args else nil)
	if endpoint.list and result[endpoint.list] == nil then result[endpoint.list] = json.decode("[]") end
	return result
end

local exports: {[string]: any} = {}
local help: {[string]: string} = {}

-- Exposes an operation when it only reads or the connection allows writes.
local function export(name: string, isRead: boolean, fn: (any) -> any, doc: string)
	if isRead or config.access == "read-write" then
		exports[name], help[name] = fn, doc
	end
end

local function exportEndpoints(endpoints: {[string]: Endpoint})
	for name, endpoint in endpoints do
		export(name, endpoint.read, function(args: Options?): any return invoke(name, endpoint, args) end, endpoint.help)
	end
end

-- help() introduces the API, then documents exactly the configured operations.
local function helpWith(overview: {string}): () -> string
	return function(): string
		local names: {string} = {}
		for name in help do table.insert(names, name) end
		table.sort(names)
		local lines = table.clone(overview)
		for _, name in names do table.insert(lines, help[name]) end
		return table.concat(lines, "\n")
	end
end
-- End of the shared request layer.

local RESPONSE = "{responseId, createTime, lastSubmittedTime, respondentEmail?, totalScore?, answers?={[questionId]={questionId, textAnswers?={answers={{value}}}, fileUploadAnswers?={answers={{fileId, fileName, mimeType}}}, grade?}}}"
local endpoints: {[string]: Endpoint} = {
	getForm = {method = "GET", path = "/forms/{formId}", read = true, list = "items",
		help = "getForm({formId}) -> {formId, info={title, documentTitle, description?}, settings, revisionId, responderUri, linkedSheetId?, publishSettings?={publishState={isPublished, isAcceptingResponses}}, items=[{itemId, title?, description?, questionItem?={question={questionId, required?, choiceQuestion?, textQuestion?, scaleQuestion?, dateQuestion?, timeQuestion?, ratingQuestion?, fileUploadQuestion?, grading?}}, questionGroupItem?={questions=[{questionId, rowQuestion={title}}], grid}, pageBreakItem?, textItem?, imageItem?, videoItem?}]}. items are in display order and [] for an empty form. responderUri is the link respondents open; linkedSheetId is the spreadsheet collecting responses, readable with the Google Sheets connector. Legacy forms have no publishSettings."},
	listResponses = {method = "GET", path = "/forms/{formId}/responses", read = true, list = "responses", query = {"filter", "pageSize", "pageToken"},
		help = "listResponses({formId, filter?, pageSize?, pageToken?}) -> {responses=[" .. RESPONSE .. "], nextPageToken?}. responses is [] when none match; Google does not document their order. filter accepts only 'timestamp > T' or 'timestamp >= T', with T in RFC 3339 UTC such as 2026-10-01T00:00:00Z, compared with the submission time. To fetch new responses later, keep the largest lastSubmittedTime and pass filter='timestamp >= <it>', skipping responseIds already handled: a respondent who edits a response sends it again with a later lastSubmittedTime. A page holds up to 5000 responses; lower pageSize for long answers, since pages over 8 MiB fail. Pass nextPageToken as pageToken with the same filter until it is absent."},
	getResponse = {method = "GET", path = "/forms/{formId}/responses/{responseId}", read = true,
		help = "getResponse({formId, responseId}) -> " .. RESPONSE .. ", plus formId."},
	createForm = {method = "POST", path = "/forms", read = false, body = true, defaults = {unpublished = true}, query = {"unpublished"}, required = {info = "object"}, list = "items",
		help = "createForm({info={title, documentTitle?}, unpublished?}) -> the new form, with formId, responderUri and revisionId. Google accepts only title and documentTitle, the file name in Drive, which batchUpdate cannot change later; add the description, questions and settings with batchUpdate. The form is created unpublished, so it accepts no responses: publish it with setPublishSettings once its questions are ready, or pass unpublished=false."},
	batchUpdate = {method = "POST", path = "/forms/{formId}:batchUpdate", read = false, body = true, required = {requests = "array"},
		help = "batchUpdate({formId, requests, includeFormInResponse?, writeControl?}) -> {replies, writeControl, form?}. Applies requests in order, all or nothing; replies match requests one to one, and a createItem reply is {createItem={itemId, questionId={...}}}. Kinds: createItem={item, location={index}}, updateItem={item, location={index}, updateMask}, deleteItem={location={index}}, moveItem={originalLocation={index}, newLocation={index}}, updateFormInfo={info, updateMask} and updateSettings={settings, updateMask}. Indexes are zero-based positions in items, after the earlier requests of the batch apply. updateMask is required: 'description', 'title,description' or '*' for all fields. Example: requests={{updateFormInfo={info={description='Team lunch survey'}, updateMask='description'}}, {createItem={item={title='Which day?', questionItem={question={required=true, choiceQuestion={type='RADIO', options={{value='Tuesday'}, {value='Thursday'}}}}}}, location={index=0}}}}. Questions: choiceQuestion={type='RADIO'|'CHECKBOX'|'DROP_DOWN', options, shuffle?}, textQuestion={paragraph?}, scaleQuestion={low, high, lowLabel?, highLabel?}, dateQuestion={includeTime?, includeYear?}, timeQuestion={duration?}, ratingQuestion={ratingScaleLevel, iconType='STAR'|'HEART'|'THUMB_UP'}; file upload questions cannot be created. Quizzes: updateSettings={settings={quizSettings={isQuiz=true}}, updateMask='quizSettings.isQuiz'}, then question.grading={pointValue, correctAnswers={answers={{value}}}}. settings.emailCollectionType is DO_NOT_COLLECT, VERIFIED or RESPONDER_INPUT."},
	setPublishSettings = {method = "POST", path = "/forms/{formId}:setPublishSettings", read = false, body = true, required = {publishSettings = "object"},
		help = "setPublishSettings({formId, publishSettings={publishState={isPublished, isAcceptingResponses}}, updateMask?}) -> {formId, publishSettings}. Both flags are required: {isPublished=true, isAcceptingResponses=true} publishes the form and accepts responses from those it is shared with, isAcceptingResponses=false closes it to new responses, and isPublished=false unpublishes it. updateMask accepts 'publish_state' or '*'. Legacy forms without publishSettings fail."},
}

for name, endpoint in endpoints do
	export(name, endpoint.read, function(input: any): any
		local args = options(input)
		if string.find(endpoint.path, "{formId}", 1, true) then
			args.formId = docsId(args.formId, "forms", "formId")
		else
			assert(args.formId == nil, name .. " assigns the formId")
		end
		return invoke(name, endpoint, args)
	end, endpoint.help)
end

local overview = {
	"Google Forms API v1. Operations take one named options object with Google's camelCase fields and return Google's JSON unchanged. Calls return completed values: use instance.getForm(...) directly, without await.",
	"formId is the ID or the form's https://docs.google.com/forms/d/<id>/edit URL. Responder links (https://docs.google.com/forms/d/e/.../viewform) and forms.gle links carry no form ID: ask for the edit link. This connector cannot search for forms: ask for the link, or find the ID with the Google Drive connector (listFiles with q=\"mimeType = 'application/vnd.google-apps.form' and trashed = false\"). The account needs access to the form itself in Drive: being able to fill it in is not enough.",
	"Answers are keyed by questionId, not question text: read the form once with getForm and map each item.questionItem.question.questionId, and each questionGroupItem.questions[i].questionId, to its title. Every answer value is a string: a choice's text (one value per ticked box), the number picked on a scale, dates as '2026-10-21' or '10-21' without a year, with ' 14:51' when the question asks for a time. File upload answers carry Google Drive fileIds; download them with the Google Drive connector.",
	"No hidden paging or retries. Errors report the HTTP status and Google's message. Google allows about 390 reads, 180 listResponses and 150 writes per minute per user, and 975, 450 and 375 per minute across all Houston users; HTTP 429 errors are retryable after a pause.",
}
if config.access == "read-write" then
	table.insert(overview, "Writes change a form's content, settings and publishing. An empty Luau table encodes as a JSON object: write an empty array, such as options, as json.decode('[]'). Responses cannot be submitted, edited or deleted, and forms cannot be deleted, renamed in Drive or shared here, including choosing who may respond: use Google Forms or the Google Drive connector. A failed or timed-out write may already have succeeded: check with getForm before repeating it, or pass writeControl={requiredRevisionId=form.revisionId} from getForm to batchUpdate, so a repeat fails with HTTP 400 instead of applying twice.")
end
exports.help = helpWith(overview)
return exports
