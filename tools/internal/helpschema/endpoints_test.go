package helpschema

import (
	"strings"
	"testing"
)

func TestEndpointDefinitions(t *testing.T) {
	source := `local endpoints = {
 first = {method = "GET", path = "/items", query = {"limit"}},
 last = {method = "POST", path = "/items/{id}",
  required = {"name"}, body = {nested = true}},
}
local response = {required = {"size"}}
`
	endpoints := Endpoints(source)
	if len(endpoints) != 2 {
		t.Fatalf("got %v", endpoints)
	}
	for i, want := range []struct{ name, method, path, definition string }{
		{"first", "GET", "/items", `first = {method = "GET", path = "/items", query = {"limit"}},`},
		{"last", "POST", "/items/{id}", "last = {method = \"POST\", path = \"/items/{id}\",\n  required = {\"name\"}, body = {nested = true}},"},
	} {
		got := endpoints[i]
		if got.Name != want.name || got.Method != want.method || got.Path != want.path || strings.TrimSpace(got.Definition) != want.definition {
			t.Fatalf("endpoint %d: %+v", i, got)
		}
	}
}
