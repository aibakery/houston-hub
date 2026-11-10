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
		local W = API .. "/drive/items/I1/workbook"
		local VALUES = "?$select=address%2CrowCount%2CcolumnCount%2Cvalues"
		local function last() return requests[#requests] end
		local function fails(expected: {string}, fn: (...any) -> any, ...: any)
			local ok, err = pcall(fn, ...)
			assert(not ok, "call succeeded")
			for _, text in expected do assert(string.find(tostring(err), text, 1, true), "missing " .. text .. " in " .. tostring(err)) end
		end
		local names = {}
		for name in c do table.insert(names, name) end
		table.sort(names)
		assert(table.concat(names, ",") == "findWorkbooks,getRange,getWorkbook,listNames,listTables,listWorksheets", "read-only got " .. table.concat(names, ","))

		-- Search keeps only .xlsx files in the user's own drive, and their paging link, which may name
		-- the drive; quotes in q are doubled.
		local link = "https://graph.microsoft.com/v1.0/drives/b!x-1/root/search(query='budget')?skipToken=abc"
		responses = {
			{body = '{"value":[{"id":"I1","name":"Budget.XLSX","file":{"mimeType":"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"}},'
				.. '{"id":"I2","name":"Budget.docx","file":{}},{"id":"F1","name":"Budget.xlsx","folder":{}},'
				.. '{"id":"R1","name":"Shared.xlsx","file":{},"remoteItem":{"id":"X1"}}],"@odata.nextLink":"' .. link .. '"}'},
			{body = '{"value":[{"id":"I3","name":"notes.txt","file":{}}],"@odata.nextLink":"' .. link .. '"}'},
			{body = '{}'},
		}
		local page = c.findWorkbooks({q = "Ana's budget", top = 25})
		assert(#page.value == 1 and page.value[1].id == "I1" and page["@odata.nextLink"] == link)
		assert(last().url == API .. "/drive/root/search(q='Ana%27%27s%20budget')?$select=id%2Cname%2Csize%2CwebUrl%2ClastModifiedDateTime%2CparentReference%2Cfile&$top=25", last().url)
		local filtered = c.findWorkbooks({nextLink = link})
		assert(last().url == link and json.encode(filtered.value) == "[]" and filtered["@odata.nextLink"] == link, last().url)
		assert(json.encode(c.findWorkbooks({q = "none"}).value) == "[]")

		-- Preauthenticated download links never reach callers.
		responses = {{body = '{"id":"I1","name":"Budget.xlsx","@microsoft.graph.downloadUrl":"https://x.sharepoint.com/download?tempauth=t"}'}, {body = '{"id":"I1"}'}}
		local workbook = c.getWorkbook({itemId = "I1"})
		assert(workbook.name == "Budget.xlsx" and workbook["@microsoft.graph.downloadUrl"] == nil)
		assert(last().url == API .. "/drive/items/I1?$select=id%2Cname%2Csize%2CwebUrl%2ClastModifiedDateTime%2CparentReference%2Cfile", last().url)
		c.getWorkbook({itemId = "I-1=", select = {"id", "webUrl"}})
		assert(last().url == API .. "/drive/items/I-1%3D?$select=id,webUrl", last().url)

		-- Workbook lists always carry a value array.
		responses = {{body = '{"value":[{"id":"{00000000-0001-0000-0000-000000000000}","name":"Sheet1","position":0}]}'}, {body = '{}'}, {body = '{"value":[{"id":"1","name":"Table1"}]}'}, {body = '{}'}, {body = '{"value":[{"name":"Rate","type":"Range","value":"Sales!$B$1"}]}'}}
		assert(c.listWorksheets({itemId = "I1"}).value[1].name == "Sheet1")
		assert(last().url == W .. "/worksheets?$select=id%2Cname%2Cposition%2Cvisibility" and last().headers["workbook-session-id"] == nil, last().url)
		assert(json.encode(c.listTables({itemId = "I1"}).value) == "[]" and last().url == W .. "/tables", last().url)
		assert(c.listTables({itemId = "I1", worksheet = "Q1 Sales"}).value[1].name == "Table1" and last().url == W .. "/worksheets/Q1%20Sales/tables", last().url)
		assert(json.encode(c.listNames({itemId = "I1"}).value) == "[]" and last().url == W .. "/names", last().url)
		assert(c.listNames({itemId = "I1", worksheet = "Sales"}).value[1].name == "Rate" and last().url == W .. "/worksheets/Sales/names", last().url)

		-- Ranges by address, with the sheet in the address or in worksheet; by name, table or used range.
		responses = {}
		for _ = 1, 9 do table.insert(responses, {body = '{"address":"Sales!A1:B2","rowCount":2,"columnCount":2,"values":[["Item","Qty"],["Pear",4]]}'}) end
		assert(c.getRange({itemId = "I1", address = "Sales!A1:B2"}).values[2][2] == 4)
		assert(last().url == W .. "/worksheets/Sales/range(address='A1%3AB2')" .. VALUES, last().url)
		c.getRange({itemId = "I1", address = "'O''Brien Q1'!$A$1:$B$2"})
		assert(last().url == W .. "/worksheets/O%27Brien%20Q1/range(address='%24A%241%3A%24B%242')" .. VALUES, last().url)
		c.getRange({itemId = "I1", worksheet = "{00000000-0001-0000-0000-000000000000}", address = "B1:B9", select = {"address", "text", "formulas"}})
		assert(last().url == W .. "/worksheets/%7B00000000-0001-0000-0000-000000000000%7D/range(address='B1%3AB9')?$select=address,text,formulas", last().url)
		-- A worksheet-scoped name's value works as an address.
		c.getRange({itemId = "I1", address = "=Sales!$B$2:$H$12"})
		assert(last().url == W .. "/worksheets/Sales/range(address='%24B%242%3A%24H%2412')" .. VALUES, last().url)
		c.getRange({itemId = "I1", worksheet = "Sheet1"})
		assert(last().url == W .. "/worksheets/Sheet1/usedRange(valuesOnly=true)" .. VALUES, last().url)
		c.getRange({itemId = "I1", worksheet = "Sheet1", valuesOnly = false})
		assert(last().url == W .. "/worksheets/Sheet1/usedRange(valuesOnly=false)" .. VALUES, last().url)
		c.getRange({itemId = "I1", name = "Totals"})
		assert(last().url == W .. "/names/Totals/range" .. VALUES, last().url)
		c.getRange({itemId = "I1", table = "Table1"})
		assert(last().url == W .. "/tables/Table1/range" .. VALUES and last().method == "GET" and last().body == nil, last().url)

		-- Invalid input never reaches the network; read-only connections take no sessions.
		local before = #requests
		fails({"itemId must be a nonempty string"}, c.getRange, {address = "Sheet1!A1"})
		fails({"pass one of address, name or table"}, c.getRange, {itemId = "I1", address = "Sheet1!A1", name = "Totals"})
		fails({"pass one of address, name or table"}, c.getRange, {itemId = "I1", worksheet = "Sheet1", table = "Table1"})
		fails({"address needs its worksheet"}, c.getRange, {itemId = "I1", address = "A1:B2"})
		fails({"name the worksheet in address or in worksheet"}, c.getRange, {itemId = "I1", address = "Sales!A1", worksheet = "Sales"})
		fails({"address must be an A1-style range"}, c.getRange, {itemId = "I1", address = "Sales!A1/../B2"})
		fails({"address must be an A1-style range"}, c.getRange, {itemId = "I1", address = "Sales!A1')/format"})
		fails({"valuesOnly applies only to a worksheet's used range"}, c.getRange, {itemId = "I1", address = "Sales!A1", valuesOnly = true})
		fails({"valuesOnly must be a boolean"}, c.getRange, {itemId = "I1", worksheet = "Sheet1", valuesOnly = "yes"})
		fails({"worksheet must be a nonempty string"}, c.getRange, {itemId = "I1"})
		fails({"getRange received an unknown option sessionId"}, c.getRange, {itemId = "I1", address = "Sales!A1", sessionId = "s1"})
		fails({"listWorksheets received an unknown option sessionId"}, c.listWorksheets, {itemId = "I1", sessionId = "s1"})
		fails({"q must be a nonempty string"}, c.findWorkbooks, {top = 5})
		fails({"top must be a positive integer"}, c.findWorkbooks, {q = "x", top = 0})
		assert(not pcall(c.findWorkbooks, {q = "a/b"}), "q with a slash reached the network")
		fails({"findWorkbooks takes nextLink alone"}, c.findWorkbooks, {nextLink = link, top = 5})
		fails({"nextLink must come from the same list"}, c.findWorkbooks, {nextLink = "https://graph.microsoft.com/v1.0/me/drive/items/I1/children"})
		fails({"nextLink may carry only paging options"}, c.findWorkbooks, {nextLink = link .. "&$expand=children"})
		fails({"getWorkbook received an unknown option"}, c.getWorkbook, {itemId = "I1", expand = "children"})
		assert(#requests == before, "invalid input reached the network")

		-- Graph errors keep the status, code and message; throttling and timeouts are retryable.
		responses = {
			{status = 404, body = '{"error":{"code":"itemNotFound","message":"The requested resource doesn\'t exist.","innerError":{"code":"itemNotFound"}}}'},
			{status = 429, headers = {["retry-after"] = {"7"}}, body = '{"error":{"code":"tooManyRequests","message":"Too many requests"}}'},
			{status = 504, body = '{"error":{"code":"gatewayTimeout","message":"The request timed out."}}'},
			{status = 401, body = '{"error":{"code":"FileOpenUserUnauthorized","message":"You do not have permissions to open this file in the browser."}}'},
			{status = 413, body = '{"error":{"code":"payloadTooLarge","message":"The response is too large."}}'},
			{status = 200, body = "[]"},
		}
		fails({"Microsoft Graph HTTP 404 (itemNotFound)", '"retryable":false'}, c.getRange, {itemId = "I1", name = "Missing"})
		fails({"HTTP 429 (tooManyRequests)", "Retry-After: 7", '"retryable":true'}, c.listWorksheets, {itemId = "I1"})
		fails({"HTTP 504 (gatewayTimeout)", '"retryable":true'}, c.getRange, {itemId = "I1", worksheet = "Sheet1"})
		fails({"HTTP 401 (FileOpenUserUnauthorized)", '"retryable":false'}, c.listTables, {itemId = "I1"})
		fails({"HTTP 413 (payloadTooLarge)", '"retryable":false'}, c.getRange, {itemId = "I1", address = "Sheet1!A:Z"})
		fails({"invalid JSON object"}, c.listNames, {itemId = "I1"})
	end,
}
