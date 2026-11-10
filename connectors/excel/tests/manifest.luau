return {
	contract = function(m)
		local api = "https://graph.microsoft.com/v1.0/me"
		local w = api .. "/drive/items/I1/workbook"
		for access, scopes in {["read-only"] = {"Files.Read"}, ["read-write"] = {"Files.ReadWrite"}} do
			local r, err = m.resolve({client_id = "publisher-client", client_secret = "publisher-secret"}, {access = access}, nil, "oauth")
			assert(r and not err, tostring(err))
			assert(m.equal(r.Scopes, m.concat({"offline_access", "User.Read"}, scopes)), "requested OAuth scopes for " .. access)
			r.Context.Auth.oauth.access_token = "fixture-token"
			-- The encoded shapes the connector sends: a braced sheet id, an encoded colon inside a
			-- range address, an apostrophe in a sheet name and a search with spaces.
			local reads = {
				"GET " .. api .. "/drive/root/search(q='budget%202026')?$select=id,name&$top=25",
				"GET https://graph.microsoft.com/v1.0/drives/b!x-1/root/search(query='budget')?skipToken=abc",
				"GET " .. api .. "/drive/items/01BYE5RZ6QN3ZWBTUFOFD3GSPGOHDJD36K?$select=id,name",
				"GET " .. w .. "/worksheets?$select=id,name", "GET " .. w .. "/tables", "GET " .. w .. "/names",
				"GET " .. w .. "/worksheets/%7B00000000-0001-0000-0000-000000000000%7D/range(address='A1%3AB2')",
				"GET " .. w .. "/worksheets/O%27Brien%20Q1/range(address='%24A%241')?$select=address,values",
				"GET " .. w .. "/worksheets/Sheet1/usedRange(valuesOnly=true)", "GET " .. w .. "/worksheets/Sales/tables",
				"GET " .. w .. "/tables/Table1/range", "GET " .. w .. "/names/Totals/range", "GET " .. w .. "/worksheets/Sales/names",
			}
			m.routes(r, "Bearer fixture-token", true, reads)
			m.rejectOverrides(r, reads)
			local writes = {
				"PATCH " .. w .. "/worksheets/Sheet1/range(address='A1%3AB2')", "PATCH " .. w .. "/names/Totals/range",
				"PATCH " .. w .. "/worksheets/Sheet2", "DELETE " .. w .. "/worksheets/Sheet2",
				"POST " .. w .. "/worksheets/Sheet1/range(address='A2%3AD9')/clear", "POST " .. w .. "/names/Totals/range/clear",
				"POST " .. w .. "/worksheets/Sheet1/range(address='5%3A7')/insert", "POST " .. w .. "/worksheets/Sheet1/range(address='5%3A5')/delete",
				"POST " .. w .. "/names/Totals/range/insert", "POST " .. w .. "/names/Totals/range/delete",
				"POST " .. w .. "/tables/Table1/rows/add", "POST " .. w .. "/worksheets/Sales/tables/add", "POST " .. w .. "/worksheets/add",
				"POST " .. w .. "/createSession", "POST " .. w .. "/closeSession",
			}
			m.routes(r, "Bearer fixture-token", access == "read-write", writes)
			if access == "read-write" then m.rejectOverrides(r, writes) end
			-- The token stays off Microsoft's token endpoints, batches that could wrap writes, other users,
			-- drives and APIs, file contents and sharing, lookalike hosts, and workbook features the
			-- connector never calls: functions, charts, protection, formats, table and name changes,
			-- row-by-index access, calculation and session refreshes. A {search} or {range} placeholder
			-- still admits any one segment there, such as root/children or a chart collection.
			m.routes(r, "Bearer fixture-token", false, {
				"POST https://login.microsoftonline.com/common/oauth2/v2.0/token", "POST https://login.microsoftonline.com/organizations/oauth2/v2.0/token", "POST https://graph.microsoft.com/v1.0/$batch",
				"GET https://graph.microsoft.com/v1.0/users/other@example.com/drive/items/I1/workbook/worksheets",
				"GET https://graph.microsoft.com/beta/me/drive/items/I1/workbook/worksheets",
				"GET https://graph.microsoft.com.evil.test/v1.0/me/drive/items/I1/workbook/worksheets",
				"GET https://graph.microsoft.com/v1.0/drives/b!x/items/I1/workbook/worksheets", "GET " .. api .. "/messages",
				"GET " .. api .. "/drive", "GET " .. api .. "/drive/recent", "GET " .. api .. "/drive/items/I1/children",
				"GET " .. api .. "/drive/items/I1/content", "GET " .. api .. "/drive/items/I1/permissions",
				"GET " .. api .. "/drive/root:/a.xlsx:/workbook/worksheets", "GET " .. api .. "/drive/root:/a.xlsx:/content", "GET " .. api .. "/drive/items/I1%2F..%2FI2/workbook/worksheets",
				"GET " .. w .. "/worksheets/a:b/range(address='A1')", "GET " .. w .. "/worksheets/Sheet1",
				"GET " .. w .. "/worksheets/S/charts/C/image", "GET " .. w .. "/worksheets/S/range(address='A1')/format",
				"GET " .. w .. "/application", "GET " .. w .. "/operations/op1", "GET " .. w .. "/tables/T/rows",
				"GET " .. w .. "/tables/T/columns", "GET " .. w .. "/names/N", "GET " .. w .. "/tables/T",
				"POST " .. w .. "/functions/vlookup", "POST " .. w .. "/application/calculate", "POST " .. w .. "/refreshSession",
				"POST " .. w .. "/tables/add", "POST " .. w .. "/worksheets/S/charts/C/delete", "POST " .. w .. "/names/add",
				"POST " .. w .. "/worksheets/S/protection/protect", "POST " .. w .. "/worksheets/S/range(address='A1')/merge",
				"POST " .. w .. "/tables/T/range/delete", "POST " .. w .. "/tables/T/rows",
				"POST " .. w .. "/tables/T/columns/add", "POST " .. w .. "/tables/T/convertToRange", "PATCH " .. w .. "/tables/T",
				"PATCH " .. w .. "/tables/T/rows/0", "PATCH " .. w .. "/names/N", "PATCH " .. w .. "/worksheets/S/range(address='A1')/format",
				"DELETE " .. w .. "/tables/T", "DELETE " .. w .. "/tables/T/rows/0", "PUT " .. w .. "/worksheets/S/range(address='A1')",
				"DELETE " .. api .. "/drive/items/I1", "PATCH " .. api .. "/drive/items/I1", "POST " .. api .. "/drive/root/children",
				"PUT " .. api .. "/drive/items/I1/content", "POST " .. api .. "/drive/items/I1/copy",
				"POST " .. api .. "/drive/items/I1/createUploadSession",
			})
		end
	end,
}
