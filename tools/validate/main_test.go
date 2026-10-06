package main

import (
	"os"
	"path/filepath"
	"testing"
)

func TestOfficialCatalog(t *testing.T) {
	count, err := validate("../..")
	if err != nil {
		t.Fatal(err)
	}
	if count != 12 {
		t.Fatalf("validated %d bundles, want 12", count)
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
	for name, body := range map[string]string{"houston.json": `{"schema_version":1,"name":"Example","description":"Example","files":["main.luau"],"proxy":[{"protocol":"http","origins":{"https://api.example.com":{}}}]}`, "main.luau": `local helper = require("lib/helper.lua"); return {answer = helper.answer}`, "lib/helper.lua": `return {answer = function() return 42 end}`} {
		if err := os.WriteFile(filepath.Join(dir, name), []byte(body), 0644); err != nil {
			t.Fatal(err)
		}
	}
	n, err := validate(dir)
	if err != nil || n != 1 {
		t.Fatalf("%d %v", n, err)
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
	os.WriteFile(filepath.Join(dir, "houston.json"), []byte(`{"schema_version":1,"name":"Example","description":"Example","files":["main.lua"],"proxy":[{"protocol":"http","origins":{"https://api.example.com":{"headers":{"Authorization":"plain"}}}}]}`), 0644)
	os.WriteFile(filepath.Join(dir, "main.lua"), []byte(`return {}`), 0644)
	if _, err := validate(dir); err == nil {
		t.Fatal("accepted non-object header recipe")
	}
}
