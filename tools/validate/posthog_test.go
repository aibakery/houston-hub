package main

import "testing"

func TestPostHogReadOnlyRoutes(t *testing.T) {
	m := parseManifest(t, "../../connectors/posthog/houston.json")
	if _, err := m.Resolve(nil, nil, nil, "token"); err == nil {
		t.Fatal("accepted missing personal API key")
	}
	if _, err := m.Resolve(nil, map[string]any{"region": "posthog.example.com"}, map[string]any{"token": "phx_fixture"}, "token"); err == nil {
		t.Fatal("accepted a host outside the cloud regions")
	}
	for region, other := range map[string]string{"us.posthog.com": "eu.posthog.com", "eu.posthog.com": "us.posthog.com"} {
		r, err := m.Resolve(nil, map[string]any{"region": region}, map[string]any{"token": "phx_fixture"}, "token")
		if err != nil {
			t.Fatal(err)
		}
		host := "https://" + region
		project := host + "/api/projects/12345"
		assertRoutes(t, r, "phx_fixture", true,
			"GET "+host+"/api/organizations/?limit=100", "GET "+host+"/api/organizations/@current/projects/?limit=100",
			"GET "+host+"/api/organizations/0188430e-316e-0000-51a6-fd646548690e/projects/?limit=100&offset=100",
			"GET "+project+"/events/?event=%24pageview&limit=100", "GET "+project+"/persons/?search=ana&limit=100",
			"GET "+project+"/insights/?basic=true&limit=100", "GET "+project+"/insights/AaVQ8Ijw/?refresh=blocking",
			"GET "+project+"/feature_flags/?active=true&limit=50", "GET "+host+"/api/projects/@current/events/?limit=1",
			"POST "+project+"/query/")
		// Writes, event capture, flag evaluation, deletion and project settings (which hold the secret
		// feature flag key) stay denied, as do the other region, other hosts and paths without the trailing slash.
		assertRoutes(t, r, "phx_fixture", false,
			"POST "+project+"/insights/", "PATCH "+project+"/insights/1/", "DELETE "+project+"/persons/1/",
			"POST "+project+"/feature_flags/", "PATCH "+project+"/feature_flags/1/", "GET "+project+"/feature_flags/1/",
			"GET "+project+"/query/abc/", "DELETE "+project+"/query/abc/", "GET "+project+"/query/",
			"POST "+project+"/events/", "GET "+project+"/events/018f/", "GET "+project+"/persons/1/",
			"GET "+host+"/api/projects/", "GET "+project+"/", "GET "+host+"/api/users/@me/",
			"GET "+host+"/api/personal_api_keys/", "POST "+host+"/api/organizations/", "GET "+project+"/events",
			"GET "+project+"/insights/%2e%2e/", "GET "+host+"/api/environments/12345/events/",
			"POST https://us.i.posthog.com/i/v0/e/", "POST https://eu.i.posthog.com/batch/", "POST https://us.i.posthog.com/flags/",
			"GET https://app.posthog.com/api/projects/12345/events/", "GET https://us.posthog.com.example.com/api/organizations/",
			"GET http://us.posthog.com:8080/api/organizations/",
			"GET https://"+other+"/api/organizations/", "POST https://"+other+"/api/projects/12345/query/")
	}
}
