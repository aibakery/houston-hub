return {
	scenario = {publisher = {client_id = "fixture-client", client_secret = "fixture-private-secret"}, config = {}, auth_method = "oauth", auth_config = {}},
	config = {access = "read-write"},
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
		local function last() return requests[#requests] end
		local function body() return json.decode(last().body) end
		local function fails(expected: {string}, fn: (...any) -> any, ...: any)
			local ok, err = pcall(fn, ...)
			assert(not ok, "call succeeded")
			for _, text in expected do assert(string.find(tostring(err), text, 1, true), "missing " .. text .. " in " .. tostring(err)) end
		end
		local names = {}
		for name in c do table.insert(names, name) end
		table.sort(names)
		assert(table.concat(names, ",") == "createContact,createContactFolder,deleteContact,deleteContactFolder,getContact,listContactFolders,listContacts,updateContact,updateContactFolder",
			"read-write got " .. table.concat(names, ","))

		-- Contacts: the body carries Graph's fields; folderId and id only shape the path.
		responses = {{status = 201, body = '{"id":"C1","displayName":"Ana Silva"}'}, {status = 201, body = '{"id":"C2"}'}, {body = '{"id":"C1","jobTitle":"CTO"}'}, {body = '{"id":"C2"}'}, {status = 204}, {status = 204}}
		local address = {street = "1 Main St", city = "Redmond", state = "WA", countryOrRegion = "United States", postalCode = "98052"}
		assert(c.createContact({givenName = "Ana", surname = "Silva", emailAddresses = {{address = "ana@example.com", name = "Ana Silva"}}, homeAddress = address}).id == "C1")
		local sent = body()
		assert(last().method == "POST" and last().url == API .. "/contacts" and last().headers["Content-Type"][1] == "application/json", last().url)
		assert(sent.givenName == "Ana" and sent.emailAddresses[1].address == "ana@example.com" and sent.homeAddress.postalCode == "98052" and sent.folderId == nil, last().body)
		c.createContact({folderId = "AQMk-F1==", displayName = "Bo Chen", businessPhones = {"+1 425 555 0100"}})
		assert(last().url == API .. "/contactFolders/AQMk-F1%3D%3D/contacts" and last().body == '{"businessPhones":["+1 425 555 0100"],"displayName":"Bo Chen"}', last().body)
		assert(c.updateContact({id = "C1", jobTitle = "CTO", categories = {}}).jobTitle == "CTO")
		assert(last().method == "PATCH" and last().url == API .. "/contacts/C1" and last().body == '{"categories":[],"jobTitle":"CTO"}', last().body)
		c.updateContact({id = "C2", folderId = "F1", mobilePhone = "+33 6 12 34 56 78", birthday = json.decode("null")})
		assert(last().url == API .. "/contactFolders/F1/contacts/C2" and last().body == '{"birthday":null,"mobilePhone":"+33 6 12 34 56 78"}', last().body)
		assert(c.deleteContact({id = "C1"}).success and last().method == "DELETE" and last().url == API .. "/contacts/C1" and last().body == nil, last().url)
		c.deleteContact({id = "C2", folderId = "F1"})
		assert(last().url == API .. "/contactFolders/F1/contacts/C2", last().url)

		-- Folders: created in the default folder or inside another, renamed, moved and deleted.
		responses = {{status = 201, body = '{"id":"F1","displayName":"Suppliers"}'}, {status = 201, body = '{"id":"F2"}'}, {body = '{"id":"F1"}'}, {body = '{"id":"F2"}'}, {status = 204}}
		assert(c.createContactFolder({displayName = "Suppliers"}).id == "F1" and last().url == API .. "/contactFolders" and last().body == '{"displayName":"Suppliers"}', last().body)
		c.createContactFolder({displayName = "Paris", parentFolderId = "F1"})
		assert(last().method == "POST" and last().url == API .. "/contactFolders/F1/childFolders" and last().body == '{"displayName":"Paris"}', last().body)
		c.updateContactFolder({folderId = "F1", displayName = "Key suppliers"})
		assert(last().method == "PATCH" and last().url == API .. "/contactFolders/F1" and last().body == '{"displayName":"Key suppliers"}', last().body)
		c.updateContactFolder({folderId = "F2", parentFolderId = "F0"})
		assert(last().url == API .. "/contactFolders/F2" and last().body == '{"parentFolderId":"F0"}', last().body)
		assert(c.deleteContactFolder({folderId = "F2"}).success and last().method == "DELETE" and last().url == API .. "/contactFolders/F2", last().url)

		-- Write bodies are closed and typed; invalid input never reaches the network.
		local before = #requests
		fails({"createContact requires contact fields"}, c.createContact, {folderId = "F1"})
		fails({"createContact received an unknown option email"}, c.createContact, {givenName = "Ana", email = "ana@example.com"})
		fails({"emailAddresses must be an array"}, c.createContact, {emailAddresses = "ana@example.com"})
		fails({"mobilePhone must be a string"}, c.createContact, {mobilePhone = 33612345678})
		fails({"homeAddress must be an object"}, c.createContact, {homeAddress = "1 Main St"})
		fails({"updateContact requires fields to change"}, c.updateContact, {id = "C1"})
		fails({"updateContact received an unknown option parentFolderId"}, c.updateContact, {id = "C1", parentFolderId = "F1"})
		fails({"id must be a nonempty string"}, c.updateContact, {jobTitle = "CTO"})
		fails({"deleteContact received an unknown option force"}, c.deleteContact, {id = "C1", force = true})
		fails({"displayName must be a nonempty string"}, c.createContactFolder, {})
		fails({"createContactFolder received an unknown option color"}, c.createContactFolder, {displayName = "X", color = "red"})
		fails({"updateContactFolder requires displayName or parentFolderId"}, c.updateContactFolder, {folderId = "F1"})
		fails({"displayName must be a nonempty string"}, c.updateContactFolder, {folderId = "F1", displayName = ""})
		fails({"folderId must be a nonempty string"}, c.deleteContactFolder, {})
		fails({"parentFolderId must be a nonempty string"}, c.updateContactFolder, {folderId = "F1", parentFolderId = ""})
		fails({"jobTitle must be a string"}, c.updateContact, {id = "C1", jobTitle = true})
		fails({"emailAddresses[1] received an unknown field email"}, c.createContact, {emailAddresses = {{email = "ana@example.com"}}})
		fails({"emailAddresses[1].address is required"}, c.createContact, {emailAddresses = {{name = "Ana"}}})
		fails({"emailAddresses[1].address must be a nonempty string"}, c.createContact, {emailAddresses = {{address = json.decode("null")}}})
		fails({"homeAddress received an unknown field zip"}, c.createContact, {homeAddress = {zip = "75001"}})
		fails({"businessPhones[2] must be a string"}, c.createContact, {businessPhones = {"+1 425 555 0100", 4255550101}})
		fails({"categories must be an array"}, c.updateContact, {id = "C1", categories = {first = "VIP"}})
		fails({"businessPhones must be an array"}, c.createContact, {businessPhones = {[1] = "+1 425 555 0100", [3] = "+1 425 555 0101"}})
		assert(#requests == before, "invalid writes reached Graph")

		-- A refused write keeps Graph's reason; a server error on a write may still have been applied.
		-- Microsoft Q&A reports, reproduced by Microsoft staff, show folder deletes refused with 403 ErrorCannotDeleteObject.
		responses = {
			{status = 403, body = '{"error":{"code":"ErrorCannotDeleteObject","message":"Object cannot be deleted."}}'},
			{status = 409, body = '{"error":{"code":"ErrorFolderExists","message":"A folder with the specified name already exists."}}'},
			{status = 503, headers = {["retry-after"] = {"30"}}, body = '{"error":{"code":"ServiceUnavailable","message":"Try later"}}'},
			{status = 429, headers = {["retry-after"] = {"5"}}, body = '{"error":{"code":"ApplicationThrottled","message":"Slow down"}}'},
		}
		fails({"HTTP 403 (ErrorCannotDeleteObject)", "Object cannot be deleted", '"retryable":false'}, c.deleteContactFolder, {folderId = "F0"})
		fails({"HTTP 409 (ErrorFolderExists)", '"retryable":false'}, c.createContactFolder, {displayName = "Suppliers"})
		fails({"HTTP 503 (ServiceUnavailable)", "Retry-After: 30", '"retryable":false'}, c.createContact, {givenName = "Ana"})
		-- Graph refuses a throttled write before acting, so repeating it is safe.
		fails({"HTTP 429 (ApplicationThrottled)", "Retry-After: 5", '"retryable":true'}, c.updateContact, {id = "C1", jobTitle = "CTO"})
		assert(#requests == before + 4 and #responses == 0)
	end,
}
