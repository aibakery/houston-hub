package manifest

import "testing"

func TestOAuthClientOwnership(t *testing.T) {
	m := example(t, 1)
	if m.Auth["oauth"].PublisherClient() {
		t.Fatal("connection-owned client reported as publisher-owned")
	}
	m.Publisher["client_id"] = m.Config["client_id"]
	m.Publisher["client_secret"] = m.Config["client_secret"]
	delete(m.Config, "client_id")
	delete(m.Config, "client_secret")
	method := m.Auth["oauth"]
	method.ClientID = "{{publisher.client_id}}"
	method.ClientSecret = "{{publisher.client_secret}}"
	m.Auth["oauth"] = method
	if err := m.Validate(); err != nil {
		t.Fatalf("publication-owned OAuth client rejected: %v", err)
	}
	if !m.Auth["oauth"].PublisherClient() {
		t.Fatal("publication-owned client not reported")
	}
	m.Config["client_secret"] = m.Publisher["client_secret"]
	delete(m.Publisher, "client_secret")
	method.ClientSecret = "{{config.client_secret}}"
	m.Auth["oauth"] = method
	if err := m.Validate(); err == nil {
		t.Fatal("OAuth client split across owners accepted")
	}
}
