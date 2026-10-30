return {
	scenario = {publisher = {}, config = {organization = " Acme-Corp "}, auth_method = "token", auth_config = {token = "fixture-token"}},
	configure = function()
		requests = {}
		payload = "[]"
		responseHeaders = {}
		http = {request = function(req)
			table.insert(requests, req)
			return fixture.operation({statusCode = 200, headers = responseHeaders, body = fixture.reader(payload)})
		end}
	end,
	run = function(sentry)
		local API = "https://us.sentry.io/api/0"
		local ORG = API .. "/organizations/acme-corp"
		local NULL = json.decode("null")
		local function last() return requests[#requests] end
		local function rejected(fn, expected)
			local before = #requests
			local ok, err = pcall(fn)
			assert(not ok and string.find(tostring(err), expected, 1, true), "wrong validation error: " .. tostring(err))
			assert(#requests == before, "invalid input reached Sentry")
		end

		local names = {}
		for name in sentry do table.insert(names, name) end
		table.sort(names)
		assert(table.concat(names, ",") == "getEvent,getIssue,getIssueEvent,getIssueTag,getOrganization,getProject,getRelease,getSessions,listIssueComments,listIssueEvents,listIssues,listMembers,listOrganizations,listProjects,listReleases,listTeams",
			"wrong read-only surface: " .. table.concat(names, ","))
		assert(#requests == 0, "initialization reached Sentry")

		-- Lists wrap Sentry's top-level arrays with the next cursor from the Link header.
		payload = '[{"id":"1","slug":"acme-corp","name":"Acme","links":{"regionUrl":"https://us.sentry.io"}}]'
		responseHeaders = {link = {'<https://us.sentry.io/api/0/organizations/?cursor=0:0:1>; rel="previous"; results="false"; cursor="0:0:1", '
			.. '<https://us.sentry.io/api/0/organizations/?cursor=0:100:0>; rel="next"; results="true"; cursor="0:100:0"'}}
		local orgs = sentry.listOrganizations({owner = true, per_page = 50})
		assert(last().method == "GET" and last().url == API .. "/organizations/?owner=true&per_page=50" and last().body == nil, last().url)
		assert(last().headers.Accept[1] == "application/json" and last().headers.Authorization == nil)
		assert(orgs.results[1].slug == "acme-corp" and orgs.next == "0:100:0" and orgs.hits == nil, json.encode(orgs))

		-- The last page links a next cursor without results.
		payload = "[]"
		responseHeaders = {link = {'<https://us.sentry.io/api/0/organizations/acme-corp/projects/?cursor=0:200:0>; rel="previous"; results="true"; cursor="0:100:1", '
			.. '<https://us.sentry.io/api/0/organizations/acme-corp/projects/?cursor=0:300:0>; rel="next"; results="false"; cursor="0:300:0"'}}
		local projects = sentry.listProjects({query = "web", cursor = "0:200:0"})
		assert(last().url == ORG .. "/projects/?query=web&cursor=0%3A200%3A0", last().url)
		assert(json.encode(projects.results) == "[]" and projects.next == NULL and json.encode(projects) == '{"next":null,"results":[]}', json.encode(projects))
		responseHeaders = {}
		-- Projects keep their public fields only: no security token, symbol servers or scrubbing rules.
		payload = '{"id":"42","slug":"web","platform":"javascript","teams":[],"latestRelease":null,"securityToken":"token-secret","securityTokenHeader":"X-Sentry-Token",'
			.. '"symbolSources":"[{\\"password\\":{\\"hidden-secret\\":true}}]","relayPiiConfig":"{}","sensitiveFields":["password"],"options":{"sentry:token":"token-secret"}}'
		local found = sentry.getProject({project_id_or_slug = "web"})
		assert(last().url == API .. "/projects/acme-corp/web/" and found.platform == "javascript" and found.latestRelease == NULL and json.encode(found.teams) == "[]")
		local encoded = json.encode(found)
		for _, leaked in {"secret", "Token", "symbol", "relay", "sensitive", "options"} do
			assert(not string.find(encoded, leaked, 1, true), "project leaked " .. leaked .. ": " .. encoded)
		end
		sentry.getOrganization({detailed = "0"})
		assert(last().url == ORG .. "/?detailed=0", last().url)
		payload = '[{"id":"7","slug":"backend","name":"Backend"}]'
		assert(sentry.listTeams({query = "back"}).results[1].id == "7" and last().url == ORG .. "/teams/?query=back")
		payload = '[{"id":"9","email":"ada@example.com","user":{"id":"3"}}]'
		assert(sentry.listMembers({query = "email:ada@example.com"}).results[1].user.id == "3")
		assert(last().url == ORG .. "/members/?query=email%3Aada%40example.com", last().url)

		-- Issue searches keep Sentry's query syntax and repeat array keys; hits reports the total.
		payload = '[{"id":"1001","shortId":"WEB-1A","title":"TypeError: x is undefined","status":"unresolved","assignedTo":null,"count":"12"}]'
		responseHeaders = {["x-hits"] = {"37"}, link = {'<https://us.sentry.io/x>; rel="next"; results="true"; cursor="1730000000000:0:0"'}}
		local opts = {query = "is:unresolved level:error release:web@1.2.0", project = {"42", "43"}, environment = "production", sort = "freq", limit = 25, statsPeriod = "24h"}
		local issues = sentry.listIssues(opts)
		assert(last().url == ORG .. "/issues/?query=is%3Aunresolved%20level%3Aerror%20release%3Aweb%401.2.0&project=42&project=43&environment=production&sort=freq&limit=25&statsPeriod=24h", last().url)
		assert(opts.project[2] == "43" and opts.limit == 25, "caller options were modified")
		assert(issues.hits == 37 and issues.next == "1730000000000:0:0" and issues.results[1].shortId == "WEB-1A" and issues.results[1].assignedTo == NULL)
		payload = "[]"
		responseHeaders = {["x-hits"] = {"0"}}
		issues = sentry.listIssues({query = ""})
		assert(last().url == ORG .. "/issues/?query=" and json.encode(issues.results) == "[]" and issues.hits == 0, last().url)
		responseHeaders = {}

		payload = '{"id":"1001","shortId":"WEB-1A","tags":[{"key":"browser","totalValues":3}]}'
		assert(sentry.getIssue({issue_id = "WEB-1A"}).id == "1001" and last().url == ORG .. "/issues/WEB-1A/")
		sentry.getIssue({issue_id = 1001, environment = {"production", "staging"}})
		assert(last().url == ORG .. "/issues/1001/?environment=production&environment=staging", last().url)
		payload = '{"key":"browser","totalValues":3,"topValues":[{"value":"Chrome","count":2}]}'
		assert(sentry.getIssueTag({issue_id = "1001", key = "browser"}).topValues[1].value == "Chrome")
		assert(last().url == ORG .. "/issues/1001/tags/browser/")
		payload = '[{"id":"5","type":"note","data":{"text":"Looking"}}]'
		assert(sentry.listIssueComments({issue_id = "1001"}).results[1].data.text == "Looking" and last().url == ORG .. "/issues/1001/comments/")

		-- Events keep the innermost frames, latest breadcrumbs and the crashed thread's stack.
		local frames = {}
		local context = {}
		for line = 90, 112 do table.insert(context, {line, "line " .. line}) end
		for i = 1, 40 do
			frames[i] = {filename = "app.js", ["function"] = "f" .. i, lineNo = 100, inApp = i > 35 or i == 2 or i == 5, vars = {big = string.rep("v", 3000)}, context = context}
		end
		local crumbs = {}
		for i = 1, 60 do crumbs[i] = {category = "http", message = "crumb " .. i, level = "info"} end
		local images = {}
		for i = 1, 200 do images[i] = {type = "macho", debug_id = "id" .. i} end
		local exceptions = {}
		for i = 1, 7 do exceptions[i] = {type = "Error" .. i, value = "failed", stacktrace = {frames = if i == 7 then frames else {}}, rawStacktrace = {frames = frames}} end
		local big = {
			id = "c0ffee00c0ffee00c0ffee00c0ffee00", eventID = "c0ffee00c0ffee00c0ffee00c0ffee00", groupID = "1001", title = "Error7: failed",
			message = string.rep("m", 5000) .. "é", nextEventID = NULL, _meta = {entries = {["0"] = {data = {}}}},
			entries = {
				{type = "exception", data = {values = exceptions, hasSystemFrames = true}},
				{type = "breadcrumbs", data = {values = crumbs}},
				{type = "threads", data = {values = {{id = 1, crashed = true, stacktrace = {frames = frames}}, {id = 2, crashed = false, current = false, name = "worker", stacktrace = {frames = frames}}}}},
				{type = "debugmeta", data = {images = images}},
				{type = "request", data = {url = "https://example.com/checkout", method = "POST"}},
			},
			tags = {{key = "release", value = "web@1.2.0"}},
		}
		payload = json.encode(big)
		local e = sentry.getIssueEvent({issue_id = "1001", event_id = "latest"})
		assert(last().url == ORG .. "/issues/1001/events/latest/", last().url)
		local exception = e.entries[1].data.values
		assert(#exception == 5 and exception[1].type == "Error1" and exception[2].type == "Error4" and exception[5].type == "Error7" and exception[5].rawStacktrace == nil)
		local kept = exception[5].stacktrace.frames
		-- The innermost 30 frames stay, and the in-app frames beyond them.
		assert(#kept == 32 and kept[1]["function"] == "f2" and kept[2]["function"] == "f5" and kept[3]["function"] == "f11" and kept[32]["function"] == "f40")
		assert(#kept[32].context == 11 and kept[32].context[1][1] == 95 and kept[32].context[11][2] == "line 105", json.encode(kept[32].context))
		assert(#kept[32].vars.big == 2048 + #"…" and e.message == string.rep("m", 2048) .. "…")
		local breadcrumbs = e.entries[2].data.values
		assert(#breadcrumbs == 50 and breadcrumbs[1].message == "crumb 11" and breadcrumbs[50].message == "crumb 60")
		local threads = e.entries[3].data.values
		assert(#threads[1].stacktrace.frames == 32 and threads[2].stacktrace == nil and threads[2].name == "worker")
		assert(json.encode(e.entries[4].data.images) == "[]" and e.entries[5].data.url == "https://example.com/checkout")
		assert(e._meta == nil and e.nextEventID == NULL and e.tags[1].value == "web@1.2.0")
		local trimmed = e.houstonTrimmed
		assert(trimmed.exceptions == 2 and trimmed.rawStacktraces == 5 and trimmed.breadcrumbs == 10 and trimmed.threadStacktraces == 1 and trimmed.debugImages == 200, json.encode(trimmed))
		assert(trimmed.frames == 16 and trimmed.contextLines == 768 and trimmed.strings == 65, json.encode(trimmed))
		assert(last().body == nil)

		-- Spans keep the first ones, a bare stack trace its innermost frames, and the current
		-- thread its stack; without a crashed or current thread, the first one keeps it. Context
		-- without a line number stays whole.
		local spans, bare = {}, {}
		for i = 1, 60 do spans[i] = {span_id = "s" .. i, op = "db"} end
		for i = 1, 35 do bare[i] = {["function"] = "g" .. i, context = context} end
		payload = json.encode({id = "ab13", entries = {
			{type = "spans", data = spans},
			{type = "stacktrace", data = {frames = bare}},
			{type = "threads", data = {values = {{id = 1, current = true, stacktrace = {frames = {{["function"] = "main"}}}}, {id = 2, stacktrace = {frames = {}}}}}},
			{type = "threads", data = {values = {{id = 3, stacktrace = {frames = {{["function"] = "run"}}}}, {id = 4, stacktrace = {frames = {}}}}}},
		}})
		e = sentry.getEvent({project_id_or_slug = "web", event_id = "ab13"})
		assert(#e.entries[1].data == 50 and e.entries[1].data[1].span_id == "s1" and e.entries[1].data[50].span_id == "s50")
		local frames2 = e.entries[2].data.frames
		assert(#frames2 == 30 and frames2[1]["function"] == "g6" and #frames2[1].context == 23)
		assert(e.entries[3].data.values[1].stacktrace.frames[1]["function"] == "main" and e.entries[3].data.values[2].stacktrace == nil)
		assert(e.entries[4].data.values[1].stacktrace.frames[1]["function"] == "run" and e.entries[4].data.values[2].stacktrace == nil)
		trimmed = e.houstonTrimmed
		assert(trimmed.spans == 10 and trimmed.frames == 5 and trimmed.threadStacktraces == 2 and trimmed.contextLines == nil, json.encode(trimmed))

		-- A small event comes back unchanged, including the null stack traces Sentry always sends.
		payload = '{"id":"ab12","entries":[{"type":"message","data":{"formatted":"hello"}},{"type":"breadcrumbs","data":{"values":[]}},'
			.. '{"type":"exception","data":{"values":[{"type":"Error","stacktrace":null,"rawStacktrace":null}]}},'
			.. '{"type":"threads","data":{"values":[{"id":1,"crashed":true,"stacktrace":null,"rawStacktrace":null},{"id":2,"stacktrace":null,"rawStacktrace":null}]}}],"contexts":{}}'
		e = sentry.getEvent({project_id_or_slug = "web", event_id = "ab12", collapse = "adjacentEvents"})
		assert(last().url == API .. "/projects/acme-corp/web/events/ab12/?collapse=adjacentEvents", last().url)
		assert(e.houstonTrimmed == nil, json.encode(e.houstonTrimmed))
		assert(e.entries[1].data.formatted == "hello" and json.encode(e.entries[2].data.values) == "[]")
		assert(e.entries[3].data.values[1].rawStacktrace == NULL and e.entries[4].data.values[2].stacktrace == NULL and e.entries[4].data.values[2].rawStacktrace == NULL)

		payload = "[" .. json.encode(big) .. ',{"id":"ab12","eventID":"ab12"}]'
		responseHeaders = {link = {'<https://us.sentry.io/x>; rel="next"; results="true"; cursor="0:10:0"'}}
		local events = sentry.listIssueEvents({issue_id = "WEB-1A", full = true, query = "user.email:ada@example.com", per_page = 10})
		assert(last().url == ORG .. "/issues/WEB-1A/events/?query=user.email%3Aada%40example.com&full=true&per_page=10", last().url)
		assert(#events.results == 2 and events.next == "0:10:0" and #events.results[1].entries[2].data.values == 50 and events.results[2].houstonTrimmed == nil)
		responseHeaders = {}
		payload = "[]"
		assert(json.encode(sentry.listIssueEvents({issue_id = "1001"}).results) == "[]")

		payload = '[{"version":"web@1.2.0","projects":[{"slug":"web","healthData":{"crashFreeSessions":99.5}}]}]'
		local releases = sentry.listReleases({project = "42", health = "1", healthStatsPeriod = "7d", per_page = 5})
		assert(last().url == ORG .. "/releases/?project=42&health=1&healthStatsPeriod=7d&per_page=5", last().url)
		assert(releases.results[1].projects[1].healthData.crashFreeSessions == 99.5)
		payload = '{"version":"web@1.2.0+45","dateReleased":null}'
		assert(sentry.getRelease({version = "web@1.2.0+45", health = "1"}).dateReleased == NULL)
		assert(last().url == ORG .. "/releases/web%401.2.0%2B45/?health=1", last().url)
		payload = '{"start":"2026-10-29T00:00:00Z","intervals":[],"groups":[]}'
		assert(json.encode(sentry.getSessions({field = {"sum(session)", "crash_free_rate(session)"}, groupBy = "release", statsPeriod = "7d", interval = "1d"}).groups) == "[]")
		assert(last().url == ORG .. "/sessions/?field=sum%28session%29&field=crash_free_rate%28session%29&groupBy=release&interval=1d&statsPeriod=7d", last().url)
		assert(#requests == 20)

		rejected(function() sentry.getIssue() end, "issue_id is required")
		rejected(function() sentry.getIssue({issue_id = "../projects"}) end, "issue_id must be a Sentry id, slug or version")
		rejected(function() sentry.getRelease({version = "a/b"}) end, "version must be a Sentry id")
		rejected(function() sentry.getIssue({issue_id = 1.5}) end, "issue_id must be a string")
		rejected(function() sentry.getEvent({project_id_or_slug = "web"}) end, "event_id is required")
		rejected(function() sentry.getSessions({statsPeriod = "7d"}) end, "field is required")
		rejected(function() sentry.listIssues({project = json.decode("[]")}) end, "project must not be an empty array")
		rejected(function() sentry.listIssues({project = {web = true}}) end, "array, not an object")
		rejected(function() sentry.listIssues({organization = "other"}) end, "listIssues has no option organization")
		rejected(function() sentry.listIssues({query = {nested = {}}}) end, "query must be")
		rejected(function() sentry.listProjects("web") end, "opts must be an object")
		rejected(function() sentry.listProjects({"web"}) end, "named fields")
	end,
}
