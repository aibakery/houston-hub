return {
	scenario = {publisher = {}, config = {}, auth_method = "token", auth_config = {token = "fixture-token"}},
	configure = function()
		requests = {}
		payload = "{}"
		http = {request = function(req)
			table.insert(requests, req)
			return fixture.operation({statusCode = 200, headers = {}, body = fixture.reader(payload)})
		end}
	end,
	run = function(incidentio)
		local API = "https://api.incident.io"
		local NULL = json.decode("null")
		local function last() return requests[#requests] end
		local function got(target)
			local req = last()
			assert(req.method == "GET" and req.url == API .. target, req.method .. " " .. req.url)
			assert(req.body == nil and req.headers.Authorization == nil and req.headers.Accept[1] == "application/json" and req.headers["Content-Type"] == nil)
			assert(req.timeoutMs == 15000, "missing header wait")
		end
		local function rejected(fn, expected)
			local before = #requests
			local ok, err = pcall(fn)
			assert(not ok and string.find(tostring(err), expected, 1, true), "wrong validation error: " .. tostring(err))
			assert(#requests == before, "invalid input reached incident.io")
		end

		local names = {}
		for name in incidentio do table.insert(names, name) end
		table.sort(names)
		assert(table.concat(names, ",") == "getAlert,getCatalogEntry,getFollowUp,getIdentity,getIncident,getSchedule,getUser,listAlerts,listCatalogEntries,listCatalogTypes,listCustomFieldOptions,listCustomFields,listFollowUps,listIncidentAlerts,listIncidentRoles,listIncidentStatuses,listIncidentTimelineItems,listIncidentTimestamps,listIncidentTypes,listIncidentUpdates,listIncidents,listScheduleEntries,listSchedules,listSeverities,listTeams,listUsers",
			"wrong read-only surface: " .. table.concat(names, ","))
		assert(#requests == 0, "initialization reached incident.io")

		payload = '{"identity":{"name":"Houston","roles":["viewer","catalog_viewer"],"team_roles":[],"teams":[],"dashboard_url":"https://app.incident.io/acme"}}'
		assert(incidentio.getIdentity().identity.roles[2] == "catalog_viewer")
		got("/v1/identity")

		-- Incidents come back unchanged, nulls included, and filters become deep-object keys.
		payload = '{"incidents":[{"id":"01HZINC","reference":"INC-42","name":"Checkout down","summary":null,"call_url":null,'
			.. '"incident_status":{"id":"01HZST","name":"Investigating","category":"live"},"severity":{"id":"01HZSEV","name":"Major","rank":2},'
			.. '"incident_role_assignments":[{"role":{"id":"01HZLEAD","name":"Incident Lead","role_type":"lead"},"assignee":null}],'
			.. '"incident_timestamp_values":[{"incident_timestamp":{"id":"01HZTS","name":"Reported at","rank":1},"value":null}],'
			.. '"custom_field_entries":[]}],"pagination_meta":{"after":"01HZINC","page_size":2,"total_record_count":7}}'
		local opts = {status_category = {one_of = {"live", "triage"}}, severity = {gte = "01HZSEV"}, created_at = {date_range = "2026-10-01~2026-10-31"},
			custom_field = {["01HZCF"] = {one_of = {"01HZOPT"}}}, incident_role = {["01HZLEAD"] = {one_of = {"01HZU"}}}, mode = {one_of = {"standard", "test"}},
			filter_mode = "all", page_size = 2, after = "01HZPREV"}
		local page = incidentio.listIncidents(opts)
		got("/v2/incidents?status_category%5Bone_of%5D=live&status_category%5Bone_of%5D=triage&severity%5Bgte%5D=01HZSEV"
			.. "&incident_role%5B01HZLEAD%5D%5Bone_of%5D=01HZU&custom_field%5B01HZCF%5D%5Bone_of%5D=01HZOPT&mode%5Bone_of%5D=standard&mode%5Bone_of%5D=test"
			.. "&filter_mode=all&created_at%5Bdate_range%5D=2026-10-01~2026-10-31&page_size=2&after=01HZPREV")
		assert(opts.status_category.one_of[2] == "triage" and opts.page_size == 2, "caller options were modified")
		local incident = page.incidents[1]
		assert(incident.reference == "INC-42" and incident.summary == NULL and incident.call_url == NULL and incident.incident_role_assignments[1].assignee == NULL)
		assert(incident.incident_timestamp_values[1].value == NULL and json.encode(incident.custom_field_entries) == "[]" and page.pagination_meta.total_record_count == 7)

		-- The last page has no cursor; page_size defaults to incident.io's 25.
		payload = '{"incidents":[],"pagination_meta":{"page_size":25}}'
		page = incidentio.listIncidents({sort_by = "created_at_oldest_first", status = {not_in = "01HZST"}})
		got("/v2/incidents?status%5Bnot_in%5D=01HZST&sort_by=created_at_oldest_first&page_size=25")
		assert(json.encode(page.incidents) == "[]" and page.pagination_meta.after == nil)

		payload = '{"incident":{"id":"01HZINC","reference":"INC-42"}}'
		assert(incidentio.getIncident({id = 42}).incident.id == "01HZINC")
		got("/v2/incidents/42")
		incidentio.getIncident({id = "01HZINC"})
		got("/v2/incidents/01HZINC")

		payload = '{"incident_updates":[{"id":"01HZUP","incident_id":"01HZINC","message":"Rolled back","new_severity":null}],"pagination_meta":{"after":null,"page_size":25}}'
		local updates = incidentio.listIncidentUpdates({incident_id = "01HZINC"})
		got("/v2/incident_updates?incident_id=01HZINC&page_size=25")
		assert(updates.incident_updates[1].new_severity == NULL and updates.pagination_meta.after == NULL)
		incidentio.listIncidentTimelineItems({incident_id = "01HZINC", page_size = 250, after = "01HZTL"})
		got("/v2/incident_timeline_items?incident_id=01HZINC&page_size=250&after=01HZTL")
		incidentio.listIncidentAlerts({alert_id = "01HZAL", page_size = 50})
		got("/v2/incident_alerts?alert_id=01HZAL&page_size=50")
		payload = '{"follow_ups":[{"id":"01HZFU","title":"Add alerting","assignee":null,"status":"outstanding"}],"pagination_meta":{"page_size":25}}'
		assert(incidentio.listFollowUps({incident_id = "01HZINC", incident_mode = "standard", updated_at = {gte = {"2026-10-01"}}}).follow_ups[1].assignee == NULL)
		got("/v3/follow_ups?incident_id=01HZINC&incident_mode=standard&updated_at%5Bgte%5D=2026-10-01&page_size=25")
		incidentio.getFollowUp({id = "01HZFU"})
		got("/v3/follow_ups/01HZFU")

		payload = '{"alerts":[{"id":"01HZAL","title":"High error rate","status":"firing","resolved_at":null}],"pagination_meta":{"page_size":10}}'
		assert(incidentio.listAlerts({status = {one_of = {"firing"}}, tags = {one_of = {"known issue"}}, attributes = {["01HZAT"] = {one_of = {"api"}}}, page_size = 10}).alerts[1].resolved_at == NULL)
		got("/v2/alerts?status%5Bone_of%5D=firing&attributes%5B01HZAT%5D%5Bone_of%5D=api&tags%5Bone_of%5D=known%20issue&page_size=10")
		incidentio.getAlert({id = "01HZAL"})
		got("/v2/alerts/01HZAL")
		-- Caller ids stay inside their encoded filter key.
		incidentio.listAlerts({attributes = {["a&b=c"] = {is = "x&y"}}, has_notes = {is = {"true"}}})
		got("/v2/alerts?attributes%5Ba%26b%3Dc%5D%5Bis%5D=x%26y&has_notes%5Bis%5D=true&page_size=25")

		payload = '{"schedules":[{"id":"01HZSC","name":"Primary","current_shifts":[{"user":{"id":"01HZU","name":"Ada"},"start_at":"2026-10-30T09:00:00Z","end_at":"2026-10-31T09:00:00Z"}],"next_shifts":null}],"pagination_meta":{"page_size":25}}'
		local schedules = incidentio.listSchedules()
		got("/v2/schedules?page_size=25")
		assert(schedules.schedules[1].current_shifts[1].user.name == "Ada" and schedules.schedules[1].next_shifts == NULL)
		incidentio.getSchedule({id = "01HZSC"})
		got("/v2/schedules/01HZSC")
		payload = '{"schedule_entries":{"final":[{"user":{"id":"01HZU"},"start_at":"2026-11-02T09:00:00Z","end_at":"2026-11-03T09:00:00Z"}],"scheduled":[],"overrides":[]},"pagination_meta":{"after":"opaque+cursor/1"}}'
		local rota = incidentio.listScheduleEntries({schedule_id = "01HZSC", entry_window_start = "2026-11-02T00:00:00Z", entry_window_end = "2026-11-09T00:00:00Z"})
		got("/v2/schedule_entries?schedule_id=01HZSC&entry_window_start=2026-11-02T00%3A00%3A00Z&entry_window_end=2026-11-09T00%3A00%3A00Z")
		assert(rota.schedule_entries.final[1].user.id == "01HZU" and json.encode(rota.schedule_entries.overrides) == "[]")
		incidentio.listScheduleEntries({schedule_id = "01HZSC", entry_window_start = rota.pagination_meta.after, entry_window_end = "2026-11-09T00:00:00Z"})
		got("/v2/schedule_entries?schedule_id=01HZSC&entry_window_start=opaque%2Bcursor%2F1&entry_window_end=2026-11-09T00%3A00%3A00Z")

		incidentio.listUsers({email = "ada@example.com", include_inactive = true})
		got("/v2/users?email=ada%40example.com&include_inactive=true&page_size=25")
		incidentio.getUser({id = "01HZU"})
		got("/v2/users/01HZU")
		incidentio.listTeams({page_size = 100})
		got("/v3/teams?page_size=100")

		for name, target in {listSeverities = "/v1/severities", listIncidentStatuses = "/v1/incident_statuses", listIncidentTypes = "/v1/incident_types",
			listIncidentRoles = "/v2/incident_roles", listIncidentTimestamps = "/v2/incident_timestamps", listCustomFields = "/v2/custom_fields",
			listCatalogTypes = "/v3/catalog_types"} do
			incidentio[name]()
			got(target)
		end
		incidentio.listCustomFieldOptions({custom_field_id = "01HZCF"})
		got("/v1/custom_field_options?custom_field_id=01HZCF&page_size=25")
		payload = '{"catalog_entries":[{"id":"01HZCE","name":"checkout","external_id":null,"aliases":[],"attribute_values":{}}],"catalog_type":{"id":"01HZCT"},"pagination_meta":{"page_size":25}}'
		local entries = incidentio.listCatalogEntries({catalog_type_id = "01HZCT", identifier = "checkout"})
		got("/v3/catalog_entries?catalog_type_id=01HZCT&identifier=checkout&page_size=25")
		assert(entries.catalog_entries[1].external_id == NULL and json.encode(entries.catalog_entries[1].aliases) == "[]")
		incidentio.getCatalogEntry({id = "01HZCE", expand = true})
		got("/v3/catalog_entries/01HZCE?expand=true")
		assert(#requests == 30, tostring(#requests))

		-- Writes are absent, and invalid input never reaches incident.io.
		assert(incidentio.createIncident == nil and incidentio.editIncident == nil and incidentio.createIncidentUpdate == nil and incidentio.createFollowUp == nil)
		rejected(function() incidentio.getIncident() end, "id is required")
		rejected(function() incidentio.getIncident({id = "../v1/api_keys"}) end, "id must be an incident.io id")
		rejected(function() incidentio.getIncident({id = 1.5}) end, "id must be a string")
		rejected(function() incidentio.getIncident({id = NULL}) end, "id is required")
		rejected(function() incidentio.listScheduleEntries({}) end, "schedule_id is required")
		rejected(function() incidentio.listCatalogEntries({identifier = "x"}) end, "catalog_type_id is required")
		rejected(function() incidentio.listIncidentTimelineItems() end, "incident_id is required")
		rejected(function() incidentio.listIncidents({page_size = 251}) end, "page_size must be a whole number from 1 to 250")
		rejected(function() incidentio.listIncidents({page_size = "10"}) end, "page_size must be a whole number")
		rejected(function() incidentio.listIncidents({status = {one_of = json.decode("[]")}}) end, "status must not be an empty array")
		rejected(function() incidentio.listIncidents({status = {one_of = {nested = {}}, [1] = "x"}}) end, "status must be")
		rejected(function() incidentio.listIncidents({status = "01HZST"}) end, "status must be an object such as {one_of={...}}")
		rejected(function() incidentio.listAlerts({has_notes = true}) end, "has_notes must be an object")
		rejected(function() incidentio.listIncidents({mode = {"test"}}) end, "mode must be an object")
		rejected(function() incidentio.listIncidents({custom_field = {["01HZCF][one_of"] = {one_of = {"x"}}}}) end, "without [ or ]")
		rejected(function() incidentio.listAlerts({attributes = {["01HZAT"] = {["is]"] = "x"}}}) end, "without [ or ]")
		rejected(function() incidentio.listAlerts({page_size = 51}) end, "page_size must be a whole number from 1 to 50")
		rejected(function() incidentio.listIncidentAlerts({page_size = 100}) end, "page_size must be a whole number from 1 to 50")
		rejected(function() incidentio.listIncidents({severity = {gte = {{"x"}}}}) end, "severity must be a string, boolean, number or array")
		rejected(function() incidentio.listIncidents({incident_id = "x"}) end, "listIncidents has no option incident_id")
		rejected(function() incidentio.listIncidents("live") end, "opts must be an object")
	end,
}
