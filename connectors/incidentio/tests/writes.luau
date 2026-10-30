return {
	scenario = {publisher = {}, config = {access = "read-write"}, auth_method = "token", auth_config = {token = "fixture-token"}},
	configure = function()
		requests = {}
		status = 200
		payload = "{}"
		http = {request = function(req)
			table.insert(requests, req)
			return fixture.operation({statusCode = status, headers = {}, body = fixture.reader(payload)})
		end}
	end,
	run = function(incidentio)
		local API = "https://api.incident.io"
		local NULL = json.decode("null")
		local function sent(target, body)
			local req = requests[#requests]
			assert(req.method == "POST" and req.url == API .. target, req.method .. " " .. req.url)
			assert(req.headers.Authorization == nil and req.headers["Content-Type"][1] == "application/json" and req.headers.Accept[1] == "application/json")
			assert(json.encode(json.decode(req.body)) == json.encode(body), req.body)
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
		assert(table.concat(names, ",") == "createFollowUp,createIncident,createIncidentUpdate,editIncident,getAlert,getCatalogEntry,getFollowUp,getIdentity,getIncident,getSchedule,getUser,listAlerts,listCatalogEntries,listCatalogTypes,listCustomFieldOptions,listCustomFields,listFollowUps,listIncidentAlerts,listIncidentRoles,listIncidentStatuses,listIncidentTimelineItems,listIncidentTimestamps,listIncidentTypes,listIncidentUpdates,listIncidents,listScheduleEntries,listSchedules,listSeverities,listTeams,listUsers",
			"wrong read-write surface: " .. table.concat(names, ","))

		status, payload = 200, '{"incident":{"id":"01HZINC","reference":"INC-43","name":"Checkout down","summary":null,"mode":"standard"}}'
		local declared = {idempotency_key = "houston-checkout-2026-10-30", visibility = "public", name = "Checkout down", severity_id = "01HZSEV",
			incident_role_assignments = {{incident_role_id = "01HZLEAD", assignee = {email = "ada@example.com"}}},
			custom_field_entries = {{custom_field_id = "01HZCF", values = {{value_option_id = "01HZOPT"}}}}}
		local incident = incidentio.createIncident(declared).incident
		sent("/v2/incidents", declared)
		assert(incident.reference == "INC-43" and incident.summary == NULL)
		local retro = {idempotency_key = "import-7", visibility = "private", name = "Old outage", mode = "retrospective",
			retrospective_incident_options = {external_id = 7}, incident_timestamp_values = {{incident_timestamp_id = "01HZTS", value = "2026-01-02T03:04:05Z"}}}
		incidentio.createIncident(retro)
		sent("/v2/incidents", retro)

		status, payload = 200, '{"incident":{"id":"01HZINC","incident_status":{"category":"learning"}}}'
		local edit = {incident = {incident_status_id = "01HZRES", summary = "Rolled back the deploy"}, notify_incident_channel = false}
		assert(incidentio.editIncident({id = "01HZINC", incident = edit.incident, notify_incident_channel = false}).incident.incident_status.category == "learning")
		sent("/v2/incidents/01HZINC/actions/edit", edit)
		incidentio.editIncident({id = "01HZINC2", incident = {severity_id = "01HZSEV2"}, notify_incident_channel = true})
		sent("/v2/incidents/01HZINC2/actions/edit", {incident = {severity_id = "01HZSEV2"}, notify_incident_channel = true})
		-- An explicit null is sent as JSON null.
		incidentio.editIncident({id = "01HZINC", incident = {call_url = NULL}, notify_incident_channel = false})
		assert(string.find(requests[#requests].body, '"incident":{"call_url":null}', 1, true), requests[#requests].body)

		status, payload = 201, '{"incident_update":{"id":"01HZUP","incident_id":"01HZINC","message":"Monitoring","new_severity":null}}'
		local update = {incident_id = "01HZINC", idempotency_key = "houston-update-1", message = "Monitoring the fix", to_incident_status_id = "01HZMON"}
		assert(incidentio.createIncidentUpdate(update).incident_update.new_severity == NULL)
		sent("/v2/incident_updates", update)

		status, payload = 201, '{"follow_up":{"id":"01HZFU","title":"Add a canary","status":"outstanding","assignee":null}}'
		local follow = {incident_id = "01HZINC", title = "Add a canary", description = "Gate deploys on **error rate**.", assignee_id = "01HZU", labels = {"deploys"}}
		assert(incidentio.createFollowUp(follow).follow_up.status == "outstanding")
		sent("/v3/follow_ups", follow)
		assert(#requests == 7)

		-- Required fields and unknown options fail before any request.
		rejected(function() incidentio.createIncident({visibility = "public", name = "x"}) end, "idempotency_key is required")
		rejected(function() incidentio.createIncident({idempotency_key = "k", name = "x"}) end, "visibility is required")
		rejected(function() incidentio.createIncident({idempotency_key = "k", visibility = "public", slack_channel_id = "C1"}) end, "createIncident has no option slack_channel_id")
		rejected(function() incidentio.editIncident({id = "01HZINC", incident = {name = "x"}}) end, "notify_incident_channel is required")
		rejected(function() incidentio.editIncident({incident = {name = "x"}, notify_incident_channel = false}) end, "id is required")
		rejected(function() incidentio.editIncident({id = "01HZINC/actions/merge", incident = {}, notify_incident_channel = false}) end, "id must be an incident.io id")
		rejected(function() incidentio.createIncidentUpdate({incident_id = "01HZINC", message = "x"}) end, "idempotency_key is required")
		rejected(function() incidentio.createFollowUp({incident_id = "01HZINC"}) end, "title is required")
		rejected(function() incidentio.createFollowUp({incident_id = "01HZINC", title = "x", status = "completed"}) end, "createFollowUp has no option status")
	end,
}
