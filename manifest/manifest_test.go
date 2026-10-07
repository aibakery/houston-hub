package manifest

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

func example(t *testing.T, n int) *Manifest {
	t.Helper()
	b, e := os.ReadFile(fmt.Sprintf("testdata/example-%02d.json", n))
	if e != nil {
		t.Fatal(e)
	}
	m, e := Parse(b)
	if e != nil {
		t.Fatal(e)
	}
	return m
}
func TestCompleteExamples(t *testing.T) {
	files, e := filepath.Glob("testdata/example-*.json")
	if e != nil || len(files) != 8 {
		t.Fatalf("eight checked examples required: %v", e)
	}
	for i := 1; i <= 8; i++ {
		t.Run(fmt.Sprint(i), func(t *testing.T) {
			m := example(t, i)
			b, e := json.Marshal(m)
			if e != nil {
				t.Fatal(e)
			}
			again, e := Parse(b)
			if e != nil {
				t.Fatal(e)
			}
			if !reflect.DeepEqual(m, again) {
				t.Fatal("manifest snapshot serialization changed meaning")
			}
		})
	}
}
func TestStrictShape(t *testing.T) {
	base := `{"description":"test","files":["main.luau"],"name":"test","proxy":[{"match":{"protocol":"http","host":["api.example.com"]},"action":{}}],"schema_version":1}`
	for _, bad := range []string{
		strings.Replace(base, `"name":"test"`, `"name":"test","name":"other"`, 1),
		strings.Replace(base, `"name":"test"`, `"name":null`, 1),
		strings.Replace(base, `"name":"test"`, `"name":"test","id":"old"`, 1),
		base + `{}`,
		strings.Replace(base, `["main.luau"]`, `"main.luau"`, 1),
		strings.Replace(base, `"proxy":`, `"auth":[],"proxy":`, 1),
		strings.Replace(base, `"proxy":`, `"secrets":{},"proxy":`, 1),
		strings.Replace(base, `"action":{}`, `"action":{},"if":""`, 1),
		strings.Replace(base, `"action":{}`, `"action":{"headers":{"set":{"X-Test":{}}}}`, 1),
		strings.Replace(base, `"action":{}`, `"action":{"basic_auth":{"password":""}}`, 1),
		strings.Replace(base, `["main.luau"]`, `["../main.luau"]`, 1),
	} {
		if _, err := Parse([]byte(bad)); err == nil {
			t.Errorf("accepted invalid shape %s", bad)
		}
	}
}
func TestDefaultsAndPrivateProjection(t *testing.T) {
	m := example(t, 2)
	r, e := m.Resolve(nil, map[string]any{"host": "db.example.com", "database": "demo", "username": "reader", "password": " exact secret "}, nil, "")
	if e != nil {
		t.Fatal(e)
	}
	if _, ok := r.PublicConfig["password"]; ok {
		t.Fatal("secret exposed")
	}
	db, e := m.Proxy[r.ProxyIndices[0]].ResolveDatabase(r.Context)
	if e != nil || db.Port != 5432 || db.Password != " exact secret " {
		t.Fatalf("database resolution: %#v %v", db, e)
	}
	for _, bad := range []any{"", "5432", nil, 0, 65536, 3.5} {
		_, e = m.Resolve(nil, map[string]any{"host": "db.example.com", "database": "demo", "username": "reader", "password": "x", "port": bad}, nil, "")
		if e == nil {
			t.Fatalf("accepted invalid port %#v", bad)
		}
	}
}
func TestInactiveValuesAndSelection(t *testing.T) {
	m := example(t, 8)
	r, e := m.Resolve(nil, map[string]any{"password": "old secret", "username": "old", "database": "old"}, map[string]any{"api_key": "public"}, "rest")
	if e != nil {
		t.Fatal(e)
	}
	if (len(r.ProxyIndices) != 1 || r.ProxyIndices[0] != 1) || len(r.PublicConfig) != 1 {
		t.Fatalf("wrong HTTP projection %#v", r.PublicConfig)
	}
	if _, ok := r.Context.Config["password"]; ok {
		t.Fatal("inactive credential resolved")
	}
	if e = r.ValidateSubmission("config", map[string]any{"password": "new"}); e == nil {
		t.Fatal("accepted inactive submission")
	}
	r, e = m.Resolve(nil, map[string]any{"connection_type": "postgres", "password": "secret", "username": "reader"}, nil, "")
	if e != nil || (len(r.ProxyIndices) != 1 || r.ProxyIndices[0] != 2) {
		t.Fatalf("Postgres resolution %v", e)
	}
	if _, ok, _ := r.Context.Lookup("auth.rest"); ok {
		t.Fatal("inactive marker defined")
	}
	if _, e = m.Resolve(nil, map[string]any{"connection_type": "postgres", "password": "secret", "username": "reader"}, nil, "rest"); e == nil {
		t.Fatal("retained ineligible auth selection")
	}
}
func TestUnavailableOAuthDoesNotBlockManual(t *testing.T) {
	m := example(t, 1)
	r, e := m.Resolve(nil, nil, map[string]any{"token": "test-token"}, "api_key")
	if e != nil {
		t.Fatal(e)
	}
	if r.Methods[1].Available {
		t.Fatal("unconfigured OAuth available")
	}
	if _, e = m.Resolve(nil, nil, nil, "oauth"); e == nil {
		t.Fatal("unconfigured selected OAuth accepted")
	}
}
func TestTemplatesAndPredicates(t *testing.T) {
	c := Context{Config: map[string]any{"false": false, "zero": json.Number("0"), "empty": "", "text": "{{config.zero}}"}, SelectedAuth: "key", Auth: map[string]map[string]any{"other": {"token": "inactive"}}}
	for input, want := range map[string]any{"{{config.false || config.zero}}": false, "{{config.zero || config.empty}}": json.Number("0"), "{{config.empty || config.zero}}": "", "{{config.text}}": "{{config.zero}}"} {
		v, e := Render(input, c)
		if e != nil || v != want {
			t.Fatalf("render %s: %#v %v", input, v, e)
		}
	}
	for _, s := range []string{`{{ isDefined config.false }}`, `{{ isDefined config.zero }}`, `{{ isDefined config.empty }}`, `{{ isDefined auth.key }}`, `{{ and (is config.false false) (is config.zero 0) }}`} {
		yes, e := EvaluatePredicate(s, c)
		if e != nil || !yes {
			t.Fatalf("predicate %s: %v", s, e)
		}
	}
	for _, s := range []string{`{{ is config.zero false }}`, `{{ isDefined auth.other }}`, `{{ isDefined auth.other.token }}`} {
		yes, e := EvaluatePredicate(s, c)
		if e != nil || yes {
			t.Fatalf("predicate %s: %v", s, e)
		}
	}
	for _, s := range []string{`true`, `{{ config.false }}`, `{{ or (isDefined config.false) (isDefined config.zero) }}`, `{{ and (isDefined config.false) }}`, `{{ is auth.key "key" }}`, `{{ is config.zero '0' }}`, `{{ isDefined config.false || config.zero }}`, `x {{ isDefined config.false }}`} {
		if _, e := EvaluatePredicate(s, c); e == nil {
			t.Errorf("invalid predicate accepted %s", s)
		}
	}
	if _, e := Render(`{{isDefined config.false}}`, c); e == nil {
		t.Fatal("predicate rendered as value")
	}
	if _, e := Render(`{{auth.key}}`, c); e == nil {
		t.Fatal("method marker rendered")
	}
	c.Errors = map[string]error{"config.missing": fmt.Errorf("required missing")}
	if _, e := EvaluatePredicate(`{{ and (is config.zero 99) (isDefined config.missing) }}`, c); e == nil {
		t.Fatal("short circuit concealed prerequisite error")
	}
}
func TestSensitiveReferenceValidation(t *testing.T) {
	m := example(t, 8)
	m.Proxy[0].If = `{{ is config.password "secret" }}`
	if err := m.Validate(); err == nil {
		t.Fatal("secret comparison selected proxy")
	}
	m = example(t, 1)
	m.Proxy[0].If = `{{ isDefined auth.oauth.access_token }}`
	if err := m.Validate(); err == nil {
		t.Fatal("OAuth token presence selected proxy")
	}
	m = example(t, 2)
	m.Proxy[0].Action.Connection.Host = `{{config.password}}`
	if e := m.Validate(); e == nil {
		t.Fatal("secret destination accepted")
	}
}
func TestCyclesAndOrdering(t *testing.T) {
	m := example(t, 7)
	f := m.Config["page_size"]
	f.If = `{{ isDefined config.page_size }}`
	m.Config["page_size"] = f
	if e := m.Validate(); e == nil {
		t.Fatal("self cycle accepted")
	}
	m = example(t, 8)
	f = m.Config["database"]
	f.Order = -99
	m.Config["database"] = f
	r, e := m.Resolve(nil, map[string]any{"connection_type": "postgres", "username": "reader", "password": "x"}, nil, "")
	if e != nil {
		t.Fatal(e)
	}
	if r.ConnectionFields[0].Name != "connection_type" {
		t.Fatal("presentation order preceded dependency")
	}
}
func TestHTTPRouteReplacementAndRemoval(t *testing.T) {
	m := example(t, 3)
	c := Context{SelectedAuth: "oauth", Auth: map[string]map[string]any{"oauth": {"access_token": "token"}}}
	p := m.Proxy
	recipe, e := p.HTTPRecipe("PUT", "https://files.collaboration.example.com/signed-upload/file", nil)
	if e != nil {
		t.Fatal(e)
	}
	h, e := recipe.Prepare(c, map[string][]string{"Authorization": {"caller"}, "X-Other": {"keep"}})
	if e != nil || h.Get("Authorization") != "" || h.Get("X-Other") != "keep" {
		t.Fatalf("override failed %#v %v", h, e)
	}
	for _, u := range []string{"https://evil.example.com/private/x", "https://files.collaboration.example.com/no-route", "https://files.collaboration.example.com/private/%2e%2e/x", "https://files.collaboration.example.com/private/a%2fb"} {
		if _, e := p.HTTPRecipe("GET", u, nil); e == nil {
			t.Fatalf("allowed unsafe URL %s", u)
		}
	}
}
func TestGeneratedSchemaCurrent(t *testing.T) {
	want, e := Schema()
	if e != nil {
		t.Fatal(e)
	}
	got, e := os.ReadFile("schema.json")
	if e != nil {
		t.Fatal(e)
	}
	if strings.TrimSpace(string(got)) != string(want) {
		t.Fatal("schema.json must be regenerated from manifest.Schema")
	}
}
func TestPublisherRecipientAndFallbackSinks(t *testing.T) {
	m := example(t, 2)
	m.Publisher = map[string]Field{"password": {Type: "secret", Label: "Publisher password", Required: true}}
	m.Proxy[0].Action.Connection.Password = `{{publisher.password || config.password}}`
	if e := m.Validate(); e == nil {
		t.Fatal("publisher secret accepted at connection-controlled target")
	}
	m.Proxy[0].Action.Connection.Host = "db.example.com"
	m.Proxy[0].Action.Connection.Port = 5432
	if e := m.Validate(); e != nil {
		t.Fatal(e)
	}
	m.Proxy[0].Action.Connection.Password = `{{config.username || publisher.password}}`
	if e := m.Validate(); e == nil {
		t.Fatal("ordinary string declassified through fallback")
	}
}
func TestRequiredPrerequisitesAndScopeIsolation(t *testing.T) {
	m := example(t, 1)
	access := m.Config["access"]
	access.Default = nil
	access.Required = true
	m.Config["access"] = access
	if _, e := m.Resolve(nil, nil, map[string]any{"token": "test"}, "api_key"); e == nil {
		t.Fatal("missing required selector hidden")
	}
	m = example(t, 1)
	a := m.Auth["oauth"]
	a.Scopes[0].If = `{{ isDefined publisher.client_id }}`
	m.Auth["oauth"] = a
	if _, e := m.Resolve(nil, nil, map[string]any{"token": "test"}, "api_key"); e != nil {
		t.Fatalf("unselected OAuth scope blocked manual: %v", e)
	}
}
func TestDatabaseTransportDefaults(t *testing.T) {
	m := example(t, 6)
	for tr, port := range map[string]int{"https": 8443, "native": 9440} {
		r, e := m.Resolve(nil, map[string]any{"host": "db.example.com", "transport": tr, "username": "reader", "password": "test"}, nil, "")
		if e != nil {
			t.Fatal(e)
		}
		db, e := m.Proxy[0].ResolveDatabase(r.Context)
		if e != nil || db.Port != port {
			t.Fatalf("%s port = %d (%v)", tr, db.Port, e)
		}
	}
}
func TestAmbiguousAndMissingProxy(t *testing.T) {
	m := example(t, 8)
	m.Proxy[2].If = `{{ is config.connection_type "http" }}`
	if _, e := m.Resolve(nil, nil, map[string]any{"api_key": "test"}, "rest"); e == nil {
		t.Fatal("multiple proxy matches accepted")
	}
	m = example(t, 8)
	m.Proxy = m.Proxy[2:]
	if _, e := m.Resolve(nil, nil, map[string]any{"api_key": "test"}, "rest"); e == nil {
		t.Fatal("zero proxy matches accepted")
	}
}

func TestDatabaseUsesFirstEnabledRule(t *testing.T) {
	m := example(t, 2)
	m.Config["optional_password"] = Field{Type: "secret", Label: "Optional password"}
	later := m.Proxy[0]
	connection := *later.Action.Connection
	connection.Password = "{{config.optional_password}}"
	later.Action.Connection = &connection
	m.Proxy = append(m.Proxy, later)
	if err := m.Validate(); err != nil {
		t.Fatal(err)
	}
	config := map[string]any{"host": "db.example.com", "database": "demo", "username": "reader", "password": "first-secret"}
	r, err := m.Resolve(nil, config, nil, "")
	if err != nil || !reflect.DeepEqual(r.ProxyIndices, []int{0, 1}) {
		t.Fatalf("first database rule was blocked by a later rule: %v", err)
	}
	db, err := m.Proxy[r.ProxyIndices[0]].ResolveDatabase(r.Context)
	if err != nil || db.Password != "first-secret" {
		t.Fatalf("first database action not selected: %v", err)
	}
	m.Proxy[0], m.Proxy[1] = m.Proxy[1], m.Proxy[0]
	if _, err := m.Resolve(nil, config, nil, ""); err == nil {
		t.Fatal("failed first database action fell through to later credentials")
	}
}
