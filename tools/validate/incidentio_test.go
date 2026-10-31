package main

import "testing"

// incident.io API keys carry their own permissions, but the proxy still allows writes only on
// read-write connections, and never API key, secret or notification-method management.
func TestIncidentioAccessRoutes(t *testing.T) {
	m := parseManifest(t, "../../connectors/incidentio/houston.json")
	const api = "https://api.incident.io"
	for _, access := range []string{"read-only", "read-write"} {
		r, err := m.Resolve(nil, map[string]any{"access": access}, map[string]any{"token": "inc_fixture"}, "token")
		if err != nil {
			t.Fatal(err)
		}
		assertRoutes(t, r, "inc_fixture", true,
			"GET "+api+"/v1/identity", "GET "+api+"/v2/incidents?status_category%5Bone_of%5D=live&page_size=25", "GET "+api+"/v2/incidents/42",
			"GET "+api+"/v2/incident_updates?incident_id=01HZINC", "GET "+api+"/v2/incident_timeline_items?incident_id=01HZINC",
			"GET "+api+"/v2/incident_alerts?page_size=50", "GET "+api+"/v3/follow_ups?incident_id=01HZINC", "GET "+api+"/v3/follow_ups/01HZFU",
			"GET "+api+"/v2/alerts?page_size=25", "GET "+api+"/v2/alerts/01HZAL", "GET "+api+"/v2/schedules", "GET "+api+"/v2/schedules/01HZSC",
			"GET "+api+"/v2/schedule_entries?schedule_id=01HZSC", "GET "+api+"/v2/users?email=ada%40example.com", "GET "+api+"/v2/users/01HZU",
			"GET "+api+"/v3/teams", "GET "+api+"/v1/severities", "GET "+api+"/v1/incident_statuses", "GET "+api+"/v1/incident_types",
			"GET "+api+"/v2/incident_roles", "GET "+api+"/v2/incident_timestamps", "GET "+api+"/v2/custom_fields",
			"GET "+api+"/v1/custom_field_options?custom_field_id=01HZCF", "GET "+api+"/v3/catalog_types",
			"GET "+api+"/v3/catalog_entries?catalog_type_id=01HZCT", "GET "+api+"/v3/catalog_entries/01HZCE?expand=true")
		assertRoutes(t, r, "inc_fixture", access == "read-write",
			"POST "+api+"/v2/incidents", "POST "+api+"/v2/incidents/01HZINC/actions/edit", "POST "+api+"/v2/incident_updates", "POST "+api+"/v3/follow_ups")
		// Other writes, deprecated routes, credentials, secrets, phone numbers, other hosts and traversal stay denied.
		assertRoutes(t, r, "inc_fixture", false,
			"PUT "+api+"/v3/follow_ups/01HZFU", "DELETE "+api+"/v3/follow_ups/01HZFU", "POST "+api+"/v3/follow_ups/01HZFU/actions/connect_external_issue",
			"POST "+api+"/v2/incidents/01HZINC/actions/connect_external_issue", "POST "+api+"/v2/incidents/01HZINC", "PATCH "+api+"/v2/incidents/01HZINC",
			"DELETE "+api+"/v2/incidents/01HZINC", "POST "+api+"/v2/alerts/01HZAL/actions/resolve", "POST "+api+"/v2/escalations",
			"POST "+api+"/v2/alert_events/http/01HZSRC", "POST "+api+"/v2/incident_alerts", "POST "+api+"/v1/incident_memberships",
			"POST "+api+"/v3/catalog_entries", "PUT "+api+"/v3/catalog_entries/01HZCE", "POST "+api+"/v2/schedule_overrides", "POST "+api+"/v2/status_page_incidents",
			"GET "+api+"/v1/incidents", "POST "+api+"/v1/incidents", "GET "+api+"/v2/follow_ups", "POST "+api+"/v2/follow_ups", "GET "+api+"/v2/catalog_entries",
			"GET "+api+"/v1/api_keys", "POST "+api+"/v1/api_keys", "POST "+api+"/v1/api_keys/01HZK/actions/rotate", "GET "+api+"/v2/secrets",
			"GET "+api+"/v2/users/01HZU/notification_methods", "GET "+api+"/v2/users/01HZU/paging_provider", "GET "+api+"/v1/ip_allowlists",
			"GET "+api+"/v2/incidents/%2e%2e", "GET "+api+"/v2/incidents/01HZINC/actions/edit", "GET "+api+"/v2/incidents/",
			"GET https://app.incident.io/api/incidents", "GET https://api.incident.io.example.com/v2/incidents", "GET http://api.incident.io/v2/incidents",
			"GET https://api.incident.io:8443/v2/incidents")
	}
}
