-- Tipeee API v2.0 (website release 20261022134411). Arguments and results keep Tipeee's native field names.
type Options = {[string]: any}
type Endpoint = {method: string, path: string, query: {string}?, body: string?, required: {string}?, write: boolean?, about: string}
local endpoints: {[string]: Endpoint} = {
	getMe = {method = "GET", path = "/v2.0/credentials/me", write = true, about = "Connected user and projects; streaming api_key fields are removed."},
	listCategories = {method = "GET", path = "/v2.0/categories", about = "Available project categories."},
	listProjects = {method = "GET", path = "/v2.0/projects", write = true, query = {"page", "perPage", "q", "mode", "lang", "category", "campaign_type"}, about = "Project discovery; items and pager."},
	getProject = {method = "GET", path = "/v2.0/projects/{project}", write = true, about = "Project by slug; streaming api_key removed."},
	createProject = {method = "POST", path = "/v2.0/projects", required = {"translations", "slug", "lang", "categories"}, body = "form", about = "Create a recurring project draft; translations={en={name='My project'}}, categories={id,...}."},
	createOneOffProject = {method = "POST", path = "/v2.0/projects/pers/projects", required = {"translations", "slug", "lang", "categories"}, body = "form", about = "Create a one-off project draft; configure campaign separately."},
	updateProject = {method = "PUT", path = "/v2.0/projects/{project}", body = "form", about = "Update translations, categories, slug, tags. Changing slug changes future project paths."},
	updateProjectDescription = {method = "POST", path = "/v2.0/projects/{project}/contents", required = {"translations"}, body = "form", about = "translations={en={html='<p>About</p>',components=...}}; changes description."},
	updateCampaign = {method = "PUT", path = "/v2.0/projects/{project}/campaign", body = "form", about = "One-off: campaignType='per_project',campaignName='-',perProjectCampaign={campaignGoalType='amount',campaignGoal=100,campaignDeadlineType='days',campaignDeadlineDays=30}. Check native fields for existing campaign type."},
	updateProjectLinks = {method = "PUT", path = "/v2.0/projects/{project}/links", required = {"links"}, body = "form", about = "links={{code=...,value=...},...}, at most 12."},
	updateProjectAvatar = {method = "PUT", path = "/v2.0/projects/{project}/avatar", body = "form", about = "files['avatar[uploadedFile]'] plus data.avatar.uploadedFileOptions={x,y,width,height}."},
	updateProjectCover = {method = "PUT", path = "/v2.0/projects/{project}/cover", body = "form", about = "files['cover[uploadedFile]']; data.cover.uploadedFileOptions={x,y,width,height} or {delete=true}."},
	updateProjectSettings = {method = "PUT", path = "/v2.0/projects/{project}/dashboard", body = "form", about = "parameters={hidedAmount={value=1},recurring_only={value=1},notification_tip={value=1},deleted_sub_notification={value=1},nsfw={value=1}}; thanksMail={content='...'} max1000."},
	getCloseDate = {method = "GET", path = "/v2.0/projects/{project}/close_date", about = "Scheduled closeDate."},
	getPayoutState = {method = "GET", path = "/v2.0/projects/{project}/payout/state", about = "Payout eligibility: status,last_date,errors. errors contains eligibility flags and is preserved, including false values."},
	requestPayout = {method = "PUT", path = "/v2.0/projects/{project}/payout", about = "Requests a money transfer. Inspect state after ambiguous failure; successful HTTP may contain errors."},
	createGoal = {method = "POST", path = "/v2.0/projects/{project}/goals", required = {"translations", "amount"}, body = "form", about = "translations={en={name='Goal',description='<p>Details</p>'}},amount=100; description max1024."},
	updateGoal = {method = "PUT", path = "/v2.0/projects/{project}/goals/{goal}", body = "form", about = "Goal fields as createGoal; response is updated goals."},
	deleteGoal = {method = "DELETE", path = "/v2.0/projects/{project}/goals/{goal}", about = "Delete a funding goal."},
	listRewards = {method = "GET", path = "/v2.0/projects/{project}/rewards", query = {"page", "perPage", "status", "stock", "endDate", "priceMin", "priceMax", "rewardSort"}, about = "items,pager,stats; page starts1, UI perPage12."},
	getReward = {method = "GET", path = "/v2.0/projects/{project}/rewards/{reward}", about = "Reward including current modular configuration."},
	createReward = {method = "POST", path = "/v2.0/projects/{project}/rewards", required = {"price", "translations"}, body = "form", about = "price,translations={en={name,description_v2}},modules,transition; see reward shape below."},
	updateReward = {method = "PUT", path = "/v2.0/projects/{project}/rewards/{reward}", body = "form", about = "Full native reward object; preserve modules you want to keep."},
	transitionReward = {method = "PUT", path = "/v2.0/projects/{project}/rewards/{reward}/transition", required = {"transition"}, body = "json", about = "transition='archive' or 'delete' (deletion is destructive); native lifecycle values are provider-controlled."},
	cloneReward = {method = "PUT", path = "/v2.0/projects/{project}/rewards/{reward}/clone", body = "json", about = "Clone the reward; returns the new reward id."},
	listNews = {method = "GET", path = "/v2.0/projects/{project}/news", query = {"page", "perPage", "latest", "statusFilter"}, about = "News including pinned entries and pager."},
	getNews = {method = "GET", path = "/v2.0/projects/{project}/news/{news}", about = "News with content, visibility and publication status."},
	createNews = {method = "POST", path = "/v2.0/projects/{project}/news", required = {"name", "contentv2", "draft"}, body = "form", about = "name,contentv2={translations={en={html='...'}}},draft=true. draft=false publishes/notifies; parameters.tip_content=1 can collect tips."},
	updateNews = {method = "PUT", path = "/v2.0/projects/{project}/news/{news}", body = "form", about = "Native news fields; publishing may notify or collect tips. See visibility/survey shape below."},
	deleteNews = {method = "DELETE", path = "/v2.0/projects/{project}/news/{news}", about = "Delete a news post."},
	listComments = {method = "GET", path = "/v2.0/threads/{thread}/comments", query = {"perPage", "token", "direction"}, about = "Thread permalink; cursor pager token and direction='next'/'previous', perPage default10."},
	createComment = {method = "POST", path = "/v2.0/threads/{thread}/comments", required = {"body"}, body = "form", about = "body text max1024; parent optional reply id."},
	deleteComment = {method = "DELETE", path = "/v2.0/threads/{thread}/comments/{comment}", about = "Delete own comment or moderate a thread you own."},
	listCampaigns = {method = "GET", path = "/v2.0/projects/{project}/campaigns", about = "Array of campaign ids and metadata."},
	listCampaignRewards = {method = "GET", path = "/v2.0/projects/{project}/campaigns/{campaign}/rewards", about = "Array of historical rewards."},
	getCampaignRewardStats = {method = "GET", path = "/v2.0/projects/{project}/campaigns/{campaign}/rewards/stats", about = "rewards,reward_tippers,total_tippers,no_reward_tippers."},
	listTippers = {method = "GET", path = "/v2.0/projects/{project}/campaigns/{campaign}/subscriptions", query = {"rewardId", "noReward", "page", "perPage"}, about = "items,pager; page starts0, UI perPage100, noReward=0/1. Contains personal supporter data."},
	listPayments = {method = "GET", path = "/v2.0/projects/{project}/payments", query = {"year"}, about = "Year YYYY; items and payment metadata, including original_payment.id for PDFs."},
	getStatistics = {method = "GET", path = "/v2.0/projects/{project}/statistics", query = {"type", "timeUnit", "startDate", "endDate", "mode"}, required = {"type", "timeUnit"}, about = "data,extra_data; e.g type='VISITOR_NUMBER',timeUnit='DAY',startDate='2026-10-01'."},
	getRecurringIndicators = {method = "GET", path = "/v2.0/projects/{project}/statistics/recurring/indicators", about = "tipNumber,tipAmount,tipAverageAmount,tipAverageDuration."},
	blockTipper = {method = "POST", path = "/v2.0/users/{username}/relations", required = {"target", "status"}, body = "json", about = "target=tipper.id,status='TIP_BANNED'; username is creator username_canonical, not project slug."},
	unblockTipper = {method = "DELETE", path = "/v2.0/users/{username}/relations/{relation}", about = "Delete the relation id created by blockTipper."},
	listInboxProjects = {method = "GET", path = "/v2.0/inbox/users/{username}/projects", write = true, about = "Creator/tipper project lists."},
	listInboxThreads = {method = "GET", path = "/v2.0/inbox/users/{username}/thread", write = true, query = {"page", "inbox_type", "project"}, about = "items,pager; page starts1, project is numeric id here."},
	getUnreadMessages = {method = "GET", path = "/v2.0/inbox/users/{username}/unread", about = "Unread message count."},
	getInboxThread = {method = "GET", path = "/v2.0/inbox/threads/{threadToUser}", write = true, about = "Recipient-thread id, distinct from thread_id used to send a reply."},
	listMessages = {method = "GET", path = "/v2.0/inbox/threads/{threadToUser}/content", write = true, query = {"token"}, about = "Array; next request token is oldest content.token or id. Empty array ends paging."},
	searchMessageTippers = {method = "GET", path = "/v2.0/inbox/search/{project}/tippers", query = {"q", "page"}, about = "Search recipients; project is slug."},
	findOrCreateThread = {method = "POST", path = "/v2.0/inbox/users/{username}/search-thread", required = {"project", "receiver"}, body = "json", about = "project is numeric id, receiver user id; may create a conversation."},
	sendMessage = {method = "POST", path = "/v2.0/inbox/contents", required = {"action", "content"}, body = "json", about = "action='CREATE' with title,rules,project numeric id (broadcast); 'RESPONSE' with thread_id as thread; 'ERRATUM' with parent,thread. attachments are uploaded slugs. Sends messages."},
	renameThread = {method = "PUT", path = "/v2.0/inbox/threads/{threadToUser}/title", required = {"title"}, body = "json", about = "Rename a recipient thread."},
	followThread = {method = "PUT", path = "/v2.0/inbox/threads/{threadToUser}/follow", about = "Follow a recipient thread."},
	unfollowThread = {method = "PUT", path = "/v2.0/inbox/threads/{threadToUser}/unfollow", about = "Unfollow a recipient thread."},
	lockThread = {method = "PUT", path = "/v2.0/inbox/threads/{threadToUser}/locked", about = "Lock a recipient thread."},
	unlockThread = {method = "PUT", path = "/v2.0/inbox/threads/{threadToUser}/unlocked", about = "Unlock a recipient thread."},
	deleteThread = {method = "DELETE", path = "/v2.0/inbox/threads/{threadToUser}", about = "Delete a conversation."},
	uploadMessageFileChunk = {method = "POST", path = "/v2.0/inbox/contents/files", required = {"fileId", "chunkIndex", "totalChunks", "fileName"}, body = "form", about = "files.file={path,filename,contentType}; data contains stable fileId UUID, zero-based chunkIndex,totalChunks,fileName. Sequential chunks <=50MiB; 201/206 intermediate,200 final slug. Max6 attachments/message."},
	uploadMedia = {method = "POST", path = "/v2.0/media", query = {"isPrivate", "type"}, body = "form", about = "files.uploadedFile={path,filename,contentType}; type=image/audio/document/pdf. Returns media id/slug/url; attach separately. UI limits image2MB,audio100MB,documents50MB."},
	getDiscordGuild = {method = "GET", path = "/v2.0/projects/{project}/discord/guild", about = "Associated Discord guild and roles; connect Discord in Tipeee's website first."},
	disconnectDiscord = {method = "DELETE", path = "/v2.0/projects/{project}/discord/guild", about = "Disconnect the project's Discord guild."},
	getWidgets = {method = "GET", path = "/v2.0/projects/{project}/widgets", write = true, about = "Widget definitions and private widget links; requires read-write."},
	configureAlertsWidget = {method = "POST", path = "/v2.0/projects/{project}/widgets/alerts", body = "form", about = "theme,text_color_var,animation,show_message,sound={type,static_id,volume=0.5}."},
	configureGoalsWidget = {method = "POST", path = "/v2.0/projects/{project}/widgets/goals", required = {"name", "goal_amount"}, body = "form", about = "theme,text_color_var,name,initial_amount,goal_amount,reset,reset_at."},
	configureLastsWidget = {method = "POST", path = "/v2.0/projects/{project}/widgets/lasts", body = "form", about = "theme,text_color_var,events_count,show_amount,show_title."},
	configureTotalsWidget = {method = "POST", path = "/v2.0/projects/{project}/widgets/totals", body = "form", about = "theme,text_color_var,show_amount,show_project_avatar."},
	enableStreaming = {method = "POST", path = "/v2.0/projects/{project}/enabled_streamings", about = "Enable streaming widgets."},
	replayStreamAlert = {method = "POST", path = "/v2.0/subscriptions/{subscription}/replays", about = "Replay the subscription's alert on stream."},
	getWidgetGoal = {method = "GET", path = "/v2.0/projects/{project}/subscription/widget/goal", query = {"date"}, about = "subscriptionsAmount for goal/date."},
	downloadPayments = {method = "GET", path = "/documents/payments/{report}", query = {"lang"}, body = "download", about = "report='project-slug_2026.csv' or .xlsx; output session path required."},
	downloadPaymentBill = {method = "GET", path = "/documents/payment-bill/{document}", query = {"lang"}, body = "download", about = "document='<original_payment.id>.pdf'; output required."},
	downloadPaymentTips = {method = "GET", path = "/documents/payment-tips/{document}", query = {"lang"}, body = "download", about = "document='<original_payment.id>.pdf'; output required."},
	downloadTippers = {method = "GET", path = "/documents/tippers/{report}", query = {"rewardId", "noReward"}, body = "download", write = true, about = "report='<campaign>.csv' or .xlsx; output required. Uses allTabs=0; route requires read-write because allTabs=1 sends email."},
	emailTippersExport = {method = "GET", path = "/documents/tippers/{report}", query = {"rewardId", "noReward"}, body = "email", write = true, about = "report='<campaign>.xlsx' or .csv. Uses allTabs=1; sends multi-tab export email. Wait at least5 minutes between requests."},
	downloadMedia = {method = "GET", path = "/v2.0/media/{media}", query = {"mode", "width", "height"}, body = "download", about = "output required; mode='original' or image dimensions."},
	downloadPrivateMedia = {method = "GET", path = "/v2.0/media/{media}/private", body = "download", about = "output required; media is private attachment slug."},
}

