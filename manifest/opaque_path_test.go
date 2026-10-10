package manifest

import (
	"fmt"
	"strings"
	"testing"
)

func TestOpaqueParametersPreserveEscapesAndScope(t *testing.T) {
	m := parseRules(t, `[
{"match":{"protocol":"http","host":["api.example.com"],"method":["GET"],"path":["/pages/{page}/properties/{property}"],"opaque_path_parameters":["property"]},"action":{"headers":{"set":{"X-Route":"opaque"}}}},
{"match":{"protocol":"http","host":["api.example.com"]},"action":{"headers":{"set":{"X-Route":"default"}}}}
]`)
	for _, id := range []string{"f%5C%5C%3Ap", "a%2Fb", "a%25b", "literal%25", "percent%25zz%2Fname", "%2525", "a%2eb", "a%255Cb"} {
		u := "https://api.example.com/pages/page-1/properties/" + id + "?start_cursor=a%2Fb"
		recipe, err := m.Proxy.HTTPRecipe("GET", u, nil)
		if err != nil || recipe.URL != u || recipe.Headers["X-Route"].Value != "opaque" {
			t.Errorf("opaque ID %s: %v, %v", id, recipe, err)
		}
		if _, err := m.Proxy[1:].HTTPRecipe("GET", u, nil); err == nil && id != "a%2eb" {
			t.Errorf("default route accepted opaque escape %s", id)
		}
	}
	for _, path := range []string{
		"/pages/page%2Fescape/properties/name", "/pages/page/properties/a%2Fb/extra",
		"/pages/page/properties/%2e", "/pages/page/properties/%2e%2e",
		"/pages/page/properties/a%2F..%2Fsecret", "/pages/page/properties/a%5c..%5csecret",
		"/pages/page/properties/a%252F%252e%252e%252Fsecret",
		"/pages/page/properties/a%25zz%2F%252e%252e%2Fsecret",
		"/pages/page/properties/a%00b", "/pages/page/properties/a%250db",
		"/pages/page/properties/a%0ab", "/pages/page/properties/a%7fb",
		"/pages/page/properties/a%2525252F..", "/pages/page/properties/../secret",
		"/pages/page/properties/%" + strings.Repeat("25", 20),
		"/pages/page/properties/raw\\backslash",
	} {
		if _, err := m.Proxy.HTTPRecipe("GET", "https://api.example.com"+path, nil); err == nil {
			t.Errorf("accepted unsafe or outside-parameter escape %s", path)
		}
	}
	for _, u := range []string{"https://api.example.com.attacker.test/pages/p/properties/a%2Fb", "https://user:secret@api.example.com/pages/p/properties/a%2Fb", "http://api.example.com/pages/p/properties/a%2Fb"} {
		if _, err := m.Proxy.HTTPRecipe("GET", u, nil); err == nil {
			t.Errorf("accepted wrong origin or credentials: %s", u)
		}
	}
	if _, err := m.Proxy.HTTPRecipe("PATCH", "https://api.example.com/pages/p/properties/a%2Fb", nil); err == nil {
		t.Fatal("opaque allowance leaked to another method")
	}
}

func TestOpaqueWildcardPreservesLiteralBucket(t *testing.T) {
	m := parseRules(t, `[{"match":{"protocol":"http","host":["s3.example.com"],"method":["GET"],"path":["/trusted-bucket/*"],"opaque_path_parameters":["*"]},"action":{"headers":{"remove":["Authorization"]}}}]`)
	for _, path := range []string{"/trusted-bucket/folder/100%25.pdf", "/trusted-bucket/folder/a%2Fb.pdf", "/trusted-bucket/a%5Cb.pdf"} {
		u := "https://s3.example.com" + path + "?signature=keep%2Fexact"
		recipe, err := m.Proxy.HTTPRecipe("GET", u, nil)
		if err != nil || recipe.URL != u {
			t.Errorf("opaque download %s: %v", path, err)
		}
	}
	for _, path := range []string{"/other-bucket/a%25.pdf", "/trusted-bucket%2Fevil/file", "/trusted-bucket/%2e%2e/other/file", "/trusted-bucket/a%252F..%252Fother", "/trusted-bucket/a%255C..%255Cother", "/trusted-bucket/line%250Afile"} {
		if _, err := m.Proxy.HTTPRecipe("GET", "https://s3.example.com"+path, nil); err == nil {
			t.Errorf("unsafe bucket escape accepted: %s", path)
		}
	}
}

func TestOpaqueParameterDeclarationValidation(t *testing.T) {
	for _, config := range []string{
		`"path":["/items/{id}"],"opaque_path_parameters":[]`,
		`"path":["/items/{id}"],"opaque_path_parameters":["unknown"]`,
		`"path":["/items/{id}"],"opaque_path_parameters":["id","id"]`,
		`"path":["/items/{id}","/other"],"opaque_path_parameters":["id"]`,
		`"path":["/items/{id}"],"opaque_path_parameters":["*"]`,
		`"opaque_path_parameters":["id"]`,
	} {
		rules := fmt.Sprintf(`[{"match":{"protocol":"http","host":["api.example.com"],%s},"action":{}}]`, config)
		if _, err := Parse([]byte(ruleManifest(rules))); err == nil {
			t.Errorf("accepted bad opaque declaration %s", config)
		}
	}
	m := parseRules(t, `[{"match":{"protocol":"http","host":["api.example.com"],"path":["/items/{id}"],"opaque_path_parameters":["id"]},"action":{}}]`)
	m.Proxy[0].Action.Rewrite = &Rewrite{StripPrefix: "/items"}
	if err := m.Validate(); err == nil {
		t.Fatal("opaque matching allowed with rewriting")
	}
	if _, err := m.Proxy.HTTPRecipe("GET", "https://api.example.com/items/a%2Fb", nil); err == nil {
		t.Fatal("unvalidated opaque rewrite accepted at runtime")
	}
}
