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

func TestGmailScopesAndRoutes(t *testing.T) {
	m := parseManifest(t, "../../connectors/gmail/houston.json")
	const api = "https://gmail.googleapis.com/gmail/v1/users/me"
	const upload = "https://gmail.googleapis.com/upload/gmail/v1/users/me"
	for _, access := range []string{"read-only", "read-write"} {
		scope := "gmail.readonly"
		if access == "read-write" {
			scope = "gmail.modify"
		}
		r := resolveGoogle(t, m, access, scope)
		reads := []string{"GET " + api + "/profile", "GET " + api + "/labels", "GET " + api + "/labels/Label_1",
			"GET " + api + "/messages?q=is%3Aunread", "GET " + api + "/messages/m1?format=full", "GET " + api + "/messages/m1/attachments/a1",
			"GET " + api + "/threads", "GET " + api + "/threads/t1", "GET " + api + "/drafts", "GET " + api + "/drafts/d1",
			"GET " + api + "/history?startHistoryId=1", "GET " + api + "/settings/sendAs"}
		assertRoutes(t, r, "fixture-token", true, reads...)
		assertStripsMethodOverrides(t, r, reads...)
		writes := []string{"POST " + api + "/messages/batchModify", "POST " + api + "/messages/m1/modify", "POST " + api + "/messages/m1/trash",
			"POST " + api + "/messages/m1/untrash", "POST " + api + "/threads/t1/modify", "POST " + api + "/threads/t1/trash",
			"POST " + api + "/threads/t1/untrash", "POST " + api + "/labels", "PATCH " + api + "/labels/Label_1", "DELETE " + api + "/labels/Label_1",
			"POST " + api + "/drafts/send", "DELETE " + api + "/drafts/d1", "POST " + upload + "/messages/send?uploadType=multipart",
			"POST " + upload + "/drafts?uploadType=multipart", "PUT " + upload + "/drafts/d1?uploadType=multipart"}
		assertRoutes(t, r, "fixture-token", access == "read-write", writes...)
		if access == "read-write" {
			assertStripsMethodOverrides(t, r, writes...)
		}
		// The token stays off Google's OAuth endpoints, other Google APIs, lookalike hosts and Gmail
		// routes the connector never calls: permanent deletes, imports, inserts, settings, watches and batches.
		assertRoutes(t, r, "fixture-token", false,
			"POST https://oauth2.googleapis.com/token", "GET https://www.googleapis.com/drive/v3/files",
			"GET https://gmail.googleapis.com.evil.test/gmail/v1/users/me/profile", "GET https://www.googleapis.com/gmail/v1/users/me/profile",
			"GET https://gmail.googleapis.com/gmail/v1/users/other@example.com/profile", "POST https://gmail.googleapis.com/batch/gmail/v1",
			"DELETE "+api+"/messages/m1", "POST "+api+"/messages/batchDelete", "DELETE "+api+"/threads/t1", "POST "+api+"/messages/import",
			"POST "+api+"/messages", "POST "+api+"/messages/send", "POST "+upload+"/messages/import", "POST "+upload+"/messages",
			"PUT "+api+"/labels/Label_1", "PUT "+api+"/drafts/d1", "POST "+api+"/drafts", "POST "+api+"/watch", "POST "+api+"/stop",
			"GET "+api+"/settings/forwardingAddresses", "POST "+api+"/settings/filters", "PUT "+api+"/settings/vacation",
			"POST "+api+"/settings/sendAs", "GET "+api+"/messages/%2e%2e/profile", "GET "+api+"/messages/m1%2F..%2Fx")
	}
}

func TestGoogleDriveScopesAndRoutes(t *testing.T) {
	m := parseManifest(t, "../../connectors/gdrive/houston.json")
	const api = "https://www.googleapis.com/drive/v3"
	const upload = "https://www.googleapis.com/upload/drive/v3"
	for _, access := range []string{"read-only", "read-write"} {
		scope := "drive.readonly"
		if access == "read-write" {
			scope = "drive"
		}
		r := resolveGoogle(t, m, access, scope)
		reads := []string{"GET " + api + "/about?fields=user", "GET " + api + "/files?q=trashed%3Dfalse", "GET " + api + "/files/f1",
			"GET " + api + "/files/f1?alt=media", "GET " + api + "/files/f1/export?mimeType=text%2Fplain", "GET " + api + "/files/f1/permissions",
			"GET " + api + "/drives"}
		assertRoutes(t, r, "fixture-token", true, reads...)
		assertStripsMethodOverrides(t, r, reads...)
		writes := []string{"POST " + api + "/files", "PATCH " + api + "/files/f1", "POST " + api + "/files/f1/copy", "DELETE " + api + "/files/f1",
			"POST " + api + "/files/f1/permissions", "DELETE " + api + "/files/f1/permissions/p1",
			"POST " + upload + "/files?uploadType=resumable", "PATCH " + upload + "/files/f1?uploadType=resumable",
			"PUT " + upload + "/files?uploadType=resumable&upload_id=xyz", "PUT " + upload + "/files/f1?uploadType=resumable&upload_id=xyz"}
		assertRoutes(t, r, "fixture-token", access == "read-write", writes...)
		// emptyTrash shares the {fileId} route, so only the connector's deleteFile check refuses it.
		assertRoutes(t, r, "fixture-token", access == "read-write", "DELETE "+api+"/files/trash")
		if access == "read-write" {
			assertStripsMethodOverrides(t, r, writes...)
		}
		// The token stays off Google's OAuth endpoints, other Google APIs, lookalike hosts and Drive
		// routes the connector never calls: emptying the trash, shared-drive and permission changes,
		// comments, revisions, watches and batches.
		assertRoutes(t, r, "fixture-token", false,
			"POST https://oauth2.googleapis.com/token", "GET https://www.googleapis.com/calendar/v3/calendars/primary",
			"GET https://www.googleapis.com.evil.test/drive/v3/files", "GET https://content.googleapis.com/drive/v3/files",
			"POST https://www.googleapis.com/batch/drive/v3", "POST "+api+"/drives", "DELETE "+api+"/drives/d1",
			"PATCH "+api+"/files/f1/permissions/p1", "POST "+api+"/files/f1/watch", "POST "+api+"/changes/watch", "GET "+api+"/changes",
			"POST "+api+"/files/f1/comments", "GET "+api+"/files/f1/revisions", "PUT "+api+"/files/f1", "POST "+api+"/files/generateIds",
			"GET "+api+"/files/f1/permissions/p1", "POST "+upload+"/files/f1", "GET "+upload+"/files/f1",
			"GET "+api+"/files/%2e%2e/about", "GET "+api+"/files/f1%2F..%2Fx")
	}
}

