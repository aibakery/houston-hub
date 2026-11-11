-- Microsoft Graph v1.0 for the connected account's Outlook contacts. Arguments and results keep
-- Graph's native field names.

-- Request layer shared verbatim by the Microsoft Graph connectors; Hub runs each copy against
-- every consumer's fixtures.
type Options = {[string]: any}
type Spec = {query: {string}?, body: boolean?, list: string?, defaults: Options?, headers: HttpHeaders?}
local GRAPH = "https://graph.microsoft.com/v1.0"
local API = GRAPH .. "/me"
-- Preauthenticated OneDrive download links, under either annotation, work without credentials,
-- so results never carry them.
local SIGNED = {"@microsoft.graph.downloadUrl", "@content.downloadUrl"}

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
	assert(unknown == nil, name .. " received an unknown option " .. tostring(unknown))
end

-- Moves the named fields from args into a query string. A $name is an OData option taken from
-- the field without $ (select, top, ...); arrays join with commas, as OData lists do.
local function query(args: Options, names: {string}): string
	local parts: {string} = {}
	for _, name in names do
		local field = if string.sub(name, 1, 1) == "$" then string.sub(name, 2) else name
		local value = args[field]
		args[field] = nil
		if value ~= nil then
			local items: {string} = {}
			for key, item in (if type(value) == "table" then value else {value}) do
				assert(type(key) == "number" and (type(item) == "string" or type(item) == "number" or type(item) == "boolean"), field .. " must be a string, number, boolean or an array of them")
				table.insert(items, url.encode(item))
			end
			assert(#items > 0, field .. " must not be an empty array")
			table.insert(parts, (if field == name then url.encode(name) else name) .. "=" .. table.concat(items, ","))
		end
	end
	return if #parts > 0 then "?" .. table.concat(parts, "&") else ""
end

-- Graph errors are {error = {code, message, innerError?}}; Excel puts its actionable code, such as
-- invalidSessionReCreatable, in innerError.code. Throttling answers 429 or 503 with Retry-After.
-- Quota (507) and other server refusals are not transient. A write that failed with a server error
-- may still have been applied, so only a refused (429) write is retryable.
local function fail(operation: string, response: HttpResponse, write: boolean?): never
	local ok, decoded = pcall(json.decode, await(response.body:readPrefix(4096)))
	local problem = if ok and type(decoded) == "table" and type(decoded.error) == "table" then decoded.error else {}
	local status = response.statusCode
	local message = "Microsoft Graph HTTP " .. tostring(status)
	if type(problem.code) == "string" then message ..= " (" .. problem.code .. ")" end
	if type(problem.message) == "string" then message ..= ": " .. string.sub(problem.message, 1, 600) end
	local detail = problem.innerError or problem.innererror
	local inner = if type(detail) == "table" then detail.code else nil
	if type(inner) == "string" and string.lower(inner) ~= string.lower(tostring(problem.code)) and not string.match(inner, "^%d+$") then
		message ..= "; innerError: " .. inner
	end
	local retry = response.headers["retry-after"]
	if retry and retry[1] then message ..= "; Retry-After: " .. retry[1] end
	return houston.fail({operation = operation, layer = "upstream", upstream_status = status, message = message,
		retryable = status == 429 or (not write and (status == 500 or status == 502 or status == 503 or status == 504 or status == 509))})
end

local function decode(operation: string, response: HttpResponse, write: boolean?): any
	if response.statusCode < 200 or response.statusCode >= 300 then fail(operation, response, write) end
	local raw = await(response.body:readAll())
	if string.match(raw, "^%s*$") then return {success = true} end
	local ok, value = pcall(json.decode, raw)
	if not ok or type(value) ~= "table" or not string.match(raw, "^%s*{") then
		houston.fail({operation = operation, layer = "upstream", upstream_status = response.statusCode,
			retryable = false, message = "Microsoft Graph returned an invalid JSON object"})
	end
	for _, key in SIGNED do
		value[key] = nil
		for _, item in (if type(value.value) == "table" then value.value else {}) :: {any} do
			if type(item) == "table" then item[key] = nil end
		end
	end
	return value
end

local function call(operation: string, method: string, href: string, body: any?, headers: HttpHeaders?): any
	local sent: HttpHeaders = if headers then table.clone(headers) else {}
	if body ~= nil then sent["Content-Type"] = {"application/json"} end
	return decode(operation, await(http.request({method = method, url = href, headers = sent,
		body = if body ~= nil then json.encode(body) elseif method == "POST" then "" else nil})), method ~= "GET")
end

-- Streams fetch()'s response to a session file; the path changes only when the whole body arrived.
local function save(operation: string, path: string, fetch: () -> HttpResponse): Options
	local output = fs.open(path, "w")
	local ok, err = pcall(function()
		local response = fetch()
		if response.statusCode ~= 200 then fail(operation, response) end
		output:write(response.body)
		await(output:close())
	end)
	if not ok then
		output:cancel()
		pcall(function() await(output:close()) end)
		error(err, 0)
	end
	return {path = path, url = await(fs.signedGetUrl(path)), size = await(fs.stat(path)).size}
end

-- Follows an @odata.nextLink of the list whose path ends with the pattern ending. It may carry only
-- paging options and a calendar view's time range: an $expand, or another route such as
-- thumbnails, could return attachment bytes or signed links. Graph may name entities by OData
-- key, as in mailFolders('inbox'), which the routes accept in their path form, mailFolders/inbox.
local PAGING = {select = true, top = true, skip = true, skiptoken = true, orderby = true, filter = true, search = true, count = true,
	startdatetime = true, enddatetime = true}
local function pageLink(link: string, ending: string): string
	local raw, search = string.match(link, "^([^?#]*)(%??[^#]*)$")
	assert(raw and search and string.sub(raw, 1, #GRAPH + 1) == GRAPH .. "/", "nextLink must be an @odata.nextLink from Microsoft Graph")
	local path = string.gsub((string.gsub(raw, "%%27", "'")), "/(%w+)%('([^'/]+)'%)", "/%1/%2")
	assert(string.find(path, ending), "nextLink must come from the same list")
	for pair in string.gmatch(string.sub(search, 2), "[^&]+") do
		local name = string.lower((string.gsub(string.match(pair, "^[^=]*") or "", "%%(%x%x)", function(hex: string): string
			return string.char(tonumber(hex, 16) or 0)
		end)))
		assert(PAGING[(string.gsub(name, "^%$", ""))], "nextLink may carry only paging options")
	end
	return path .. search
end

-- A list's nextLink, the previous page's @odata.nextLink, replaces every other option.
local function nextLink(name: string, args: Options, ending: string): string?
	if args.nextLink == nil then return nil end
	local link = text(args.nextLink, "nextLink")
	args.nextLink = nil
	assert(next(args) == nil, name .. " takes nextLink alone, from a previous page of the same list")
	return pageLink(link, ending)
end

-- One Graph request built from args: {field} placeholders take URL-encoded path segments, query
-- names the query fields and, with body, the other fields form the JSON body. A list (the Lua
-- pattern its path ends with) also accepts nextLink and always returns a value array.
local function request(name: string, method: string, path: string, input: any, spec: Spec?): any
	local args = options(input)
	local s: Spec = spec or {}
	local href = if s.list then nextLink(name, args, s.list) else nil
	if not href then
		local defaults: Options = s.defaults or {}
		for key, value in defaults do
			if args[key] == nil then args[key] = value end
		end
		local route = string.gsub(path, "{(%w+)}", function(field: string)
			local value = url.segment(text(args[field], field), field)
			args[field] = nil
			return value
		end)
		href = API .. route .. query(args, s.query or {})
		if not s.body then done(name, args) end
	end
	local result = call(name, method, href :: string, if s.body then args else nil, s.headers)
	if s.list and result.value == nil then result.value = json.decode("[]") end
	return result
end
-- End of the shared request layer.

-- Summary fields for contact lists; getContact returns every field.
local LIST = "id,displayName,givenName,surname,emailAddresses,businessPhones,homePhones,mobilePhone,companyName,jobTitle,department,categories,parentFolderId,lastModifiedDateTime"

local help = {
	text = [[Microsoft Graph v1.0 for the connected account's Outlook contacts. Operations take one named
options object with Graph's camelCase fields and return Graph's JSON unchanged. Connector calls
return completed values: use them directly, without await.
Contacts live in the default Contacts folder unless folderId names one of its folders, from
listContactFolders; folders can nest. Each list covers one folder. To see every contact, list the
default folder, then walk listContactFolders and each folder's subfolders, skipping folder ids
already seen, and list each folder's contacts. Some accounts list the default folder itself among
the folders, as Contacts: its id is the parentFolderId of default-folder contacts, and its
contacts are the ones already listed.
Lists return one page: while ['@odata.nextLink'] is present, pass it back as nextLink (alone).
Example: listContacts({filter="emailAddresses/any(a:a/address eq 'ana@example.com')", top=50}).
Houston itself retries only a short 429 wait. Errors report the HTTP status and Graph's code and
message, e.g. 'Microsoft Graph HTTP 404 (ErrorItemNotFound)'; 429 is retryable, and so are
503 and other transient server errors on reads. Graph serves at most 4 concurrent requests per mailbox.]] .. (if config.access == "read-write" then [[

Writes change only the user's own contacts and contact folders, and notify nobody. Deletes return
{success=true}; Outlook normally keeps deleted contacts and folders in Deleted Items. A failed or
timed-out create may already have succeeded: check with listContacts before repeating it.]] else ""),
	functions = {} :: {[string]: any},
}
local exports: {[string]: any} = {help = help}

-- Schemas and hints shared by several operations.
local ID = {type = "string", minLength = 1}
local CONTACT_ID = "AAMkAGI2TG93AAA="
local FOLDER_ID = "AAMkAGI2TGuLAAA="
local SELECT = {type = {"string", "array"}, items = {type = "string"}, description = "Fields, comma-separated or as an array."}
local NEXT = {type = "string", description = "The previous page's @odata.nextLink; pass it alone."}
local FOLDER = {type = "string", minLength = 1, description = "A contact folder's id from listContactFolders; defaults to the default Contacts folder."}
-- Contact fields take null, json.decode('null'), to clear them.
local TEXT = {type = {"string", "null"}}
local STRINGS = {type = {"array", "null"}, items = {type = "string"}}
local ADDRESS = {
	type = {"object", "null"},
	properties = {street = TEXT, city = TEXT, state = TEXT, countryOrRegion = TEXT, postalCode = TEXT},
	additionalProperties = false,
	description = "A postal address; an update replaces the whole address, so send every part.",
}
local CONTACT = {
	displayName = {type = {"string", "null"}, description = "Outlook may regenerate it from the name parts: send it with every update that should keep it."},
	givenName = TEXT, middleName = TEXT, surname = TEXT, nickName = TEXT, initials = TEXT, title = TEXT,
	generation = {type = {"string", "null"}, description = "A suffix such as Jr."},
	fileAs = TEXT, yomiGivenName = TEXT, yomiSurname = TEXT, yomiCompanyName = TEXT,
	emailAddresses = {
		type = {"array", "null"},
		items = {type = "object", properties = {address = ID, name = TEXT}, required = {"address"}, additionalProperties = false},
		description = "The contact's email addresses, the only email field this connector writes; Outlook shows three.",
	},
	imAddresses = STRINGS, businessPhones = STRINGS, homePhones = STRINGS, mobilePhone = TEXT,
	businessAddress = ADDRESS, homeAddress = ADDRESS, otherAddress = ADDRESS,
	companyName = TEXT, department = TEXT, jobTitle = TEXT, officeLocation = TEXT, profession = TEXT,
	manager = TEXT, assistantName = TEXT, businessHomePage = TEXT,
	birthday = {type = {"string", "null"}, description = "A date such as 1974-07-22, as in Microsoft's example; Graph returns it as a UTC date and time."},
	spouseName = TEXT, children = STRINGS, personalNotes = TEXT, categories = STRINGS,
}
local READ = {readOnlyHint = true, openWorldHint = true}
local WRITE = {readOnlyHint = false, destructiveHint = false, openWorldHint = true}
local DESTRUCTIVE = {readOnlyHint = false, destructiveHint = true, openWorldHint = true}

local function with(base: Options, extra: Options): Options
	local merged = table.clone(base)
	for key, value in extra do merged[key] = value end
	return merged
end

local NULL = json.decode("null")

-- Checks a value against its string, array or object schema, whose type may also allow null, and
-- returns it; a top-level empty array becomes [] rather than {}. No schema here nests arrays.
local function check(value: any, schema: Options, path: string): any
	local kind = schema.type
	if type(kind) == "table" then
		if value == NULL and table.find(kind, "null") then return value end
		kind = kind[1]
	end
	if kind == "string" then
		assert(type(value) == "string" and #value >= (schema.minLength or 0), path .. " must be a " .. (if schema.minLength then "nonempty " else "") .. "string")
		return value
	end
	assert(kind == "array" or kind == "object", path .. " has a schema type check() does not handle")
	assert(type(value) == "table", path .. " must be " .. (if kind == "array" then "an array" else "an object"))
	if kind == "array" then
		local count = 0
		for index, item in value do
			count += 1
			assert(type(index) == "number", path .. " must be an array")
			check(item, schema.items, path .. "[" .. index .. "]")
		end
		assert(count == #value, path .. " must be an array")
		return if count == 0 then json.decode("[]") else value
	end
	for key, item in value do
		local property = schema.properties[key]
		assert(property ~= nil, path .. " received an unknown field " .. tostring(key))
		check(item, property, path .. "." .. key)
	end
	local required: {string} = schema.required or {}
	for _, key in required do assert(value[key] ~= nil, path .. "." .. key .. " is required") end
	return value
end

-- Write bodies are closed and checked before any request: Graph's schema makes contact an open
-- type, so a misspelt field might be kept or dropped rather than refused.
local function fields(name: string, args: Options, schema: Options)
	for key, value in args do
		local field = schema[key]
		assert(field ~= nil, name .. " received an unknown option " .. key)
		args[key] = check(value, field, key)
	end
end

-- A contact by id, in the default folder or in folderId.
local function contact(args: Options): string
	return if args.folderId == nil then "/contacts/{id}" else "/contactFolders/{folderId}/contacts/{id}"
end

help.functions.listContactFolders = {
	description = [[One page of the folders in the default Contacts folder, or of folderId's subfolders:
{value={{id, displayName, parentFolderId}}, ['@odata.nextLink']?}. Some accounts list the default
Contacts folder itself here, with the other folders as its subfolders.]],
	inputSchema = {
		type = "object",
		properties = {folderId = {type = "string", minLength = 1, description = "A folder whose subfolders to list."}, select = SELECT,
			filter = {type = "string"}, top = {type = "integer", minimum = 1}, nextLink = NEXT},
		additionalProperties = false,
		examples = {{top = 100}, {folderId = FOLDER_ID}} :: {any},
	},
	annotations = READ,
}
function exports.listContactFolders(input: any): Options
	local args = options(input)
	return request("listContactFolders", "GET", if args.folderId == nil then "/contactFolders" else "/contactFolders/{folderId}/childFolders", args,
		{list = "/c[a-z]+Folders$", query = {"$select", "$filter", "$top"}}) -- contactFolders or childFolders; the proxy refuses any other
end

help.functions.listContacts = {
	description = [[One page of the contacts in the default Contacts folder, or in folderId: {value={contact},
['@odata.nextLink']?}. Default fields: ]] .. LIST .. [[. select replaces them, so name every field
needed, such as "id,displayName,homeAddress,birthday". Graph documents one filter, an exact email
address: "emailAddresses/any(a:a/address eq 'ana@example.com')". Other filters, such as
"startswith(displayName,'Ana')", and orderby, such as displayName, are undocumented for contacts
and may be refused. Pages are small unless top asks for more, such as 100.]],
	inputSchema = {
		type = "object",
		properties = {
			folderId = FOLDER, filter = {type = "string"}, orderby = {type = "string"}, select = SELECT,
			top = {type = "integer", minimum = 1}, nextLink = NEXT,
		},
		additionalProperties = false,
		examples = {
			{top = 100},
			{folderId = FOLDER_ID, filter = "emailAddresses/any(a:a/address eq 'ana@example.com')"},
		} :: {any},
	},
	annotations = READ,
}
function exports.listContacts(input: any): Options
	local args = options(input)
	return request("listContacts", "GET", if args.folderId == nil then "/contacts" else "/contactFolders/{folderId}/contacts", args,
		{list = "/contacts$", defaults = {select = LIST}, query = {"$select", "$filter", "$orderby", "$top"}})
end

help.functions.getContact = {
	description = [[One contact with every field unless select narrows them: {id, displayName, givenName, surname,
emailAddresses={{name, address}}, businessPhones, homePhones, mobilePhone, businessAddress,
homeAddress, otherAddress, companyName, jobTitle, birthday, personalNotes, categories,
parentFolderId, changeKey, ...}. folderId is optional: if Graph answers 404 for a contact outside
the default folder, pass the contact's parentFolderId as folderId.]],
	inputSchema = {
		type = "object",
		properties = {id = ID, folderId = FOLDER, select = SELECT},
		required = {"id"},
		additionalProperties = false,
		examples = {{id = CONTACT_ID}, {id = CONTACT_ID, folderId = FOLDER_ID, select = "displayName,emailAddresses"}} :: {any},
	},
	annotations = READ,
}
function exports.getContact(input: any): Options
	local args = options(input)
	return request("getContact", "GET", contact(args), args, {query = {"$select"}})
end

if config.access == "read-write" then
	local NEW = with(CONTACT, {folderId = FOLDER})
	local CHANGE = with(CONTACT, {id = ID, folderId = FOLDER})

	help.functions.createContact = {
		description = [[Creates a contact in the default Contacts folder, or in folderId, and returns it. Phones are
businessPhones and homePhones (arrays) and mobilePhone (one number).]],
		inputSchema = {
			type = "object",
			properties = NEW,
			additionalProperties = false,
			examples = {
				{givenName = "Ana", surname = "Silva", emailAddresses = {{address = "ana@example.com", name = "Ana Silva"}},
					mobilePhone = "+33 6 12 34 56 78", companyName = "Contoso"},
				{folderId = FOLDER_ID, displayName = "Bo Chen", businessPhones = {"+1 425 555 0100"},
					businessAddress = {street = "1 Main St", city = "Redmond", state = "WA", countryOrRegion = "United States", postalCode = "98052"}},
			} :: {any},
		},
		annotations = WRITE,
	}
	function exports.createContact(input: any): Options
		local args = options(input)
		fields("createContact", args, NEW)
		local body = table.clone(args)
		body.folderId = nil
		assert(next(body) ~= nil, "createContact requires contact fields")
		return request("createContact", "POST", if args.folderId == nil then "/contacts" else "/contactFolders/{folderId}/contacts", args, {body = true})
	end

	help.functions.updateContact = {
		description = [[Changes the given fields of a contact and returns it. Arrays such as emailAddresses and
businessPhones are replaced whole, and so are addresses: read the contact and send the full value.
json.decode('null') clears a field, such as birthday.
Graph documents no move action, and updateContact does not send parentFolderId: to move a
contact, create it in the target folder and delete the original, which gives it a new id.]],
		inputSchema = {
			type = "object",
			properties = CHANGE,
			required = {"id"},
			additionalProperties = false,
			examples = {{id = CONTACT_ID, jobTitle = "CTO", emailAddresses = {{address = "ana@example.com"}, {address = "ana.silva@example.org"}}}},
		},
		annotations = WRITE,
	}
	function exports.updateContact(input: any): Options
		local args = options(input)
		fields("updateContact", args, CHANGE)
		local body = table.clone(args)
		body.id, body.folderId = nil, nil
		assert(next(body) ~= nil, "updateContact requires fields to change")
		return request("updateContact", "PATCH", contact(args), args, {body = true})
	end

	help.functions.deleteContact = {
		description = "Deletes a contact and returns {success=true}; Outlook normally keeps it in Deleted Items.",
		inputSchema = {type = "object", properties = {id = ID, folderId = FOLDER}, required = {"id"}, additionalProperties = false, examples = {{id = CONTACT_ID}}},
		annotations = DESTRUCTIVE,
	}
	function exports.deleteContact(input: any): Options
		local args = options(input)
		return request("deleteContact", "DELETE", contact(args), args)
	end

	local NAME = {type = "string", minLength = 1, description = "The folder's name."}
	local NEW_FOLDER = {displayName = NAME, parentFolderId = {type = "string", minLength = 1, description = "The folder to create it in."}}
	local CHANGE_FOLDER = {folderId = ID, displayName = NAME, parentFolderId = {type = "string", minLength = 1, description = "The folder to move it into."}}

	help.functions.createContactFolder = {
		description = "Creates a contact folder in the default Contacts folder, or inside parentFolderId, and returns {id, displayName, parentFolderId}.",
		inputSchema = {
			type = "object",
			properties = NEW_FOLDER,
			required = {"displayName"},
			additionalProperties = false,
			examples = {{displayName = "Suppliers"}, {displayName = "Paris", parentFolderId = FOLDER_ID}} :: {any},
		},
		annotations = WRITE,
	}
	function exports.createContactFolder(input: any): Options
		local args = options(input)
		text(args.displayName, "displayName")
		fields("createContactFolder", args, NEW_FOLDER)
		return request("createContactFolder", "POST", if args.parentFolderId == nil then "/contactFolders" else "/contactFolders/{parentFolderId}/childFolders", args, {body = true})
	end

	help.functions.updateContactFolder = {
		description = "Renames a contact folder, or moves it into parentFolderId, and returns it.",
		inputSchema = {
			type = "object",
			properties = CHANGE_FOLDER,
			required = {"folderId"},
			anyOf = {{required = {"displayName"}}, {required = {"parentFolderId"}}} :: {any},
			additionalProperties = false,
			examples = {{folderId = FOLDER_ID, displayName = "Key suppliers"}},
		},
		annotations = WRITE,
	}
	function exports.updateContactFolder(input: any): Options
		local args = options(input)
		fields("updateContactFolder", args, CHANGE_FOLDER)
		assert(args.displayName ~= nil or args.parentFolderId ~= nil, "updateContactFolder requires displayName or parentFolderId")
		return request("updateContactFolder", "PATCH", "/contactFolders/{folderId}", args, {body = true})
	end

	help.functions.deleteContactFolder = {
		description = "Deletes a contact folder with its contacts and subfolders and returns {success=true}; Outlook normally keeps them in Deleted Items. The default Contacts folder cannot be deleted, and Graph sometimes refuses other folders with 403 ErrorCannotDeleteObject.",
		inputSchema = {type = "object", properties = {folderId = ID}, required = {"folderId"}, additionalProperties = false, examples = {{folderId = FOLDER_ID}}},
		annotations = DESTRUCTIVE,
	}
	function exports.deleteContactFolder(input: any): Options
		local args = options(input)
		return request("deleteContactFolder", "DELETE", "/contactFolders/{folderId}", args)
	end
end

return exports
