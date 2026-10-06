package interfaces_test

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/aibakery/houston-hub/manifest"
	"github.com/aibakery/houston-hub/tools/conformance"
	"github.com/aibakery/houston-hub/tools/typecheck"
)

func TestReferenceImplementations(t *testing.T) {
	definitions, err := filepath.Glob("*.json")
	if err != nil || len(definitions) == 0 {
		t.Fatalf("interface definitions: %v", err)
	}
	for _, path := range definitions {
		reference := strings.TrimSuffix(path, ".json")
		t.Run(reference, func(t *testing.T) {
			source, err := os.ReadFile(reference + ".lua")
			if err != nil {
				t.Fatal(err)
			}
			fixture, err := os.ReadFile(reference + ".test.lua")
			if err != nil {
				t.Fatal(err)
			}
			m, err := manifest.Parse([]byte(fmt.Sprintf(`{"schema_version":1,"name":"Reference example","description":"Mocked interface verification","files":["example.lua"],"implements":[%q],"proxy":[{"protocol":"http","origins":{"https://interface.example.com":{}}}]}`, reference)))
			if err != nil {
				t.Fatal(err)
			}
			modules := map[string]string{"example.lua": string(source)}
			if err := typecheck.Check(context.Background(), "", *m, modules); err != nil {
				t.Fatal(err)
			}
			if err := conformance.Check(context.Background(), "", *m, modules, map[string]string{"behavior.lua": string(fixture)}); err != nil {
				t.Fatal(err)
			}
		})
	}
}
