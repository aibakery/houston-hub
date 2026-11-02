return {
	scenario = {publisher = {}, config = {}, auth_method = "token", auth_config = {token = "attio-fixture-private-key"}},
	configure = function()
		requests = {}
		payload = '{"data":[]}'
		http = {request = function(req)
			table.insert(requests, req)
			assert(req.headers.Authorization == nil, "credentials must remain in the proxy")
			assert(req.headers.Accept[1] == "application/json")
			if req.method == "POST" then
				assert(req.headers["Content-Type"][1] == "application/json")
			else
				assert(req.method == "GET" and req.body == nil and req.headers["Content-Type"] == nil, "reads must be bodiless GETs")
			end
			return fixture.operation({statusCode = 200, headers = {}, body = fixture.reader(payload)})
		end}
	end,
	run = function(attio)
		local API = "https://api.attio.com/v2"
		local RECORD, MEETING, RECORDING = "891dcbfc-9141-415d-9b2a-2238a6cc012d", "2e6e29ea-c4e0-4f44-842d-78a891f8c156", "a649e4d9-435c-43fb-83ba-847b4876f27a"
		local function last() return requests[#requests] end
		local function get(call, url)
			call()
			assert(last().method == "GET" and last().url == url, last().url)
		end
		local function same(a, b)
			if type(a) ~= "table" or type(b) ~= "table" then return a == b end
			for k, v in a do if not same(v, b[k]) then return false end end
			for k in b do if a[k] == nil then return false end end
			return true
		end
		local function post(call, url, body)
			call()
			assert(last().method == "POST" and last().url == url, last().url)
			assert(same(json.decode(last().body), json.decode(body)), last().body)
		end
		local function rejected(call, expected)
			local before = #requests
			local ok, err = pcall(call)
			local message = if type(err) == "table" then json.encode(err) else tostring(err)
			assert(not ok and string.find(message, expected, 1, true), "wrong validation error: " .. message)
			assert(#requests == before, "invalid input reached Attio")
		end

		local names = {}
		for name, fn in attio do
			assert(type(fn) == "function")
			table.insert(names, name)
		end
		table.sort(names)
		assert(table.concat(names, ",") == "getCallRecording,getComment,getFile,getList,getMeeting,getNote,getRecord,getTask,getThread,getWorkspaceMember,"
			.. "identify,listAttributes,listCallRecordings,listEmails,listFiles,listLists,listMeetings,listNotes,listObjects,listTasks,listThreads,"
			.. "listWorkspaceMembers,queryListEntries,queryRecords,searchRecords", table.concat(names, ","))
		assert(#requests == 0, "initialization reached Attio")

		payload = '{"active":true,"workspace_name":"Acme","scope":"record_permission:read"}'
		local me = attio.identify()
		assert(last().url == API .. "/self" and me.active == true and me.workspace_name == "Acme")

		payload = '{"data":[{"id":{"workspace_id":"w","object_id":"o"},"api_slug":"people","singular_noun":"Person"}]}'
		get(attio.listObjects, API .. "/objects")
		assert(attio.listObjects().data[1].api_slug == "people")
		payload = '{"data":[]}'
		local empty = attio.listObjects()
		assert(json.encode(empty.data) == "[]")
		get(attio.listLists, API .. "/lists")
		get(attio.listWorkspaceMembers, API .. "/workspace_members")

		get(function() attio.listAttributes("objects", "people", {limit = 20, offset = 40, show_archived = true}) end,
			API .. "/objects/people/attributes?limit=20&offset=40&show_archived=true")
		get(function() attio.listAttributes("lists", RECORD) end, API .. "/lists/" .. RECORD .. "/attributes")

		payload = '{"data":{"id":{"record_id":"' .. RECORD .. '"},"values":{"name":[{"value":"Ada"}],"email_addresses":[]}}}'
		get(function() attio.getRecord("people", RECORD) end, API .. "/objects/people/records/" .. RECORD)
		local record = attio.getRecord("people", RECORD)
		assert(record.data.values.name[1].value == "Ada" and json.encode(record.data.values.email_addresses) == "[]")

		payload = '{"data":[]}'
		post(function() attio.queryRecords("companies") end, API .. "/objects/companies/records/query", "{}")
		local query = {filter = {name = {["$contains"] = "Acme"}}, sorts = {{attribute = "created_at", direction = "desc"}}, limit = 50, offset = 100}
		post(function() attio.queryRecords("companies", query) end, API .. "/objects/companies/records/query",
			'{"filter":{"name":{"$contains":"Acme"}},"sorts":[{"attribute":"created_at","direction":"desc"}],"limit":50,"offset":100}')
		assert(query.limit == 50 and query.sorts[1].direction == "desc", "caller options were modified")
		post(function() attio.queryListEntries("sales", {filter_view_id = RECORD, sorts = {}}) end, API .. "/lists/sales/entries/query",
			'{"filter_view_id":"' .. RECORD .. '","sorts":[]}')
		assert(string.find(last().body, '"sorts":[]', 1, true), "empty sorts must stay a JSON array")
		post(function() attio.searchRecords("Acme", {objects = {"companies", "people"}, limit = 25}) end, API .. "/objects/records/search",
			'{"query":"Acme","objects":["companies","people"],"limit":25,"request_as":{"type":"workspace"}}')
		post(function() attio.searchRecords("", {objects = "deals", request_as = {type = "workspace-member", email_address = "ada@example.com"}}) end,
			API .. "/objects/records/search", '{"query":"","objects":["deals"],"request_as":{"type":"workspace-member","email_address":"ada@example.com"}}')

		get(function() attio.listNotes({parent_object = "companies", parent_record_id = RECORD, limit = 50, offset = 0}) end,
			API .. "/notes?limit=50&offset=0&parent_object=companies&parent_record_id=" .. RECORD)
		get(function() attio.getNote(RECORD) end, API .. "/notes/" .. RECORD)
		get(function() attio.listEmails({participants = {"ada@example.com", "bo@example.com"}, exclude_automated_participants = true, cursor = "c+/="}) end,
			API .. "/emails?cursor=c%2B%2F%3D&exclude_automated_participants=true&participants=ada%40example.com%2Cbo%40example.com")
		get(function() attio.listEmails({linked_object = "people", linked_record_ids = RECORD, sent_after = "2026-10-01T00:00:00Z"}) end,
			API .. "/emails?linked_object=people&linked_record_ids=" .. RECORD .. "&sent_after=2026-10-01T00%3A00%3A00Z")
		get(function() attio.listTasks({sort = "created_at:desc", assignee = "null", is_completed = false, limit = 1000}) end,
			API .. "/tasks?assignee=null&is_completed=false&limit=1000&sort=created_at%3Adesc")
		get(function() attio.getTask(RECORD) end, API .. "/tasks/" .. RECORD)
		get(function() attio.listThreads({object = "people", record_id = RECORD}) end, API .. "/threads?object=people&record_id=" .. RECORD)
		get(function() attio.getThread(RECORD, {limit = 250, cursor = "next"}) end, API .. "/threads/" .. RECORD .. "?cursor=next&limit=250")
		get(function() attio.getComment(RECORD) end, API .. "/comments/" .. RECORD)
		get(function() attio.listMeetings({sort = "start_desc", participants = "ada@example.com", limit = 200}) end,
			API .. "/meetings?limit=200&participants=ada%40example.com&sort=start_desc")
		get(function() attio.getMeeting(MEETING) end, API .. "/meetings/" .. MEETING)
		get(function() attio.listCallRecordings(MEETING, {limit = 10, cursor = "c1"}) end, API .. "/meetings/" .. MEETING .. "/call_recordings?cursor=c1&limit=10")
		get(function() attio.getCallRecording(MEETING, RECORDING) end, API .. "/meetings/" .. MEETING .. "/call_recordings/" .. RECORDING)
		get(function() attio.getList("sales") end, API .. "/lists/sales")
		get(function() attio.getWorkspaceMember(RECORD) end, API .. "/workspace_members/" .. RECORD)
		get(function() attio.listFiles({object = "companies", record_id = RECORD, storage_provider = "google-drive"}) end,
			API .. "/files?object=companies&record_id=" .. RECORD .. "&storage_provider=google-drive")
		get(function() attio.getFile(RECORD) end, API .. "/files/" .. RECORD)

		get(function() attio.getRecord("people", "r:2 ü@") end, API .. "/objects/people/records/r%3A2%20%C3%BC%40")
		get(function() attio.getList("Sales Pipeline") end, API .. "/lists/Sales%20Pipeline")
		get(function() attio.getNote({id = {workspace_id = "w", note_id = RECORD}, title = "Call"}) end, API .. "/notes/" .. RECORD)
		get(function() attio.getRecord("people", {id = {object_id = "o", record_id = RECORD}, values = {}}) end, API .. "/objects/people/records/" .. RECORD)
		get(function() attio.getCallRecording({meeting_id = MEETING}, {call_recording_id = RECORDING}) end,
			API .. "/meetings/" .. MEETING .. "/call_recordings/" .. RECORDING)
		post(function() attio.queryListEntries({id = {list_id = "l"}, api_slug = "sales"}) end, API .. "/lists/sales/entries/query", "{}")

		rejected(function() attio.getRecord("people") end, "record_id must be a nonempty string")
		rejected(function() attio.getNote({id = {record_id = RECORD}}) end, "note_id must be a nonempty string")
		rejected(function() attio.listAttributes("objects", "people", {target = "lists"}) end, "unknown option target")
		rejected(function() attio.queryRecords("people", {sorts = {{attribute = "name"}, direction = "asc"}}) end, "sorts must be an array")
		rejected(function() attio.getRecord("people", "r/2") end, "record_id")
		rejected(function() attio.getRecord("..", RECORD) end, "object")
		rejected(function() attio.getNote(42) end, "note_id must be a nonempty string")
		rejected(function() attio.listAttributes("webhooks", "people") end, "target must be")
		rejected(function() attio.listNotes({limit = 51}) end, "limit must be an integer from 1 to 50")
		rejected(function() attio.listNotes({offset = -1}) end, "offset must be an integer from 0")
		rejected(function() attio.listNotes({page = 2}) end, "unknown option page")
		rejected(function() attio.listNotes("people") end, "options must be a table")
		rejected(function() attio.listTasks({sort = "due"}) end, "sort must be one of")
		rejected(function() attio.listTasks({is_completed = "true"}) end, "is_completed must be a boolean")
		rejected(function() attio.listEmails({participants = {}}) end, "participants must be a nonempty string or array")
		rejected(function() attio.listEmails({participants = {a = "x"}}) end, "participants must be")
		rejected(function() attio.listCallRecordings(MEETING, {offset = 10}) end, "unknown option offset")
		rejected(function() attio.listFiles({object = "companies"}) end, "listFiles requires record_id")
		rejected(function() attio.listFiles() end, "listFiles requires object")
		rejected(function() attio.searchRecords("Acme") end, "searchRecords requires objects")
		rejected(function() attio.searchRecords(nil, {objects = {"people"}}) end, "query must be a string")
		rejected(function() attio.searchRecords("Acme", {objects = {"people"}, query = "Other"}) end, "unknown option query")
		rejected(function() attio.searchRecords("Acme", {objects = {"people"}, limit = 26}) end, "limit must be an integer from 1 to 25")
		rejected(function() attio.queryRecords("people", {sorts = {attribute = "name"}}) end, "sorts must be")
		rejected(function() attio.queryRecords("people", {limit = 0.5}) end, "limit must be an integer")
		rejected(function() attio.getTask(RECORD, {}, {}) end, "getTask takes at most 2 arguments")
	end,
}