local API = "https://api.tipeee.com"
local NONE: {string} = table.freeze({})
local NULL = json.decode("null")

local function identifier(value: any, field: string): string
	if type(value) == "number" then
		assert(value >= 0 and value % 1 == 0 and value <= 9007199254740991, field .. " must be an integer ID")
		return string.format("%d", value)
	end
	assert(type(value) == "string" and string.match(value, "^[%w_%-]+$"), field .. " must be an ID or slug")
	return value
end

local function object(value: any, field: string): Options
	assert(type(value) == "table", field .. " must be an object")
	for key in value do assert(type(key) == "string", field .. " must have named fields") end
	return value
end

local function writes(endpoint: Endpoint): boolean
	return endpoint.write == true or endpoint.method ~= "GET"
end

-- The project streaming key is distinct from the session token, but is still a secret.
-- Keep cursor fields named token, which are used by comments and inbox pagination.
local function project(value: any): any
	if type(value) == "table" then
		for key, child in value do
			if key == "api_key" or key == "access_token" or key == "refresh_token" then
				value[key] = nil
			else
				project(child)
			end
		end
	end
	return value
end

local function fail(name: string, response: HttpResponse, value: any): never
	local message = "Tipeee HTTP " .. tostring(response.statusCode)
	if type(value) == "table" then
		if type(value.code) == "string" then message ..= " (" .. string.sub(value.code, 1, 40) .. ")" end
		if type(value.message) == "string" then message ..= ": " .. string.sub(value.message, 1, 600) end
		if value.errors ~= nil then message ..= " " .. string.sub(json.encode(project(value.errors)), 1, 1000) end
	end
	local retry = response.headers["retry-after"]
	if retry and retry[1] then message ..= "; Retry-After: " .. string.sub(retry[1], 1, 100) end
	return houston.fail({operation = name, layer = "upstream", upstream_status = response.statusCode,
		retryable = response.statusCode == 429 or response.statusCode >= 500, message = message})
