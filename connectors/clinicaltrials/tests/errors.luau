-- Invalid input never reaches the network; plain-text errors, aliases and bad pages map to clear failures.
return {
	scenario = {publisher = {}, config = {}, auth_method = "", auth_config = {}},
	configure = function()
		calls = 0
		status = 200
		payload = "{}"
		responseHeaders = {}
		-- Sealing is native; a table of opaque handles stands in for it.
		local sealed, count = {}, 0
		houston = table.clone(houston)
		houston.seal = function(value)
			count += 1
			sealed["sealed:" .. count] = json.encode(value)
			return "sealed:" .. count
		end
		houston.unseal = function(token)
			assert(type(token) == "string" and sealed[token], "invalid sealed token")
			return json.decode(sealed[token])
		end
		http = {request = function()
			calls += 1
			return fixture.operation({statusCode = status, headers = responseHeaders, body = fixture.reader(payload)})
		end}
	end,
	run = function(trials)
		local function rejected(fn, expected)
			local before = calls
			local ok, err = pcall(fn)
			assert(not ok and string.find(tostring(err), expected, 1, true), "wrong validation error: " .. tostring(err))
			assert(calls == before, "invalid input reached ClinicalTrials.gov")
		end
		for _, id in {"NCT123", "nct04368728", "NCT123456789", "04368728", "NCT0436872a", "NCT04368728/../x", 4368728, ""} do
			rejected(function() trials.getStudy(id) end, "nctId must be NCT followed by 8 digits")
		end
		rejected(function() trials.getStudy() end, "nctId must be")
		rejected(function() trials.getStudy({nctId = "NCT04368728"}, {}) end, "takes (nctId, opts?)")
		rejected(function() trials.getStudy("NCT04368728", {format = "csv"}) end, "unknown option format")
		rejected(function() trials.getStudy("NCT04368728", {fields = "@query"}) end, "fields contains an invalid value")
		rejected(function() trials.getStudy("NCT04368728", {fields = {}}) end, "fields must list 1 to 200")
		rejected(function() trials.getStudy("NCT04368728", "fields") end, "options must be a table")
		rejected(function() trials.searchStudies("diabetes") end, "options must be a table")
		rejected(function() trials.searchStudies({pageSize = 10}) end, "unknown option pageSize")
		rejected(function() trials.searchStudies({phase = "PHASE3"}) end, "unknown option phase")
		rejected(function() trials.searchStudies({["query.cond"] = ""}) end, "query.cond must be a nonempty string")
		rejected(function() trials.searchStudies({["query.cond"] = string.rep("a", 2001)}) end, "at most 2000 bytes")
		rejected(function() trials.searchStudies({["filter.advanced"] = 3}) end, "filter.advanced must be")
		rejected(function() trials.searchStudies({["filter.overallStatus"] = "recruiting"}) end, "invalid value: recruiting")
		rejected(function() trials.searchStudies({["filter.overallStatus"] = {"RECRUITING", 1}}) end, "dense array of strings")
		rejected(function() trials.searchStudies({["filter.overallStatus"] = {[1] = "RECRUITING", [3] = "COMPLETED"}}) end, "dense array")
		rejected(function() trials.searchStudies({["filter.overallStatus"] = ", |"}) end, "must list 1 to 14")
		rejected(function() trials.searchStudies({["filter.ids"] = "NCT04368728,NCT123"}) end, "invalid value: NCT123")
		rejected(function() trials.searchStudies({["filter.ids"] = table.create(501, "NCT04368728")}) end, "1 to 500")
		for _, key in {"BriefTitle:up", "LastUpdatePostDate:", "Last Update", ":desc", "@relevance:"} do
			rejected(function() trials.searchStudies({sort = {key}}) end, "sort contains an invalid value")
		end
		rejected(function() trials.searchStudies({sort = {"A", "B", "C"}}) end, "sort must list 1 to 2")
		rejected(function() trials.searchStudies({fields = "Bad;Field"}) end, "fields contains an invalid value")
		rejected(function() trials.searchStudies({countTotal = "true"}) end, "countTotal must be a boolean")
		for _, limit in {0, 2001, 1.5, "10", false} do
			rejected(function() trials.searchStudies({limit = limit}) end, "limit must be an integer from 1 to 2000")
		end
		rejected(function() trials.searchStudies({pageToken = "ZVJ76sWHmqU2wRk2CJf6"}) end, "nextPageToken of an earlier searchStudies")
		rejected(function()
			trials.searchStudies({pageToken = houston.seal({operation = "getStudy", query = "fields=NCTId", token = "t"})})
		end, "nextPageToken of an earlier searchStudies")
		rejected(function()
			trials.searchStudies({pageToken = houston.seal({operation = "searchStudies", query = "fields=NCTId", token = "t"}),
				["query.cond"] = "asthma"})
		end, "pass only pageToken and limit")

		local function upstream(code, body, headers, call, expected, absent)
			status, payload, responseHeaders = code, body, headers
			local before = calls
			local ok, err = pcall(call)
			for _, text in expected do
				assert(not ok and string.find(tostring(err), text, 1, true), "missing " .. text .. " in " .. tostring(err))
			end
			if absent then assert(not string.find(tostring(err), absent, 1, true), "unexpected " .. absent .. " in " .. tostring(err)) end
			assert(calls == before + 1, "a failed request was repeated")
		end
		local function search() trials.searchStudies({["query.cond"] = "asthma"}) end
		local function read() trials.getStudy("NCT05730322") end

		upstream(400, "Error parsing query in advanced filter: Allowed values for enum field `protocolSection.designModule.phases` are `NA`\n", {}, search,
			{"HTTP 400: Error parsing query in advanced filter: Allowed values", "`NA`", '"retryable":false'}, "\\n")
		upstream(400, string.rep("y", 1000), {}, search, {"HTTP 400: " .. string.rep("y", 300)}, string.rep("y", 301))
		upstream(400, string.rep("y", 299) .. "é", {}, search, {"HTTP 400: " .. string.rep("y", 299)})
		upstream(404, "NCT number NCT05730322 not found", {}, read, {"HTTP 404: NCT number NCT05730322 not found", '"retryable":false'})
		upstream(404, "", {}, read, {"HTTP 404"}, "HTTP 404:")
		upstream(301, "", {location = {"/api/v2/studies/NCT03682900"}}, read,
			{"HTTP 301: NCT05730322 is an alias of NCT03682900; call getStudy with NCT03682900", '"retryable":false'})
		for _, location in {"https://clinicaltrials.gov/api/v2/studies/NCT03682900", "/api/v2/studies/NCT03682900?fields=NCTId"} do
			upstream(301, "", {location = {location}}, read, {"NCT05730322 is an alias of NCT03682900; call getStudy with NCT03682900"})
		end
		upstream(301, "", {location = {"https://clinicaltrials.gov.example.com/api/v2/studies/NCT03682900"}}, read, {"unexpected redirect"}, "alias")
		upstream(302, "", {location = {"https://evil.example.com/"}}, read, {"HTTP 302: unexpected redirect"}, "evil")
		upstream(429, "Too Many Requests", {["retry-after"] = {"7"}}, search, {"HTTP 429", "retry after 7s", '"retryable":true'})
		upstream(503, "", {["retry-after"] = {"Thu, 29 Oct 2026 20:00:00 GMT"}}, search,
			{"retry after Thu, 29 Oct 2026 20:00:00 GMT", '"retryable":true'}, "GMTs")
		upstream(503, "<html>Unavailable</html>", {}, read, {"HTTP 503", '"retryable":true'})
		upstream(500, "", {}, search, {"HTTP 500", '"retryable":true'})
		upstream(200, "<html>Maintenance</html>", {}, read, {"invalid JSON object", '"retryable":false'})
		upstream(200, "[]", {}, read, {"invalid JSON object"})
		upstream(200, '{"studies":null}', {}, search, {"unexpected search page"})
		upstream(200, '{"studies":[],"nextPageToken":5}', {}, search, {"unexpected search page"})
		upstream(200, '{"x":"' .. string.rep("z", 4 * 1024 * 1024) .. '"}', {}, read, {"more data than one call can hold"})
	end,
}
