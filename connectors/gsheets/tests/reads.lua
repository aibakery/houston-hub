return {
	scenario = {publisher = {client_id = "fixture-client", client_secret = "fixture-private-secret"}, config = {}, auth_method = "oauth", auth_config = {}},
	config = {access = "read-only"},
	configure = function()
		requests, responses = {}, {}
		http = {request = function(req)
			table.insert(requests, req)
			assert(#responses > 0, "unexpected request: " .. req.url)
			return fixture.operation({statusCode = 200, headers = {}, body = fixture.reader(table.remove(responses, 1))})
		end}
	end,
	run = function(c)
		local API = "https://sheets.googleapis.com/v4/spreadsheets/"
		for _, name in {"updateValues", "appendValues", "clearValues", "batchUpdateValues", "batchClearValues", "createSpreadsheet", "batchUpdate"} do
			assert(c[name] == nil, "read-only leaked " .. name)
		end
		local names = {}
		for name in c do table.insert(names, name) end
		table.sort(names)
		assert(table.concat(names, ",") == "batchGetValues,getSpreadsheet,getValues", table.concat(names, ","))

		responses = {'{"range":"\'Q1 Sales\'!B2","majorDimension":"ROWS","values":[["42"]]}', '{"range":"Sheet1!Z9","majorDimension":"ROWS"}', '{"range":"Sheet1!A1:B2","values":[[1,2],[3]]}'}
		local cell = c.getValues({spreadsheetId = "https://docs.google.com/spreadsheets/d/1AbC_d-9/edit?gid=0#gid=0", range = "'Q1 Sales'!B2"})
		assert(cell.values[1][1] == "42")
		assert(requests[1].method == "GET" and requests[1].url == API .. "1AbC_d-9/values/%27Q1%20Sales%27%21B2", requests[1].url)
		local empty = c.getValues({spreadsheetId = "https://docs.google.com/spreadsheets/u/1/d/s1/edit", range = "Sheet1!Z9"})
		assert(json.encode(empty.values) == "[]" and requests[2].url == API .. "s1/values/Sheet1%21Z9", requests[2].url)
		local raw = c.getValues({spreadsheetId = "s1", range = "Sheet1!A1:B2", valueRenderOption = "UNFORMATTED_VALUE", majorDimension = "ROWS"})
		assert(raw.values[2][1] == 3 and requests[3].url == API .. "s1/values/Sheet1%21A1%3AB2?majorDimension=ROWS&valueRenderOption=UNFORMATTED_VALUE", requests[3].url)

		responses = {'{"spreadsheetId":"s1","valueRanges":[{"range":"Sheet1!A1:B2","values":[["a"]]},{"range":"Totals!C3"}]}', '{"spreadsheetId":"s1"}'}
		local batch = c.batchGetValues({spreadsheetId = "s1", ranges = {"Sheet1!A1:B2", "Totals!C3"}, valueRenderOption = "FORMULA"})
		assert(batch.valueRanges[1].values[1][1] == "a" and json.encode(batch.valueRanges[2].values) == "[]")
		assert(requests[4].url == API .. "s1/values:batchGet?ranges=Sheet1%21A1%3AB2&ranges=Totals%21C3&valueRenderOption=FORMULA", requests[4].url)
		local none = c.batchGetValues({spreadsheetId = "s1", ranges = {"Q2/Q3!A1"}})
		assert(json.encode(none.valueRanges) == "[]" and requests[5].url == API .. "s1/values:batchGet?ranges=Q2%2FQ3%21A1", requests[5].url)

		local fields = "spreadsheetId,spreadsheetUrl,properties(title,locale,timeZone),sheets.properties,namedRanges"
		responses = {'{"spreadsheetId":"s1","sheets":[{"properties":{"sheetId":0,"title":"Sheet1"}}]}', '{"spreadsheetId":"s1"}'}
		assert(c.getSpreadsheet({spreadsheetId = "s1"}).sheets[1].properties.title == "Sheet1")
		assert(requests[6].url == API .. "s1?fields=" .. url.encode(fields), requests[6].url)
		c.getSpreadsheet({spreadsheetId = "s1", fields = "sheets(data(rowData(values(note))))", ranges = {"A1:B2"}})
		assert(requests[7].url == API .. "s1?fields=sheets%28data%28rowData%28values%28note%29%29%29%29&ranges=A1%3AB2", requests[7].url)
		for _, req in requests do
			assert(req.method == "GET" and req.body == nil, req.method .. " " .. req.url)
			assert(req.headers == nil or req.headers.Authorization == nil, "connector set credentials")
		end

		local sent = #requests
		local invalid = {
			{spreadsheetId = "s1"},
			{spreadsheetId = "s1", range = ""},
			{spreadsheetId = "s1", range = "Q2/Q3!A1"},
			{spreadsheetId = "s1", range = "100%!A1"},
			{spreadsheetId = "..", range = "A1"},
			{spreadsheetId = "s/1", range = "A1"},
			{spreadsheetId = "https://docs.google.com/spreadsheets/d/e/2PACX-1vT/pubhtml", range = "A1"},
			{spreadsheetId = "https://docs.google.com.example.com/spreadsheets/d/s1/edit", range = "A1"},
			{spreadsheetId = "https://example.com/?u=https://docs.google.com/spreadsheets/d/s1", range = "A1"},
			{spreadsheetId = "https://docs.google.com/spreadsheets/abcd/s1", range = "A1"},
			{spreadsheetId = "https://docs.google.com/spreadsheets/u/0/?usp=d/s1", range = "A1"},
			{spreadsheetId = "https://docs.google.com/spreadsheets/#d/s1", range = "A1"},
			{spreadsheetId = "https://docs.google.com/spreadsheets/d/s1.x/edit", range = "A1"},
			{spreadsheetId = "s1 x", range = "A1"},
			{range = "A1"},
			{spreadsheetId = "s1", range = "A1", key = "api-key"},
		}
		for _, args in invalid do
			assert(not pcall(c.getValues, args), "accepted " .. json.encode(args))
		end
		assert(not pcall(c.getValues, "s1"))
		assert(not pcall(c.batchGetValues, {spreadsheetId = "s1"}), "batchGetValues requires ranges")
		assert(not pcall(c.batchGetValues, {spreadsheetId = "s1", ranges = {}}))
		assert(not pcall(c.batchGetValues, {spreadsheetId = "s1", ranges = ""}))
		assert(not pcall(c.batchGetValues, {spreadsheetId = "s1", ranges = "Sheet1!A1"}))
		assert(not pcall(c.getSpreadsheet, {spreadsheetId = "s1", includeGridData = true}))
		assert(#requests == sent, "invalid input reached Google")
		assert(#responses == 0)
	end,
}
