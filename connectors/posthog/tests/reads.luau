return {
	scenario = {publisher = {}, config = {}, auth_method = "token", auth_config = {token = "phx_fixture-private-key"}},
	configure = function()
		requests = {}
		payloads = {}
		http = {request = function(req)
			table.insert(requests, req)
			assert(req.headers.Authorization == nil, "credentials must remain in the proxy")
			assert(req.headers.Accept[1] == "application/json")
			assert(req.timeoutMs == 15000 or req.timeoutMs == 5000 or req.timeoutMs == 20000, "requests must bound the wait for headers")
			if req.method == "GET" then
				assert(req.body == nil, "PostHog reads must be bodiless GETs")
			else
				assert(req.method == "POST" and req.headers["Content-Type"][1] == "application/json", "only queries are posted")
			end
			local payload = table.remove(payloads, 1)
			assert(payload, "unexpected request " .. req.url)
			return fixture.operation({statusCode = 200, headers = {}, body = fixture.reader(payload)})
		end}
	end,
	run = function(posthog)
		local API = "https://us.posthog.com/api"
		local P = API .. "/projects/12345"
		local ORG = "0188430e-316e-0000-51a6-fd646548690e"
		local NULL = json.decode("null")
		local function urls(from)
			local out = {}
			for index = from, #requests do table.insert(out, requests[index].url) end
			return table.concat(out, " ")
		end
		local function last() return requests[#requests].url end
		local function rejected(fn, expected)
			local before = #requests
			local ok, err = pcall(fn)
			assert(not ok and string.find(tostring(err), expected, 1, true), "wrong validation error: " .. tostring(err))
			assert(#requests == before, "invalid input reached PostHog")
		end

		local names = {}
		for name, fn in posthog do
			assert(type(fn) == "function")
			table.insert(names, name)
		end
		table.sort(names)
		assert(table.concat(names, ",") == "getInsight,listEvents,listFeatureFlags,listInsights,listOrganizations,listPersons,listProjects,query", table.concat(names, ","))
		assert(#requests == 0, "initialization reached PostHog")

		payloads = {'{"count":1,"next":null,"previous":null,"results":[{"id":"' .. ORG .. '","name":"Acme","slug":"acme","created_at":"2024-01-02T00:00:00Z","membership_level":8,"member_count":3,"teams":[{"api_token":"phc_public"}],"customer_id":"cus_1"}]}'}
		local orgs = posthog.listOrganizations()
		assert(last() == API .. "/organizations/?limit=100", last())
		assert(orgs.count == 1 and orgs.next == NULL and orgs.results[1].name == "Acme" and orgs.results[1].membership_level == 8)
		assert(orgs.results[1].teams == nil and orgs.results[1].customer_id == nil, "organization rows must stay compact")

		payloads = {'{"count":2,"next":null,"previous":null,"results":[{"id":12345,"uuid":"u1","organization":"' .. ORG .. '","project_id":12345,"api_token":"phc_public","name":"Web","timezone":"UTC","is_demo":false,"ingested_event":true,"tags":[],"access_control":false}]}'}
		local projects = posthog.listProjects()
		assert(last() == API .. "/organizations/@current/projects/?limit=100", last())
		assert(projects.results[1].id == 12345 and projects.results[1].api_token == nil and json.encode(projects.results[1].tags) == "[]")
		payloads = {'{"count":0,"next":null,"previous":null,"results":[]}'}
		local none = posthog.listProjects({organization = ORG, search = "web app", limit = 5})
		assert(last() == API .. "/organizations/" .. ORG .. "/projects/?search=web%20app&limit=5", last())
		assert(json.encode(none.results) == "[]" and none.count == 0)
		payloads = {'{"count":0,"next":null,"previous":null,"results":[]}'}
		posthog.listProjects({organization = ORG, next = "https://us.posthog.com/api/organizations/" .. ORG .. "/projects/?limit=5&offset=5&search=web%20app"})
		assert(last() == API .. "/organizations/" .. ORG .. "/projects/?offset=5&search=web%20app&limit=100", last())

		-- A call follows PostHog's next links until it has limit rows, asking each page only for the rest.
		local event = '{"id":"018f-a","distinct_id":"d1","event":"$pageview","timestamp":"2026-10-29T10:00:00Z","properties":{"$browser":"Firefox"},"elements":[{"tag_name":"a"}],"elements_chain":"a:nth-child(1)"}'
		payloads = {'{"next":"https://us.posthog.com/api/projects/12345/events/?event=%24pageview&limit=1&before=2026-10-29T10%3A00%3A00Z","results":[' .. event .. ']}',
			'{"next":"https://us.posthog.com/api/projects/12345/events/?event=%24pageview&limit=1&before=2026-10-29T09%3A00%3A00Z","results":[' .. event .. ']}'}
		local before = #requests + 1
		local filters = {{key = "$browser", value = "Firefox", operator = "exact", type = "event"}}
		local events = posthog.listEvents(12345, {event = "$pageview", after = "2026-10-29T00:00:00Z", before = "2026-10-30T00:00:00Z", distinct_id = "d1",
			person_id = "0190-person", properties = filters, include_person = true, limit = 2})
		assert(urls(before) == P .. "/events/?after=2026-10-29T00%3A00%3A00Z&before=2026-10-30T00%3A00%3A00Z&distinct_id=d1&event=%24pageview&include_person=true"
			.. "&person_id=0190-person&properties=" .. url.encode(json.encode(filters)) .. "&limit=2 "
			.. P .. "/events/?event=%24pageview&before=2026-10-29T10%3A00%3A00Z&limit=1", urls(before))
		assert(#events.results == 2 and events.results[1].properties["$browser"] == "Firefox" and events.results[1].elements == nil and events.results[1].elements_chain == nil)
		assert(events.count == nil and events.next == "https://us.posthog.com/api/projects/12345/events/?event=%24pageview&limit=1&before=2026-10-29T09%3A00%3A00Z", tostring(events.next))
		payloads = {'{"next":null,"results":[]}'}
		local rest = posthog.listEvents("12345", {next = events.next, limit = 50})
		assert(last() == P .. "/events/?event=%24pageview&before=2026-10-29T09%3A00%3A00Z&limit=50", last())
		assert(json.encode(rest.results) == "[]" and rest.next == NULL)
		assert(requests[before].timeoutMs == 15000 and requests[before + 1].timeoutMs == 5000, "a second page must get the rest of the call's time")
		-- A call stops after two pages and hands back the link to the next one.
		local link = '"https://us.posthog.com/api/projects/@current/events/?offset=1"'
		payloads = {}
		for _ = 1, 2 do table.insert(payloads, '{"next":' .. link .. ',"results":[' .. event .. ']}') end
		before = #requests + 1
		local capped = posthog.listEvents("@current", {limit = 1000})
		assert(#requests - before + 1 == 2 and #capped.results == 2 and capped.next == "https://us.posthog.com/api/projects/@current/events/?offset=1")
		assert(requests[before].url == API .. "/projects/@current/events/?limit=1000" and last() == API .. "/projects/@current/events/?offset=1&limit=999", last())
		-- When the second page fails, the first comes back with the link to the second.
		payloads = {'{"next":' .. link .. ',"results":[' .. event .. ']}', "<html>Bad gateway</html>"}
		before = #requests + 1
		local partial = posthog.listEvents("@current", {limit = 10})
		assert(#requests - before + 1 == 2 and #partial.results == 1 and partial.next == "https://us.posthog.com/api/projects/@current/events/?offset=1")
		-- A link to another path is handed back, never followed.
		payloads = {'{"next":"https://us.posthog.com/api/projects/999/events/?offset=1","results":[' .. event .. ']}'}
		before = #requests + 1
		assert(posthog.listEvents(12345, {limit = 10}).next == "https://us.posthog.com/api/projects/999/events/?offset=1" and #requests == before)

		payloads = {'{"count":1,"next":"https://us.posthog.com/api/projects/12345/persons/?limit=1&offset=1","previous":null,"results":[{"id":"0190-person","uuid":"0190-person","name":"ana@example.com","distinct_ids":["d1"],"properties":{"email":"ana@example.com"},"created_at":"2026-01-01T00:00:00Z","last_seen_at":null,"is_identified":true}]}'}
		local persons = posthog.listPersons(12345, {search = "ana", email = "ana@example.com", distinct_id = "d1", properties = {{key = "plan", value = "pro", type = "person"}}, limit = 1})
		assert(last() == P .. "/persons/?distinct_id=d1&email=ana%40example.com&properties=" .. url.encode(json.encode({{key = "plan", value = "pro", type = "person"}})) .. "&search=ana&limit=1", last())
		assert(persons.results[1].distinct_ids[1] == "d1" and persons.results[1].last_seen_at == NULL and persons.results[1].is_identified == nil)
		assert(persons.next == "https://us.posthog.com/api/projects/12345/persons/?limit=1&offset=1" and persons.count == 1)
		payloads = {'{"count":1,"next":null,"previous":"/api/projects/12345/persons/?limit=1","results":[]}'}
		assert(json.encode(posthog.listPersons(12345, {next = "/api/projects/12345/persons/?offset=1"}).results) == "[]")
		assert(last() == P .. "/persons/?offset=1&limit=100", last())

		payloads = {'{"count":1,"next":null,"previous":null,"results":[{"id":7,"short_id":"AaVQ8Ijw","name":"Signups","derived_name":null,"query":{"kind":"InsightVizNode"},"saved":true,"favorited":false,"tags":[],"created_by":{"id":1,"uuid":"u","first_name":"Ana","last_name":"Lee","email":"ana@example.com","hedgehog_config":{}},"dashboards":[1],"dashboard_tiles":[{"id":2}],"user_access_level":"editor"}]}'}
		local insights = posthog.listInsights(12345, {search = "signup", saved = true, insight = "TRENDS"})
		assert(last() == P .. "/insights/?basic=true&insight=TRENDS&saved=true&search=signup&limit=100", last())
		local insight = insights.results[1]
		assert(insight.short_id == "AaVQ8Ijw" and insight.derived_name == NULL and insight.dashboards == nil and insight.user_access_level == nil)
		assert(insight.created_by.email == "ana@example.com" and insight.created_by.hedgehog_config == nil and insight.created_by.uuid == nil)
		payloads = {'{"count":0,"next":null,"previous":null,"results":[]}'}
		assert(json.encode(posthog.listInsights(12345).results) == "[]" and last() == P .. "/insights/?basic=true&limit=100")
		payloads = {'{"count":0,"next":null,"previous":null,"results":[]}'}
		posthog.listInsights(12345, {next = "https://us.posthog.com/api/projects/12345/insights/?basic=true&limit=100&offset=100&search=signup"})
		assert(last() == P .. "/insights/?offset=100&search=signup&basic=true&limit=100", last())

		payloads = {'{"id":7,"short_id":"AaVQ8Ijw","name":"Signups","result":[{"data":[1,2,3]}],"last_refresh":"2026-10-29T00:00:00Z","dashboards":[1],"user_access_level":"editor","created_by":{"id":1,"email":"ana@example.com","hedgehog_config":{}}}'}
		local full = posthog.getInsight(12345, 7)
		assert(last() == P .. "/insights/7/" and requests[#requests].timeoutMs == 20000 and full.result[1].data[3] == 3, last())
		assert(full.dashboards == nil and full.last_refresh == "2026-10-29T00:00:00Z" and full.created_by.email == "ana@example.com" and full.created_by.hedgehog_config == nil, "insights must stay compact")
		payloads = {'{"id":7,"short_id":"AaVQ8Ijw","result":null}'}
		assert(posthog.getInsight("@current", "AaVQ8Ijw", {refresh = "blocking"}).result == NULL)
		assert(last() == API .. "/projects/@current/insights/AaVQ8Ijw/?refresh=blocking", last())

		payloads = {'{"count":2,"next":null,"previous":null,"results":['
			.. '{"id":3,"key":"new-nav","name":"New navigation","active":true,"status":"ACTIVE","filters":{"groups":[{"properties":[],"rollout_percentage":50}],"payloads":{"true":"{\\"color\\":\\"blue\\"}"}},"has_encrypted_payloads":false,"created_by":null,"surveys":{},"usage_dashboard":9,"can_edit":true},'
			.. '{"id":4,"key":"stripe-config","name":"Remote config","active":true,"filters":{"groups":[],"payloads":{"true":"sk_live_secret"}},"has_encrypted_payloads":true,"is_remote_configuration":true}]}'}
		local flags = posthog.listFeatureFlags(12345, {active = true, search = "nav", key = "new-nav", type = "boolean", limit = 50})
		assert(last() == P .. "/feature_flags/?active=true&key=new-nav&search=nav&type=boolean&limit=50", last())
		assert(flags.results[1].filters.groups[1].rollout_percentage == 50 and flags.results[1].filters.payloads["true"] == '{"color":"blue"}')
		assert(flags.results[1].created_by == NULL and flags.results[1].surveys == nil and flags.results[1].usage_dashboard == nil and flags.results[1].can_edit == nil)
		assert(flags.results[2].filters.payloads["true"] == "(encrypted)", "decrypted remote config payloads must be redacted")
		payloads = {'{"count":0,"next":null,"previous":null,"results":[]}'}
		assert(json.encode(posthog.listFeatureFlags(12345, {active = "STALE"}).results) == "[]" and last() == P .. "/feature_flags/?active=STALE&limit=100")

		payloads = {'{"columns":["day","pageviews"],"types":[["day","Date"],["pageviews","UInt64"]],"results":[["2026-10-28",10],["2026-10-29",12]],"hasMore":false,"hogql":"SELECT ...","clickhouse":"SELECT ...","timings":[{"k":"x","t":1}],"is_cached":false}'}
		local sql = "select toDate(timestamp) as day, count() as pageviews from events where event = {name} group by day"
		local result = posthog.query(12345, sql, {values = {name = "$pageview"}, name = "daily pageviews"})
		local request = requests[#requests]
		assert(request.method == "POST" and request.url == P .. "/query/", request.url)
		local body = json.decode(request.body)
		assert(body.query.kind == "HogQLQuery" and body.query.query == sql and body.query.values.name == "$pageview")
		assert(body.refresh == "blocking" and body.name == "daily pageviews" and body.client_query_id == nil)
		assert(result.columns[2] == "pageviews" and result.types[1][2] == "Date" and result.results[2][2] == 12 and result.hasMore == false and result.truncated == false)
		assert(result.hogql == nil and result.clickhouse == nil and result.timings == nil, "query results must stay compact")
		local rows = {}
		for index = 1, 1001 do rows[index] = {index} end
		payloads = {json.encode({columns = {"n"}, types = {{"n", "Int64"}}, results = rows, hasMore = true})}
		local big = posthog.query("12345", "select number as n from numbers(1001)")
		assert(json.decode(requests[#requests].body).name == "houston" and json.decode(requests[#requests].body).query.values == nil)
		assert(#big.results == 1000 and big.results[1000][1] == 1000 and big.truncated == true and big.hasMore == true)
		payloads = {'{"columns":["n"],"types":[["n","Int64"]],"results":[],"hasMore":false}'}
		local empty = posthog.query(12345, "select 1 where 0")
		assert(json.encode(empty.results) == "[]" and empty.truncated == false)

		rejected(function() posthog.listEvents() end, "project must be")
		rejected(function() posthog.listEvents(0) end, "project must be")
		rejected(function() posthog.listEvents(12.5) end, "project must be")
		rejected(function() posthog.listEvents("12345/../1") end, "project must be")
		rejected(function() posthog.listEvents("current") end, "project must be")
		rejected(function() posthog.listEvents(12345, "next") end, "must be a table")
		rejected(function() posthog.listEvents(12345, {limit = 0}) end, "1 to 1000")
		rejected(function() posthog.listEvents(12345, {limit = 1001}) end, "1 to 1000")
		rejected(function() posthog.listEvents(12345, {limit = 2.5}) end, "1 to 1000")
		rejected(function() posthog.listEvents(12345, {select = {"*"}}) end, "unknown option select")
		rejected(function() posthog.listEvents(12345, {event = ""}) end, "nonempty string")
		rejected(function() posthog.listEvents(12345, {event = string.rep("x", 1001)}) end, "nonempty string")
		rejected(function() posthog.listEvents(12345, {properties = {}}) end, "property filters")
		rejected(function() posthog.listEvents(12345, {properties = {key = "plan"}}) end, "property filters")
		rejected(function() posthog.listEvents(12345, {include_person = "yes"}) end, "include_person must be one of true, false")
		rejected(function() posthog.listEvents(12345, {next = "https://us.posthog.com/api/projects/12345/events/"}) end, "next link")
		rejected(function() posthog.listEvents(12345, {next = "https://us.posthog.com/projects/12345/events?offset=1"}) end, "next link")
		rejected(function() posthog.listEvents(12345, {next = events.next, event = "$pageview"}) end, "takes only limit with next")
		rejected(function() posthog.listInsights(12345, {next = "/api/?refresh=force_blocking"}) end, "next link")
		rejected(function() posthog.listEvents(999, {next = events.next}) end, "same project")
		rejected(function() posthog.listPersons(12345, {next = events.next}) end, "next link")
		rejected(function() posthog.listProjects({next = "https://us.posthog.com/api/organizations/" .. ORG .. "/projects/?offset=5"}) end, "same project or organization")
		rejected(function() posthog.query(12345, "select 1", {name = string.rep("x", 129)}) end, "128 characters")
		rejected(function() posthog.listInsights(12345, {next = "/api/projects/12345/insights/?basic=false&offset=100"}) end, "next link")
		rejected(function() posthog.listEvents(12345, {next = "/api/projects/12345/events/?select=%5B%22*%22%5D"}) end, "next link")
		rejected(function() posthog.listEvents(12345, {next = "/api/projects/12345/persons/?search=ana"}) end, "next link")
		rejected(function() posthog.listPersons(12345, {next = "/api/projects/12345/persons/?offset=1x"}) end, "next link")
		rejected(function() posthog.listPersons(12345, {next = "/api/projects/12345/persons/?format=csv&offset=100"}) end, "next link")
		rejected(function() posthog.listProjects({organization = "acme"}) end, "organization uuid")
		rejected(function() posthog.listOrganizations({organization = ORG}) end, "unknown option organization")
		rejected(function() posthog.listInsights(12345, {insight = "trends"}) end, "insight must be one of")
		rejected(function() posthog.listInsights(12345, {favorited = true}) end, "unknown option favorited")
		rejected(function() posthog.listFeatureFlags(12345, {active = "stale"}) end, "active must be one of")
		rejected(function() posthog.getInsight(12345) end, "short_id")
		rejected(function() posthog.getInsight(12345, "AaVQ8Ij/") end, "short_id")
		rejected(function() posthog.getInsight(12345, "AaVQ8Ijw1") end, "short_id")
		rejected(function() posthog.getInsight(12345, 7, {refresh = "force_blocking"}) end, "refresh must be one of force_cache, blocking")
		rejected(function() posthog.getInsight(12345, 7, {include_dashboards = true}) end, "unknown option include_dashboards")
		rejected(function() posthog.query(12345, "  ") end, "nonempty HogQL")
		rejected(function() posthog.query(12345, string.rep("x", 32 * 1024 + 1)) end, "nonempty HogQL")
		rejected(function() posthog.query(12345, {kind = "HogQLQuery"}) end, "nonempty HogQL")
		rejected(function() posthog.query(12345, "select 1", {values = {"x"}}) end, "placeholder values")
		rejected(function() posthog.query(12345, "select 1", {refresh = "force_async"}) end, "unknown option refresh")
		rejected(function() posthog.query("abc", "select 1") end, "project must be")
	end,
}
