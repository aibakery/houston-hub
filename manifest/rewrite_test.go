package manifest

import (
	"fmt"
	"testing"
)

func TestStripPrefixRewrite(t *testing.T) {
	m := parseRules(t, `[{"match":{"protocol":"http","host":["api.example.com"],"path":["/v1","/v1/*"]},"action":{"rewrite":{"strip_prefix":"/v1"}}}]`)
	for _, tc := range []struct{ input, want string }{
		{"/v1", "/"}, {"/v1/", "/"}, {"/v1/records", "/records"},
		{"/v1/records?token=a%2Fb&keep=1", "/records?token=a%2Fb&keep=1"},
		{"/v1/a%20b", "/a%20b"},
		{"/v1/a%3Bb", "/a%3Bb"},
		{"/v1/a%3Ab", "/a%3Ab"},
		{"/v1/a%40b", "/a%40b"},
		{"/v1/%61", "/%61"},
		{"/%76%31/a%3bb?keep=%3A", "/a%3bb?keep=%3A"},
	} {
		recipe, err := m.Proxy.HTTPRecipe("GET", "https://api.example.com"+tc.input, nil)
		if err != nil || recipe.URL != "https://api.example.com"+tc.want {
			t.Errorf("%s: URL %q, error %v", tc.input, recipe.URL, err)
		}
	}
	for _, path := range []string{"/v10/records", "/v1/../secret", "/v1/%2e%2e/secret", "/v1/%2Fsecret", "/v1/%5csecret", "/v1/%252e%252e/secret", "/v1//secret"} {
		if _, err := m.Proxy.HTTPRecipe("GET", "https://api.example.com"+path, nil); err == nil {
			t.Errorf("accepted unsafe or unmatched path %s", path)
		}
	}
}

func TestStripPrefixFailureDoesNotFallThrough(t *testing.T) {
	m := parseRules(t, `[
 {"match":{"protocol":"http","host":["api.example.com"]},"action":{"rewrite":{"strip_prefix":"/v1"}}},
 {"match":{"protocol":"http","host":["api.example.com"]},"action":{}}
 ]`)
	for _, path := range []string{"/v10/records", "/other"} {
		if _, err := m.Proxy.HTTPRecipe("GET", "https://api.example.com"+path, nil); err == nil {
			t.Errorf("rewrite mismatch fell through: %s", path)
		}
	}
}

func TestStripPrefixDeclarationValidation(t *testing.T) {
	for _, prefix := range []string{"", "/", "v1", "/v1/", "/v1/*", "/v1/{id}", "/v1?x=y", "/v1#x", "/v1/%2f", "/v1/../secret", "/v1//a", "/v1\\a"} {
		rules := fmt.Sprintf(`[{"match":{"protocol":"http","host":["api.example.com"]},"action":{"rewrite":{"strip_prefix":%q}}}]`, prefix)
		if _, err := Parse([]byte(ruleManifest(rules))); err == nil {
			t.Errorf("accepted prefix %q", prefix)
		}
	}
	for _, rewrite := range []string{`{}`, `{"strip_prefix":"/v1","host":"evil.example.com"}`} {
		rules := `[{"match":{"protocol":"http","host":["api.example.com"]},"action":{"rewrite":` + rewrite + `}}]`
		if _, err := Parse([]byte(ruleManifest(rules))); err == nil {
			t.Errorf("accepted rewrite %s", rewrite)
		}
	}
}
