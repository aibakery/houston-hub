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

func ruleManifest(rules string) string {
	config := `"enabled":{"type":"boolean","label":"Enabled","default":true}`
	if strings.Contains(rules, "config.token") {
		config += `,"token":{"type":"secret","label":"Token","required":true}`
	}
	return fmt.Sprintf(`{"schema_version":1,"name":"Ordered rules","description":"Shared transport configuration","files":["main.luau"],"config":{%s},"proxy":%s}`, config, rules)
}

func parseRules(t *testing.T, rules string) *Manifest {
	t.Helper()
	m, err := Parse([]byte(ruleManifest(rules)))
	if err != nil {
		t.Fatal(err)
	}
	return m
}

func TestRulesConditionsAndSnapshot(t *testing.T) {
	m := parseRules(t, `[
 {"if":"{{ is config.enabled true }}","match":{"protocol":"http","host":["api.example.com","*.api.example.com"],"method":["GET","POST"],"path":["/records/*","/users/*"]},"action":{"headers":{"set":{"Authorization":"Bearer {{config.token}}","X-Off":{"value":"never","if":"{{ is config.enabled false }}"}}}}},
 {"match":{"protocol":"http","host":["api.example.com","*.api.example.com"]},"action":{}}
 ]`)
	encoded, err := json.Marshal(m)
	if err != nil {
		t.Fatal(err)
	}
	var snapshot Manifest
	if err = json.Unmarshal(encoded, &snapshot); err != nil || !reflect.DeepEqual(m.Proxy, snapshot.Proxy) {
		t.Fatalf("snapshot changed rules: %v", err)
	}
	for _, enabled := range []bool{true, false} {
		r, err := snapshot.Resolve(nil, map[string]any{"token": "bound-secret", "enabled": enabled}, nil, "")
		if err != nil {
			t.Fatal(err)
		}
		rules := snapshot.Proxy.Select(r.ProxyIndices)
		wantCount := 1
		if enabled {
			wantCount = 2
		}
		if len(rules) != wantCount {
			t.Fatalf("active rules: %v", r.ProxyIndices)
		}
		for _, host := range []string{"api.example.com", "phl.api.example.com"} {
			caller := http.Header{"Authorization": {"caller"}, "X-Off": {"caller"}}
			recipe, err := rules.HTTPRecipe("GET", "https://"+host+"/records/a", caller)
			if err != nil {
				t.Fatal(err)
			}
			headers, err := recipe.Prepare(r.Context, caller)
			wantAuth := "caller"
			if enabled {
				wantAuth = "Bearer bound-secret"
			}
			if err != nil || headers.Get("Authorization") != wantAuth || headers.Get("X-Off") != "caller" {
				t.Fatalf("headers: %v %v", headers, err)
			}
			if caller.Get("Authorization") != "caller" {
				t.Fatal("modified original headers")
			}
			for method := range methods {
				recipe, err = rules.HTTPRecipe(method, "https://"+host+"/signed/a", caller)
				if err != nil {
					t.Fatal(err)
				}
				headers, err = recipe.Prepare(r.Context, caller)
				if err != nil || headers.Get("Authorization") != "caller" {
					t.Fatalf("unselected action changed caller header: %v %v", headers, err)
				}
			}
		}
	}
}

func TestRulesHeaderMatchingAndPriority(t *testing.T) {
	m := parseRules(t, `[
 {"match":{"protocol":"http","host":["api.example.com"],"method":["GET"],"path":["/v1/*"],"header":{"X-Mode":"special","X-Present":true}},"action":{"headers":{"set":{"X-Selected":"specific","X-Mode":"changed"},"remove":["X-Present"]}}},
 {"match":{"protocol":"http","host":["api.example.com"]},"action":{"headers":{"set":{"X-Selected":"fallback"}}}}
 ]`)
	for _, tc := range []struct {
		name, method, path string
		headers            http.Header
		want               string
	}{
		{"all filters", "GET", "/v1/a", http.Header{"X-Mode": {"other", "special"}, "X-Present": {""}}, "specific"},
		{"header casing", "GET", "/v1/a", http.Header{"x-mode": {"special"}, "x-present": {"yes"}}, "specific"},
		{"missing presence", "GET", "/v1/a", http.Header{"X-Mode": {"special"}}, "fallback"},
		{"wrong value", "GET", "/v1/a", http.Header{"X-Mode": {"SPECIAL"}, "X-Present": {"yes"}}, "fallback"},
		{"not combined values", "GET", "/v1/a", http.Header{"X-Mode": {"spe", "cial"}, "X-Present": {"yes"}}, "fallback"},
		{"wrong method", "POST", "/v1/a", http.Header{"X-Mode": {"special"}, "X-Present": {"yes"}}, "fallback"},
		{"wrong path", "GET", "/v2/a", http.Header{"X-Mode": {"special"}, "X-Present": {"yes"}}, "fallback"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			recipe, err := m.Proxy.HTTPRecipe(tc.method, "https://api.example.com"+tc.path, tc.headers)
			if err != nil {
				t.Fatal(err)
			}
			headers, err := recipe.Prepare(Context{}, tc.headers)
			if err != nil || headers.Get("X-Selected") != tc.want {
				t.Fatalf("selection: %v %v", headers, err)
			}
			if tc.want == "specific" && (headers.Get("X-Mode") != "changed" || headers.Get("X-Present") != "") {
				t.Fatalf("action: %v", headers)
			}
		})
	}
	m.Proxy[0], m.Proxy[1] = m.Proxy[1], m.Proxy[0]
	recipe, err := m.Proxy.HTTPRecipe("GET", "https://api.example.com/v1/a", http.Header{"X-Mode": {"special"}, "X-Present": {"yes"}})
	if err != nil || recipe.Headers["X-Selected"].Value != "fallback" {
		t.Fatalf("first matching rule did not win: %v %v", recipe, err)
	}
}

