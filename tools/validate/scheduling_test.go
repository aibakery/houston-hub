package main

import (
	"net/http"
	"os"
	"regexp"
	"slices"
	"strings"
	"testing"

	"github.com/aibakery/houston-hub/manifest"
)

func parseManifest(t *testing.T, path string) *manifest.Manifest {
	t.Helper()
	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	m, err := manifest.Parse(raw)
	if err != nil {
		t.Fatal(err)
	}
	return m
}

// assertRoutes checks that each "METHOD URL" route is allowed or denied, and that
// allowed routes replace a forged Authorization header with the connection's token.
func assertRoutes(t *testing.T, r *manifest.Resolved, token string, allowed bool, routes ...string) {
	t.Helper()
	assertAuthorizedRoutes(t, r, "Bearer "+token, allowed, routes...)
}

// assertAuthorizedRoutes is assertRoutes for any Authorization value, such as Basic.
func assertAuthorizedRoutes(t *testing.T, r *manifest.Resolved, authorization string, allowed bool, routes ...string) {
	t.Helper()
	for _, route := range routes {
		method, url, _ := strings.Cut(route, " ")
		recipe, err := r.Proxy.HTTPRecipe(method, url, nil)
		if (err == nil) != allowed {
			t.Fatalf("%s allowed=%v: %v", route, err == nil, err)
		}
		if err != nil {
			continue
		}
		headers, err := recipe.Prepare(r.Context, http.Header{"Authorization": {"forged"}})
		if err != nil || headers.Get("Authorization") != authorization {
			t.Fatalf("credential injection for %s: %v", route, err)
		}
	}
}

func TestCalcomAccessRoutes(t *testing.T) {
	m := parseManifest(t, "../../connectors/calcom/houston.json")
	const api = "https://api.cal.com/v2"
	for _, access := range []string{"read-only", "read-write"} {
		r, err := m.Resolve(nil, map[string]any{"access": access}, map[string]any{"token": "cal_live_fixture"}, "api_key")
		if err != nil {
			t.Fatal(err)
		}
		assertRoutes(t, r, "cal_live_fixture", true,
			"GET "+api+"/me", "GET "+api+"/bookings?status=upcoming&limit=20", "GET "+api+"/bookings/2NtaeaVcKfpmSZ4CthFdfk",
			"GET "+api+"/slots?eventTypeId=1&start=2026-10-15&end=2026-10-16", "GET "+api+"/teams/3/bookings",
			"POST "+api+"/routing-forms/f1/calculate-slots?start=2026-10-15&end=2026-10-16")
		// Webhook reads return signing secrets, so they need read-write access too.
		assertRoutes(t, r, "cal_live_fixture", access == "read-write",
			"GET "+api+"/webhooks", "GET "+api+"/event-types/1/webhooks/w1",
			"POST "+api+"/bookings", "POST "+api+"/bookings/b1/cancel", "PATCH "+api+"/event-types/1",
			"PUT "+api+"/event-types/1/booking-fields", "DELETE "+api+"/webhooks/w1", "POST "+api+"/conferencing/zoom/default")
		// Key rotation would revoke the connection's own key; credits cost money; calendar
		// credentials, org administration and bulk webhook deletion are not exposed.
		assertRoutes(t, r, "cal_live_fixture", false,
			"POST "+api+"/api-keys/refresh", "POST "+api+"/credits/charge", "POST "+api+"/calendars/apple/credentials",
			"GET "+api+"/organizations/1/users", "DELETE "+api+"/event-types/1/webhooks", "PATCH "+api+"/bookings/b1",
			"GET https://api.cal.com/v1/bookings", "GET https://api.cal.eu/v2/me", "GET https://app.cal.com/v2/me",
			"GET "+api+"/bookings/%2e%2e/me")
	}
}

func TestCalendlyScopesAndAccessRoutes(t *testing.T) {
	m := parseManifest(t, "../../connectors/calendly/houston.json")
	// Write scopes add to the read scopes, so narrowing a caller to read-only keeps a granted set.
	readScopes := []string{"users:read", "organizations:read", "event_types:read", "availability:read", "scheduled_events:read", "locations:read",
		"routing_forms:read", "groups:read", "webhooks:read", "contacts:read", "meeting_recaps:read", "activity_log:read", "outgoing_communications:read"}
	writeScopes := []string{"organizations:write", "event_types:write", "availability:write", "scheduled_events:write", "scheduling_links:write",
		"shares:write", "webhooks:write", "contacts:write", "meeting_recaps:write"}
	const api = "https://api.calendly.com"
	for _, method := range []string{"token", "oauth"} {
		for _, access := range []string{"read-only", "read-write"} {
			config := map[string]any{"access": access}
			input := map[string]any{"token": "calendly-pat"}
			if method == "oauth" {
				config["client_id"], config["client_secret"], input = "fixture-client", "fixture-secret", nil
			}
			r, err := m.Resolve(nil, config, input, method)
			if err != nil {
				t.Fatal(err)
			}
			token := "calendly-pat"
			if method == "oauth" {
				scopes := readScopes
				if access == "read-write" {
					scopes = slices.Concat(readScopes, writeScopes)
				}
				if !slices.Equal(r.Scopes, scopes) {
					t.Fatalf("access=%s scopes %v", access, r.Scopes)
				}
				token = "calendly-oauth"
				r.Context.Auth["oauth"]["access_token"] = token
			}
			assertRoutes(t, r, token, true,
				"GET "+api+"/users/me", "GET "+api+"/scheduled_events?user=https%3A%2F%2Fapi.calendly.com%2Fusers%2FU1",
				"GET "+api+"/scheduled_events/E1/invitees/I1", "GET "+api+"/organizations/O1/invitations/INV1",
				"GET "+api+"/meeting_recaps/R1/transcript")
			assertRoutes(t, r, token, access == "read-write",
				"POST "+api+"/invitees", "POST "+api+"/scheduled_events/E1/cancellation", "PATCH "+api+"/event_type_availability_schedules?event_type=x",
				"DELETE "+api+"/webhook_subscriptions/W1", "DELETE "+api+"/organization_memberships/M1")
			// Account deletion and data-compliance deletion are irreversible and not exposed.
			assertRoutes(t, r, token, false,
				"POST "+api+"/users/me/deletion", "POST "+api+"/data_compliance/deletion/invitees", "DELETE "+api+"/event_types/T1",
				"PUT "+api+"/event_types/T1", "GET https://calendly.com/users/me", "GET https://auth.calendly.com/oauth/token",
				"GET "+api+"/scheduled_events/%2e%2e/users/me")
		}
	}
}

