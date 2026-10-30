return {
	scenario = {publisher = {}, config = {}, auth_method = "token", auth_config = {token = "fixture-token"}},
	configure = function()
		requests = {}
		payload = '{"success":true,"errors":[],"messages":[],"result":[]}'
		http = {request = function(req)
			table.insert(requests, req)
			return fixture.operation({statusCode = 200, headers = {}, body = fixture.reader(payload)})
		end}
	end,
	run = function(cloudflare)
		local API = "https://api.cloudflare.com/client/v4"
		local ACCOUNT = "0123456789abcdef0123456789abcdef"
		local ZONE = "023e105f4ecef8ad9ca31a8372d0c353"
		local NULL = json.decode("null")
		local function last() return requests[#requests] end
		local function got(target)
			local req = last()
			assert(req.method == "GET" and req.url == target and req.body == nil, req.method .. " " .. req.url)
			assert(req.headers.Accept[1] == "application/json" and req.headers.Authorization == nil and req.headers["Content-Type"] == nil)
		end
		local function rejected(fn, expected)
			local before = #requests
			local ok, err = pcall(fn)
			assert(not ok and string.find(tostring(err), expected, 1, true), "wrong validation error: " .. tostring(err))
			assert(#requests == before, "invalid input reached Cloudflare")
		end

		local names = {}
		for name in cloudflare do table.insert(names, name) end
		table.sort(names)
		assert(table.concat(names, ",") == "getAccount,getDnsRecord,getPagesDeployment,getPagesDeploymentLogs,getPagesProject,getR2Bucket,getWorkerVersion,getZone,getZoneAnalytics,listAccounts,listDnsRecords,listPagesDeployments,listPagesProjects,listR2Buckets,listWorkerDeployments,listWorkerScripts,listWorkerVersions,listZones",
			"wrong read-only surface: " .. table.concat(names, ","))
		assert(#requests == 0, "initialization reached Cloudflare")

		-- An empty list comes back unchanged.
		local accounts = cloudflare.listAccounts()
		got(API .. "/accounts")
		assert(accounts.success == true and json.encode(accounts.result) == "[]", json.encode(accounts))
		cloudflare.listAccounts({name = "Acme Inc", page = 2, per_page = 50})
		got(API .. "/accounts?name=Acme%20Inc&page=2&per_page=50")
		cloudflare.getAccount({account_id = ACCOUNT})
		got(API .. "/accounts/" .. ACCOUNT)

		-- Populated results keep Cloudflare's nulls and paging fields.
		payload = '{"success":true,"errors":[],"messages":[],"result":[{"id":"' .. ZONE .. '","name":"example.com","status":"active","paused":false,'
			.. '"account":{"id":"' .. ACCOUNT .. '","name":"Acme"},"owner":{"id":null,"type":"user","email":null},"vanity_name_servers":null}],'
			.. '"result_info":{"page":1,"per_page":20,"count":1,"total_count":21,"total_pages":2}}'
		local zones = cloudflare.listZones({name = "contains:example", type = {"full", "partial"}, ["account.id"] = ACCOUNT, status = "active", page = 1})
		got(API .. "/zones?name=contains%3Aexample&status=active&type=full,partial&account.id=" .. ACCOUNT .. "&page=1")
		local zone = zones.result[1]
		assert(zone.name == "example.com" and zone.owner.id == NULL and zone.vanity_name_servers == NULL and zones.result_info.total_pages == 2, json.encode(zones))
		cloudflare.getZone({zone_id = ZONE})
		got(API .. "/zones/" .. ZONE)

		payload = '{"success":true,"errors":[],"messages":[],"result":[{"id":"372e67954025e0ba6aaa6d586b9e0b59","type":"CNAME","name":"www.example.com",'
			.. '"content":"example.com","proxied":true,"ttl":1,"comment":null,"tags":[],"settings":{"flatten_cname":false}}],"result_info":{"page":1,"per_page":1000,"count":1,"total_count":1,"total_pages":1}}'
		local records = cloudflare.listDnsRecords({zone_id = ZONE, type = "CNAME", ["name.endswith"] = ".example.com", proxied = true, search = "www", per_page = 1000})
		got(API .. "/zones/" .. ZONE .. "/dns_records?type=CNAME&name.endswith=.example.com&proxied=true&search=www&per_page=1000")
		assert(records.result[1].comment == NULL and records.result[1].proxied == true)
		cloudflare.getDnsRecord({zone_id = ZONE, dns_record_id = "372e67954025e0ba6aaa6d586b9e0b59"})
		got(API .. "/zones/" .. ZONE .. "/dns_records/372e67954025e0ba6aaa6d586b9e0b59")

		payload = '{"success":true,"errors":[],"messages":[],"result":[{"id":"api","created_on":"2026-10-01T00:00:00Z","tags":null}]}'
		assert(cloudflare.listWorkerScripts({account_id = ACCOUNT, tags = "prod:yes"}).result[1].id == "api")
		got(API .. "/accounts/" .. ACCOUNT .. "/workers/scripts?tags=prod%3Ayes")
		local SCRIPT = API .. "/accounts/" .. ACCOUNT .. "/workers/scripts/api"
		cloudflare.listWorkerDeployments({account_id = ACCOUNT, script_name = "api", per_page = 5})
		got(SCRIPT .. "/deployments?per_page=5")
		cloudflare.listWorkerVersions({account_id = ACCOUNT, script_name = "api", deployable = true, page = 2})
		got(SCRIPT .. "/versions?deployable=true&page=2")
		cloudflare.getWorkerVersion({account_id = ACCOUNT, script_name = "api", version_id = "bcf48806-b317-4351-9ee7-36e7d557d4de"})
		got(SCRIPT .. "/versions/bcf48806-b317-4351-9ee7-36e7d557d4de")

		local PAGES = API .. "/accounts/" .. ACCOUNT .. "/pages/projects"
		cloudflare.listPagesProjects({account_id = ACCOUNT})
		got(PAGES)
		cloudflare.getPagesProject({account_id = ACCOUNT, project_name = "site"})
		got(PAGES .. "/site")
		cloudflare.listPagesDeployments({account_id = ACCOUNT, project_name = "site", env = "production", per_page = 10})
		got(PAGES .. "/site/deployments?env=production&per_page=10")
		cloudflare.getPagesDeployment({account_id = ACCOUNT, project_name = "site", deployment_id = "4f0b3a52-3c5d-4b6c-9c1a-1d2e3f4a5b6c"})
		got(PAGES .. "/site/deployments/4f0b3a52-3c5d-4b6c-9c1a-1d2e3f4a5b6c")
		payload = '{"success":true,"errors":[],"messages":[],"result":{"total":2,"includes_container_logs":true,"data":[{"ts":"2026-10-30T10:00:00Z","line":"Cloning repository..."},{"ts":"2026-10-30T10:00:05Z","line":"Success: Build complete!"}]}}'
		local logs = cloudflare.getPagesDeploymentLogs({account_id = ACCOUNT, project_name = "site", deployment_id = "4f0b3a52-3c5d-4b6c-9c1a-1d2e3f4a5b6c"})
		got(PAGES .. "/site/deployments/4f0b3a52-3c5d-4b6c-9c1a-1d2e3f4a5b6c/history/logs")
		assert(logs.result.total == 2 and logs.result.data[2].line == "Success: Build complete!")

		-- R2 pages with a cursor, and a jurisdiction travels as Cloudflare's header.
		payload = '{"success":true,"errors":[],"messages":[],"result":{"buckets":[{"name":"assets","creation_date":"2026-01-01T00:00:00Z","location":"WEUR","jurisdiction":"eu"}]},"result_info":{"cursor":"YXNzZXRz","per_page":1}}'
		local buckets = cloudflare.listR2Buckets({account_id = ACCOUNT, per_page = 1, cursor = "YXNzZXRz", jurisdiction = "eu"})
		assert(last().url == API .. "/accounts/" .. ACCOUNT .. "/r2/buckets?per_page=1&cursor=YXNzZXRz" and last().headers["cf-r2-jurisdiction"][1] == "eu", last().url)
		assert(buckets.result.buckets[1].name == "assets" and buckets.result_info.cursor == "YXNzZXRz")
		cloudflare.getR2Bucket({account_id = ACCOUNT, bucket_name = "assets"})
		got(API .. "/accounts/" .. ACCOUNT .. "/r2/buckets/assets")
		assert(last().headers["cf-r2-jurisdiction"] == nil)
		cloudflare.getR2Bucket({account_id = ACCOUNT, bucket_name = "records", jurisdiction = "fedramp-high"})
		assert(last().url == API .. "/accounts/" .. ACCOUNT .. "/r2/buckets/records" and last().headers["cf-r2-jurisdiction"][1] == "fedramp-high")

		-- Analytics send a fixed GraphQL query, with caller values only as variables.
		payload = '{"data":{"viewer":{"zones":[{"groups":[{"dimensions":{"date":"2026-10-01"},"sum":{"requests":1200,"cachedRequests":800,"bytes":5000000,'
			.. '"responseStatusMap":[{"edgeResponseStatus":200,"requests":1100},{"edgeResponseStatus":404,"requests":100}]},"uniq":{"uniques":90}}]}]}},"errors":null}'
		local traffic = cloudflare.getZoneAnalytics({zone_id = string.upper(ZONE), since = "2026-10-01", ["until"] = "2026-10-07", breakdowns = {"responseStatusMap", "countryMap"}})
		local req = last()
		assert(req.method == "POST" and req.url == API .. "/graphql" and req.headers["Content-Type"][1] == "application/json" and req.headers.Authorization == nil)
		local sent = json.decode(req.body)
		assert(json.encode(sent.variables) == json.encode({zoneTag = ZONE, since = "2026-10-01", ["until"] = "2026-10-07"}), req.body)
		assert(sent.query == "query ZoneAnalytics($zoneTag: string, $since: Date, $until: Date) { viewer { zones(filter: {zoneTag: $zoneTag}) { "
			.. "groups: httpRequests1dGroups(limit: 100, orderBy: [date_ASC], filter: {date_geq: $since, date_leq: $until}) { dimensions { date } "
			.. "sum { requests cachedRequests bytes cachedBytes encryptedRequests encryptedBytes threats pageViews responseStatusMap { edgeResponseStatus requests } "
			.. "countryMap { clientCountryName requests bytes threats } } uniq { uniques } } } } }", sent.query)
		local group = traffic.data.viewer.zones[1].groups[1]
		assert(traffic.errors == NULL and group.sum.requests == 1200 and group.sum.responseStatusMap[2].edgeResponseStatus == 404 and group.uniq.uniques == 90)

		payload = '{"data":{"viewer":{"zones":[{"groups":[]}]}},"errors":null}'
		local hourly = cloudflare.getZoneAnalytics({zone_id = ZONE, granularity = "hour", since = "2026-10-29T00:00:00Z", ["until"] = "2026-10-30T00:00:00Z"})
		sent = json.decode(last().body)
		assert(sent.query == "query ZoneAnalytics($zoneTag: string, $since: Time, $until: Time) { viewer { zones(filter: {zoneTag: $zoneTag}) { "
			.. "groups: httpRequests1hGroups(limit: 1000, orderBy: [datetime_ASC], filter: {datetime_geq: $since, datetime_lt: $until}) { dimensions { datetime } "
			.. "sum { requests cachedRequests bytes cachedBytes encryptedRequests encryptedBytes threats pageViews } uniq { uniques } } } } }", sent.query)
		assert(json.encode(hourly.data.viewer.zones[1].groups) == "[]")

		local analytics = {zone_id = ZONE, since = "2026-10-01", ["until"] = "2026-10-07"}
		local function variant(changes)
			local args = table.clone(analytics)
			for key, value in changes do args[key] = value end
			return function() cloudflare.getZoneAnalytics(args) end
		end
		rejected(variant({granularity = "minute"}), "granularity must be day or hour")
		rejected(variant({zone_id = 'x") { secret }'}), "zone_id must be a zone id")
		rejected(variant({since = "2026-10-01T00:00:00Z"}), "since must be a real date such as 2026-10-01")
		rejected(variant({granularity = "hour"}), "since must be a real whole UTC hour such as 2026-10-01T00:00:00Z")
		rejected(variant({since = "2026-13-01"}), "since must be a real date")
		rejected(variant({["until"] = "2026-02-29"}), "until must be a real date")
		rejected(variant({granularity = "hour", since = "2026-10-01T24:00:00Z", ["until"] = "2026-10-02T01:00:00Z"}), "since must be a real whole UTC hour")
		rejected(variant({granularity = "hour", since = "2026-10-01T00:00:00Z", ["until"] = "2026-10-01T10:30:00Z"}), "until must be a real whole UTC hour")
		rejected(variant({["until"] = "2026-09-30"}), "since must come before until")
		rejected(variant({granularity = "hour", since = "2026-10-01T00:00:00Z", ["until"] = "2026-10-01T00:00:00Z"}), "since must come before until")
		rejected(variant({breakdowns = {"countryMap { secret }"}}), "breakdowns has no item")
		rejected(variant({breakdowns = "countryMap"}), "breakdowns must be an array")
		rejected(variant({["until"] = NULL}), "until is required")
		rejected(variant({limit = 5}), "getZoneAnalytics has no option limit")
		-- A request spans at most 1000 days or hours, or 100 with breakdowns, counted across leap days.
		payload = '{"data":{"viewer":{"zones":[{"groups":[]}]}},"errors":null}'
		cloudflare.getZoneAnalytics({zone_id = ZONE, since = "2024-02-29", ["until"] = "2024-02-29", breakdowns = {"countryMap"}})
cloudflare.getZoneAnalytics({zone_id = ZONE, since = "2024-01-01", ["until"] = "2024-04-09", breakdowns = {"countryMap"}})
		assert(string.find(json.decode(last().body).query, "(limit: 100,", 1, true))
		cloudflare.getZoneAnalytics({zone_id = ZONE, since = "2023-12-31", ["until"] = "2026-09-25"})
		cloudflare.getZoneAnalytics({zone_id = ZONE, granularity = "hour", since = "2024-02-28T00:00:00Z", ["until"] = "2024-04-09T16:00:00Z"})
		rejected(variant({since = "2024-01-01", ["until"] = "2024-04-10", breakdowns = {"countryMap"}}), "since to until spans 101 days; ask for at most 100")
		rejected(variant({since = "2023-12-31", ["until"] = "2026-09-26"}), "since to until spans 1001 days; ask for at most 1000")
		rejected(variant({granularity = "hour", since = "2024-02-28T00:00:00Z", ["until"] = "2024-04-09T17:00:00Z"}), "spans 1001 hours; ask for at most 1000")

		rejected(function() cloudflare.getZone() end, "zone_id is required")
		rejected(function() cloudflare.getZone({zone_id = "../accounts"}) end, "zone_id must be a Cloudflare id or name")
		rejected(function() cloudflare.getDnsRecord({zone_id = ZONE, dns_record_id = ".."}) end, "dns_record_id must be a Cloudflare id or name")
		rejected(function() cloudflare.listDnsRecords({zone_id = ZONE, per_page = 1001}) end, "per_page must be 1 to 1000")
		rejected(function() cloudflare.listZones({type = {}}) end, "type must not be an empty array")
		rejected(function() cloudflare.listZones({account = {id = ACCOUNT}}) end, "listZones has no option account")
		rejected(function() cloudflare.listR2Buckets({account_id = ACCOUNT, jurisdiction = "eu\r\nX-Evil: 1"}) end, "jurisdiction must be a name such as eu")
		rejected(function() cloudflare.listAccounts("acme") end, "opts must be an object")
	end,
}
