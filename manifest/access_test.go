package manifest

import (
	"fmt"
	"reflect"
	"testing"
)

func TestReservedAccessFieldUsesCanonicalCallerPolicy(t *testing.T) {
	for _, tc := range []struct {
		name, field string
		valid       bool
	}{
		{"default", `{"type":"string","label":"Access","default":"read-only","options":[{"value":"read-only","label":"Read"},{"value":"read-write","label":"Read and write"}]}`, true},
		{"absent default", `{"type":"string","label":"Access"}`, true},
		{"secret", `{"type":"secret","label":"Access"}`, false},
		{"other default", `{"type":"string","label":"Access","default":"write"}`, false},
		{"other option", `{"type":"string","label":"Access","options":[{"value":"administrator","label":"Admin"}]}`, false},
		{"write only", `{"type":"string","label":"Access","options":[{"value":"read-write","label":"Write"}]}`, false},
		{"hidden", `{"type":"string","label":"Access","if":"{{ is config.enabled true }}"}`, false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			raw := fmt.Sprintf(`{"schema_version":1,"name":"Access fixture","files":["main.lua"],"config":{"access":%s},"proxy":[{"match":{"protocol":"http","host":["example.com"]},"action":{}}]}`, tc.field)
			_, err := Parse([]byte(raw))
			if (err == nil) != tc.valid {
				t.Fatalf("valid=%v err=%v", tc.valid, err)
			}
		})
	}
}

func TestReservedAccessImplicitDefaultResolvesDependentPolicy(t *testing.T) {
	for _, tc := range []struct {
		name, explicitDefault, want string
		input                       map[string]any
	}{
		{name: "implicit read only", want: "read-only"},
		{name: "explicit read only", input: map[string]any{"access": "read-only"}, want: "read-only"},
		{name: "explicit read write", input: map[string]any{"access": "read-write"}, want: "read-write"},
		{name: "read write default", explicitDefault: `,"default":"read-write"`, want: "read-write"},
		{name: "override read write default", explicitDefault: `,"default":"read-write"`, input: map[string]any{"access": "read-only"}, want: "read-only"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			raw := fmt.Sprintf(`{
				"schema_version":1,"name":"Access resolution","files":["main.lua"],
				"publisher":{"client_id":{"type":"string","label":"Client","default":"fixture-client"}},
				"config":{
					"access":{"type":"string","label":"Access"%s},
					"a_read_route":{"type":"string","label":"Read route","default":"read","if":"{{ is config.access \"read-only\" }}"},
					"a_write_route":{"type":"string","label":"Write route","default":"write","if":"{{ is config.access \"read-write\" }}"}
				},
				"auth":{"oauth":{"type":"oauth2","label":"OAuth","authorize_url":"https://example.com/auth","token_url":"https://example.com/token","client_id":"{{publisher.client_id}}","client_auth":"none","pkce":"S256","scopes":[
					{"if":"{{ is config.access \"read-only\" }}","values":["read"]},
					{"if":"{{ is config.access \"read-write\" }}","values":["write"]}
				]}},
				"proxy":[
					{"if":"{{ is config.access \"read-only\" }}","match":{"protocol":"http","host":["read.example.com"]},"action":{}},
					{"if":"{{ is config.access \"read-write\" }}","match":{"protocol":"http","host":["write.example.com"]},"action":{}}
				]
			}`, tc.explicitDefault)
			m, err := Parse([]byte(raw))
			if err != nil {
				t.Fatal(err)
			}
			for _, draft := range []bool{false, true} {
				resolve := m.Resolve
				if draft {
					resolve = m.ResolveDraft
				}
				r, err := resolve(nil, tc.input, nil, "oauth")
				if err != nil {
					t.Fatal(err)
				}
				mode, proxy := "read", 0
				if tc.want == "read-write" {
					mode, proxy = "write", 1
				}
				wantConfig := map[string]any{"access": tc.want, "a_" + mode + "_route": mode}
				if !reflect.DeepEqual(r.PublicConfig, wantConfig) || !reflect.DeepEqual(r.Context.Config, wantConfig) || !reflect.DeepEqual(r.Scopes, []string{mode}) || !reflect.DeepEqual(r.ProxyIndices, []int{proxy}) {
					t.Fatalf("draft=%v inconsistent policy: config=%v context=%v scopes=%v proxies=%v", draft, r.PublicConfig, r.Context.Config, r.Scopes, r.ProxyIndices)
				}
			}
			if _, err := m.Resolve(nil, map[string]any{"access": nil}, nil, "oauth"); err == nil {
				t.Fatal("null access must remain an invalid explicit input")
			}
		})
	}
}
