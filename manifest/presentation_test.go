package manifest

import (
	"encoding/json"
	"strings"
	"testing"
)

func TestMultilineFieldContract(t *testing.T) {
	for _, source := range []string{"config", "publisher", "auth"} {
		t.Run(source, func(t *testing.T) {
			for _, field := range []string{
				`{"type":"string","label":"Notes","multiline":true}`,
				`{"type":"string","label":"Policy","multiline":true,"format":"json","default":"not yet JSON"}`,
			} {
				raw := multilineManifest(source, field)
				m, err := Parse([]byte(raw))
				if err != nil {
					t.Fatal(err)
				}
				snapshot, err := json.Marshal(m)
				if err != nil {
					t.Fatal(err)
				}
				if !strings.Contains(string(snapshot), `"multiline":true`) {
					t.Fatal("multiline lost from snapshot")
				}
				if _, err := Parse(snapshot); err != nil {
					t.Fatal(err)
				}
			}
		})
	}
	for _, field := range []string{
		`{"type":"secret","label":"Secret","multiline":true}`,
		`{"type":"boolean","label":"Flag","multiline":false}`,
		`{"type":"string","label":"Hidden","display":"masked","multiline":true}`,
		`{"type":"string","label":"Choice","options":[{"value":"x","label":"X"}],"multiline":false}`,
		`{"type":"string","label":"JSON","format":"json"}`,
		`{"type":"string","label":"JSON","multiline":false,"format":"json"}`,
		`{"type":"string","label":"JSON","multiline":true,"format":"yaml"}`,
		`{"type":"string","label":"JSON","multiline":true,"format":""}`,
	} {
		if _, err := Parse([]byte(multilineManifest("config", field))); err == nil {
			t.Fatalf("accepted %s", field)
		}
	}
}

func multilineManifest(source, field string) string {
	settings := `"` + source + `":{"notes":` + field + `}`
	reference := source + ".notes"
	if source == "auth" {
		settings = `"auth":{"manual":{"type":"manual","label":"Manual","config":{"notes":` + field + `}}}`
		reference = "auth.manual.notes"
	}
	return `{"schema_version":1,"name":"Multiline","files":["connector.lua"],` + settings + `,"proxy":[{"match":{"protocol":"http","host":["example.com"]},"action":{"headers":{"set":{"X-Notes":"{{` + reference + `}}"}}}}]}`
}

func TestConditionalRequiredMultiline(t *testing.T) {
	m, err := Parse([]byte(`{"schema_version":1,"name":"Conditional","files":["connector.lua"],"config":{"mode":{"type":"string","label":"Mode","default":"simple"},"policy":{"type":"string","label":"Policy","required":true,"multiline":true,"format":"json","if":"{{ is config.mode \"custom\" }}"}},"proxy":[{"match":{"protocol":"http","host":["example.com"]},"action":{}}]}`))
	if err != nil {
		t.Fatal(err)
	}
	inactive, err := m.Resolve(nil, nil, nil, "")
	if err != nil {
		t.Fatal(err)
	}
	if len(inactive.ConnectionFields) != 1 {
		t.Fatal("inactive policy shown")
	}
	if _, err := m.Resolve(nil, map[string]any{"mode": "custom"}, nil, ""); err == nil {
		t.Fatal("missing active required policy accepted")
	}
	draft, err := m.ResolveDraft(nil, map[string]any{"mode": "custom"}, nil, "")
	if err != nil || len(draft.ConnectionFields) != 2 {
		t.Fatalf("required field unavailable in draft: %#v %v", draft, err)
	}
	if err := inactive.ValidateSubmission("config", map[string]any{"policy": "{}"}); err == nil {
		t.Fatal("inactive submitted policy accepted")
	}
	saved, err := m.Resolve(nil, map[string]any{"mode": "simple", "policy": "{}"}, nil, "")
	if err != nil {
		t.Fatal(err)
	}
	if _, ok := saved.Context.Config["policy"]; ok {
		t.Fatal("inactive saved policy exposed")
	}
}

func TestOAuthBrandContract(t *testing.T) {
	const oauth = `"type":"oauth2","label":"OAuth","authorize_url":"https://example.com/auth","token_url":"https://example.com/token","client_id":"{{config.client_id}}","client_auth":"none"`
	for _, brand := range Brands {
		m, err := Parse([]byte(brandManifest(oauth+`,"brand":"`+brand+`"`, "access_token")))
		if err != nil {
			t.Fatal(err)
		}
		snapshot, err := json.Marshal(m)
		if err != nil {
			t.Fatal(err)
		}
		if _, err := Parse(snapshot); err != nil || !strings.Contains(string(snapshot), `"brand":"`+brand+`"`) {
			t.Fatalf("brand %s lost from snapshot: %v", brand, err)
		}
		r, err := m.Resolve(nil, map[string]any{"client_id": "client"}, nil, "oauth")
		if err != nil {
			t.Fatal(err)
		}
		if len(r.Methods) != 1 || r.Methods[0].Brand != brand {
			t.Fatalf("methods = %+v", r.Methods)
		}
	}
	for _, invalid := range [][2]string{
		{oauth + `,"brand":"github"`, "access_token"},
		{oauth + `,"brand":""`, "access_token"},
		{`"type":"manual","label":"Token","brand":"google","config":{"token":{"type":"secret","label":"Token"}}`, "token"},
	} {
		if _, err := Parse([]byte(brandManifest(invalid[0], invalid[1]))); err == nil || !strings.Contains(err.Error(), "brand") {
			t.Fatalf("%s: %v", invalid[0], err)
		}
	}
}

func brandManifest(method, credential string) string {
	return `{"schema_version":1,"name":"Brand","files":["connector.lua"],"config":{"client_id":{"type":"string","label":"Client ID"}},"auth":{"oauth":{` + method + `}},"proxy":[{"match":{"protocol":"http","host":["example.com"]},"action":{"headers":{"set":{"Authorization":"{{auth.oauth.` + credential + `}}"}}}}]}`
}
