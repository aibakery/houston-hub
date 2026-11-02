-- WordPress REST API (wp/v2). Arguments and results keep WordPress's native field names, nulls and arrays.
type Options = {[string]: any}
type Endpoint = {method: string, path: string, doc: string, sensitive: boolean?, private: {[string]: boolean}?, upload: boolean?, signature: string?}

local PROVIDER = "WordPress"
local SITE = string.lower(config.site_host)
local API = "https://" .. SITE .. "/wp-json/wp/v2"
local DOCS = "https://developer.wordpress.org/rest-api/reference/"
-- _embed adds linked authors, terms, featured media and replies in their public embed context.
local META_QUERY = {_fields = true, _embed = true}
local DOMAIN = "site domain"
local WRITE = config.access == "read-write"

-- Core resources share one CRUD shape; {parent} is the revised post or page. Read-only
-- connections refuse the edit context, which adds post passwords and users' and commenters'
-- email and IP addresses, and accept only the listed users and comments options: WordPress
-- matches searches and some filters against those addresses. Settings include the admin
-- email and need read-write even to read.
-- Plugins, themes, application passwords, user changes, batch requests and the site
-- editor are deliberately not exposed (the manifest allows only these routes).
local function set(...: string): {[string]: boolean}
	local names: {[string]: boolean} = {}
	for _, name in {...} do names[name] = true end
	return names
end
local USER_OPTIONS = set("id", "context", "page", "per_page", "offset", "include", "exclude", "slug", "who", "has_published_posts",
	"order", "orderby", "_fields", "_embed")
local COMMENT_OPTIONS = set("id", "context", "page", "per_page", "offset", "include", "exclude", "post", "parent", "parent_exclude",
	"author", "author_exclude", "status", "type", "after", "before", "password", "order", "orderby", "_fields", "_embed")
local function names(options: {[string]: boolean}): string
	local list: {string} = {}
	for name in options do if name ~= "id" and name ~= "context" then table.insert(list, name) end end
	table.sort(list)
	return table.concat(list, ", ")
end
local ALL = {"list", "get", "create", "update", "delete"}
local READ = {"list", "get"}
local RESOURCES = {
	{one = "Post", many = "Posts", path = "/posts", ops = ALL, doc = "posts"},
	{one = "PostRevision", many = "PostRevisions", path = "/posts/{parent}/revisions", ops = READ, doc = "post-revisions"},
	{one = "Page", many = "Pages", path = "/pages", ops = ALL, doc = "pages"},
	{one = "PageRevision", many = "PageRevisions", path = "/pages/{parent}/revisions", ops = READ, doc = "page-revisions"},
	{one = "Media", many = "Media", path = "/media", ops = {"list", "get", "update", "delete"}, doc = "media"},
	{one = "Category", many = "Categories", path = "/categories", ops = ALL, doc = "categories"},
	{one = "Tag", many = "Tags", path = "/tags", ops = ALL, doc = "tags"},
	{one = "Comment", many = "Comments", path = "/comments", ops = ALL, doc = "comments", private = COMMENT_OPTIONS},
	{one = "User", many = "Users", path = "/users", ops = READ, doc = "users", private = USER_OPTIONS},
	{one = "PostType", many = "PostTypes", path = "/types", ops = READ, doc = "post-types"},
	{one = "PostStatus", many = "PostStatuses", path = "/statuses", ops = READ, doc = "post-statuses"},
	{one = "Taxonomy", many = "Taxonomies", path = "/taxonomies", ops = READ, doc = "taxonomies"},
}
local OPERATIONS = {
	list = {many = true, method = "GET", suffix = ""},
	get = {many = false, method = "GET", suffix = "/{id}"},
	create = {many = false, method = "POST", suffix = ""},
	update = {many = false, method = "POST", suffix = "/{id}"},
	delete = {many = false, method = "DELETE", suffix = "/{id}"},
}
local endpoints: {[string]: Endpoint} = {
	search = {method = "GET", path = "/search", doc = "search-results"},
	uploadMedia = {method = "POST", path = "/media", doc = "media", upload = true, signature = "path, content_type, filename?, ...fields?"},
	getSettings = {method = "GET", path = "/settings", doc = "settings", sensitive = true},
}
for _, resource in RESOURCES do
	for _, verb in resource.ops do
		local operation = OPERATIONS[verb]
		endpoints[verb .. (if operation.many then resource.many else resource.one)] = {method = operation.method,
			path = resource.path .. operation.suffix, doc = resource.doc, private = resource.private}
	end
