package main

import (
	"context"
	"encoding/json"
	"os"
	"strings"
	"testing"

	"github.com/aibakery/houston-hub/manifest"
	"github.com/aibakery/houston-hub/tools/conformance"
)

func TestNativeSchemasAndConnectorTransport(t *testing.T) {
	b, err := os.ReadFile("../../connectors/calcom/lib/help.luau")
	if err != nil {
		t.Fatal(err)
	}
	modules := map[string]string{"lib/help.luau": string(b)}
	m, err := manifest.Parse([]byte(`{"schema_version":1,"name":"Cal.com schema fixture","files":["main.luau"],"proxy":[{"match":{"protocol":"http","host":["example.com"]},"action":{}}]}`))
	if err != nil {
		t.Fatal(err)
	}
	for _, tc := range []struct {
		name, operation, input string
		valid                  bool
	}{

		{"numeric path", "getBooking", "{\"bookingUid\":123}", true},
		{"unsafe identifier", "getBooking", "{\"bookingUid\":\"../booking\"}", false},
		{"missing path", "getBooking", "{}", false},
		{"limit maximum", "listBookings", "{\"limit\":100}", true},
		{"limit overflow", "listBookings", "{\"limit\":101}", false},
		{"limit fractional", "listBookings", "{\"limit\":1.5}", false},
		{"query null", "listBookings", "{\"limit\":null}", false},
		{"team CSV statuses", "listTeamBookings", "{\"teamId\":42,\"status\":\"upcoming,past\"}", true},
		{"single status controller", "listBookings", "{\"status\":\"upcoming,past\"}", false},
		{"invalid CSV status", "listTeamBookings", "{\"teamId\":42,\"status\":\"upcoming,typo\"}", false},
		{"slot event selector", "getSlots", "{\"start\":\"2026-11-16\",\"end\":\"2026-11-20\",\"eventTypeSlug\":\"intro\",\"username\":\"ana\"}", true},
		{"missing slot selector", "getSlots", "{\"start\":\"2026-11-16\",\"end\":\"2026-11-20\"}", false},
		{"missing booking selector", "createBooking", "{\"start\":\"2026-11-16T09:00:00Z\",\"attendee\":{\"name\":\"Ana\",\"timeZone\":\"Europe/Paris\"}}", false},
		{"booking attendee type", "createBooking", "{\"eventTypeId\":123,\"start\":\"2026-11-16T09:00:00Z\",\"attendee\":\"ana\"}", false},
		{"recurrence range", "createBooking", "{\"eventTypeId\":123,\"start\":\"2026-11-16T09:00:00Z\",\"attendee\":{\"name\":\"Ana\",\"timeZone\":\"Europe/Paris\"},\"recurrenceCount\":33}", false},
		{"seat cancel", "cancelBooking", "{\"bookingUid\":\"booking-demo\",\"seatUid\":\"seat-demo\"}", true},
		{"seat cancel type", "cancelBooking", "{\"bookingUid\":\"booking-demo\",\"seatUid\":false}", false},
		{"empty calendar array", "getBusyTimes", "{\"dateFrom\":\"2026-11-16\",\"dateTo\":\"2026-11-20\",\"calendar\":[]}", false},
		{"wrapped routing answers", "calculateRoutingFormSlots", "{\"routingFormId\":\"form-demo\",\"start\":\"2026-11-16\",\"end\":\"2026-11-20\",\"answers\":{\"email\":\"ana@example.com\"}}", true},
		{"routing answers required", "calculateRoutingFormSlots", "{\"routingFormId\":\"form-demo\",\"start\":\"2026-11-16\",\"end\":\"2026-11-20\"}", false},
		{"native custom field discriminator", "addBookingFields", "{\"eventTypeId\":123,\"bookingFields\":[{\"field\":\"custom\",\"type\":\"shortText\",\"slug\":\"agenda\",\"label\":\"Agenda\"}]}", true},
		{"unknown custom field type", "addBookingFields", "{\"eventTypeId\":123,\"bookingFields\":[{\"field\":\"custom\",\"type\":\"typo\",\"slug\":\"agenda\",\"label\":\"Agenda\"}]}", false},
		{"custom field label required", "addBookingFields", "{\"eventTypeId\":123,\"bookingFields\":[{\"field\":\"custom\",\"type\":\"shortText\",\"slug\":\"agenda\"}]}", false},
		{"empty booking fields", "replaceBookingFields", "{\"eventTypeId\":123,\"bookingFields\":[]}", false},
		{"webhook trigger enum", "createWebhook", "{\"active\":true,\"subscriberUrl\":\"https://example.com/hook\",\"triggers\":[\"typo\"]}", false},
		{"workflow nonempty steps", "createWorkflow", "{\"name\":\"Reminder\",\"activation\":{\"isActiveOnAllEventTypes\":true},\"trigger\":{\"type\":\"newEvent\"},\"steps\":[]}", false},
		{"workflow trigger enum", "createWorkflow", "{\"name\":\"Reminder\",\"activation\":{\"isActiveOnAllEventTypes\":true},\"trigger\":{\"type\":\"typo\"},\"steps\":[{\"action\":\"webhook\",\"stepNumber\":1,\"url\":\"https://example.com/hook\"}]}", false},
		{"workflow webhook step", "createWorkflow", "{\"name\":\"Reminder\",\"activation\":{\"isActiveOnAllEventTypes\":true},\"trigger\":{\"type\":\"newEvent\"},\"steps\":[{\"action\":\"webhook\",\"stepNumber\":1,\"url\":\"https://example.com/hook\"}]}", true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			operation, _ := json.Marshal(tc.operation)
			modules["main.luau"] = `local schema=require("lib/help.luau")[` + string(operation) + `].inputSchema;schema.examples={json.decode([====[` + tc.input + `]====])};return {invoke=function(input) return input end,help={text="Schema fixture",functions={invoke={description="Native input",inputSchema=schema}}}}`
			_, err := conformance.CheckCatalog(context.Background(), "", *m, modules, map[string]string{"example.luau": `return {scenario={},run=function(c) assert(type(fixture.example("invoke"))=="table") end}`})
			if tc.valid && err != nil {
				t.Fatal(err)
			}
			if !tc.valid && (err == nil || !strings.Contains(err.Error(), "inputSchema.examples[0]")) {
				t.Fatalf("invalid input should fail schema validation: %v", err)
			}
		})
	}
}
