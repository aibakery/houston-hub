package manifest

import (
	"fmt"
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
