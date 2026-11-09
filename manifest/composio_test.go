package manifest

import (
	"encoding/json"
	"net/http"
	"reflect"
	"strings"
	"testing"
)

const brokerManifest = `{"schema_version":1,"name":"Broker","files":["connector.luau"],"publisher":{"id":{"type":"string","label":"ID"},"secret":{"type":"secret","label":"Secret"}},"auth":{"broker":{"type":"composio","label":"Connect","auth_config_id":"{{publisher.id}}","api_key":"{{publisher.secret}}","app":"example","account":{"url":"https://api.example.com/profile","label":"/email"}}},"proxy":[{"match":{"protocol":"http","host":["api.example.com"],"method":["GET"],"path":["/profile"]},"action":{}}]}`

func TestComposioResolutionAndDiscovery(t *testing.T) {
	m, err := Parse([]byte(brokerManifest))
	if err != nil {
		t.Fatal(err)
	}
	publisher := map[string]any{"id": "ac_fixture", "secret": "private"}
	r, err := m.Resolve(publisher, nil, nil, "broker")
	if err != nil {
		t.Fatal(err)
	}
	if !r.Methods[0].Eligible || !r.Methods[0].Available || !r.Methods[0].PublisherClient || len(r.Scopes) != 0 || len(r.PublicConfig) != 0 {
		t.Fatalf("unexpected resolution: %#v", r)
	}
	auth := m.DiscoveryAuth("broker", nil, map[string]string{"token": "private"})
	if auth.Scopes != nil || len(auth.Facts) != 0 {
		t.Fatalf("discovery: %#v", auth)
	}
	for _, status := range []string{"available", "preview", "disabled"} {
		a := m.Auth["broker"]
		a.Availability = &AuthAvailability{Status: status, Message: "Waiting for approval"}
		m.Auth["broker"] = a
		r, err = m.Resolve(publisher, nil, nil, "broker")
		if err != nil || !r.Methods[0].Available || r.Methods[0].Availability.Status != status {
			t.Fatalf("existing grant affected by presentation status %s: %v", status, err)
		}
	}
	for _, key := range []string{"id", "secret"} {
		for _, blank := range []any{nil, ""} {
			incomplete := map[string]any{}
			for field, value := range publisher {
				if field != key {
					incomplete[field] = value
				}
			}
			if blank != nil {
				incomplete[key] = blank
			}
			draft, err := m.ResolveDraft(incomplete, nil, nil, "broker")
			if err != nil || draft.Methods[0].Eligible || draft.Methods[0].Available {
				t.Fatalf("incomplete %s offered: %v", key, err)
			}
			if _, err := m.Resolve(incomplete, nil, nil, "broker"); err == nil {
				t.Fatalf("incomplete %s resolved", key)
			}
		}
	}
	serialized, err := json.Marshal(m)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := Parse(serialized); err != nil {
		t.Fatalf("snapshot roundtrip: %v", err)
	}
}

func TestComposioRejectsUnsafeDeclarations(t *testing.T) {
	for _, change := range [][2]string{
		{`"app":"example"`, `"app":"{{publisher.id}}"`},
		{`"app":"example"`, `"app":"example","token_url":"https://attacker.example/token"`},
		{`"app":"example"`, `"app":"example","availability":{"status":"unknown"}`},
		{`"app":"example"`, `"app":"example","availability":{"status":"preview"}`},
		{`"api_key":"{{publisher.secret}}"`, `"api_key":"{{publisher.id}}"`},
		{`"auth_config_id":"{{publisher.id}}"`, `"auth_config_id":"{{publisher.secret}}"`},
		{`"api_key":"{{publisher.secret}}"`, `"api_key":"literal-key"`},
		{`"auth_config_id":"{{publisher.id}}"`, `"auth_config_id":"ac_literal"`},
		{`"label":"/email"`, `"label":"/email","headers":{"Authorization":{"value":"{{publisher.secret}}"}}`},
		{`"label":"/email"`, `"label":"/email","method":"POST"`},
	} {
		if _, err := Parse([]byte(strings.Replace(brokerManifest, change[0], change[1], 1))); err == nil {
			t.Fatalf("accepted %s", change[1])
		}
	}
}

func TestConditionalProxyHeadersAndStringSnapshots(t *testing.T) {
	raw := strings.Replace(brokerManifest, `"action":{}`, `"action":{"headers":{"set":{"X-Static":"unchanged","X-Broker":{"if":"{{ isDefined auth.broker }}","value":"connected"}}}}`, 1)
	m, err := Parse([]byte(raw))
	if err != nil {
		t.Fatal(err)
	}
	recipe, err := m.Proxy.HTTPRecipe("GET", "https://api.example.com/profile", nil)
	if err != nil {
		t.Fatal(err)
	}
	for _, selected := range []string{"", "broker"} {
		c := Context{SelectedAuth: selected, Auth: map[string]map[string]any{selected: {}}}
		headers, err := recipe.Prepare(c, http.Header{})
		if err != nil || headers.Get("X-Static") != "unchanged" || (headers.Get("X-Broker") == "connected") != (selected == "broker") {
			t.Fatalf("conditional headers: %v %v", headers, err)
		}
	}
	snapshot, err := json.Marshal(m)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(snapshot), `"X-Static":"unchanged"`) {
		t.Fatalf("string shorthand changed: %s", snapshot)
	}
	if _, err := Parse(snapshot); err != nil {
		t.Fatal(err)
	}
}

func TestHeaderActionsDecodeReplacesPreviousValue(t *testing.T) {
	var reused HeaderActions
	for _, raw := range []string{
		`{"set":{"Authorization":"Bearer first"},"remove":["X-Old"]}`,
		`{"remove":["Authorization"]}`,
		`{"set":{"X-Selected":{"value":"second","if":"{{ isDefined auth.broker }}"}}}`,
	} {
		var fresh HeaderActions
		if err := json.Unmarshal([]byte(raw), &fresh); err != nil {
			t.Fatal(err)
		}
		if err := json.Unmarshal([]byte(raw), &reused); err != nil {
			t.Fatal(err)
		}
		if !reflect.DeepEqual(reused, fresh) {
			t.Fatalf("decoding %s depends on previous receiver: %#v", raw, reused)
		}
	}
}