end

-- Request layer shared verbatim by the WordPress REST connectors
-- (tools/validate checks they match). It uses each connector's PROVIDER, API, DOCS, DOMAIN
-- (its domain setting), META_QUERY and Endpoint type.
local function options(input: Options?): Options
	if input == nil then return {} end
	assert(type(input) == "table", "opts must be an object")
	for key in input do assert(type(key) == "string", "opts must have named fields") end
	return table.clone(input)
end

-- IDs are nonnegative integers (WooCommerce's shipping zone 0 is "rest of the world");
-- other resources use slugs or codes, such as a post type, a setting group or "me".
local function identifier(value: any, field: string): string
	if type(value) == "number" then
		assert(value >= 0 and value % 1 == 0 and value <= 9007199254740991, field .. " must be a nonnegative integer ID")
		return string.format("%d", value)
	end
	assert(type(value) == "string" and string.match(value, "^[%w_%-]+$"), field .. " must be an ID, slug or code")
	return value
end

-- WordPress reads _method and rest_route from any query string, so they could change
-- a request's method or route, and PHP turns dots and spaces in names into
-- underscores. Query names are plain parameters, plus the connector's META_QUERY.
local function queryKey(key: string): string
	assert(META_QUERY[key] or (string.match(key, "^%a[%w_]*$") and key ~= "rest_route"), key .. " is not a " .. PROVIDER .. " query parameter")
	return key
end

local function scalar(value: any, key: string): string
	local kind = type(value)
	assert(kind == "string" or kind == "boolean" or (kind == "number" and value == value and math.abs(value) < math.huge),
		key .. " must be a string, boolean, finite number or array of those")
	return url.encode(value)
end

-- Arrays use WordPress's key[]=value form; their order is preserved (orderby=include).
local function query(args: Options): string
	local keys: {string} = {}
	for key in args do table.insert(keys, queryKey(key)) end
	table.sort(keys)
	local parts: {string} = {}
	for _, key in keys do
		local value = args[key]
		if type(value) == "table" then
			local count = 0
			for index in value do
				assert(type(index) == "number", key .. " must be an array, not an object")
				count += 1
			end
			assert(count == #value, key .. " must be a dense array")
			assert(count > 0, key .. " must not be an empty array: pass at least one value or omit it")
			for _, item in ipairs(value) do table.insert(parts, key .. "%5B%5D=" .. scalar(item, key)) end
		else
			table.insert(parts, key .. "=" .. scalar(value, key))
		end
	end
	return if #parts > 0 then "?" .. table.concat(parts, "&") else ""
end

local function fail(name: string, response: HttpResponse, message: string): never
	return houston.fail({operation = name, layer = "upstream", upstream_status = response.statusCode,
		retryable = response.statusCode == 429 or response.statusCode >= 500, message = message})
end

local function header(response: HttpResponse, name: string): string?
	local values = response.headers[name]
	return if values then values[1] else nil
end

-- Host firewalls answer with HTML pages; keep their visible text and comments, which
-- name the blocking layer.
local function excerpt(raw: string): string
	local text = string.gsub(raw, "<!%-%-(.-)%-%->", " %1 ")
	for _, tag in {"script", "style"} do text = string.gsub(text, "<" .. tag .. "[%s>].-</" .. tag .. ">", " ") end
	text = string.gsub(string.gsub(text, "<[^>]*>", " "), "%s+", " ")
	return string.sub((string.gsub(text, "^ ", "")), 1, 300)
end

local function failStatus(name: string, response: HttpResponse): never
	local message = PROVIDER .. " HTTP " .. tostring(response.statusCode)
	local raw = await(response.body:readPrefix(16 * 1024))
	local ok, value = pcall(json.decode, raw)
	if ok and type(value) == "table" then
		if type(value.code) == "string" then message ..= " (" .. value.code .. ")" end
		if type(value.message) == "string" then message ..= ": " .. string.sub(value.message, 1, 600) end
		if type(value.data) == "table" and type(value.data.params) == "table" then
			message ..= " " .. string.sub(json.encode(value.data.params), 1, 600)
		end
	elseif string.match(raw, "%S") then
		message ..= ": " .. excerpt(raw)
	end
	local server = header(response, "server")
	if server then message ..= "; Server: " .. string.sub(server, 1, 100) end
	local location = header(response, "location")
	if response.statusCode >= 300 and response.statusCode < 400 and location then
		message ..= "; redirected to " .. string.sub(location, 1, 200) .. ". Set the connection's " .. DOMAIN .. " to the final host."
	end
	local retry = header(response, "retry-after")
	if retry then message ..= "; Retry-After: " .. retry end
	return fail(name, response, message)
end

-- JSON arrays become {items, total?, total_pages?}, keeping WordPress's paging headers.
local function decode(name: string, response: HttpResponse): any
	if response.statusCode < 200 or response.statusCode >= 300 then failStatus(name, response) end
	local raw = await(response.body:readAll())
	local ok, value = pcall(json.decode, raw)
	if not ok or type(value) ~= "table" then
		fail(name, response, PROVIDER .. " returned a response that is not JSON; check that the " .. DOMAIN .. " serves the WordPress REST API at /wp-json")
	end
	if string.match(raw, "^%s*%[") then
		return {items = value, total = tonumber(header(response, "x-wp-total")), total_pages = tonumber(header(response, "x-wp-totalpages"))}
	end
	return value
end

-- The endpoint's path with its {fields} taken out of args.
local function route(endpoint: Endpoint, args: Options): string
	return (string.gsub(endpoint.path, "{([%w_]+)}", function(field: string)
		local value = identifier(args[field], field)
		args[field] = nil
		return value
	end))
end

local function request(name: string, endpoint: Endpoint, input: Options?): any
	local args = options(input)
	local path = route(endpoint, args)
	local headers: HttpHeaders = {Accept = {"application/json"}}
	local body: string? = nil
	if endpoint.method == "GET" or endpoint.method == "DELETE" then
		path ..= query(args)
	else
		headers["Content-Type"] = {"application/json"}
		body = json.encode(args)
	end
	return decode(name, await(http.request({method = endpoint.method, url = API .. path, headers = headers, body = body})))
end

local function signature(endpoint: Endpoint): string
	local fields: {string} = {}
	for field in string.gmatch(endpoint.path, "{([%w_]+)}") do table.insert(fields, field) end
	if endpoint.signature then
		table.insert(fields, endpoint.signature)
	elseif endpoint.method == "GET" or endpoint.method == "DELETE" then
		table.insert(fields, "...query?")
	else
		table.insert(fields, "...fields")
	end
	return "({" .. table.concat(fields, ", ") .. "})"
end

-- Reads, plus writes and sensitive reads on read-write connections, and help listing them
-- after intro.
local function operations(endpoints: {[string]: Endpoint}, call: (string, Endpoint, Options?) -> any, intro: {string}): {[string]: any}
	local exports: {[string]: any} = {}
	for name, endpoint in endpoints do
		if (endpoint.method == "GET" and not endpoint.sensitive) or config.access == "read-write" then
			exports[name] = function(args: Options?): any return call(name, endpoint, args) end
		end
	end
	exports.help = function(): string
		local names: {string} = {}
		for name in exports do if name ~= "help" then table.insert(names, name) end end
		table.sort(names)
		local lines = table.clone(intro)
		table.insert(lines, "Each function below names its route and its reference page, " .. DOCS .. "<page>/, which lists fields, filters and response shapes.")
		for _, name in names do
			local endpoint = endpoints[name]
			table.insert(lines, name .. signature(endpoint) .. ": " .. endpoint.method .. " " .. endpoint.path .. " (" .. endpoint.doc .. ")")
		end
		return table.concat(lines, "\n")
	end
	return exports
end
-- End of the shared request layer.

-- WordPress stores the request body as the file, named by Content-Disposition's plain
-- filename attribute; the other fields travel in the query string, which WordPress reads
-- like a JSON body. It would parse form bodies into $_POST, where a rest_route field
-- reroutes the request, and JSON bodies into parameters that outrank the query, so those
-- media types are refused. url would make the site download a remote file instead.
local function upload(name: string, input: Options?): any
	local args = options(input)
	local path, contentType = args.path, args.content_type
	assert(type(path) == "string" and path ~= "", "path must name a session file")
	assert(type(contentType) == "string" and string.match(contentType, "^[%w!#$&^_.+-]+/[%w!#$&^_.+-]+$"),
		"content_type must be a media type such as image/jpeg")
	contentType = string.lower(contentType)
	assert(contentType ~= "application/x-www-form-urlencoded" and not string.match(contentType, "^multipart/")
		and not string.match(contentType, "^application/.*json"), "content_type must be the file's media type, not a form or JSON type")
	assert(args.url == nil, "url is not supported: upload a session file with path")
	local filename = args.filename or string.match(path, "[^/]+$")
	assert(type(filename) == "string" and string.match(filename, "^[%w _.,()+@=%-]+%.%w+$"),
		"filename must be an ASCII file name with an extension, such as photo.jpg; pass filename when the path's name is not")
	args.path, args.content_type, args.filename = nil, nil, nil
	local target = API .. "/media" .. query(args)
	local file = fs.open(path, "r")
	return decode(name, await(http.request({method = "POST", url = target, body = file, headers = {
		Accept = {"application/json"}, ["Content-Type"] = {contentType},
		["Content-Disposition"] = {'attachment; filename="' .. filename .. '"'},
	}})))
end

local function call(name: string, endpoint: Endpoint, input: Options?): any
	if not WRITE and type(input) == "table" then
		local context = input.context
		assert(context == nil or context == "view" or context == "embed", "context must be view or embed: context='edit' needs read-write access because it adds post passwords and users' and commenters' email and IP addresses")
		local allowed = endpoint.private
		if allowed then
			for key in input do
				assert(allowed[key], tostring(key) .. " is not available on read-only connections: it can match email or IP addresses")
			end
			assert(input.orderby ~= "email", "orderby='email' is not available on read-only connections")
		end
	end
	if endpoint.upload then return upload(name, input) end
	return request(name, endpoint, input)
end

local intro = {
	"WordPress REST API (wp/v2) for " .. SITE .. ". Every function takes one named options object with WordPress's snake_case names; ? marks optional fields. Path IDs (id, parent) are numbers, or slugs for post types, statuses and taxonomies; getUser({id='me'}) returns the connection's own user. Other options are query parameters on " .. (if WRITE then "list/get/delete calls" else "these calls") .. " (arrays send key[]=value and must not be empty; names are plain WordPress parameters, _fields or _embed)" .. (if WRITE then " and the unchanged JSON body on create/update calls" else "") .. ". Results keep WordPress's native fields and nulls. Connector calls return completed values: use them directly, without await.",
	"JSON array responses return {items, total?, total_pages?}, with totals from X-WP-Total/X-WP-TotalPages. Lists fetch one page: pass page (1-based) and per_page (1-100, default 10), and continue while page < total_pages; a page past the end fails with rest_post_invalid_page_number. per_page=1 with total counts matches without fetching them. listPostTypes, listPostStatuses and listTaxonomies are not paged and return one object keyed by slug. _fields='id,title,status,link' trims each item; _embed=true adds author, terms and featured media under _embedded. Dates such as after, before and date are ISO 8601 in the site's time zone; the *_gmt fields are UTC.",
	"Content: title, content and excerpt read as {rendered}" .. (if WRITE then "; pass context='edit' to also get the raw block markup" else "") .. ". List drafts, scheduled and private items with status={'draft','future','private','pending','publish'}. Statuses: draft, pending (submitted for review), publish, future (scheduled), private (visible to logged-in editors only) and trash.",
	"Examples: listPosts({status={'draft','future'}, _fields='id,title,status,date'}); getPost({id=12, _embed=true}); listComments({status='hold', post=12}); listCategories({search='news'}); search({search='pricing', type='post'}); getUser({id='me'}).",
}
if WRITE then
	table.insert(intro, "Writing: title, content and excerpt are strings of HTML or block markup; read with context='edit' before editing to get the raw markup. status='draft' saves, 'pending' submits for review, 'publish' publishes now (or schedules, when date is in the future), 'future' with a future date or date_gmt schedules (a past date publishes at once: read back status and date_gmt), and 'private' publishes for logged-in editors only. categories and tags are arrays of term IDs: find or create them with listCategories({search=...}) or createTag({name=...}) first.")
	table.insert(intro, "Examples: createPost({title='Launch notes', content='<!-- wp:paragraph --><p>Hello</p><!-- /wp:paragraph -->', status='draft', categories={4}}); updatePost({id=12, status='future', date='2026-11-10T09:00:00'}); uploadMedia({path='photo.jpg', content_type='image/jpeg', alt_text='Team photo', post=12}) then updatePost({id=12, featured_media=<the returned id>}); listComments({status='hold', context='edit'}); updateComment({id=5, status='approved'}).")
	table.insert(intro, "Deleting: posts, pages and comments move to the trash unless force=true; media, categories and tags cannot be trashed and require force=true; trashed posts and pages return with status='trash' and are restored with updatePost({id, status='draft'}); comments are restored with updateComment({id, status='untrash'}), and moderated with status approved, hold, spam or unspam. uploadMedia streams the session file at path as one attachment (up to the size the site's web server and PHP accept; the extension must be a type WordPress allows, and filename must be ASCII). Its other fields, such as title, alt_text or post (the post it belongs to), are scalar query parameters of the same request: set long captions, descriptions or meta afterwards with updateMedia.")
end
table.insert(intro, (if WRITE
	then "Access: context='edit' returns post passwords and users' and commenters' email and IP addresses, and getSettings (Administrators only) includes the site's admin email: treat them as sensitive."
	else "Access: this connection is read-only. It refuses context='edit', which adds post passwords and users' and commenters' email and IP addresses, Users and comments accept only these options, because searches and email filters match those addresses: users " .. names(USER_OPTIONS) .. "; comments " .. names(COMMENT_OPTIONS) .. ". List authors with listUsers({who='authors'}) and look users up by slug or include.")
	.. " Plugins, themes, application passwords, user changes and site settings changes are not available. The WordPress user's role still applies: an Author can only publish and edit their own posts, can add tags but not categories, and cannot manage pages or comments; an Editor manages everyone's content and comments. Houston waits and retries HTTP 429 at most twice unless Retry-After asks for more than 5 seconds; nothing else is retried: after a timeout or 5xx, read the item again before repeating a write. A remaining 429 usually comes from the site's host firewall or a security plugin: space calls out. Errors report the HTTP status, WordPress code (such as rest_forbidden or incorrect_password), message, invalid parameters, Retry-After, the Server header and the start of non-JSON bodies; a 401 usually means the application password is wrong or revoked, or the web server drops the Authorization header.")

return operations(endpoints, call, intro)
