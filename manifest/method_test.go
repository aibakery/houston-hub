package manifest

import (
	"fmt"
	"net/http"
	"testing"
)

// request selects a rule and prepares it, as Houston's transport does.
func request(rules ProxyRules, method, rawURL string, caller http.Header) error {
	recipe, err := rules.HTTPRecipe(method, rawURL, caller)
	if err != nil {
		return err
	}
	_, err = recipe.Prepare(Context{}, caller)
	return err
}

func TestMethodOverridesAreRejected(t *testing.T) {
	m := parseRules(t, `[
{"match":{"protocol":"http","host":["api.example.com"],"method":["GET","HEAD","OPTIONS"],"path":["/v1/items/{id}"]},"action":{"headers":{"remove":["X-HTTP-Method-Override"]}}},
{"match":{"protocol":"http","host":["api.example.com"],"method":["GET"],"path":["/legacy/*"]},"action":{"rewrite":{"strip_prefix":"/legacy"}}}
]`)
	const item = "https://api.example.com/v1/items/a"
	for _, name := range []string{"X-HTTP-Method-Override", "x-http-method-override", "X-Http-Method", "X-Method-Override", "X_HTTP_Method_Override", "x_method-override", "X.HTTP.Method.Override", "XHTTPMethod"} {
		if err := request(m.Proxy, "GET", item, http.Header{name: {"DELETE"}}); err == nil {
			t.Errorf("accepted override header %s", name)
		}
		// Tests and the OAuth account request prepare without selecting a rule.
		recipe, err := m.Proxy.HTTPRecipe("GET", item, nil)
		if err != nil {
			t.Fatal(err)
		}
		if _, err := recipe.Prepare(Context{}, http.Header{name: {""}}); err == nil {
			t.Errorf("prepared override header %s", name)
		}
	}
	for _, query := range []string{
		"$httpMethod=DELETE", "%24httpMethod=DELETE", "%24HTTPMETHOD=PATCH", "$httpmethod",
		"fields=id&$httpMethod=DELETE", "fields=id;$httpMethod=DELETE", "$httpMethod=GET&$httpMethod=DELETE",
		"_method=DELETE", "_METHOD=PUT", "%5Fmethod=DELETE",
		// PHP drops leading spaces, ends a name at NUL or "[", and reads "." and " " as "_".
		".method=DELETE", "%2Emethod=DELETE", "+_method=DELETE", "%20_method=DELETE", "x.y=1&a b=1&_method=DELETE",
		"_method%00x=DELETE", "_method[]=DELETE", "_method%5B0%5D=DELETE", "%20%24httpMethod=DELETE",
	} {
		for _, method := range []string{"GET", "HEAD", "OPTIONS"} {
			if err := request(m.Proxy, method, item+"?"+query, nil); err == nil {
				t.Errorf("accepted override query %s on %s", query, method)
			}
		}
	}
	if err := request(m.Proxy, "GET", "https://api.example.com/legacy/v1/items/a?_method=DELETE", nil); err == nil {
		t.Error("a rewritten request kept an override query")
	}
	for _, query := range []string{"", "fields=id", "q=$httpMethod%3DDELETE", "httpMethod=DELETE", "method=DELETE", "x_method=1", "my.method=1", "_methods=1", "%zz=1", "%=1", "q=foo;100%", "_method%zz=1"} {
		u := item
		if query != "" {
			u += "?" + query
		}
		if err := request(m.Proxy, "GET", u, http.Header{"Accept": {"application/json"}}); err != nil {
			t.Errorf("rejected ordinary query %q: %v", query, err)
		}
	}
}

