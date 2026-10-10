package manifest

import (
	"encoding/json"
	"strings"
	"testing"
)

func TestOAuthTokenEncodingAndHeaders(t *testing.T) {
	for _, encoding := range []string{"", "form", "json"} {
		t.Run("encoding_"+encoding, func(t *testing.T) {
			m := example(t, 1)
			for key, auth := range m.Auth {
				if auth.Type != "oauth2" {
					continue
				}
				auth.TokenEncoding = encoding
				auth.TokenHeaders = map[string]string{"Notion-Version": "2026-03-11"}
				m.Auth[key] = auth
			}
			body, err := json.Marshal(m)
			if err != nil {
				t.Fatal(err)
			}
			parsed, err := Parse(body)
			if err != nil {
				t.Fatal(err)
			}
			for _, auth := range parsed.Auth {
				if auth.Type != "oauth2" {
					continue
				}
				want := encoding
				if want == "" {
					want = "form"
				}
				if auth.TokenEncoding != want || auth.TokenHeaders["Notion-Version"] != "2026-03-11" {
					t.Fatal("token transport settings did not survive parsing")
				}
			}
		})
	}
	for _, headers := range []map[string]string{
		{"Authorization": "Basic attacker"}, {"content-TYPE": "text/plain"},
		{"Host": "attacker.test"}, {"Transfer-Encoding": "chunked"},
		{"X-Houston-Token": "x"}, {"bad header": "x"},
		{"Notion-Version": "a", "notion-version": "b"},
		{"Notion-Version": "2026\r\nx-injected: yes"},
		{"Notion-Version": "{{config.client_secret}}"},
	} {
		if err := ValidateTokenHeaders(headers); err == nil {
			t.Errorf("accepted unsafe token headers: %v", headers)
		}
	}
	m := example(t, 1)
	for key, auth := range m.Auth {
		if auth.Type != "oauth2" {
			continue
		}
		auth.TokenEncoding = "xml"
		m.Auth[key] = auth
	}
	body, err := json.Marshal(m)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := Parse(body); err == nil {
		t.Fatal("accepted unknown token encoding")
	}
	if _, err := Parse([]byte(strings.ReplaceAll(string(body), `"token_encoding":"xml"`, `"token_encoding":""`))); err == nil {
		t.Fatal("accepted explicit empty token encoding")
	}
	manual := `{"schema_version":1,"name":"Manual","files":["connector.lua"],"auth":{"token":{"type":"manual","label":"Token","config":{"token":{"type":"secret","label":"Token"}},%s}},"proxy":[{"match":{"protocol":"http","host":["api.example.com"]},"action":{"headers":{"set":{"Authorization":"{{auth.token.token}}"}}}}]}`
	for _, setting := range []string{`"token_encoding":"json"`, `"token_headers":{}`} {
		if _, err := Parse([]byte(strings.Replace(manual, "%s", setting, 1))); err == nil {
			t.Fatal("accepted OAuth token setting on manual method")
		}
	}
}
