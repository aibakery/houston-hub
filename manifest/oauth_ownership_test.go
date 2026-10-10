package manifest

import "testing"

func TestOAuthClientsRequireConnectionFields(t *testing.T) {
	m := example(t, 1)
	method := m.Auth["oauth"]
	m.Publisher["client_id"] = m.Config["client_id"]
	m.Publisher["client_secret"] = m.Config["client_secret"]
	delete(m.Config, "client_id")
	delete(m.Config, "client_secret")
	method.ClientID = "{{publisher.client_id}}"
	method.ClientSecret = "{{publisher.client_secret}}"
	m.Auth["oauth"] = method
	if err := m.Validate(); err == nil {
		t.Fatal("publication-owned OAuth client credentials accepted")
	}
}
