package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func fixture(t *testing.T, module string, auth any, publisher string) string {
	t.Helper()
	root := t.TempDir()
	dir := filepath.Join(root, "connectors", "example")
	if err := os.MkdirAll(filepath.Join(dir, "tests"), 0755); err != nil {
		t.Fatal(err)
	}
	m := map[string]any{
		"schema_version": 1, "id": "example", "name": "Example", "description": "Example service",
		"auth": auth, "access": []any{map[string]any{"id": "read-only"}}, "proxy": map[string]any{"protocol": "http"},
	}
	filename := "connector.lua"
	if module != "" {
		m["module"] = module
		filename = module
	}
	if publisher != "" {
		m["publisher_id"] = publisher
	}
	raw, err := json.Marshal(m)
	if err != nil {
		t.Fatal(err)
	}
	for name, contents := range map[string][]byte{
		"houston.json": raw, filename: []byte("return { functions = {} }"),
		"tests/contract.lua": []byte("return function(connector) assert(connector) end"),
	} {
		if err := os.WriteFile(filepath.Join(dir, name), contents, 0644); err != nil {
			t.Fatal(err)
		}
	}
	return root
}

func oauth(id string) map[string]any {
	method := map[string]any{"type": "oauth2", "oauth": map[string]any{"registration_id": "registration"}}
	if id != "" {
		method["id"] = id
	}
	return method
}

func TestDefaultModuleAndExplicitLuauWithoutPublisher(t *testing.T) {
	for _, module := range []string{"", "custom.luau"} {
		root := fixture(t, module, map[string]any{"type": "secret"}, "")
		count, err := validate(root)
		if err != nil || count != 1 {
			t.Fatalf("module=%q: count=%d err=%v", module, count, err)
		}
	}
}

func TestAuthenticationChoices(t *testing.T) {
	tests := []struct {
		name      string
		auth      any
		publisher string
		want      string
	}{
		{"single OAuth", oauth(""), "publisher", ""},
		{"key and OAuth", []any{map[string]any{"type": "secret", "label": "API key"}, oauth("")}, "publisher", ""},
		{"two explicit keys", []any{map[string]any{"type": "secret", "id": "personal"}, map[string]any{"type": "secret", "id": "service"}}, "", ""},
		{"ambiguous key IDs", []any{map[string]any{"type": "secret"}, map[string]any{"type": "secret"}}, "", "explicit ids"},
		{"conflicting IDs", []any{map[string]any{"type": "secret", "id": "oauth2"}, oauth("")}, "publisher", "unique slugs"},
		{"missing OAuth publisher", oauth(""), "", "publisher_id"},
		{"missing registration", map[string]any{"type": "oauth2"}, "publisher", "registration_id"},
		{"empty choices", []any{}, "", "at least one"},
		{"public credential", map[string]any{"type": "secret", "access_token": "do-not-publish"}, "", "access_token"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			_, err := validate(fixture(t, "", tt.auth, tt.publisher))
			if tt.want == "" {
				if err != nil {
					t.Fatal(err)
				}
				return
			}
			if err == nil || !strings.Contains(err.Error(), tt.want) {
				t.Fatalf("want %q, got %v", tt.want, err)
			}
		})
	}
}

func TestRefusesMissingTestsAndEscapingModule(t *testing.T) {
	root := fixture(t, "", map[string]any{"type": "secret"}, "")
	dir := filepath.Join(root, "connectors", "example")
	if err := os.Remove(filepath.Join(dir, "tests", "contract.lua")); err != nil {
		t.Fatal(err)
	}
	if _, err := validate(root); err == nil || !strings.Contains(err.Error(), "test is required") {
		t.Fatalf("missing tests: %v", err)
	}
	if _, err := bundleFile(dir, "../outside.lua"); err == nil {
		t.Fatal("accepted escaping module")
	}
}

func TestEachAuthenticationModeResolvesItsOwnConfiguration(t *testing.T) {
	key := map[string]any{"type": "secret", "label": "API key"}
	account := oauth("")
	account["module"] = "oauth.luau"
	account["description"] = "OAuth can also write records"
	account["access"] = []any{map[string]any{"id": "read-write"}}
	account["proxy"] = map[string]any{"protocol": "http"}
	account["config_fields"] = []any{}
	account["setup"] = ""
	root := fixture(t, "", []any{key, account}, "publisher")
	if _, err := validate(root); err == nil || !strings.Contains(err.Error(), "oauth.luau") {
		t.Fatalf("must check alternate module: %v", err)
	}
	if err := os.WriteFile(filepath.Join(root, "connectors", "example", "oauth.luau"), []byte("return {}"), 0644); err != nil {
		t.Fatal(err)
	}
	if _, err := validate(root); err != nil {
		t.Fatal(err)
	}
	raw, err := os.ReadFile(filepath.Join(root, "connectors", "example", "houston.json"))
	if err != nil {
		t.Fatal(err)
	}
	method, _ := json.Marshal(account)
	effective, err := resolveMethod(raw, method)
	if err != nil {
		t.Fatal(err)
	}
	if effective.ID != "example" || effective.PublisherID != "publisher" || effective.Module != "oauth.luau" || effective.Access[0].ID != "read-write" || effective.Proxy.Protocol != "http" {
		t.Fatalf("wrong effective mode: %+v", effective)
	}
}

func TestOverridesReplaceWholeFieldsAndCannotChangeIdentity(t *testing.T) {
	for _, test := range []struct {
		name     string
		override map[string]any
		want     string
	}{
		{"empty access replaces", map[string]any{"access": []any{}}, "access modes"},
		{"partial proxy cannot merge", map[string]any{"proxy": map[string]any{"routes": []any{}}}, "unknown proxy protocol"},
		{"blank description replaces", map[string]any{"description": ""}, "description"},
		{"publisher stays top", map[string]any{"publisher_id": "other"}, "top level"},
		{"name stays top", map[string]any{"name": "other"}, "top level"},
	} {
		t.Run(test.name, func(t *testing.T) {
			test.override["type"] = "secret"
			root := fixture(t, "", test.override, "")
			if _, err := validate(root); err == nil || !strings.Contains(err.Error(), test.want) {
				t.Fatalf("want %q, got %v", test.want, err)
			}
		})
	}
}

func TestAllModesMaySelectAlternateModulesWithoutUnusedDefault(t *testing.T) {
	root := fixture(t, "", map[string]any{"type": "secret", "module": "key.luau"}, "")
	dir := filepath.Join(root, "connectors", "example")
	if err := os.Rename(filepath.Join(dir, "connector.lua"), filepath.Join(dir, "key.luau")); err != nil {
		t.Fatal(err)
	}
	if _, err := validate(root); err != nil {
		t.Fatal(err)
	}
}
