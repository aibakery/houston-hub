package main

import (
	"slices"
	"testing"

	"github.com/aibakery/houston-hub/manifest"
)

// resolveGoogle resolves a Google bundle for an access level and checks it requests
// the account email plus exactly the given data scopes.
func resolveGoogle(t *testing.T, m *manifest.Manifest, access string, scopes ...string) *manifest.Resolved {
	t.Helper()
	publisher := map[string]any{"client_id": "publisher-client", "client_secret": "publisher-secret"}
	r, err := m.Resolve(publisher, map[string]any{"access": access}, nil, "oauth")
	if err != nil {
		t.Fatal(err)
	}
	want := []string{"https://www.googleapis.com/auth/userinfo.email"}
	for _, scope := range scopes {
		want = append(want, "https://www.googleapis.com/auth/"+scope)
	}
	if !slices.Equal(r.Scopes, want) {
		t.Fatalf("access=%s scopes %v", access, r.Scopes)
	}
	r.Context.Auth["oauth"]["access_token"] = "fixture-token"
	return r
}

func TestGoogleSheetsScopesAndRoutes(t *testing.T) {
	m := parseManifest(t, "../../connectors/gsheets/houston.json")
	const api = "https://sheets.googleapis.com/v4/spreadsheets"
	for _, access := range []string{"read-only", "read-write"} {
		scope := "spreadsheets.readonly"
		if access == "read-write" {
			scope = "spreadsheets"
		}
		r := resolveGoogle(t, m, access, scope)
		assertRoutes(t, r, "fixture-token", true,
			"GET "+api+"/s1?fields=sheets.properties", "GET "+api+"/s1/values/%27Q1%20Sales%27%21B2",
			"GET "+api+"/s1/values:batchGet?ranges=Q2%2FQ3%21A1", "GET "+api+"/s1/values/%2710%2F16%27%21A1",
			"GET "+api+"/s1/values/%27100%25%27%21A1")
		writes := []string{"POST " + api, "POST " + api + "/s1:batchUpdate", "PUT " + api + "/s1/values/Sheet1%21B2?valueInputOption=RAW",
			"POST " + api + "/s1/values/Log%21A%3AD:append?valueInputOption=RAW", "POST " + api + "/s1/values/A1:clear",
			"POST " + api + "/s1/values:batchUpdate", "POST " + api + "/s1/values:batchClear",
			"PUT " + api + "/s1/values/%27Q2%2FQ3%27%21B2", "POST " + api + "/s1/values/%27Log%2F2026%27%21A%3AD:append"}
		assertRoutes(t, r, "fixture-token", access == "read-write", writes...)
		// The token stays off Google's OAuth endpoints, other Google APIs, lookalike hosts and unused methods.
		assertRoutes(t, r, "fixture-token", false,
			"POST https://oauth2.googleapis.com/token", "GET https://www.googleapis.com/drive/v3/files",
			"GET https://sheets.googleapis.com/v4/spreadsheets", "GET https://sheets.googleapis.com.evil.test/v4/spreadsheets/s1",
			"GET https://sheets.googleapis.com/v3/spreadsheets/s1", "DELETE "+api+"/s1", "PATCH "+api+"/s1/values/A1",
			"GET "+api+"/s1/developerMetadata/1", "POST "+api+"/s1/developerMetadata:search", "POST "+api+"/s1/sheets/0:copyTo",
			"POST "+api+"/s1/values:batchUpdateByDataFilter", "GET "+api+"/s1/values/%2e%2e/x",
			// Ranges may carry encoded separators, but never traversal or an encoded spreadsheet ID.
			"GET "+api+"/s1/values/%2e%2e%2F%2e%2e%2Fdrive", "GET "+api+"/s1/values/%252e%252e%252Fx", "GET "+api+"/s1%2F..%2Fx/values/A1")
		assertStripsMethodOverrides(t, r, "GET "+api+"/s1", "GET "+api+"/s1/values/A1")
		if access == "read-write" {
			assertStripsMethodOverrides(t, r, writes...)
		}
	}
}

func TestGoogleCalendarScopesAndRoutes(t *testing.T) {
	m := parseManifest(t, "../../connectors/gcalendar/houston.json")
	const api = "https://www.googleapis.com/calendar/v3"
	const team = api + "/calendars/team%40group.calendar.google.com"
	for _, access := range []string{"read-only", "read-write"} {
		scopes := []string{"calendar.readonly"}
		if access == "read-write" {
			scopes = append(scopes, "calendar.events")
		}
		r := resolveGoogle(t, m, access, scopes...)
		reads := []string{"GET " + api + "/users/me/calendarList?maxResults=250", "GET " + api + "/colors", "GET " + api + "/calendars/primary",
			"GET " + api + "/calendars/en.usa%23holiday%40group.v.calendar.google.com/events?singleEvents=true",
			"GET " + team + "/events/e1", "GET " + team + "/events/e1/instances", "POST " + api + "/freeBusy"}
		assertRoutes(t, r, "fixture-token", true, reads...)
		assertStripsMethodOverrides(t, r, reads...)
		writes := []string{"POST " + team + "/events?sendUpdates=all", "POST " + api + "/calendars/primary/events/quickAdd?text=Lunch",
			"POST " + team + "/events/e1/move?destination=primary", "PATCH " + team + "/events/e1", "DELETE " + team + "/events/e1"}
		assertRoutes(t, r, "fixture-token", access == "read-write", writes...)
		if access == "read-write" {
			assertStripsMethodOverrides(t, r, writes...)
		}
		// The token stays off Google's OAuth endpoints, other Google APIs, lookalike hosts and
		// Calendar routes the connector never calls: calendar and ACL changes, imports,
		// push-notification channels and settings.
		assertRoutes(t, r, "fixture-token", false,
			"POST https://oauth2.googleapis.com/token", "GET https://www.googleapis.com/drive/v3/files",
			"GET https://www.googleapis.com.evil.test/calendar/v3/calendars/primary", "GET https://calendar-json.googleapis.com/calendar/v3/calendars/primary", "GET https://content.googleapis.com/calendar/v3/calendars/primary",
			"POST https://www.googleapis.com/batch/calendar/v3",
			"GET "+api+"/calendars/primary/acl", "POST "+api+"/calendars/primary/acl", "POST "+api+"/calendars", "DELETE "+api+"/calendars/c1",
			"PUT "+api+"/calendars/primary", "PATCH "+api+"/calendars/primary", "POST "+api+"/calendars/primary/clear",
			"PUT "+team+"/events/e1", "POST "+team+"/events/import", "POST "+team+"/events/watch", "POST "+api+"/users/me/calendarList",
			"POST "+api+"/users/me/calendarList/watch", "DELETE "+api+"/users/me/calendarList/c1", "GET "+api+"/users/me/settings",
			"POST "+api+"/channels/stop", "GET "+team+"/events/%2e%2e/acl", "GET "+api+"/calendars/primary%2F..%2Facl/events")
	}
}
