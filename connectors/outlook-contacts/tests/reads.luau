return {
	scenario = {publisher = {client_id = "fixture-client", client_secret = "fixture-private-secret"}, config = {}, auth_method = "oauth", auth_config = {}},
	config = {access = "read-only"},
	configure = function()
		requests, responses = {}, {}
		http = {request = function(req)
			assert(req.headers == nil or req.headers.Authorization == nil, "the proxy injects Authorization")
			table.insert(requests, req)
			assert(#responses > 0, "unexpected request: " .. req.url)
			local response = table.remove(responses, 1)
			return fixture.operation({statusCode = response.status or 200, headers = response.headers or {}, body = fixture.reader(response.body or "")})
		end}
	end,
	run = function(c)
		local API = "https://graph.microsoft.com/v1.0/me"
		local LIST = "$select=id%2CdisplayName%2CgivenName%2Csurname%2CemailAddresses%2CbusinessPhones%2ChomePhones%2CmobilePhone%2CcompanyName%2CjobTitle%2Cdepartment%2Ccategories%2CparentFolderId%2ClastModifiedDateTime"
		local function last() return requests[#requests] end
		local function fails(expected: {string}, fn: (...any) -> any, ...: any)
			local ok, err = pcall(fn, ...)
			assert(not ok, "call succeeded")
			for _, text in expected do assert(string.find(tostring(err), text, 1, true), "missing " .. text .. " in " .. tostring(err)) end
		end
		local names = {}
		for name in c do table.insert(names, name) end
		table.sort(names)
		assert(table.concat(names, ",") == "getContact,listContactFolders,listContacts", "read-only got " .. table.concat(names, ","))

		-- Contact lists default to summary fields and always carry a value array; a nextLink, which
		-- Graph may write with an OData key, is followed alone.
		local link = "https://graph.microsoft.com/v1.0/me/contactFolders('AQMk-F1%3D%3D')/contacts?%24select=id&%24top=2&%24skip=2"
		responses = {
			{body = '{"value":[{"id":"C1","displayName":"Ana Silva","emailAddresses":[{"name":"Ana Silva","address":"ana@example.com"}]}],"@odata.nextLink":"https://graph.microsoft.com/v1.0/me/contacts?%24top=1&%24skip=1"}'},
			{body = '{"value":[]}'}, {body = '{}'}, {body = '{"value":[{"id":"C3"}]}'},
		}
		local page = c.listContacts({top = 1, orderby = "displayName", filter = "emailAddresses/any(a:a/address eq 'ana@example.com')"})
		assert(page.value[1].emailAddresses[1].address == "ana@example.com" and page["@odata.nextLink"] ~= nil)
		assert(last().method == "GET" and last().url == API .. "/contacts?" .. LIST
			.. "&$filter=emailAddresses%2Fany%28a%3Aa%2Faddress%20eq%20%27ana%40example.com%27%29&$orderby=displayName&$top=1", last().url)
		assert(json.encode(c.listContacts({nextLink = page["@odata.nextLink"]}).value) == "[]" and last().url == API .. "/contacts?%24top=1&%24skip=1", last().url)
		assert(json.encode(c.listContacts({folderId = "AQMk-F1==", select = {"id", "birthday"}}).value) == "[]")
		assert(last().url == API .. "/contactFolders/AQMk-F1%3D%3D/contacts?$select=id,birthday", last().url)
		assert(c.listContacts({nextLink = link}).value[1].id == "C3" and last().url == API .. "/contactFolders/AQMk-F1%3D%3D/contacts?%24select=id&%24top=2&%24skip=2", last().url)

		-- Folders: the default folder's children, or a folder's subfolders.
		responses = {{body = '{"value":[{"id":"F1","displayName":"Suppliers","parentFolderId":"F0"}],"@odata.nextLink":"https://graph.microsoft.com/v1.0/me/contactFolders?%24skip=1"}'}, {body = '{}'}, {body = '{}'}}
		local folders = c.listContactFolders({top = 1})
		assert(folders.value[1].parentFolderId == "F0" and last().url == API .. "/contactFolders?$top=1", last().url)
		assert(json.encode(c.listContactFolders({nextLink = folders["@odata.nextLink"]}).value) == "[]" and last().url == API .. "/contactFolders?%24skip=1", last().url)
		assert(json.encode(c.listContactFolders({folderId = "F1", filter = "displayName eq 'Paris'"}).value) == "[]")
		assert(last().url == API .. "/contactFolders/F1/childFolders?$filter=displayName%20eq%20%27Paris%27", last().url)

		-- One contact, from the default folder or another.
		responses = {{body = '{"id":"C1","displayName":"Ana Silva","homeAddress":{}}'}, {body = '{"id":"C2"}'}}
		assert(c.getContact({id = "AAMk-_="}).displayName == "Ana Silva" and last().url == API .. "/contacts/AAMk-_%3D", last().url)
		assert(c.getContact({id = "C2", folderId = "F1", select = "displayName,emailAddresses"}).id == "C2")
		assert(last().url == API .. "/contactFolders/F1/contacts/C2?$select=displayName%2CemailAddresses" and last().body == nil, last().url)

		-- Invalid input never reaches the network.
		local before = #requests
		fails({"id must be a nonempty string"}, c.getContact, {})
		fails({"folderId must be a nonempty string"}, c.listContacts, {folderId = ""})
		fails({"getContact received an unknown option expand"}, c.getContact, {id = "C1", expand = "extensions"})
		fails({"listContacts received an unknown option search"}, c.listContacts, {search = "Ana"})
		fails({"listContacts takes nextLink alone"}, c.listContacts, {nextLink = link, top = 5})
		fails({"nextLink must come from the same list"}, c.listContacts, {nextLink = "https://graph.microsoft.com/v1.0/me/messages?%24skip=2"})
		fails({"nextLink must come from the same list"}, c.listContactFolders, {nextLink = link})
		fails({"nextLink may carry only paging options"}, c.listContacts, {nextLink = "https://graph.microsoft.com/v1.0/me/contacts?%24expand=extensions"})
		fails({"nextLink must be an @odata.nextLink from Microsoft Graph"}, c.listContacts, {nextLink = "https://graph.microsoft.com.evil.test/v1.0/me/contacts"})
		assert(not pcall(c.getContact, {id = "C1/../../messages"}), "an id with a slash reached the network")
		assert(#requests == before, "invalid input reached the network")

		-- Graph errors keep the status, code and message; throttling and server errors on reads are retryable.
		responses = {
			{status = 404, body = '{"error":{"code":"ErrorItemNotFound","message":"The specified object was not found in the store.","innerError":{"request-id":"r1"}}}'},
			{status = 400, body = '{"error":{"code":"ErrorInvalidUrlQueryFilter","message":"The filter expression is not supported."}}'},
			{status = 429, headers = {["retry-after"] = {"7"}}, body = '{"error":{"code":"ApplicationThrottled","message":"Slow down"}}'},
			{status = 503, body = '{"error":{"code":"ServiceUnavailable","message":"Try later"}}'},
			{status = 200, body = "[]"},
		}
		fails({"Microsoft Graph HTTP 404 (ErrorItemNotFound): The specified object was not found", '"retryable":false'}, c.getContact, {id = "gone"})
		fails({"HTTP 400 (ErrorInvalidUrlQueryFilter)", '"retryable":false'}, c.listContacts, {filter = "startswith(displayName,'A')"})
		fails({"HTTP 429 (ApplicationThrottled)", "Retry-After: 7", '"retryable":true'}, c.listContactFolders)
		fails({"HTTP 503 (ServiceUnavailable)", '"retryable":true'}, c.listContacts)
		fails({"invalid JSON object"}, c.getContact, {id = "C1"})
	end,
}
