package manifest

import (
	"encoding/json"
	"os"
	"testing"
)

// Only changes to the configuration shape, model or types alter a manifest's shape.
func TestShapeIgnoresValuesAndCode(t *testing.T) {
	raw, err := os.ReadFile("testdata/example-01.json")
	if err != nil {
		t.Fatal(err)
	}
	parsed, err := Parse(raw)
	if err != nil {
		t.Fatal(err)
	}
	published, err := json.Marshal(parsed)
	if err != nil {
		t.Fatal(err)
	}
	want := shapeOf(t, published)
	if got := shapeOf(t, raw); got != want {
		t.Fatal("defaults applied at publication changed the shape")
	}
	same := map[string]func(m map[string]any){
		"name and docs": func(m map[string]any) {
			m["name"], m["description"], m["setup"] = "Renamed", "Other", "Other setup"
			m["files"] = []any{"other.luau"}
			m["stateless"] = true
		},
		"field presentation": func(m map[string]any) {
			f := object(m, "config", "access")
			f["label"], f["description"], f["placeholder"], f["order"] = "Access level", "Choose", "read-only", 9
			object(m, "config", "access")["options"].([]any)[0].(map[string]any)["label"] = "Read"
		},
		"auth presentation": func(m map[string]any) {
			method := object(m, "auth", "oauth")
			method["label"], method["description"], method["order"] = "Sign in", "Recommended", 5
			object(m, "auth", "api_key", "config", "token")["label"] = "Token"
		},
		"field values": func(m map[string]any) {
			f := object(m, "config", "page_size")
			f["default"], f["minimum"], f["maximum"] = 7, 2, 500
			object(m, "auth", "api_key", "config", "token")["placeholder"] = "Paste"
		},
		"oauth values": func(m map[string]any) {
			method := object(m, "auth", "oauth")
			method["token_url"] = "https://other.example.com/token"
			method["scopes"] = []any{map[string]any{"values": []any{"files.write"}}}
			method["pkce"] = "none"
		},
		"proxy rules": func(m map[string]any) {
			m["proxy"].([]any)[0].(map[string]any)["match"].(map[string]any)["host"] = []any{"other.example.com"}
		},
		"default omitted by older releases": func(m map[string]any) {
			delete(object(m, "auth", "oauth"), "token_encoding")
		},
		"empty values serialized differently": func(m map[string]any) {
			object(m, "config", "client_id")["options"] = []any{}
		},
		"field removed from the contract": func(m map[string]any) {
			object(m, "auth", "oauth")["retired_setting"] = "value"
		},
	}
	changed := map[string]func(m map[string]any){
		"field type": func(m map[string]any) { object(m, "config", "page_size")["type"] = "string" },
		"field added": func(m map[string]any) {
			object(m, "config")["region"] = map[string]any{"type": "string", "label": "Region"}
		},
		"field removed": func(m map[string]any) { delete(object(m, "config"), "page_size") },
		"required":      func(m map[string]any) { object(m, "config", "client_id")["required"] = true },
		"condition":     func(m map[string]any) { object(m, "config", "client_id")["if"] = "{{ isDefined config.access }}" },
		"option value": func(m map[string]any) {
			object(m, "config", "access")["options"].([]any)[0].(map[string]any)["value"] = "viewer"
		},
		"auth method removed": func(m map[string]any) { delete(object(m, "auth"), "api_key") },
		"auth method type":    func(m map[string]any) { object(m, "auth", "api_key")["type"] = "oauth2" },
		"auth field type":     func(m map[string]any) { object(m, "auth", "api_key", "config", "token")["type"] = "string" },
		"publisher":           func(m map[string]any) { m["publisher"] = map[string]any{} },
	}
	for name, edit := range same {
		if shapeOf(t, edited(t, published, edit)) != want {
			t.Errorf("%s changed the shape", name)
		}
	}
	for name, edit := range changed {
		if shapeOf(t, edited(t, published, edit)) == want {
			t.Errorf("%s kept the shape", name)
		}
	}
}

func shapeOf(t *testing.T, raw []byte) string {
	t.Helper()
	shape, err := Shape(raw)
	if err != nil {
		t.Fatal(err)
	}
	return shape
}

func edited(t *testing.T, raw []byte, edit func(map[string]any)) []byte {
	t.Helper()
	var m map[string]any
	if err := json.Unmarshal(raw, &m); err != nil {
		t.Fatal(err)
	}
	edit(m)
	out, err := json.Marshal(m)
	if err != nil {
		t.Fatal(err)
	}
	return out
}

func object(m map[string]any, path ...string) map[string]any {
	for _, key := range path {
		m = m[key].(map[string]any)
	}
	return m
}