func TestGoogleFormsScopesAndRoutes(t *testing.T) {
	m := parseManifest(t, "../../connectors/gforms/houston.json")
	const api = "https://forms.googleapis.com/v1/forms"
	for _, access := range []string{"read-only", "read-write"} {
		scope := "forms.body.readonly"
		if access == "read-write" {
			scope = "forms.body"
		}
		r := resolveGoogle(t, m, access, scope, "forms.responses.readonly")
		reads := []string{"GET " + api + "/f1", "GET " + api + "/f1/responses?filter=timestamp%20%3E%202026-10-01T00%3A00%3A00Z",
			"GET " + api + "/f1/responses/ACYD"}
		assertRoutes(t, r, "fixture-token", true, reads...)
		assertStripsMethodOverrides(t, r, reads...)
		writes := []string{"POST " + api + "?unpublished=true", "POST " + api + "/f1:batchUpdate", "POST " + api + "/f1:setPublishSettings"}
		assertRoutes(t, r, "fixture-token", access == "read-write", writes...)
		if access == "read-write" {
			assertStripsMethodOverrides(t, r, writes...)
		}
		// The token stays off Google's OAuth endpoints, other Google APIs, lookalike hosts and Forms
		// routes the connector never calls: Pub/Sub watches and unused methods.
		assertRoutes(t, r, "fixture-token", false,
			"POST https://oauth2.googleapis.com/token", "GET https://www.googleapis.com/drive/v3/files",
			"GET https://forms.googleapis.com.evil.test/v1/forms/f1", "GET https://content.googleapis.com/v1/forms/f1",
			"GET https://forms.googleapis.com/v2/forms/f1", "GET "+api, "DELETE "+api+"/f1", "PATCH "+api+"/f1", "PUT "+api+"/f1",
			"GET "+api+"/f1/watches", "POST "+api+"/f1/watches", "POST "+api+"/f1/watches/w1:renew", "DELETE "+api+"/f1/watches/w1",
			"POST "+api+"/f1/responses", "DELETE "+api+"/f1/responses/ACYD", "GET "+api+"/%2e%2e/f1", "GET "+api+"/f1%2F..%2Fwatches",
			"GET "+api+"/f1/responses/%2e%2e")
	}
}

func TestGoogleDocsScopesAndRoutes(t *testing.T) {
	m := parseManifest(t, "../../connectors/gdocs/houston.json")
	const api = "https://docs.googleapis.com/v1/documents"
	for _, access := range []string{"read-only", "read-write"} {
		scope := "documents.readonly"
		if access == "read-write" {
			scope = "documents"
		}
		r := resolveGoogle(t, m, access, scope)
		reads := []string{"GET " + api + "/d1?includeTabsContent=true", "GET " + api + "/1DoC_x-9?fields=documentId%2Ctitle%2CrevisionId%2Ctabs"}
		assertRoutes(t, r, "fixture-token", true, reads...)
		assertStripsMethodOverrides(t, r, reads...)
		writes := []string{"POST " + api, "POST " + api + "/d1:batchUpdate"}
		assertRoutes(t, r, "fixture-token", access == "read-write", writes...)
		if access == "read-write" {
			assertStripsMethodOverrides(t, r, writes...)
		}
		// The token stays off Google's OAuth endpoints, other Google APIs, lookalike hosts and
		// methods the API does not have.
		assertRoutes(t, r, "fixture-token", false,
			"POST https://oauth2.googleapis.com/token", "GET https://www.googleapis.com/drive/v3/files",
			"GET https://docs.googleapis.com.evil.test/v1/documents/d1", "GET https://content.googleapis.com/v1/documents/d1",
			"GET https://docs.googleapis.com/v2/documents/d1", "GET "+api, "DELETE "+api+"/d1", "PATCH "+api+"/d1", "PUT "+api+"/d1",
			"GET "+api+"/d1/tabs", "GET "+api+"/%2e%2e/d1", "GET "+api+"/d1%2F..%2Fx", "POST "+api+"/d1/batchUpdate")
	}
}
