package main

import (
	"net/http"
	"slices"
	"testing"
)

func TestGoogleSheetsScopesAndRoutes(t *testing.T) {
	m := parseManifest(t, "../../connectors/gsheets/houston.json")
	const api = "https://sheets.googleapis.com/v4/spreadsheets"
	publisher := map[string]any{"client_id": "publisher-client", "client_secret": "publisher-secret"}
	for _, access := range []string{"read-only", "read-write"} {
		r, err := m.Resolve(publisher, map[string]any{"access": access}, nil, "oauth")
		if err != nil {
			t.Fatal(err)
		}
		scope := "https://www.googleapis.com/auth/spreadsheets.readonly"
		if access == "read-write" {
			scope = "https://www.googleapis.com/auth/spreadsheets"
		}
		if want := []string{"https://www.googleapis.com/auth/userinfo.email", scope}; !slices.Equal(r.Scopes, want) {
			t.Fatalf("access=%s scopes %v", access, r.Scopes)
		}
		r.Context.Auth["oauth"]["access_token"] = "fixture-token"
		assertRoutes(t, r, "fixture-token", true,
			"GET "+api+"/s1?fields=sheets.properties", "GET "+api+"/s1/values/%27Q1%20Sales%27%21B2",
			"GET "+api+"/s1/values:batchGet?ranges=Q2%2FQ3%21A1")
		assertRoutes(t, r, "fixture-token", access == "read-write",
			"POST "+api, "POST "+api+"/s1:batchUpdate", "PUT "+api+"/s1/values/Sheet1%21B2?valueInputOption=RAW",
			"POST "+api+"/s1/values/Log%21A%3AD:append?valueInputOption=RAW", "POST "+api+"/s1/values/A1:clear",
			"POST "+api+"/s1/values:batchUpdate", "POST "+api+"/s1/values:batchClear")
		// The token stays off Google's OAuth endpoints, other Google APIs, lookalike hosts and unused methods.
		assertRoutes(t, r, "fixture-token", false,
			"POST https://oauth2.googleapis.com/token", "GET https://www.googleapis.com/drive/v3/files",
			"GET https://sheets.googleapis.com/v4/spreadsheets", "GET https://sheets.googleapis.com.evil.test/v4/spreadsheets/s1",
			"GET https://sheets.googleapis.com/v3/spreadsheets/s1", "DELETE "+api+"/s1", "PATCH "+api+"/s1/values/A1",
			"GET "+api+"/s1/developerMetadata/1", "POST "+api+"/s1/developerMetadata:search", "POST "+api+"/s1/sheets/0:copyTo",
			"POST "+api+"/s1/values:batchUpdateByDataFilter", "GET "+api+"/s1/values/%2e%2e/x", "GET "+api+"/s1/values/A%2FB")

		// Reads cannot be turned into writes with a method override.
		recipe, err := r.Proxy.HTTPRecipe("GET", api+"/s1", nil)
		if err != nil {
			t.Fatal(err)
		}
		headers, err := recipe.Prepare(r.Context, http.Header{"X-HTTP-Method-Override": {"POST"}})
		if err != nil || headers.Get("X-HTTP-Method-Override") != "" {
			t.Fatalf("method override kept: %v %v", headers, err)
		}
	}
}
