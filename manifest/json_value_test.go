package manifest

import (
	"strings"
	"testing"
)

func TestJSONFieldValues(t *testing.T) {
	field := Field{Type: "string", Label: "Folder access", Multiline: true, Format: "json"}
	for _, input := range []any{nil, `{}`, `[]`, `{"folder":"read-only"}`, `"text"`, `false`, `42`, `null`, " \n{}\t"} {
		if err := ValidateValue(field, input); err != nil {
			t.Errorf("valid JSON %v: %v", input, err)
		}
	}
	for _, input := range []any{"", " \n\t", `{"private-folder":"read-only",}`, `{`, `{} {}`, `NaN`, "private-token", map[string]any{}, 12} {
		if err := ValidateValue(field, input); err == nil {
			t.Errorf("accepted invalid JSON %v", input)
		} else if strings.Contains(err.Error(), "private") {
			t.Errorf("error exposed submitted content: %v", err)
		}
	}
	field.Required = true
	if err := ValidateValue(field, nil); err == nil {
		t.Fatal("required JSON accepted omission")
	}
	if err := ValidateValue(field, `null`); err != nil {
		t.Fatalf("JSON null text is still a supplied valid JSON value: %v", err)
	}
}

func TestJSONValidationAcrossFieldOwners(t *testing.T) {
	for _, source := range []string{"config", "publisher", "auth"} {
		t.Run(source, func(t *testing.T) {
			if _, err := Parse([]byte(multilineManifest(source, `{"type":"string","label":"Policy","multiline":true,"format":"json","default":"invalid"}`))); err == nil {
				t.Fatal("invalid JSON default accepted")
			}
			m, err := Parse([]byte(multilineManifest(source, `{"type":"string","label":"Policy","multiline":true,"format":"json"}`)))
			if err != nil {
				t.Fatal(err)
			}
			var publisher, config, auth map[string]any
			selected, ref := "", source+".notes"
			bad := map[string]any{"notes": `{"private-path":true,}`}
			switch source {
			case "publisher":
				publisher = bad
			case "config":
				config = bad
			case "auth":
				auth, selected, ref = bad, "manual", "auth.manual.notes"
			}
			if _, err := m.Resolve(publisher, config, auth, selected); err == nil || !strings.Contains(err.Error(), ref) || strings.Contains(err.Error(), "private-path") {
				t.Fatalf("invalid JSON must return a safe field error: %v", err)
			}
			draft, err := m.ResolveDraft(publisher, config, auth, selected)
			if err != nil || draft.Context.Errors[ref] == nil {
				t.Fatalf("draft must expose editable field metadata and validation error: %+v %v", draft, err)
			}
		})
	}
}

func TestInactiveJSONDoesNotBlockResolution(t *testing.T) {
	m, err := Parse([]byte(`{"schema_version":1,"name":"Conditional","files":["connector.lua"],"config":{"mode":{"type":"string","label":"Mode","default":"simple"},"policy":{"type":"string","label":"Policy","multiline":true,"format":"json","if":"{{ is config.mode \"custom\" }}"}},"proxy":[{"match":{"protocol":"http","host":["example.com"]},"action":{}}]}`))
	if err != nil {
		t.Fatal(err)
	}
	input := map[string]any{"mode": "simple", "policy": `{"private-folder":true,}`}
	if _, err := m.Resolve(nil, input, nil, ""); err != nil {
		t.Fatalf("inactive legacy JSON blocked unrelated valid configuration: %v", err)
	}
	input["mode"] = "custom"
	if _, err := m.Resolve(nil, input, nil, ""); err == nil || !strings.Contains(err.Error(), "config.policy") {
		t.Fatalf("reactivated invalid JSON must require repair: %v", err)
	}
}
