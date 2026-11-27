package manifest

import (
	"encoding/json"
	"strings"
	"testing"
)

const labelManifest = `{"schema_version":2,"name":"Example","files":["main.luau"],
"config":{"workspace":{"type":"string","label":"Workspace","reauthorize_on_change":false},"host":{"type":"string","label":"Host"}},
"auth":{"token":{"type":"manual","label":"Token","config":{"token":{"type":"secret","label":"Token"},"username":{"type":"string","label":"User"}}}},
"connection_label":LABEL,
"proxy":[{"match":{"protocol":"http","host":["api.example.com"]},"action":{"headers":{"set":{"Authorization":"Bearer {{auth.token.token}}","X-User":"{{auth.token.username}}"}}}}]}`

func parseLabelManifest(t *testing.T, rules string) *Manifest {
	t.Helper()
	m, err := Parse([]byte(strings.Replace(labelManifest, "LABEL", rules, 1)))
	if err != nil {
		t.Fatal(err)
	}
	return m
}

func TestConnectionLabelSelectionAndPublicRendering(t *testing.T) {
	m := parseLabelManifest(t, `[
{"if":"{{ isDefined auth.token }}","value":"{{auth.token.username}}"},
{"value":"{{config.workspace}}"}]`)
	for _, tc := range []struct {
		method string
		user   string
		want   string
	}{{"token", "alice@example.test", "alice@example.test"}, {"", "ignored", "Team"}, {"token", "", ""}} {
		c := Context{Config: map[string]any{"workspace": "Team"}, SelectedAuth: tc.method, Auth: map[string]map[string]any{"token": {"username": tc.user}}}
		rule, err := m.SelectConnectionLabel(c)
		if err != nil || rule == nil || rule.Value == nil {
			t.Fatalf("select: %v, %v", rule, err)
		}
		got, err := RenderString(*rule.Value, c)
		if err != nil || got != tc.want {
			t.Fatalf("method %q: label %q, want %q, error %v", tc.method, got, tc.want, err)
		}
	}
	m.ConnectionLabel = m.ConnectionLabel[:1]
	if rule, err := m.SelectConnectionLabel(Context{}); err != nil || rule != nil {
		t.Fatalf("unmatched rules must have no label: %v, %v", rule, err)
	}
	m.ConnectionLabel = nil
	if rule, err := m.SelectConnectionLabel(Context{}); err != nil || rule != nil {
		t.Fatalf("omitted rules must have no label: %v, %v", rule, err)
	}
}

func TestConnectionLabelValidation(t *testing.T) {
	for _, rules := range []string{
		`[{"value":"API key"}]`,
		`[{"value":""}]`,
		`[{"value":"{{config.workspace}}"}]`,
		`[{"if":"{{ is config.workspace \"Team\" }}","value":"{{auth.token.username}}"}]`,
		`[{"request":{"url":"https://api.example.com/profile","headers":{"Authorization":{"value":"Bearer {{auth.token.token}}"}}},"select":"/email"}]`,
		`[{"request":{"url":"https://{{config.host}}/profile"},"select":"/email"}]`,
		`[{"request":{"url":"https://api.example.com/profile","method":"POST","body":{"if":true,"page":1}},"select":"/name"}]`,
	} {
		m := parseLabelManifest(t, rules)
		raw, err := json.Marshal(m)
		if err != nil {
			t.Fatal(err)
		}
		if _, err := Parse(raw); err != nil {
			t.Fatalf("serialized label no longer validates: %v", err)
		}
	}
	for _, rules := range []string{
		`[{}]`,
		`[{"value":"x","request":{"url":"https://api.example.com"},"select":"/name"}]`,
		`[{"value":"x","select":""}]`,
		`[{"value":"{{auth.token.token}}"}]`,
		`[{"value":"{{config.workspace || auth.token.token}}"}]`,
		`[{"value":"{{config.missing}}"}]`,
		`[{"if":"{{ isDefined auth.token.token }}","value":"key"}]`,
		`[{"request":{"url":"http://api.example.com"},"select":"/name"}]`,
		`[{"request":{"url":"https://api.example.com/{{auth.token.token}}"},"select":"/name"}]`,
		`[{"request":{"url":"https://api.example.com","method":"DELETE"},"select":"/name"}]`,
		`[{"request":{"url":"https://api.example.com","method":""},"select":"/name"}]`,
		`[{"request":{"url":"https://api.example.com","body":{"x":1}},"select":"/name"}]`,
		`[{"request":{"url":"https://api.example.com","method":"POST","body":{"x":"{{config.workspace}}"}},"select":"/name"}]`,
		`[{"request":{"url":"https://api.example.com"},"select":"name"}]`,
		`[{"request":{"url":"https://api.example.com"},"select":"/~bad"}]`,
	} {
		if _, err := Parse([]byte(strings.Replace(labelManifest, "LABEL", rules, 1))); err == nil {
			t.Errorf("accepted invalid label recipe %s", rules)
		}
	}
}

