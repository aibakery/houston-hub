return {
	scenario = {publisher = {}, config = {}, auth_method = "token", auth_config = {token = "grn_fixture-private-key"}},
	configure = function()
		requests = {}
		payload = "{}"
		http = {request = function(req)
			table.insert(requests, req)
			assert(req.method == "GET" and req.body == nil, "Granola reads must be bodiless GETs")
			assert(req.headers.Authorization == nil, "credentials must remain in the proxy")
			assert(req.headers.Accept[1] == "application/json")
			return fixture.operation({statusCode = 200, headers = {}, body = fixture.reader(payload)})
		end}
	end,
	run = function(granola)
		local API = "https://public-api.granola.ai/v1"
		local NULL = json.decode("null")
		local NOTE, FOLDER, SPACE = "not_1d3tmYTlCICgjy", "fol_4y6LduVdwSKC27", "spa_8kTq2mWxLp4Rz7"
		local function last() return requests[#requests].url end
		local function rejected(fn, expected)
			local before = #requests
			local ok, err = pcall(fn)
			assert(not ok and string.find(tostring(err), expected, 1, true), "wrong validation error: " .. tostring(err))
			assert(#requests == before, "invalid input reached Granola")
		end

		local names = {}
		for name, fn in granola do
			assert(type(fn) == "function")
			table.insert(names, name)
		end
		table.sort(names)
		assert(table.concat(names, ",") == "getNote,getTranscript,listFolders,listNotes,listSpaces", table.concat(names, ","))
		assert(#requests == 0, "initialization reached Granola")

		payload = '{"notes":[{"id":"' .. NOTE .. '","object":"note","title":null,"owner":{"name":"Ana","email":"ana@example.com"},"deleted_at":null}],"hasMore":true,"cursor":"eyJ+/="}'
		local opts = {created_after = "2026-10-01T00:00:00-07:00", created_before = "2026-10-24", updated_after = "2026-10-02",
			folder_id = FOLDER, space_id = SPACE, page_size = 30, cursor = "start+/="}
		local page = granola.listNotes(opts)
		assert(last() == API .. "/notes?created_after=2026-10-01T00%3A00%3A00-07%3A00&created_before=2026-10-24&cursor=start%2B%2F%3D"
			.. "&folder_id=" .. FOLDER .. "&page_size=30&space_id=" .. SPACE .. "&updated_after=2026-10-02", last())
		assert(opts.page_size == 30 and opts.cursor == "start+/=", "caller options were modified")
		assert(page.hasMore == true and page.cursor == "eyJ+/=" and page.notes[1].title == NULL and page.notes[1].owner.name == "Ana")
		granola.listNotes({cursor = page.cursor})
		assert(last() == API .. "/notes?cursor=eyJ%2B%2F%3D", last())

		payload = '{"notes":[],"hasMore":false,"cursor":null}'
		local empty = granola.listNotes()
		assert(last() == API .. "/notes" and json.encode(empty.notes) == "[]" and empty.cursor == NULL)

		payload = '{"id":"' .. NOTE .. '","title":"Weekly sync","attendees":[],"summary_markdown":"## Decisions","transcript":null,"calendar_event":{"organiser":"ana@example.com","invitees":[{"email":"bo@example.com"}]}}'
		local note = granola.getNote(NOTE)
		assert(last() == API .. "/notes/" .. NOTE)
		assert(note.summary_markdown == "## Decisions" and note.transcript == NULL and json.encode(note.attendees) == "[]")
		assert(note.calendar_event.invitees[1].email == "bo@example.com")
		granola.getNote(NOTE, {include = "transcript"})
		assert(last() == API .. "/notes/" .. NOTE .. "?include=transcript")
		granola.getNote({id = "NOT_1d3tmYTlCICgjy", include = "transcript"})
		assert(last() == API .. "/notes/NOT_1d3tmYTlCICgjy?include=transcript", "IDs are case-insensitive")

		payload = '{"transcript":[{"speaker":{"source":"microphone","attribution":"me"},"text":"Hello","start_time":"2026-10-24T10:00:00Z","end_time":"2026-10-24T10:00:02Z"}],"hasMore":true,"cursor":"t2"}'
		local lines = granola.getTranscript(NOTE, {page_size = 100})
		assert(last() == API .. "/notes/" .. NOTE .. "/transcript?page_size=100")
		assert(lines.transcript[1].speaker.source == "microphone" and lines.cursor == "t2")
		payload = '{"transcript":[],"hasMore":false,"cursor":null}'
		assert(json.encode(granola.getTranscript({id = NOTE, cursor = "t2"}).transcript) == "[]")
		assert(last() == API .. "/notes/" .. NOTE .. "/transcript?cursor=t2")

		payload = '{"folders":[{"id":"' .. FOLDER .. '","object":"folder","name":"Customers","parent_folder_id":null,"space_id":"' .. SPACE .. '"}],"hasMore":false,"cursor":null}'
		local folders = granola.listFolders({page_size = 1})
		assert(last() == API .. "/folders?page_size=1" and folders.folders[1].parent_folder_id == NULL)
		payload = '{"folders":[],"hasMore":false,"cursor":null}'
		assert(json.encode(granola.listFolders().folders) == "[]" and last() == API .. "/folders")

		payload = '{"spaces":[{"id":"' .. SPACE .. '","object":"space","name":"Team"}],"hasMore":false,"cursor":null}'
		assert(granola.listSpaces().spaces[1].name == "Team" and last() == API .. "/spaces")
		payload = '{"spaces":[],"hasMore":false,"cursor":null}'
		assert(json.encode(granola.listSpaces({cursor = "s2"}).spaces) == "[]" and last() == API .. "/spaces?cursor=s2")

		rejected(function() granola.getNote("not_1d3tmYTlCICgj/") end, "not_ ID")
		rejected(function() granola.getNote("../not_1d3tmYTlCI") end, "not_ ID")
		rejected(function() granola.getNote(FOLDER) end, "not_ ID")
		rejected(function() granola.getNote("not_1d3tmYTlCICgjyX") end, "not_ ID")
		rejected(function() granola.getNote("") end, "nonempty")
		rejected(function() granola.getNote({include = "transcript"}) end, "nonempty")
		rejected(function() granola.getNote({id = NOTE}, {}) end, "one table")
		rejected(function() granola.getNote(NOTE, {include = "summary"}) end, "\"transcript\"")
		rejected(function() granola.getNote(NOTE, {includeTranscript = true}) end, "unknown option includeTranscript")
		rejected(function() granola.getTranscript(NOTE, {page_size = 101}) end, "1 to 100")
		rejected(function() granola.listNotes({page_size = 31}) end, "1 to 30")
		rejected(function() granola.listNotes({page_size = 0}) end, "1 to 30")
		rejected(function() granola.listNotes({page_size = 2.5}) end, "1 to 30")
		rejected(function() granola.listNotes({created_after = "yesterday"}) end, "RFC 3339")
		rejected(function() granola.listNotes({created_after = 20261001}) end, "nonempty string")
		rejected(function() granola.listNotes({folder_id = SPACE}) end, "fol_ ID")
		rejected(function() granola.listNotes({space_id = "spa_x&page_size=99"}) end, "spa_ ID")
		rejected(function() granola.listNotes({cursor = ""}) end, "nonempty")
		rejected(function() granola.listNotes({limit = 10}) end, "unknown option limit")
		rejected(function() granola.listFolders({folder_id = FOLDER}) end, "unknown option folder_id")
		rejected(function() granola.listSpaces("next") end, "must be a table")
	end,
}
