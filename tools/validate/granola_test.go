package main

import "testing"

func TestGranolaReadOnlyRoutes(t *testing.T) {
	m := parseManifest(t, "../../connectors/granola/houston.json")
	if _, err := m.Resolve(nil, nil, nil, "token"); err == nil {
		t.Fatal("accepted missing API key")
	}
	r, err := m.Resolve(nil, nil, map[string]any{"token": "grn_fixture"}, "token")
	if err != nil {
		t.Fatal(err)
	}
	const api = "https://public-api.granola.ai/v1"
	assertRoutes(t, r, "grn_fixture", true,
		"GET "+api+"/notes?created_after=2026-10-01&page_size=30", "GET "+api+"/notes/not_1d3tmYTlCICgjy?include=transcript",
		"GET "+api+"/notes/not_1d3tmYTlCICgjy/transcript?cursor=c1", "GET "+api+"/folders", "GET "+api+"/spaces")
	// Webhook endpoints return signing secrets and push notes elsewhere; audit and
	// legal hold routes belong to separate Enterprise key types.
	assertRoutes(t, r, "grn_fixture", false,
		"POST "+api+"/notes", "DELETE "+api+"/notes/not_1d3tmYTlCICgjy", "HEAD "+api+"/notes",
		"GET "+api+"/webhook-endpoints", "POST "+api+"/webhook-endpoints", "GET "+api+"/audit", "GET "+api+"/legal-holds",
		"GET "+api+"/notes/%2e%2e/transcript", "GET "+api+"/folders/fol_4y6LduVdwSKC27",
		"GET https://api.granola.ai/v1/notes", "GET https://public-api.granola.ai.example.com/v1/notes",
		"GET https://mcp.granola.ai/mcp", "GET http://public-api.granola.ai:8080/v1/notes")
}
