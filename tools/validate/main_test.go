package main

import (
	"bytes"
	"context"
	"os"
	"path/filepath"
	"slices"
	"testing"

	"github.com/aibakery/houston-hub/tools/conformance"
)

func TestSupportedBundles(t *testing.T) {
	for _, name := range []string{"fastmail", "notion", "gmail", "gcalendar", "gdrive", "mercury", "x", "linkedin", "calcom", "calendly", "dropbox", "resend"} {
		t.Run(name, func(t *testing.T) {
			count, err := validate("../../connectors/" + name)
			if err != nil {
				t.Fatal(err)
			}
			if count != 1 {
				t.Fatalf("validated %d bundles, want 1", count)
			}
		})
	}
}

// Bundles still on the old synchronous HTTP API fail typecheck, but their fixtures
// run, so changes to them stay verified until they are migrated.
func TestUnmigratedBundleFixtures(t *testing.T) {
	entries, err := os.ReadDir("../../connectors")
	if err != nil {
		t.Fatal(err)
	}
	for _, entry := range entries {
		if !entry.IsDir() || slices.Contains(migrated, "connectors/"+entry.Name()) {
			continue
		}
		t.Run(entry.Name(), func(t *testing.T) {
			m, modules, fixtures, err := loadBundle("../../connectors/" + entry.Name())
			if err != nil {
				t.Fatal(err)
			}
			if err := conformance.Check(context.Background(), "", *m, modules, fixtures); err != nil {
				t.Fatal(err)
			}
		})
	}
}
func TestStandaloneBundleAndPrivateFiles(t *testing.T) {
	dir := t.TempDir()
	if err := os.Mkdir(filepath.Join(dir, "lib"), 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.Mkdir(filepath.Join(dir, "tests"), 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "tests", "behavior.lua"), []byte(`return {scenario={},run=function(c) assert(c.answer()==42) end}`), 0644); err != nil {
		t.Fatal(err)
	}
	for name, body := range map[string]string{"houston.json": `{"description":"Example","files":["main.luau"],"name":"Example","proxy":[{"action":{},"match":{"host":["api.example.com"],"protocol":"http"}}],"schema_version":1}`, "main.luau": `local helper = require("lib/helper.lua"); return {answer = helper.answer, help = function() return "answer() returns 42" end}`, "lib/helper.lua": `return {answer = function() return 42 end}`} {
		if err := os.WriteFile(filepath.Join(dir, name), []byte(body), 0644); err != nil {
			t.Fatal(err)
		}
	}
	n, err := validate(dir)
	if err != nil || n != 1 {
		t.Fatalf("%d %v", n, err)
	}
	// File-backed documentation can replace inline text without changing source
	// publication. Keep the preceding inline-only case as compatibility coverage.
	manifestPath := filepath.Join(dir, "houston.json")
	raw, err := os.ReadFile(manifestPath)
	if err != nil {
		t.Fatal(err)
	}
	raw = bytes.Replace(raw, []byte(`"description":"Example",`), nil, 1)
	if err := os.WriteFile(manifestPath, raw, 0644); err != nil {
		t.Fatal(err)
	}
	for name, source := range map[string]string{"README.md": "---\ndescription: Example card\n---\n# Example\n\nRead example records.", "SETUP.md": "Create and enter an API token."} {
		if err := os.WriteFile(filepath.Join(dir, name), []byte(source), 0644); err != nil {
			t.Fatal(err)
		}
	}
	if _, err := validate(dir); err != nil {
		t.Fatal(err)
	}
	outside := filepath.Join(t.TempDir(), "secret.lua")
	os.WriteFile(outside, []byte("private"), 0644)
	if err := os.Symlink(outside, filepath.Join(dir, "lib", "escape.lua")); err != nil {
		t.Fatal(err)
	}
	if _, err := validate(dir); err == nil {
		t.Fatal("bundle accepted an escaping private source")
	}
}
func TestManifestUsesAuthoritativeValidation(t *testing.T) {
	dir := t.TempDir()
	os.WriteFile(filepath.Join(dir, "houston.json"), []byte(`{"description":"Example","files":["main.lua"],"name":"Example","proxy":[{"action":{"headers":{"set":{"Authorization":{}}}},"match":{"host":["api.example.com"],"protocol":"http"}}],"schema_version":1}`), 0644)
	os.WriteFile(filepath.Join(dir, "main.lua"), []byte(`return {}`), 0644)
	if _, err := validate(dir); err == nil {
		t.Fatal("accepted non-object header recipe")
	}
}
