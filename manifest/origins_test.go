package manifest

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"reflect"
	"strings"
	"testing"
)

func originManifest(origins string) string {
	return fmt.Sprintf(`{"schema_version":1,"name":"Origin groups","description":"Shared transport configuration","files":["main.luau"],"config":{"token":{"type":"secret","label":"Token","required":true}},"proxy":[{"protocol":"http","origins":%s}]}`, origins)
}

func TestOriginGroupsShareExistingTransportSemantics(t *testing.T) {
	const config = `{"headers":{"Authorization":{"value":"Bearer {{config.token}}"}},"allowlist":[{"methods":["GET"],"paths":["/records/*"]},{"methods":["PUT"],"paths":["/signed/*"],"headers":{}}]}`
	grouped := `[{"match":["https://api.example.com","https://*.api.example.com"],"config":` + config + `},{"match":["https://special.api.example.com"],"config":{"allowlist":[{"methods":["POST"],"paths":["/exact"]}]}}]`
	expanded := `{"https://api.example.com":` + config + `,"https://*.api.example.com":` + config + `,"https://special.api.example.com":{"allowlist":[{"methods":["POST"],"paths":["/exact"]}]}}`
	m, err := Parse([]byte(originManifest(grouped)))
	if err != nil {
		t.Fatal(err)
	}
	want, err := Parse([]byte(originManifest(expanded)))
	if err != nil || !reflect.DeepEqual(m, want) {
		t.Fatalf("group expansion changed semantics: %v", err)
	}
	encoded, err := json.Marshal(m)
	if err != nil {
		t.Fatal(err)
	}
	var snapshot Manifest
	if err := json.Unmarshal(encoded, &snapshot); err != nil || !reflect.DeepEqual(m.Proxy, snapshot.Proxy) {
		t.Fatalf("snapshot changed groups: %v", err)
	}
	r, err := snapshot.Resolve(nil, map[string]any{"token": "bound-secret"}, nil, "")
	if err != nil {
		t.Fatal(err)
	}
	p := snapshot.Proxy[r.ProxyIndex]
	for _, tc := range []struct{ method, url, auth string }{
		{"GET", "https://api.example.com/records/a", "Bearer bound-secret"},
		{"GET", "https://phl.api.example.com/records/a", "Bearer bound-secret"},
		{"PUT", "https://phl.api.example.com/signed/a", ""},
		{"POST", "https://special.api.example.com/exact", "caller"},
	} {
		recipe, err := p.HTTPRecipe(tc.method, tc.url)
		if err != nil {
			t.Fatal(err)
		}
		headers, err := recipe.Prepare(r.Context, http.Header{"Authorization": {"caller"}})
		if err != nil || headers.Get("Authorization") != tc.auth {
			t.Fatalf("%s: %v %v", tc.url, headers, err)
		}
	}
	if _, err := p.HTTPRecipe("GET", "https://special.api.example.com/records/a"); err == nil {
		t.Fatal("exact origin fell back to group wildcard")
	}
}

func TestOriginGroupsRejectInvalidDeclarations(t *testing.T) {
	for _, origins := range []string{
		`[]`, `[{}]`, `[{"match":[],"config":{}}]`, `[{"match":["https://api.example.com"]}]`,
		`[{"match":"https://api.example.com","config":{}}]`, `[{"match":[42],"config":{}}]`,
		`[{"match":["https://api.example.com"],"config":{},"extra":true}]`,
		`[{"match":["https://api.example.com"],"config":{"extra":true}}]`,
		`[{"match":["https://api.example.com"],"config":null}]`,
		`[{"match":["https://api.example.com","https://api.example.com"],"config":{}}]`,
		`[{"match":["https://api.example.com"],"config":{}},{"match":["https://api.example.com"],"config":{}}]`,
		`[{"match":["https://*.api.example.com","https://*.API.example.com:443"],"config":{}}]`,
		`[{"match":["https://*.api.example.com"],"config":{}},{"match":["https://*.API.example.com:443"],"config":{}}]`,
		`[{"match":["https://a.*.example.com"],"config":{}}]`,
		`[{"match":["https://api.example.com"],"config":{"headers":{"X-Test":{}}}}]`,
		`[{"match":["https://api.example.com"],"config":{"allowlist":[{"methods":["GET"],"paths":["/"],"headers":{"X-Test":{}}}]}}]`,
		`[{"match":["https://api.example.com"],"config":{"basic_auth":{"password":"secret"}}}]`,
		`[{"match":["https://api.example.com"],"config":{"allowlist":[]}}]`,
	} {
		if _, err := Parse([]byte(originManifest(origins))); err == nil {
			t.Errorf("accepted invalid groups: %s", origins)
		}
	}
	source := strings.Replace(originManifest(`[{"match":["https://api.example.com"],"config":{}}]`), `"protocol":"http"`, `"protocol":"postgres"`, 1)
	if _, err := Parse([]byte(source)); err == nil {
		t.Fatal("database accepted HTTP origin groups")
	}
}

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
