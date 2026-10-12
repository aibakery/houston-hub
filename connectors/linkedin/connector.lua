-- The connected member's LinkedIn profile and posts, through Sign In with LinkedIn
-- (OpenID Connect) and Share on LinkedIn. Credentials are injected only by Houston's proxy.
type Options = {[string]: any}
type Post = {id: string, url: string}

local API = "https://api.linkedin.com"
-- Versioned REST APIs (YYYYMM) are supported for about a year after release.
local VERSION = "202609"
local VISIBILITY = table.freeze({PUBLIC = true, CONNECTIONS = true})

local function text(value: any, field: string): string
	assert(type(value) == "string" and value ~= "", field .. " must be a nonempty string")
	return value
end

local function optionalText(value: any, field: string): string?
	if value == nil then return nil end
	return text(value, field)
end

local function fields(value: any, field: string, allowed: {[string]: boolean}): Options
	assert(type(value) == "table", field .. " must be an options object")
	for key in value do assert(allowed[key], field .. " received an unknown option " .. tostring(key)) end
	return value
end

-- Commentary uses LinkedIn's little text format. Escape its reserved characters so
-- text is posted literally; # stays unescaped so hashtags still link.
local function commentary(value: string): string
	return (string.gsub(value, "[\\|{}@%[%]()<>*_~]", "\\%0"))
end

local function invalid(operation: string, message: string): never
	return houston.fail({operation = operation, layer = "upstream", retryable = false, message = message})
end

local function send(operation: string, request: HttpRequest): HttpResponse
	local response = await(http.request(request))
	if response.statusCode >= 200 and response.statusCode < 300 then return response end
	-- LinkedIn errors are small JSON objects: keep only their code and message.
	local chunk = await(response.body:read(4096))
	response.body:close()
	local ok, body = pcall(json.decode, if chunk.done then "" else chunk.data)
	local message = "LinkedIn HTTP " .. tostring(response.statusCode)
	if ok and type(body) == "table" then
		if type(body.code) == "string" then message ..= " (" .. body.code .. ")" end
		if type(body.message) == "string" then message ..= ": " .. string.sub(body.message, 1, 600) end
	end
	if response.statusCode == 401 then message ..= "; reconnect LinkedIn, its access tokens expire after 60 days" end
	return houston.fail({operation = operation, layer = "upstream", upstream_status = response.statusCode,
		retryable = response.statusCode == 429 or response.statusCode >= 500, message = message})
end

local function decode(operation: string, response: HttpResponse): Options
	local ok, value = pcall(json.decode, await(response.body:readAll()))
	if not ok or type(value) ~= "table" then invalid(operation, "LinkedIn returned an invalid JSON object") end
	return value
end

local function rest(operation: string, method: string, path: string, payload: Options?): HttpResponse
	local headers: HttpHeaders = {["LinkedIn-Version"] = {VERSION}, ["X-Restli-Protocol-Version"] = {"2.0.0"}}
	if payload then headers["Content-Type"] = {"application/json"} end
	return send(operation, {method = method, url = API .. path, headers = headers,
		body = if payload then json.encode(payload) else nil})
end

local function profile(operation: string): Options
	local member = decode(operation, send(operation, {method = "GET", url = API .. "/v2/userinfo"}))
	if type(member.sub) ~= "string" or member.sub == "" then invalid(operation, "LinkedIn profile has no member ID") end
	member.urn = "urn:li:person:" .. member.sub
	return member
end

-- Register the image, then stream the session file to LinkedIn's signed upload URL.
local function uploadImage(owner: string, path: string): string
	local registered = decode("createPost", rest("createPost", "POST", "/rest/images?action=initializeUpload",
		{initializeUploadRequest = {owner = owner}})).value
	if type(registered) ~= "table" or type(registered.uploadUrl) ~= "string" or type(registered.image) ~= "string" then
		invalid("createPost", "LinkedIn did not return an image upload URL")
	end
	send("createPost", {method = "PUT", url = registered.uploadUrl,
		headers = {["Content-Type"] = {"application/octet-stream"}}, body = fs.open(path, "r")}).body:close()
	return registered.image
end

