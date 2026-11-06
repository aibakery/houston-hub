package main

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/aibakery/houston-hub/tools/conformance"
)

func TestSupportedBundles(t *testing.T) {
	directories, err := catalogDirectories("../..")
	if err != nil {
		t.Fatal(err)
	}
	for _, directory := range directories {
		t.Run(filepath.Base(directory), func(t *testing.T) {
			report := map[string][]conformance.Coverage{}
			count, err := validateWithCoverage(directory, report)
			if err != nil {
				t.Fatal(err)
			}
			if count != 1 {
				t.Fatalf("validated %d bundles, want 1", count)
			}
		})
	}
}

func TestCatalogPolicyAndStandaloneCompatibility(t *testing.T) {
	root := t.TempDir()
	directory := filepath.Join(root, "connectors", "nested", "example")
	if err := os.MkdirAll(filepath.Join(directory, "tests"), 0755); err != nil {
		t.Fatal(err)
	}
	write := func(name, content string) {
		t.Helper()
		if err := os.WriteFile(filepath.Join(directory, name), []byte(content), 0644); err != nil {
			t.Fatal(err)
		}
	}
	write("houston.json", `{"schema_version":1,"description":"Example","name":"Example","files":["main.luau"],"proxy":[{"match":{"host":["api.example.com"],"protocol":"http"},"action":{}}]}`)
	write("main.luau", `return {answer=function() return 42 end,help="answer() returns 42"}`)
	write("tests/behavior.luau", `return {scenario={},run=function(c) assert(c.answer()==42) end}`)
	if count, err := validate(directory); err != nil || count != 1 {
		t.Fatalf("legacy standalone publication: count=%d error=%v", count, err)
	}
	if _, err := validate(root); err == nil || !strings.Contains(err.Error(), "structured help.functions") {
		t.Fatalf("maintained catalog must require structured function coverage: %v", err)
	}
	write("main.luau", `return {answer=function() return 42 end,help={text="Example",functions={answer={description="Return the answer",args={},inputSchema={type="object",properties={},additionalProperties=false,examples={{}}}}}}}`)
	write("tests/behavior.luau", `return {scenario={},run=function(c) assert(fixture.example("answer")==42) end}`)
	if count, err := validate(root); err != nil || count != 1 {
		t.Fatalf("nested maintained connector: count=%d error=%v", count, err)
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
