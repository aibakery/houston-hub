package manifest

import (
	"encoding/json"
	"fmt"
	"net/url"
	"reflect"
	"strings"
	"testing"
)

func TestQueryInjectionSelectionEncodingAndSnapshot(t *testing.T) {
	m := parseRules(t, `[
 {"if":"{{ is config.enabled true }}","match":{"protocol":"http","host":["api.example.com"],"path":["/v1/*"]},"action":{"query":{"access_token":"{{config.token}}","empty":""},"rewrite":{"strip_prefix":"/v1"}}},
 {"match":{"protocol":"http","host":["api.example.com"]},"action":{}}
 ]`)
	raw, err := json.Marshal(m)
	if err != nil {
		t.Fatal(err)
	}
	snapshot, err := Parse(raw)
	if err != nil || !reflect.DeepEqual(snapshot.Proxy, m.Proxy) {
		t.Fatalf("query snapshot: %v", err)
	}
	secret := "private +&=/#?%é\r\n"
	for _, enabled := range []bool{true, false} {
		r, err := snapshot.Resolve(nil, map[string]any{"token": secret, "enabled": enabled}, nil, "")
		if err != nil {
			t.Fatal(err)
		}
		original := "https://api.example.com/v1/a%3Ab?access_token=attacker&access%5ftoken=second&tag=a&tag=b&next=x%2Fy&empty=caller"
		recipe, err := r.Proxy.HTTPRecipe("GET", original, nil)
		if err != nil {
			t.Fatal(err)
		}
		prepared, err := recipe.PrepareURL(r.Context)
		if err != nil {
			t.Fatal(err)
		}
		u, _ := url.Parse(prepared)
		q := u.Query()
		if enabled {
			if u.EscapedPath() != "/a%3Ab" || !reflect.DeepEqual(q["access_token"], []string{secret}) || q.Get("next") != "x/y" || !reflect.DeepEqual(q["tag"], []string{"a", "b"}) || !reflect.DeepEqual(q["empty"], []string{""}) {
				t.Fatalf("prepared query/path: %s", prepared)
			}
			if strings.Contains(recipe.URL, secret) || recipe.Query["access_token"] != "{{config.token}}" {
				t.Fatal("preparation mutated recipe")
			}
		} else if prepared != original {
			t.Fatal("inactive query rule altered request")
		}
	}
	for _, destination := range []string{"https://api.example.com.evil.test/v1/a", "http://api.example.com/v1/a"} {
		if _, err := m.Proxy.HTTPRecipe("GET", destination, nil); err == nil {
			t.Fatalf("allowed %s", destination)
		}
	}
}

func TestQueryInjectionRejectsMalformedQueryAndMissingCredential(t *testing.T) {
	m := parseRules(t, `[{"match":{"protocol":"http","host":["api.example.com"]},"action":{"query":{"access_token":"{{config.token}}"}}}]`)
	for _, suffix := range []string{"?bad=%", "?bad=%GG", "?a=b;c=d"} {
		recipe, err := m.Proxy.HTTPRecipe("GET", "https://api.example.com/"+suffix, nil)
		if err != nil {
			t.Fatal(err)
		}
		_, err = recipe.PrepareURL(Context{Config: map[string]any{"token": "private-value"}})
		if err == nil || strings.Contains(err.Error(), suffix) || strings.Contains(err.Error(), "private-value") {
			t.Fatalf("unsafe query error: %v", err)
		}
	}
	recipe, _ := m.Proxy.HTTPRecipe("GET", "https://api.example.com/", nil)
	if _, err := recipe.PrepareURL(Context{}); err == nil {
		t.Fatal("missing token accepted")
	}
	optional := strings.Replace(ruleManifest(`[{"match":{"protocol":"http","host":["api.example.com"]},"action":{"query":{"access_token":"{{config.token}}"}}}]`), `"required":true`, `"required":false`, 1)
	m, err := Parse([]byte(optional))
	if err != nil {
		t.Fatal(err)
	}
	if _, err := m.Resolve(nil, nil, nil, ""); err == nil {
		t.Fatal("connection resolved with missing active query credential")
	}
}

