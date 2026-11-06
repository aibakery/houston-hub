package main

import (
	"regexp"
	"strings"
)

func requires(names ...string) object { return object{"required": names} }
func eventSelector() object {
	return object{"anyOf": []any{requires("eventTypeId"), requires("usernames"), object{"required": []string{"eventTypeSlug"}, "anyOf": []any{requires("username"), requires("teamSlug")}}}}
}

// The published spec omits several discriminators that its own descriptions
// require. Restore them without replacing the native nested payload schemas.
func supplement(spec object) {
	schemas := obj(obj(spec["components"])["schemas"])
	literal := regexp.MustCompile(`(?i)^(?:Only allowed value (?:for type )?is|Must be) ['\x60]([^'\x60]+)['\x60]`)
	for name, raw := range schemas {
		s := obj(raw)
		props := obj(s["properties"])
		for _, raw := range props {
			p := obj(raw)
			description, _ := p["description"].(string)
			if m := literal.FindStringSubmatch(description); len(m) > 0 {
				p["const"] = m[1]
			}
		}
		if strings.HasPrefix(name, "Workflow") && strings.Contains(name, "StepDto_2026_09_22") {
			action := obj(props["action"])
			if action["default"] != nil {
				action["const"] = action["default"]
			}
		}
	}
	// Regular and recurring schemas otherwise both accept every ordinary booking.
	// An omitted recurrence count is valid for either and uses the event defaults.
	regular := obj(schemas["CreateBookingInput_2024_08_13"])
	obj(regular["properties"])["recurrenceCount"] = false
	obj(regular["properties"])["instant"] = false
	recurring := obj(schemas["CreateRecurringBookingInput_2024_08_13"])
	recurring["required"] = append(list(recurring["required"]), "recurrenceCount")
	obj(recurring["properties"])["instant"] = false
	instant := obj(schemas["CreateInstantBookingInput_2024_08_13"])
	obj(instant["properties"])["recurrenceCount"] = false
	obj(obj(instant["properties"])["instant"])["const"] = true
	for _, name := range []string{"CreateBookingInput_2024_08_13", "CreateRecurringBookingInput_2024_08_13", "CreateInstantBookingInput_2024_08_13"} {
		s := obj(schemas[name])
		s["allOf"] = []any{eventSelector()}
	}
	for _, name := range []string{"CancelBookingInput_2024_08_13", "RescheduleBookingInput_2024_08_13"} {
		obj(obj(schemas[name])["properties"])["seatUid"] = false
	}
}