func TestConnectionLabelDoesNotRequireInputsOrReauthorization(t *testing.T) {
	m := parseLabelManifest(t, `[{"value":"{{config.workspace}}"}]`)
	r, err := m.Resolve(Inputs{Method: "token", Auth: map[string]any{"token": "private", "username": "alice"}})
	if err != nil {
		t.Fatalf("missing optional display input blocked setup: %v", err)
	}
	rule, err := m.SelectConnectionLabel(r.Context)
	if err != nil || rule == nil {
		t.Fatalf("select: %v, %v", rule, err)
	}
	if _, err := RenderString(*rule.Value, r.Context); err == nil {
		t.Fatal("missing display input must not invent a value")
	}
	// A manual field used only for display is still a meaningful declared input.
	raw := strings.Replace(labelManifest, `,"X-User":"{{auth.token.username}}"`, "", 1)
	raw = strings.Replace(raw, "LABEL", `[{"value":"{{auth.token.username}}"}]`, 1)
	if _, err := Parse([]byte(raw)); err != nil {
		t.Fatalf("display-only field rejected as unused: %v", err)
	}
}

func TestConnectionLabelPublisherCredentialRecipients(t *testing.T) {
	for _, url := range []string{"https://api.example.com/teams/{{auth.oauth.team_id}}", "https://{{config.host}}/profile"} {
		label := `"connection_label":[{"request":{"url":"` + url + `","headers":{"Authorization":{"value":"Bearer {{auth.oauth.access_token}}"}}},"select":"/name"}],`
		raw := strings.Replace(factsManifest, `"proxy":`, label+`"proxy":`, 1)
		_, err := Parse([]byte(raw))
		if (err == nil) != strings.HasPrefix(url, "https://api.example.com/") {
			t.Fatalf("credential recipient %q: %v", url, err)
		}
	}
	for _, label := range []string{`{"value":"{{publisher.client_id}}"}`, `{"if":"{{ isDefined publisher.client_id }}","value":"Team"}`} {
		raw := strings.Replace(factsManifest, `"proxy":`, `"connection_label":[`+label+`],"proxy":`, 1)
		if _, err := Parse([]byte(raw)); err == nil {
			t.Fatalf("publisher value exposed through label %s", label)
		}
	}
}

func TestConnectionLabelOverlayPreservesBoundRequestAuthority(t *testing.T) {
	m, err := Parse([]byte(factsManifest))
	if err != nil {
		t.Fatal(err)
	}
	c := Context{SelectedAuth: "oauth", Publisher: map[string]any{"client_id": "client", "client_secret": "client-secret", "bot": "bot-secret"}, Config: map[string]any{"host": "api.example.com"}, Auth: map[string]map[string]any{"oauth": {"access_token": "access-token", "team_id": "T1", "team_name": "Team"}}}
	for _, tc := range []struct {
		name, target, method, credential string
		allowed                          bool
	}{
		{"bound team", "https://api.example.com/teams/{{auth.oauth.team_id}}", "GET", "Bot {{publisher.bot}}", true},
		{"another team", "https://api.example.com/teams/T2", "GET", "Bot {{publisher.bot}}", false},
		{"another recipient", "https://other.example.com/teams/T1", "GET", "Bot {{publisher.bot}}", false},
		{"credential swap", "https://api.example.com/teams/T1", "GET", "Bearer {{auth.oauth.access_token}}", false},
		{"write method", "https://api.example.com/teams/T1", "POST", "Bot {{publisher.bot}}", false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			labels := []ConnectionLabelRule{{Request: &ConnectionLabelRequest{URL: tc.target, Method: tc.method, Headers: map[string]HeaderValue{"Authorization": {Value: tc.credential}, "X-Team": {Value: "{{auth.oauth.team_id}}"}}}, Select: "/name"}}
			next, err := m.WithConnectionLabels(labels, c)
			if (err == nil) != tc.allowed {
				t.Fatalf("overlay permission=%v, want %v: %v", err == nil, tc.allowed, err)
			}
			if err == nil && len(next.ConnectionLabel) != 1 || len(m.ConnectionLabel) != 0 {
				t.Fatal("overlay did not preserve the pinned manifest")
			}
		})
	}
	value := "Workspace"
	if _, err := m.WithConnectionLabels([]ConnectionLabelRule{{Value: &value}}, c); err != nil {
		t.Fatalf("literal display requires no transport authority: %v", err)
	}
	for _, tc := range []struct {
		name, value string
		allowed     bool
	}{{"Accept", "application/json", true}, {"X-Workspace", "{{config.host}}", true}, {"X-Extra", "{{publisher.client_secret}}", false}, {"X-Extra", "{{auth.oauth.access_token}}", false}} {
		headers := map[string]HeaderValue{"Authorization": {Value: "Bot {{publisher.bot}}"}, "X-Team": {Value: "{{auth.oauth.team_id}}"}, tc.name: {Value: tc.value}}
		labels := []ConnectionLabelRule{{Request: &ConnectionLabelRequest{URL: "https://api.example.com/teams/T1", Headers: headers}, Select: "/name"}}
		if _, err := m.WithConnectionLabels(labels, c); (err == nil) != tc.allowed {
			t.Errorf("additional header %s=%s: %v", tc.name, tc.value, err)
		}
	}
}