func TestQueryDeclarationValidationAndPublisherOwnership(t *testing.T) {
	m := parseRules(t, `[{"match":{"protocol":"http","host":["api.example.com"]},"action":{"query":{"if":""}}}]`)
	recipe, err := m.Proxy.HTTPRecipe("GET", "https://api.example.com/", nil)
	if err != nil {
		t.Fatal(err)
	}
	if prepared, err := recipe.PrepareURL(Context{}); err != nil || prepared != "https://api.example.com/?if=" {
		t.Fatalf("query dictionary key treated as predicate: %s %v", prepared, err)
	}
	for _, query := range []string{`{"":"x"}`, `{"access token":"x"}`, `{"access_token[]":"x"}`, `{"x&y":"x"}`, `{"x":true}`, `{"x":{"value":"token"}}`, `{"x":"{{config.missing}}"}`, `{"x":"one","x":"two"}`, `null`} {
		input := ruleManifest(`[{"match":{"protocol":"http","host":["api.example.com"]},"action":{"query":` + query + `}}]`)
		if _, err := Parse([]byte(input)); err == nil {
			t.Errorf("accepted %s", query)
		}
	}
	for _, owner := range []string{"publisher", "config"} {
		fields := `"publisher":{"token":{"type":"secret","label":"Token"}},"config":{"host":{"type":"string","label":"Host","required":true}}`
		if owner == "publisher" {
			fields = `"publisher":{"token":{"type":"secret","label":"Token"},"host":{"type":"string","label":"Host","required":true}}`
		}
		input := fmt.Sprintf(`{"schema_version":1,"name":"Query","files":["main.lua"],%s,"proxy":[{"match":{"protocol":"http","host":["{{%s.host}}"]},"action":{"query":{"access_token":"{{publisher.token}}"}}}]}`, fields, owner)
		_, err := Parse([]byte(input))
		if (err == nil) != (owner == "publisher") {
			t.Errorf("%s recipient: %v", owner, err)
		}
	}
	for _, query := range []string{`{"token":"literal"}`, `{}`, `null`} {
		native := `{"schema_version":1,"name":"Database","files":["main.lua"],"proxy":[{"match":{"protocol":"postgres"},"action":{"connection":{"host":"db.example.com","database":"db","user":"reader","password":""},"query":` + query + `}}]}`
		if _, err := Parse([]byte(native)); err == nil {
			t.Fatal("database query action accepted")
		}
	}
}

func TestQueryManagedOAuthAndManualSecrets(t *testing.T) {
	raw := `{"schema_version":1,"name":"Query OAuth","files":["main.lua"],"config":{"client_id":{"type":"string","label":"Client","required":true}},"auth":{"oauth":{"type":"oauth2","label":"OAuth","authorize_url":"https://api.example.com/auth","token_url":"https://api.example.com/token","client_id":"{{config.client_id}}","client_auth":"none","pkce":"S256"},"token":{"type":"manual","label":"Token","config":{"token":{"type":"secret","label":"Token","required":true}}}},"proxy":[{"match":{"protocol":"http","host":["api.example.com"]},"action":{"query":{"access_token":"{{auth.oauth.access_token || auth.token.token}}"}}}]}`
	m, err := Parse([]byte(raw))
	if err != nil {
		t.Fatal(err)
	}
	for _, method := range []string{"oauth", "token"} {
		inputs := map[string]any{}
		if method == "token" {
			inputs["token"] = "manual-secret"
		}
		resolved, err := m.Resolve(nil, map[string]any{"client_id": "public-client"}, inputs, method)
		if err != nil {
			t.Fatal(err)
		}
		if method == "oauth" {
			resolved.Context.Auth[method] = map[string]any{"access_token": "fresh-oauth-secret"}
		}
		recipe, err := resolved.Proxy.HTTPRecipe("GET", "https://api.example.com/records", nil)
		if err != nil {
			t.Fatal(err)
		}
		prepared, err := recipe.PrepareURL(resolved.Context)
		if err != nil {
			t.Fatal(err)
		}
		expected := "manual-secret"
		if method == "oauth" {
			expected = "fresh-oauth-secret"
		}
		if prepared != "https://api.example.com/records?access_token="+expected {
			t.Fatalf("%s: %s", method, prepared)
		}
	}
}
