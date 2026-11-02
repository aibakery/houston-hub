package main

import "testing"

func TestAttioReadOnlyRoutes(t *testing.T) {
	m := parseManifest(t, "../../connectors/attio/houston.json")
	if _, err := m.Resolve(nil, nil, nil, "token"); err == nil {
		t.Fatal("accepted missing API key")
	}
	r, err := m.Resolve(nil, nil, map[string]any{"token": "attio_fixture"}, "token")
	if err != nil {
		t.Fatal(err)
	}
	const api = "https://api.attio.com/v2"
	const id = "891dcbfc-9141-415d-9b2a-2238a6cc012d"
	assertRoutes(t, r, "attio_fixture", true,
		"GET "+api+"/self", "GET "+api+"/objects", "GET "+api+"/objects/people/attributes?limit=20",
		"GET "+api+"/objects/people/records/"+id, "GET "+api+"/notes?parent_object=people", "GET "+api+"/notes/"+id,
		"GET "+api+"/emails?domain=example.com", "GET "+api+"/tasks", "GET "+api+"/tasks/"+id, "GET "+api+"/threads",
		"GET "+api+"/threads/"+id+"?cursor=c1", "GET "+api+"/comments/"+id, "GET "+api+"/meetings", "GET "+api+"/meetings/"+id,
		"GET "+api+"/meetings/"+id+"/call_recordings", "GET "+api+"/meetings/"+id+"/call_recordings/"+id,
		"GET "+api+"/lists", "GET "+api+"/lists/sales", "GET "+api+"/lists/sales/attributes",
		"GET "+api+"/workspace_members", "GET "+api+"/workspace_members/"+id, "GET "+api+"/files?object=people", "GET "+api+"/files/"+id,
		"POST "+api+"/objects/people/records/query", "POST "+api+"/objects/records/search", "POST "+api+"/lists/sales/entries/query")
	// Writes, webhooks (whose creation returns signing secrets), file downloads that
	// redirect to signed storage, SQL and the deprecated transcript route stay denied.
	assertRoutes(t, r, "attio_fixture", false,
		"POST "+api+"/objects/people/records", "PUT "+api+"/objects/people/records", "PATCH "+api+"/objects/people/records/"+id,
		"DELETE "+api+"/objects/people/records/"+id, "POST "+api+"/notes", "DELETE "+api+"/notes/"+id, "POST "+api+"/tasks",
		"POST "+api+"/comments", "POST "+api+"/lists/sales/entries", "HEAD "+api+"/self",
		"GET "+api+"/webhooks", "POST "+api+"/webhooks", "GET "+api+"/webhooks/"+id, "GET "+api+"/files/"+id+"/download",
		"GET "+api+"/meetings/"+id+"/call_recordings/"+id+"/transcript", "POST "+api+"/sql",
		"GET "+api+"/activities/calls/attributes", "GET "+api+"/objects/%2e%2e/records/"+id, "GET "+api+"/objects/people/records/a%2Fb",
		"GET https://app.attio.com/oauth/token", "GET https://api.attio.com.example.com/v2/self", "GET http://api.attio.com:8080/v2/self")
}