func TestConnectionLabelOverlayHonorsProxyOriginAndSelection(t *testing.T) {
	m := parseLabelManifest(t, `[]`)
	m.Proxy[0].Match.Host = []string{"*.example.test"}
	m.Proxy[0].Match.Method = []string{"GET"}
	m.Proxy[0].Match.Path = []string{"/profile"}
	c := Context{SelectedAuth: "token", Config: map[string]any{"workspace": "Team", "host": "self.example.test"}, Auth: map[string]map[string]any{"token": {"token": "secret", "username": "alice"}}}
	labels := func(target string) []ConnectionLabelRule {
		return []ConnectionLabelRule{{Request: &ConnectionLabelRequest{URL: target, Headers: m.Proxy[0].Action.Headers.Set}, Select: "/name"}}
	}
	for _, tc := range []struct {
		target  string
		allowed bool
	}{{"https://child.example.test/profile", true}, {"https://example.test/profile", false}, {"https://child.example.test.attacker.test/profile", false}, {"https://child.example.test:8443/profile", false}, {"https://child.example.test/write", false}} {
		if _, err := m.WithConnectionLabels(labels(tc.target), c); (err == nil) != tc.allowed {
			t.Errorf("target %s: %v", tc.target, err)
		}
	}
	m.Proxy[0].Match.Host = []string{"{{config.host}}"}
	host := m.Config["host"]
	host.Required = true
	m.Config["host"] = host
	if _, err := m.WithConnectionLabels(labels("https://self.example.test/profile"), c); err != nil {
		t.Fatalf("saved dynamic origin refused: %v", err)
	}
	m.Proxy[0].If = `{{ is config.workspace "Other" }}`
	if _, err := m.WithConnectionLabels(labels("https://self.example.test/profile"), c); err == nil {
		t.Fatal("inactive proxy authorized a label request")
	}
}

func TestConnectionLabelOverlayExactLifecycleRequest(t *testing.T) {
	m, err := Parse([]byte(factsManifest))
	if err != nil {
		t.Fatal(err)
	}
	a := m.Auth["oauth"]
	a.TokenResponse.Label = ""
	a.Account = &OAuthAccount{URL: "https://identity.example.test/current", Method: "POST", Label: "/name", Headers: map[string]HeaderValue{"Authorization": {Value: "Bearer {{auth.oauth.access_token}}"}}}
	m.Auth["oauth"] = a
	c := Context{SelectedAuth: "oauth", Publisher: map[string]any{"client_id": "client", "client_secret": "client-secret", "bot": "bot-secret"}, Config: map[string]any{"host": "api.example.com"}, Auth: map[string]map[string]any{"oauth": {"access_token": "access-token", "team_id": "T1", "team_name": "Team"}}}
	for _, tc := range []struct {
		name    string
		request ConnectionLabelRequest
		allowed bool
	}{
		{"profile POST", ConnectionLabelRequest{URL: a.Account.URL, Method: "POST", Headers: a.Account.Headers}, true},
		{"different path", ConnectionLabelRequest{URL: "https://identity.example.test/delete", Method: "POST", Headers: a.Account.Headers}, false},
		{"different method", ConnectionLabelRequest{URL: a.Account.URL, Method: "GET", Headers: a.Account.Headers}, false},
		{"different body", ConnectionLabelRequest{URL: a.Account.URL, Method: "POST", Headers: a.Account.Headers, Body: map[string]any{"delete": true}}, false},
	} {
		if _, err := m.WithConnectionLabels([]ConnectionLabelRule{{Request: &tc.request, Select: "/email"}}, c); (err == nil) != tc.allowed {
			t.Errorf("%s: %v", tc.name, err)
		}
	}
	// A previous explicit label can authorize an otherwise unavailable profile
	// endpoint, but only its selected request and credential injection survive.
	m.ConnectionLabel = []ConnectionLabelRule{{Request: &ConnectionLabelRequest{URL: "https://profile.example.test/account", Headers: a.Account.Headers}, Select: "/old_name"}}
	request := *m.ConnectionLabel[0].Request
	if _, err := m.WithConnectionLabels([]ConnectionLabelRule{{Request: &request, Select: "/new_name"}}, c); err != nil {
		t.Fatalf("changing only the selector lost approved profile authority: %v", err)
	}
	request.URL += "/other"
	if _, err := m.WithConnectionLabels([]ConnectionLabelRule{{Request: &request, Select: "/new_name"}}, c); err == nil {
		t.Fatal("same-origin profile change exceeded approved request authority")
	}
}

func TestConnectionLabelRequestRejectsMethodOverrides(t *testing.T) {
	for _, request := range []ConnectionLabelRequest{
		{URL: "https://api.example.test/profile?_method=DELETE"},
		{URL: "https://api.example.test/profile", Headers: map[string]HeaderValue{"X-HTTP-Method-Override": {Value: "DELETE"}}},
	} {
		if _, _, err := request.Prepare(Context{}); err == nil {
			t.Fatal("label lookup accepted a provider method override")
		}
	}
}