func TestRulesRemoveAndConditionalSet(t *testing.T) {
	m := parseRules(t, `[{"match":{"protocol":"http","host":["api.example.com"]},"action":{"headers":{"remove":["Authorization","X-Delete"],"set":{"Authorization":{"value":"Bearer {{config.token}}","if":"{{ is config.enabled true }}"},"X-Keep":{"value":"replacement","if":"{{ is config.enabled true }}"}}}}}]`)
	for _, enabled := range []bool{true, false} {
		caller := http.Header{"Authorization": {"caller"}, "X-Delete": {"private"}, "X-Keep": {"original"}}
		recipe, err := m.Proxy.HTTPRecipe("GET", "https://api.example.com/", caller)
		if err != nil {
			t.Fatal(err)
		}
		h, err := recipe.Prepare(Context{Config: map[string]any{"token": "secret", "enabled": enabled}}, caller)
		if err != nil {
			t.Fatal(err)
		}
		auth, keep := "", "original"
		if enabled {
			auth, keep = "Bearer secret", "replacement"
		}
		if h.Get("Authorization") != auth || h.Get("X-Keep") != keep || h.Get("X-Delete") != "" {
			t.Fatalf("remove/set order: %v", h)
		}
	}
}

func TestHeaderNamedIfIsNotAPredicate(t *testing.T) {
	for _, filter := range []string{`true`, `""`} {
		m := parseRules(t, `[{"match":{"protocol":"http","host":["api.example.com"],"header":{"if":`+filter+`}},"action":{"headers":{"set":{"if":""}}}}]`)
		recipe, err := m.Proxy.HTTPRecipe("GET", "https://api.example.com/", http.Header{"If": {""}})
		if err != nil {
			t.Fatal(err)
		}
		headers, err := recipe.Prepare(Context{}, http.Header{"If": {"original"}})
		if err != nil || !reflect.DeepEqual(headers.Values("If"), []string{""}) {
			t.Fatalf("header named if: %v %v", headers, err)
		}
	}
}

func TestHeaderValueDecodeReplacesPriorCondition(t *testing.T) {
	var value HeaderValue
	if err := json.Unmarshal([]byte(`{"value":"guarded","if":"{{ is config.enabled true }}"}`), &value); err != nil {
		t.Fatal(err)
	}
	if err := json.Unmarshal([]byte(`"unconditional"`), &value); err != nil {
		t.Fatal(err)
	}
	if value.Value != "unconditional" || value.If != "" {
		t.Fatalf("retained previous header state: %#v", value)
	}
}

