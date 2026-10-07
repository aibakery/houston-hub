package manifest

import (
	"errors"
	"net/http"
	"testing"
)

func TestOriginPatternValidation(t *testing.T) {
	for _, origin := range []string{"https://api.example.com", "https://*.api.example.com", "https://*.API.example.com:443", "https://*.example.com:8443", "https://[::1]:8443"} {
		m := example(t, 3)
		m.Proxy[0].Origins = map[string]HTTPOrigin{origin: {}}
		if err := m.Validate(); err != nil {
			t.Errorf("%s: %v", origin, err)
		}
	}
	for _, origin := range []string{"https://*", "https://*example.com", "https://api.*.com", "https://*.*.example.com", "https://*.127.0.0.1", "https://*.[::1]", "https://*.bad..example.com", "https://*.example.com/", "https://*.example.com?token=x", "https://user@*.example.com", "http://*.example.com", "https://{{config.host}}"} {
		m := example(t, 3)
		m.Proxy[0].Origins = map[string]HTTPOrigin{origin: {}}
		if err := m.Validate(); err == nil {
			t.Errorf("accepted %s", origin)
		}
	}
	m := example(t, 3)
	m.Proxy[0].Origins = map[string]HTTPOrigin{"https://*.EXAMPLE.com:443": {}, "https://*.example.com": {}}
	if err := m.Validate(); err == nil {
		t.Fatal("accepted duplicate normalized wildcard")
	}
}

func TestWildcardOriginBoundaries(t *testing.T) {
	p := Proxy{Protocol: "http", Origins: map[string]HTTPOrigin{"https://*.API.example.com:443": {}, "https://*.example.net:8443": {}}}
	for _, origin := range []string{"https://phl.api.example.com", "https://a.phl.api.example.com:443", "https://PHL.API.EXAMPLE.COM", "https://a.example.net:8443"} {
		if _, err := p.HTTPRecipe("GET", origin+"/path"); err != nil {
			t.Errorf("%s: %v", origin, err)
		}
	}
	for _, origin := range []string{"https://api.example.com", "https://notapi.example.com", "https://api.example.com.evil.test", "https://a.api.example.com:8443", "https://example.net:8443", "https://a.example.net"} {
		_, err := p.HTTPRecipe("GET", origin+"/private-message?token=secret")
		var denied *OriginDeniedError
		if !errors.As(err, &denied) || denied.Origin != origin || err.Error() != "origin denied: "+origin {
			t.Errorf("expected origin-only denial for %s, got %v", origin, err)
		}
	}
	for _, raw := range []string{"https://*.api.example.com/path", "https://.api.example.com/path", "https://a..api.example.com/path", "https://user:secret@a.api.example.com/path", "http://a.api.example.com/path"} {
		if _, err := p.HTTPRecipe("GET", raw); err == nil {
			t.Errorf("accepted invalid request %s", raw)
		}
	}
}

func TestOriginSpecificityDoesNotMergeOrFallback(t *testing.T) {
	p := Proxy{Protocol: "http", Origins: map[string]HTTPOrigin{
		"https://*.example.com":           {Headers: map[string]HeaderValue{"Authorization": {Value: "Bearer broad"}}},
		"https://*.api.example.com":       {Headers: map[string]HeaderValue{"Authorization": {Value: "Bearer {{config.token}}"}}, Allowlist: []AllowedRequest{{Methods: []string{"GET"}, Paths: []string{"/allowed"}}}},
		"https://special.api.example.com": {Allowlist: []AllowedRequest{{Methods: []string{"POST"}, Paths: []string{"/exact"}}}},
	}}
	for _, tc := range []struct{ method, url, auth string }{
		{"GET", "https://other.example.com/anything", "Bearer broad"},
		{"GET", "https://phl.api.example.com/allowed", "Bearer scoped"},
		{"POST", "https://special.api.example.com/exact", ""},
	} {
		recipe, err := p.HTTPRecipe(tc.method, tc.url)
		if err != nil {
			t.Fatal(err)
		}
		headers, err := recipe.Prepare(Context{Config: map[string]any{"token": "scoped"}}, http.Header{})
		if err != nil || headers.Get("Authorization") != tc.auth {
			t.Fatalf("%s: %v %v", tc.url, headers, err)
		}
	}
	for _, tc := range [][2]string{{"GET", "https://special.api.example.com/allowed"}, {"GET", "https://phl.api.example.com/anything"}, {"POST", "https://phl.api.example.com/allowed"}} {
		if _, err := p.HTTPRecipe(tc[0], tc[1]); err == nil || err.Error() != "route denied" {
			t.Fatalf("route fell back: %v %v", tc, err)
		}
	}
}