end

local function responseOK(name: string, response: HttpResponse)
	if response.statusCode < 200 or response.statusCode >= 300 then
		local ok, value = pcall(json.decode, await(response.body:readPrefix(16 * 1024)))
		fail(name, response, if ok then value else nil)
	end
end

local function decode(name: string, response: HttpResponse, allowEmpty: boolean): any
	responseOK(name, response)
	local raw = await(response.body:readAll())
	if allowEmpty and string.match(raw, "^%s*$") then return {status = "success"} end
	local ok, value = pcall(json.decode, raw)
	if not ok or type(value) ~= "table" or not string.match(raw, "^%s*[%[{]") then
		fail(name, response, {message = "Invalid JSON response"})
	end
	if name ~= "getPayoutState" and value.errors ~= nil and value.errors ~= NULL and (type(value.errors) ~= "table" or next(value.errors) ~= nil) then fail(name, response, value) end
	return project(value)
end

local function scalar(value: any, field: string): string
	local kind = type(value)
	assert(kind == "string" or kind == "boolean" or (kind == "number" and value == value and math.abs(value) ~= math.huge), field .. " must be a finite scalar")
	return tostring(value)
end

-- Native browser forms use bracket names and zero-based array indexes.
local function flatten(value: any, field: string, emit: (string, string) -> (), depth: number)
	assert(depth <= 16, "form/query nesting exceeds 16 levels")
	if value == NULL then return end
	if type(value) ~= "table" then emit(field, scalar(value, field)); return end
	local array = #value > 0
	for key, child in value do
		local name: string
		if array then
			assert(type(key) == "number" and key >= 1 and key % 1 == 0 and key <= #value, "arrays must be dense")
			name = tostring(key - 1)
		else
			assert(type(key) == "string" and string.match(key, "^[%w_%-]+$"), "field names must be simple identifiers")
			name = key
		end
		flatten(child, if field == "" then name else field .. "[" .. name .. "]", emit, depth + 1)
	end
end

local function validateData(name: string, data: Options)
	assert(data._method == nil and data.access_token == nil, "authentication and method overrides are not body fields")
	if name == "sendMessage" then
		assert(table.find({"CREATE", "RESPONSE", "ERRATUM"}, data.action), "action must be CREATE, RESPONSE or ERRATUM")
		local required: {string} = if data.action == "CREATE" then {"project", "title", "rules"} elseif data.action == "ERRATUM" then {"parent", "thread"} else {"thread"}
		for _, key in required do assert(data[key] ~= nil and data[key] ~= NULL, key .. " is required") end
	elseif name == "blockTipper" then
		assert(data.status == "TIP_BANNED", "status must be TIP_BANNED")
	elseif name == "createComment" then
		assert(type(data.body) == "string", "body must be comment text")
		local length = utf8.len(data.body)
		assert(length ~= nil and length > 0 and length <= 1024, "body must be nonempty UTF-8 comment text (max1024 characters)")
	elseif name == "createNews" then
		assert(type(data.draft) == "boolean", "draft must explicitly be true or false")
	elseif name == "uploadMessageFileChunk" then
		identifier(data.fileId, "fileId")
		assert(type(data.chunkIndex) == "number" and data.chunkIndex >= 0 and data.chunkIndex % 1 == 0, "chunkIndex must be a zero-based integer")
		assert(type(data.totalChunks) == "number" and data.totalChunks % 1 == 0 and data.totalChunks > data.chunkIndex, "totalChunks must exceed chunkIndex")
	end
end

local function request(name: string, endpoint: Endpoint, input: Options?): any
	local args = table.clone(object(if input == nil then {} else input, "opts"))
	local path = string.gsub(endpoint.path, "{([%w_]+)}", function(field: string): string
		local value = args[field]
		args[field] = nil
		if field == "report" or field == "document" then
			assert(type(value) == "string", field .. " must be a report filename")
			local stem, extension = string.match(value, "^([%w_%-]+)%.([%a]+)$")
			assert(stem and ((field == "document" and extension == "pdf") or (field == "report" and (extension == "csv" or extension == "xlsx"))), "unsupported report filename")
			if name == "downloadPayments" then assert(string.match(stem, "^.+_%d%d%d%d$"), "payment report must end with _YYYY") end
			return value
		end
		return identifier(value, field)
	end)
	local data = object(args.data or {}, "data")
	args.data = nil
	local files = object(args.files or {}, "files")
	args.files = nil
	for _, key in endpoint.required or NONE do
		local value = if endpoint.body == "form" or endpoint.body == "json" then data[key] else args[key]
		assert(value ~= nil and value ~= NULL, key .. " is required")
	end
	validateData(name, data)
	local query: {string} = {}
	for _, key in endpoint.query or NONE do
		if args[key] ~= nil then
			flatten(args[key], key, function(k: string, v: string) table.insert(query, url.encode(k) .. "=" .. url.encode(v)) end, 0)
		end
		args[key] = nil
	end
	if name == "downloadTippers" then table.insert(query, "allTabs=0") end
	if name == "emailTippersExport" then table.insert(query, "allTabs=1") end
	if #query > 0 then path ..= "?" .. table.concat(query, "&") end
	local output = args.output
	args.output = nil
	local unknown = next(args)
	assert(unknown == nil, "unknown option " .. tostring(unknown))
	if endpoint.body == "download" then
		assert(type(output) == "string" and #output > 0, "output must be a session file path")
	else
		assert(output == nil, "output is only for downloads")
	end
	local method = endpoint.method
	local headers: HttpHeaders = {Accept = {if endpoint.body == "download" then "*/*" else "application/json"}}
	local body: any = nil
	if endpoint.body == "form" then
		local parts: {any} = {}
		flatten(data, "", function(k: string, v: string) table.insert(parts, {name = k, body = v}) end, 0)
		local fileSpecs: {any} = {}
		for field, spec in files do
			assert(string.match(field, "^[%w_%-]+[%w_%-%[%]]*$") and field ~= "_method" and field ~= "access_token", "invalid upload field")
			object(spec, "file specification")
			assert(type(spec.path) == "string" and #spec.path > 0 and type(spec.filename) == "string" and #spec.filename > 0 and type(spec.contentType) == "string", "file requires path, filename and contentType")
			for key in spec do assert(key == "path" or key == "filename" or key == "contentType", "unknown file option") end
			for _, part in parts do assert(part.name ~= field, "duplicate file/form field") end
			table.insert(fileSpecs, {name = field, spec = spec})
		end
		if name == "uploadMedia" then assert(files.uploadedFile ~= nil, "files.uploadedFile is required") end
		if name == "uploadMessageFileChunk" then assert(files.file ~= nil, "files.file is required") end
		if method == "PUT" then method = "POST"; table.insert(parts, {name = "_method", body = "put"}) end
		for _, file in fileSpecs do
			table.insert(parts, {name = file.name, filename = file.spec.filename, contentType = file.spec.contentType, body = fs.open(file.spec.path, "r")})
		end
		local contentType: string
		body, contentType = http.multipart(parts)
		headers["Content-Type"] = {contentType}
	elseif endpoint.body == "json" then
		assert(next(files) == nil, "files require a multipart operation")
		body = json.encode(data)
		headers["Content-Type"] = {"application/json"}
	else
		assert(next(data) == nil and next(files) == nil, "this operation has no request body")
	end
	local response = await(http.request({method = method, url = API .. path, headers = headers, body = body}))
	if endpoint.body == "download" then
		responseOK(name, response)
		local file = fs.open(output, "w")
		file:write(response.body)
		await(file:close())
		return {path = output, size = await(fs.stat(output)).size, url = await(fs.signedGetUrl(output))}
	end
	return decode(name, response, endpoint.method ~= "GET" or endpoint.body == "email")
end

local exports: {[string]: any} = {}
for name, endpoint in endpoints do
	if not writes(endpoint) or config.access == "read-write" then
		exports[name] = function(args: Options?): any return request(name, endpoint, args) end
	end
end
exports.help = function(): string
	local lines = {
		"Tipeee creator API v2.0, unofficial website contracts checked 2026-10-23. Official partial docs: https://api.tipeee.com/api/doc/default ; partner docs https://api.tipeee.com/api/doc/partner concern tipper integrations. No supported public creator-management spec or self-service OAuth registration was found. Session token setup; reconnect when it expires. Never pass credentials to functions.",
		"Every function takes one named options object; path/query fields are native names. Writes take data={native body}; multipart writes optionally take files={['native[field]']={path='session-file',filename='name.png',contentType='image/png'}}. Nested forms flatten to bracket names, arrays use zero-based indexes, null values are skipped. JSON keeps json.decode('null') and json.decode('[]'). Calls return completed values without await; results keep native envelopes/arrays except api_key/access_token/refresh_token removed recursively. Empty successful write returns {status='success'}. 2xx errors also fail.",
		"With read-write, use getMe() to discover creator projects and username_canonical. For read-only, use the known project slug from its website URL: listCampaigns({project='my-slug'}), then listTippers({project='my-slug',campaign='ID',page=0,perPage=100}). Numeric ids or simple slugs are accepted; no full URLs. Lists return items,pager (currentPage,perPage,next,pageNbr), except arrays noted below. Return one page; follow pager.next, comments token/direction, or message token. No automatic paging or connector retry loop. Houston transport can retry non-streamed HTTP429 responses twice (including JSON/bodyless writes); streamed forms,5xx and transport failures are not replayed. Rates and token lifetime are undocumented; 429/5xx are retryable, errors include Retry-After when present. Inspect outcome before retrying writes.",
		"Reward data: price, translations={en={name,description_v2}}, presale,has_presale,transition,modules. Modules: display={is_pinned,is_private,private_link,start,['end'],_is_Activate}; stock={noReset,available={unlimited,quantity},perUser={unlimited,quantity},_is_Activate}; attachment={content,files,links,_is_Activate} max3; discord={role_name,role_id,duration,_is_Activate}; shipping={addressRequired,phonenumberRequired,_is_Activate}; custom={settings={{name,options={{name,is_additional_config=false}}}}}. Keep existing module values when updating. Reward name<=100, HTML description<=1500; recurring price1..1000,one-off1..5000. File values use files with bracket paths.",
		"News: name,contentv2={translations={en={html,components}}},draft,private,parameters={private_type='amount'/'rewards',private_rule_amount,private_rule_rewards={id,...},tip_content=1},tags={{name}},isPinned,publishedAt,survey={name,questions={{type,name,answers={{name}}}}}. Draft creation example: createNews({project='my-slug',data={name='Update',contentv2={translations={en={html='<p>Hello</p>'}}},draft=true}}). Publishing can notify supporters; tip_content=1 can charge them. Payouts move funds; inbox CREATE broadcasts to rules; exports can email personal data. Obtain user instruction for these actions.",
		"Read-only omits all writes, account/project discovery and inbox project/thread/content reads (project objects may carry streaming keys; opening inbox content may mark it read), widget secret links, and tipper exports (the shared GET route can email exports). Creator ownership/role and payout eligibility are enforced by Tipeee. Connect Discord and complete KYC, terms acceptance, publication/closure and account security on Tipeee's website. Credential rotation, tipper checkout/subscription purchases, admin, and streaming endpoints requiring a project API key are outside this connector.",
		"Files stream to/from session storage; downloads return {path,size,url} with Houston's signed file URL. Failed transfers can leave partial files. No external URL fetches. Native limits include256 calls/invocation,64MiB Luau memory,8MiB JSON frames; use smaller pages and stream files. Upload chunks sequentially with stable fileId,chunkIndex,totalChunks; do not replay ambiguous uploads. Private uploaded slugs must be attached separately.",
	}
	local names: {string} = {}
	for name in exports do if name ~= "help" then table.insert(names, name) end end
	table.sort(names)
	for _, name in names do
		local endpoint = endpoints[name]
		local fields: {string} = {}
		for field in string.gmatch(endpoint.path, "{([%w_]+)}") do table.insert(fields, field) end
		for _, field in endpoint.query or NONE do table.insert(fields, field .. (if table.find(endpoint.required or NONE, field) then "" else "?")) end
		if endpoint.body == "form" then table.insert(fields, "data?,files?") elseif endpoint.body == "json" then table.insert(fields, "data?") elseif endpoint.body == "download" then table.insert(fields, "output") end
		table.insert(lines, name .. "({" .. table.concat(fields, ",") .. "}): " .. endpoint.about)
	end
	return table.concat(lines, "\n")
end
return exports