type endpointEntry struct {
	method, path, rest string
	write              bool
}

// endpointTable reads a connector's endpoint table. Only GET reads unless an entry sets write or read.
func endpointTable(t *testing.T, name string) (string, []endpointEntry) {
	t.Helper()
	raw, err := os.ReadFile("../../connectors/" + name + "/connector.luau")
	if err != nil {
		t.Fatal(err)
	}
	lua := string(raw)
	endpoint := regexp.MustCompile(`(?m)^\t\w+ = \{method = "([A-Z]+)", path = "([^"]+)"(.*)$`)
	override := regexp.MustCompile(`\b(write|read) = (true|false)\b`)
	matches := endpoint.FindAllStringSubmatch(lua, -1)
	if entries := strings.Count(lua, "= {method = "); len(matches) != entries || entries == 0 {
		t.Fatalf("%s: matched %d of %d endpoint entries", name, len(matches), entries)
	}
	entries := make([]endpointEntry, 0, len(matches))
	for _, match := range matches {
		write := match[1] != "GET"
		if flag := override.FindStringSubmatch(match[3]); flag != nil {
			write = (flag[2] == "true") != (flag[1] == "read")
		}
		entries = append(entries, endpointEntry{method: match[1], path: match[2], rest: match[3], write: write})
	}
	return lua, entries
}

// The proxy must allow exactly the routes in each connector's endpoint table, and the
// writes only on read-write connections. Paths are relative to the connector's API base URL,
// such as Calendar's /calendar/v3.
// Credential-free rules, such as Resend's signed attachment links, are not API routes.
// A {format} placeholder expands to the connector's FORMATS list (Wise statements). A custom
// method such as Carta's {capitalCallId}:adjust is routed by its whole-segment placeholder.
func TestProxyMatchesEndpointTables(t *testing.T) {
	const readWrite = `{{ is config.access "read-write" }}`
	base := regexp.MustCompile(`(?m)^local API = "https://[^/"]+([^"]*)"`)
	formats := regexp.MustCompile(`local FORMATS = table\.freeze\(\{([^}]*)\}\)`)
	customMethod := regexp.MustCompile(`\}:\w+$`)
	for _, name := range []string{"assessfirst", "calcom", "calendly", "carta", "carta-crm", "gusto", "resend", "stripe", "vercel", "wise", "github", "incidentio", "gcalendar", "gsheets", "gforms", "gdocs", "gslides"} {
		lua, entries := endpointTable(t, name)
		prefix := ""
		if api := base.FindStringSubmatch(lua); api != nil {
			prefix = api[1]
		}
		var want, got []string
		for _, entry := range entries {
			gate := ""
			if entry.write {
				gate = readWrite
			}
			paths := []string{prefix + customMethod.ReplaceAllString(entry.path, "}")}
			if strings.Contains(entry.path, "{format}") {
				list := formats.FindStringSubmatch(lua)
				if list == nil {
					t.Fatalf("%s: {format} without FORMATS", name)
				}
				paths = nil
				for _, format := range strings.Split(list[1], ",") {
					paths = append(paths, prefix+strings.Replace(entry.path, "{format}", strings.Trim(format, ` "`), 1))
				}
			}
			for _, path := range paths {
				want = append(want, entry.method+" "+path+" "+gate)
			}
		}
		for _, rule := range parseManifest(t, "../../connectors/"+name+"/houston.json").Proxy {
			if len(rule.Action.Headers.Set) == 0 {
				continue
			}
			for _, method := range rule.Match.Method {
				for _, path := range rule.Match.Path {
					got = append(got, method+" "+path+" "+rule.If)
				}
			}
		}
		// Custom methods of one resource, such as two exercise verbs, share its route.
		slices.Sort(want)
		want = slices.Compact(want)
		slices.Sort(got)
		if !slices.Equal(got, want) {
			t.Errorf("%s: proxy routes %v, endpoint table %v", name, got, want)
		}
	}
}
