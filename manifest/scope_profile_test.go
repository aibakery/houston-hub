package manifest

import (
	"reflect"
	"strings"
	"testing"
)

func TestPipedreamScopeProfileSelection(t *testing.T) {
	m, err := Parse([]byte(brokerManifest))
	if err != nil {
		t.Fatal(err)
	}
	publisher := map[string]any{"id": "client", "secret": "secret", "project": "proj_test", "environment": "development"}
	a := m.Auth["broker"]
	a.Scopes = []ScopeGroup{{If: `{{ is publisher.environment "development" }}`, Profile: "read_only", Values: []string{"read"}}, {If: `{{ is publisher.environment "production" }}`, Profile: "read_write", Values: []string{"read", "write"}}}
	m.Auth["broker"] = a
	for _, test := range []struct {
		environment, profile string
		scopes               []string
	}{{"development", "read_only", []string{"read"}}, {"production", "read_write", []string{"read", "write"}}} {
		publisher["environment"] = test.environment
		r, err := m.Resolve(publisher, nil, nil, "broker")
		if err != nil {
			t.Fatal(err)
		}
		if r.ScopeProfile != test.profile || !reflect.DeepEqual(r.Scopes, test.scopes) {
			t.Fatalf("unexpected consent selection: %+v", r)
		}
	}
	for _, groups := range [][]ScopeGroup{
		{{If: `{{ is publisher.environment "development" }}`, Profile: "read_only", Values: []string{"read"}}},
		{{Profile: "read_only", Values: []string{"read"}}, {Profile: "read_write", Values: []string{"read", "write"}}},
	} {
		a.Scopes = groups
		m.Auth["broker"] = a
		if _, err := m.Resolve(publisher, nil, nil, "broker"); err == nil {
			t.Fatal("ambiguous or unavailable consent profile accepted")
		}
	}
}

func TestPipedreamScopeProfileValidation(t *testing.T) {
	for _, profile := range []string{"read_only", "read_write", "admin", "unknown"} {
		raw := strings.Replace(brokerManifest, `"values":["read"]`, `"profile":"`+profile+`","values":["read"]`, 1)
		_, err := Parse([]byte(raw))
		if (err == nil) != (profile != "unknown") {
			t.Fatalf("profile %s: %v", profile, err)
		}
	}
	m, err := Parse([]byte(brokerManifest))
	if err != nil {
		t.Fatal(err)
	}
	a := m.Auth["broker"]
	a.Type, a.AuthorizeURL, a.TokenURL = "oauth2", "https://example.com/authorize", "https://example.com/token"
	a.Scopes = []ScopeGroup{{Profile: "read_only", Values: []string{"read"}}}
	if err := m.validateOAuth("broker", a, map[string]bool{}); err == nil || !strings.Contains(err.Error(), "scope profiles require") {
		t.Fatal("OAuth accepted broker-only scope profile")
	}
}