func TestCustomMethodSegments(t *testing.T) {
	m := parseRules(t, `[
{"match":{"protocol":"http","host":["api.example.com"],"method":["POST"],"path":["/v1/items/{id}:archive","/v1/items/{id}/notes/{note}:pin","/v1/items:batchGet"]},"action":{}},
{"match":{"protocol":"http","host":["api.example.com"],"method":["POST"],"path":["/v4/sheets/{sheet}/values/{range}:clear"],"colon_path_parameters":["range"]},"action":{}},
{"match":{"protocol":"http","host":["api.example.com"],"method":["PUT"],"path":["/v4/sheets/{sheet}/values/{range}:append"],"opaque_path_parameters":["range"]},"action":{}},
{"match":{"protocol":"http","host":["api.example.com"],"method":["PATCH"],"path":["/files/{id}:copy"],"opaque_path_parameters":["id"]},"action":{}},
{"match":{"protocol":"http","host":["api.example.com"],"method":["PATCH"],"path":["/buckets/{bucket}:copy/*"],"opaque_path_parameters":["*"]},"action":{}}
]`)
	for _, c := range []struct {
		method, path string
		allowed      bool
	}{
		{"POST", "/v1/items/a:archive", true},
		{"POST", "/v1/items/a/notes/n:pin", true},
		{"POST", "/v1/items/a:delete", false},
		{"POST", "/v1/items/a", false},
		{"POST", "/v1/items/:archive", false},
		{"POST", "/v1/items/a:b:archive", false},
		{"POST", "/v1/items/a:archive/extra", false},
		{"GET", "/v1/items/a:archive", false},
		{"POST", "/v4/sheets/s/values/A1:B2:clear", true},
		{"POST", "/v4/sheets/s/values/A1:clear", true},
		{"POST", "/v4/sheets/s:x/values/A1:clear", true},
		{"POST", "/v4/sheets/s/values/A1:B2:append", false},
		{"PUT", "/v4/sheets/s/values/Sheet%2F1!A1:B2:append", true},
		{"PUT", "/v4/sheets/s/values/A1:B2", false},
		{"PUT", "/v4/sheets/s/values/%2e%2e:append", false},
		// An encoded colon never selects a verb, and counts as a colon inside the value.
		{"POST", "/v1/items/a%3Aarchive", false},
		{"POST", "/v1/items:batchGet", true},
		{"POST", "/v1/items%3AbatchGet", false},
		{"POST", "/v1/item%73:batchGet", true},
		{"POST", "/v1/items/a%3Adelete:archive", false},
		{"POST", "/v4/sheets/s/values/A1%3AB2:clear", true},
		{"PATCH", "/files/a%2Fb:copy", true},
		// Opaque values accept colons, plain or encoded, like other safe bytes.
		{"PATCH", "/files/a:b:copy", true},
		{"PATCH", "/files/a%3Ab:copy", true},
		{"PATCH", "/files/a%3Acopy", false},
		{"PATCH", "/files/a%2540:copy", true},
		{"PATCH", "/buckets/b:copy/x%2Fy", true},
		{"PATCH", "/buckets/b:move/x", false},
	} {
		_, err := m.Proxy.HTTPRecipe(c.method, "https://api.example.com"+c.path, nil)
		if (err == nil) != c.allowed {
			t.Errorf("%s %s: allowed %v, want %v (%v)", c.method, c.path, err == nil, c.allowed, err)
		}
	}
}

func TestCustomMethodAndColonDeclarations(t *testing.T) {
	for _, path := range []string{"/items/{id}:archive", "/items/{id}:batchUpdate", "/items/{id}/sub/{sub}:run", "/items:batchGet"} {
		if _, err := Parse([]byte(ruleManifest(fmt.Sprintf(`[{"match":{"protocol":"http","host":["api.example.com"],"path":[%q]},"action":{}}]`, path)))); err != nil {
			t.Errorf("rejected custom method path %s: %v", path, err)
		}
	}
	for _, path := range []string{"/items/{id}:", "/items/{id}:1run", "/items/{id}:run-now", "/items/x{id}:run", "/items/{id}:run:now", "/items/{id}:{verb}", "/items/{id}x"} {
		if _, err := Parse([]byte(ruleManifest(fmt.Sprintf(`[{"match":{"protocol":"http","host":["api.example.com"],"path":[%q]},"action":{}}]`, path)))); err == nil {
			t.Errorf("accepted invalid path %s", path)
		}
	}
	for _, config := range []string{
		`"path":["/items/{id}"],"colon_path_parameters":[]`,
		`"path":["/items/{id}"],"colon_path_parameters":["unknown"]`,
		`"path":["/items/{id}"],"colon_path_parameters":["id","id"]`,
		`"path":["/items/*"],"colon_path_parameters":["*"]`,
		`"colon_path_parameters":["id"]`,
		`"path":["/items/{id}:run"],"colon_path_parameters":["id"],"opaque_path_parameters":["id"]`,
	} {
		rules := fmt.Sprintf(`[{"match":{"protocol":"http","host":["api.example.com"],%s},"action":{}}]`, config)
		if _, err := Parse([]byte(ruleManifest(rules))); err == nil {
			t.Errorf("accepted bad colon declaration %s", config)
		}
	}
	for _, config := range []string{
		`"path":["/items/{id}","/items/{id}:run"],"colon_path_parameters":["id"]`,
		`"path":["/items/{id}:run","/other"],"colon_path_parameters":["id"]`,
	} {
		rules := fmt.Sprintf(`[{"match":{"protocol":"http","host":["api.example.com"],%s},"action":{}}]`, config)
		if _, err := Parse([]byte(ruleManifest(rules))); err != nil {
			t.Errorf("rejected colon declaration %s: %v", config, err)
		}
	}
}
