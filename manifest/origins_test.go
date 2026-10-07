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
 {"if":"{{ is config.enabled true }}","match":{"protocol":"http","host":["api.example.com","*.api.example.com"],"method":["GET","POST"],"path":["/records/*","/users/*"]},"action":{"headers":{"set":{"Authorization":"Bearer {{config.token}}"},"remove":["X-Off"]}}},
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
			wantOff := "caller"
			if enabled {
				wantAuth = "Bearer bound-secret"
				wantOff = ""
			}
			if err != nil || headers.Get("Authorization") != wantAuth || headers.Get("X-Off") != wantOff {
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

func TestRulesOptionalSecretAndFallback(t *testing.T) {
	for _, source := range []string{"config", "publisher", "manual"} {
		t.Run(source, func(t *testing.T) {
			ref, selected := source+".token", ""
			fields := `"` + source + `":{"token":{"type":"secret","label":"Optional token"}}`
			if source == "manual" {
				ref, selected = "auth.manual.token", "manual"
				fields = `"auth":{"manual":{"type":"manual","label":"Manual","config":{"token":{"type":"secret","label":"Optional token"}}}}`
			}
			data := fmt.Sprintf(`{"schema_version":1,"name":"Optional credential","description":"Rule fallback","files":["main.luau"],%s,"proxy":[
 {"if":"{{ isDefined %s }}","match":{"protocol":"http","host":["api.example.com"]},"action":{"headers":{"remove":["Authorization"],"set":{"Authorization":"Bearer {{%s}}","X-Selected":"credential"}}}},
 {"match":{"protocol":"http","host":["api.example.com"]},"action":{"headers":{"remove":["Authorization"],"set":{"X-Selected":"fallback"}}}}
 ]}`, fields, ref, ref)
			m, err := Parse([]byte(data))
			if err != nil {
				t.Fatal(err)
			}
			for _, present := range []bool{true, false} {
				var publisher, config, auth map[string]any
				if present {
					values := map[string]any{"token": "secret"}
					switch source {
					case "config":
						config = values
					case "publisher":
						publisher = values
					case "manual":
						auth = values
					}
				}
				r, err := m.Resolve(publisher, config, auth, selected)
				if err != nil {
					t.Fatal(err)
				}
				caller := http.Header{"Authorization": {"caller"}}
				recipe, err := m.Proxy.Select(r.ProxyIndices).HTTPRecipe("GET", "https://api.example.com/", caller)
				if err != nil {
					t.Fatal(err)
				}
				h, err := recipe.Prepare(r.Context, caller)
				wantAuth, wantRule := "", "fallback"
				if present {
					wantAuth, wantRule = "Bearer secret", "credential"
				}
				if err != nil || h.Get("Authorization") != wantAuth || h.Get("X-Selected") != wantRule {
					t.Fatalf("present=%v, headers=%v, error=%v", present, h, err)
				}
			}
			m.Proxy[0].If = `{{ is ` + ref + ` "guess" }}`
			if err := m.Validate(); err == nil {
				t.Fatal("accepted secret equality in rule predicate")
			}
		})
	}
}

func TestRulesOAuthSelectionUsesMethodMarker(t *testing.T) {
	data := `{"schema_version":1,"name":"OAuth rules","description":"Stable selection","files":["main.luau"],"publisher":{"client_id":{"type":"string","label":"Client","required":true}},"auth":{"oauth":{"type":"oauth2","label":"OAuth","authorize_url":"https://example.com/auth","token_url":"https://example.com/token","client_id":"{{publisher.client_id}}","client_auth":"none","pkce":"S256"}},"proxy":[{"if":"{{ isDefined auth.oauth }}","match":{"protocol":"http","host":["api.example.com"]},"action":{"headers":{"set":{"Authorization":"Bearer {{auth.oauth.access_token}}"}}}}]}`
	m, err := Parse([]byte(data))
	if err != nil {
		t.Fatal(err)
	}
	r, err := m.Resolve(map[string]any{"client_id": "client"}, nil, nil, "oauth")
	if err != nil || !reflect.DeepEqual(r.ProxyIndices, []int{0}) {
		t.Fatalf("OAuth rule unavailable before token acquisition: %v %v", r, err)
	}
	m.Proxy[0].If = "{{ isDefined auth.oauth.access_token }}"
	if err := m.Validate(); err == nil {
		t.Fatal("accepted rule selection depending on managed OAuth token")
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
		`{"match":{"protocol":"http","host":["api.example.com"]},"action":{"headers":{"set":{"X-Test":{"value":"x"}}}}}`,
		`{"match":{"protocol":"http","host":["api.example.com"]},"action":{"headers":{"set":{"X-Test":{"value":"x","if":"{{ is config.enabled true }}"}}}}}`,
		`{"match":{"protocol":"http","host":["api.example.com"],"if":"{{ is config.enabled true }}"},"action":{}}`,
		`{"match":{"protocol":"http","host":["api.example.com"]},"action":{"if":"{{ is config.enabled true }}"}}`,
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