local function createPost(input: Options): Post
	local options = fields(input, "createPost", {text = true, visibility = true, image = true, article = true})
	local visibility = options.visibility or "PUBLIC"
	assert(VISIBILITY[visibility], "visibility must be PUBLIC or CONNECTIONS")
	assert(options.image == nil or options.article == nil, "createPost accepts an image or an article, not both")
	local post: Options = {
		commentary = commentary(text(options.text, "text")), visibility = visibility,
		distribution = {feedDistribution = "MAIN_FEED", targetEntities = json.decode("[]"), thirdPartyDistributionChannels = json.decode("[]")},
		lifecycleState = "PUBLISHED", isReshareDisabledByAuthor = false,
	}
	local image = if options.image == nil then nil else fields(options.image, "image", {path = true, altText = true})
	if image then
		assert(await(fs.stat(text(image.path, "image.path"))).isFile, "image.path must be a session file")
		optionalText(image.altText, "image.altText")
	elseif options.article ~= nil then
		local article = fields(options.article, "article", {url = true, title = true, description = true})
		assert(string.match(text(article.url, "article.url"), "^https?://"), "article.url must be an http(s) URL")
		post.content = {article = {source = article.url, title = text(article.title, "article.title"),
			description = optionalText(article.description, "article.description")}}
	end
	post.author = profile("createPost").urn
	if image then
		post.content = {media = {id = uploadImage(post.author, image.path), altText = image.altText}}
	end
	local response = rest("createPost", "POST", "/rest/posts", post)
	response.body:close()
	local id = response.headers["x-restli-id"]
	if not id or type(id[1]) ~= "string" or id[1] == "" then
		invalid("createPost", "LinkedIn did not confirm the post ID; check your recent activity before retrying")
	end
	return {id = id[1], url = "https://www.linkedin.com/feed/update/" .. id[1] .. "/"}
end

local function deletePost(id: string): {id: string}
	local urn = text(id, "id")
	assert(string.match(urn, "^urn:li:share:%d+$") or string.match(urn, "^urn:li:ugcPost:%d+$"),
		"id must be a post URN such as urn:li:share:123")
	rest("deletePost", "DELETE", "/rest/posts/" .. (string.gsub(urn, ":", "%%3A"))).body:close()
	return {id = urn}
end

local exports: {[string]: any} = {getProfile = function(): Options return profile("getProfile") end}
if config.access == "read-write" then
	exports.createPost = createPost
	exports.deletePost = deletePost
end

local operationHelp: {[string]: string} = {
	getProfile = [[getProfile() -> {sub, urn, name, given_name, family_name, picture?, locale, email?, email_verified?}
The connected member's OpenID Connect profile. urn (urn:li:person:<sub>) identifies the member as a post author. LinkedIn omits email when it does not share one.]],
	createPost = [==[createPost({text, visibility?, image?, article?}) -> {id, url}
Publishes a post as the connected member. text is posted literally, up to LinkedIn's 3,000 characters; #hashtags link, mentions are not supported. visibility is "PUBLIC" (default) or "CONNECTIONS". Attach at most one of:
- image = {path, altText?}: a JPG, GIF or PNG session file, streamed to LinkedIn.
- article = {url, title, description?}: a link card. LinkedIn does not fetch link previews, so supply the title.
id is the post URN (urn:li:share:... or urn:li:ugcPost:...); url opens the post. Never retry automatically: after an error or timeout the post may already be live, so check the member's recent activity first.

```lua
-- linkedin is this configured connection.
local post = linkedin.createPost({
    text = "We're hiring engineers! #hiring",
    image = {path = "photos/team.png", altText = "Our team at the office"},
})
```]==],
	deletePost = [[deletePost(id) -> {id}
Permanently deletes one of the member's own posts by URN, such as the id returned by createPost. Deleting an already deleted post succeeds.]],
}

exports.help = function(): string
	local names: {string} = {}
	for name in exports do
		if name ~= "help" then table.insert(names, name) end
	end
	table.sort(names)
	local sections = {"LinkedIn: the connected member's profile and posts. Credentials stay on Houston. Calls return completed values; do not wrap them in await(). Posting requires Read and write access. LinkedIn does not let apps read feeds, existing posts, connections or messages."}
	for _, name in names do
		local section = operationHelp[name]
		assert(section, "missing help for configured function " .. name)
		table.insert(sections, "## " .. section)
	end
	return table.concat(sections, "\n\n")
end

return exports