func TestRulesRejectInvalidDeclarations(t *testing.T) {
	for _, rule := range []string{
		`{}`, `{"match":{"protocol":"http","host":["api.example.com"]}}`, `{"action":{}}`,
		`{"match":{"host":["api.example.com"]},"action":{}}`,
		`{"match":{"protocol":"http"},"action":{}}`,
		`{"match":{"protocol":"http","host":[]},"action":{}}`,
		`{"match":{"protocol":"http","host":["api.example.com"],"method":[]},"action":{}}`,
		`{"match":{"protocol":"http","host":["api.example.com"],"method":["get"]},"action":{}}`,
		`{"match":{"protocol":"http","host":["api.example.com"],"method":["GET","GET"]},"action":{}}`,
		`{"match":{"protocol":"http","host":["api.example.com"],"path":[]},"action":{}}`,
		`{"match":{"protocol":"http","host":["api.example.com"],"path":["/","/"]},"action":{}}`,
		`{"match":{"protocol":"http","host":["api.example.com"],"header":{"X-Test":false}},"action":{}}`,
		`{"match":{"protocol":"http","host":["api.example.com"],"header":{"X-Test":42}},"action":{}}`,
		`{"match":{"protocol":"http","host":["api.example.com"],"header":{"X-Test":true,"x-test":"value"}},"action":{}}`,
		`{"match":{"protocol":"http","host":["api.example.com"]},"action":{"headers":{"set":{"X-Test":"a","x-test":"b"}}}}`,
		`{"match":{"protocol":"http","host":["api.example.com"]},"action":{"headers":{"remove":["X-Test","x-test"]}}}`,
		`{"match":{"protocol":"http","host":["api.example.com"]},"action":{"headers":{"set":{"X-Test":{}}}}}`,
		`{"match":{"protocol":"http","host":["api.example.com"]},"action":{"headers":{"set":{"if":{"value":"x","if":""}}}}}`,
		`{"match":{"protocol":"http","host":["api.example.com"]},"action":{"headers":{"remove":["SomeOtherHeader "]}}}`,
		`{"origins":["api.example.com"],"routes":[{"path":["/"]}]}`,
	} {
		if _, err := Parse([]byte(ruleManifest("[" + rule + "]"))); err == nil {
			t.Errorf("accepted %s", rule)
		}
	}
}

func TestHostPatternValidation(t *testing.T) {
	for _, host := range []string{"api.example.com", "*.api.example.com", "*.API.example.com:443", "*.example.com:8443", "[::1]:8443"} {
		m := parseRules(t, `[{"match":{"protocol":"http","host":["api.example.com"]},"action":{}}]`)
		m.Proxy[0].Match.Host = []string{host}
		if err := m.Validate(); err != nil {
			t.Errorf("%s: %v", host, err)
		}
	}
	for _, host := range []string{"*", "*example.com", "api.*.com", "*.*.example.com", "*.127.0.0.1", "*.[::1]", "*.bad..example.com", "*.example.com/", "*.example.com?token=x", "user@*.example.com", "https://api.example.com", "http://*.example.com", "{{config.host}}"} {
		m := parseRules(t, `[{"match":{"protocol":"http","host":["api.example.com"]},"action":{}}]`)
		m.Proxy[0].Match.Host = []string{host}
		if err := m.Validate(); err == nil {
			t.Errorf("accepted %s", host)
		}
	}
	m := parseRules(t, `[{"match":{"protocol":"http","host":["api.example.com"]},"action":{}}]`)
	m.Proxy[0].Match.Host = []string{"*.EXAMPLE.com:443", "*.example.com"}
	if err := m.Validate(); err == nil {
		t.Fatal("accepted duplicate normalized wildcard")
	}
}

func TestWildcardHostBoundariesAndSafeDenial(t *testing.T) {
	m := parseRules(t, `[{"match":{"protocol":"http","host":["*.API.example.com:443","*.example.net:8443"]},"action":{}}]`)
	for _, origin := range []string{"https://phl.api.example.com", "https://a.phl.api.example.com:443", "https://PHL.API.EXAMPLE.COM", "https://a.example.net:8443"} {
		if _, err := m.Proxy.HTTPRecipe("GET", origin+"/path", nil); err != nil {
			t.Errorf("%s: %v", origin, err)
		}
	}
	for _, origin := range []string{"https://api.example.com", "https://notapi.example.com", "https://api.example.com.evil.test", "https://a.api.example.com:8443", "https://example.net:8443", "https://a.example.net"} {
		_, err := m.Proxy.HTTPRecipe("GET", origin+"/private-message?token=secret", nil)
		var denied *OriginDeniedError
		if !errors.As(err, &denied) || denied.Origin != origin || err.Error() != "origin denied: "+origin {
			t.Errorf("expected origin-only denial for %s, got %v", origin, err)
		}
	}
	for _, raw := range []string{"https://*.api.example.com/path", "https://.api.example.com/path", "https://a..api.example.com/path", "https://user:secret@a.api.example.com/path", "http://a.api.example.com/path"} {
		if _, err := m.Proxy.HTTPRecipe("GET", raw, nil); err == nil {
			t.Errorf("accepted invalid request %s", raw)
		} else if strings.Contains(err.Error(), "secret") {
			t.Errorf("error leaks userinfo: %v", err)
		}
	}
}
