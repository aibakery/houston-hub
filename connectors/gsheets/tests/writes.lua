return {
	scenario = {publisher = {client_id = "fixture-client", client_secret = "fixture-private-secret"}, config = {}, auth_method = "oauth", auth_config = {}},
	config = {access = "read-write"},
	configure = function()
		requests, responses = {}, {}
		http = {request = function(req)
			table.insert(requests, req)
			assert(#responses > 0, "unexpected request: " .. req.url)
			return fixture.operation({statusCode = 200, headers = {}, body = fixture.reader(table.remove(responses, 1))})
		end}
	end,
	run = function(c)
		local API = "https://sheets.googleapis.com/v4/spreadsheets"
		local names = {}
		for name in c do table.insert(names, name) end
		table.sort(names)
		assert(table.concat(names, ",") == "appendValues,batchClearValues,batchGetValues,batchUpdate,batchUpdateValues,clearValues,createSpreadsheet,getSpreadsheet,getValues,updateValues", table.concat(names, ","))
		local function sent(method, href, body)
			local req = requests[#requests]
			assert(req.method == method and req.url == href, req.method .. " " .. req.url)
			assert(req.headers["Content-Type"][1] == "application/json" and req.headers.Authorization == nil)
			assert(req.body == body, req.body)
		end

		responses = {'{"spreadsheetId":"s1","updatedRange":"Sheet1!B2","updatedCells":1}'}
		assert(c.updateValues({spreadsheetId = "https://docs.google.com/spreadsheets/d/s1/edit#gid=0", range = "Sheet1!B2", values = {{42}}}).updatedCells == 1)
		sent("PUT", API .. "/s1/values/Sheet1%21B2?valueInputOption=RAW", '{"values":[[42]]}')
		responses = {'{"spreadsheetId":"s1"}'}
		c.updateValues({spreadsheetId = "s1", range = "B2:C2", values = {{json.decode("null"), ""}}, valueInputOption = "USER_ENTERED", includeValuesInResponse = true})
		sent("PUT", API .. "/s1/values/B2%3AC2?valueInputOption=USER_ENTERED&includeValuesInResponse=true", '{"values":[[null,""]]}')

		responses = {'{"spreadsheetId":"s1","tableRange":"Log!A1:D3","updates":{"updatedRows":1}}'}
		assert(c.appendValues({spreadsheetId = "s1", range = "Log!A:D", values = {{"2026-10-16", "paid", 120}}, insertDataOption = "INSERT_ROWS"}).updates.updatedRows == 1)
		sent("POST", API .. "/s1/values/Log%21A%3AD:append?valueInputOption=RAW&insertDataOption=INSERT_ROWS", '{"values":[["2026-10-16","paid",120]]}')

		responses = {'{"spreadsheetId":"s1","clearedRange":"Sheet1!A2:D1000"}'}
		assert(c.clearValues({spreadsheetId = "s1", range = "Sheet1!A2:D"}).clearedRange == "Sheet1!A2:D1000")
		sent("POST", API .. "/s1/values/Sheet1%21A2%3AD:clear", "{}")

		responses = {'{"spreadsheetId":"s1","totalUpdatedCells":2}', '{"spreadsheetId":"s1","clearedRanges":["Q2/Q3!A1"]}'}
		c.batchUpdateValues({spreadsheetId = "s1", data = {{range = "Q2/Q3!A1", values = {{1, 2}}}}})
		local body = json.decode(requests[#requests].body)
		assert(requests[#requests].url == API .. "/s1/values:batchUpdate" and body.valueInputOption == "RAW" and body.data[1].range == "Q2/Q3!A1" and body.spreadsheetId == nil)
		c.batchClearValues({spreadsheetId = "s1", ranges = {"Q2/Q3!A1"}})
		sent("POST", API .. "/s1/values:batchClear", '{"ranges":["Q2/Q3!A1"]}')

		responses = {'{"spreadsheetId":"new","spreadsheetUrl":"https://docs.google.com/spreadsheets/d/new/edit"}', '{"spreadsheetId":"s1","replies":[{"addSheet":{"properties":{"sheetId":7}}}]}'}
		assert(c.createSpreadsheet({properties = {title = "Report"}}).spreadsheetId == "new")
		sent("POST", API, '{"properties":{"title":"Report"}}')
		assert(c.batchUpdate({spreadsheetId = "s1", requests = {{addSheet = {properties = {title = "Archive"}}}}}).replies[1].addSheet.properties.sheetId == 7)
		sent("POST", API .. "/s1:batchUpdate", '{"requests":[{"addSheet":{"properties":{"title":"Archive"}}}]}')

		local count = #requests
		assert(not pcall(c.updateValues, {spreadsheetId = "s1", range = "A1"}), "updateValues requires values")
		assert(not pcall(c.updateValues, {spreadsheetId = "s1", range = "A1", values = json.decode("null")}))
		assert(not pcall(c.updateValues, {spreadsheetId = "s1", range = "A1", values = {}}))
		assert(not pcall(c.appendValues, {spreadsheetId = "s1", range = "Log/2026!A:D", values = {{1}}}))
		assert(not pcall(c.batchUpdateValues, {spreadsheetId = "s1"}))
		assert(not pcall(c.batchClearValues, {spreadsheetId = "s1"}))
		assert(not pcall(c.batchUpdate, {spreadsheetId = "s1"}))
		assert(not pcall(c.clearValues, {spreadsheetId = "s1"}))
		assert(not pcall(c.batchUpdate, {spreadsheetId = "https://docs.google.com/spreadsheets/d/e/2PACX-1vT/pubhtml", requests = {}}))
		assert(#requests == count, "invalid input reached Google")
		assert(#responses == 0)
	end,
}
