// Conformance tests exercise the same subprocess and projection used for publication.
package conformance

import (
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/aibakery/houston-hub/manifest"
)

func fixtureHost(t *testing.T) string {
	t.Helper()
	binary := os.Getenv("HOUSTON_CLI")
	if binary == "" {
		binary = "houston"
	}
	found, err := exec.LookPath(binary)
	if err != nil {
		t.Fatal("real fixture host required: ", err)
	}
	absolute, err := filepath.Abs(found)
	if err != nil {
		t.Fatal(err)
	}
	return absolute
}
func TestPublicationProjectsConfigAndRequiresEveryVariant(t *testing.T) {
	m, err := manifest.Parse([]byte(`{"schema_version":1,"name":"Fixture","description":"Publication projection","files":["main.lua"],"config":{"enabled":{"type":"boolean","label":"Enabled","default":false},"private":{"type":"secret","label":"Private","required":true}},"proxy":[{"protocol":"http","if":"{{ is config.enabled false }}","origins":{"https://one.example.com":{"headers":{"Authorization":{"value":"{{config.private}}"}}}}},{"protocol":"http","if":"{{ is config.enabled true }}","origins":{"https://two.example.com":{"headers":{"Authorization":{"value":"{{config.private}}"}}}}}]}`))
	if err != nil {
		t.Fatal(err)
	}
	modules := map[string]string{"main.lua": `return {read=function() return config.enabled end}`}
	fixtures := map[string]string{"disabled.lua": `return {scenario={config={private="synthetic"}},run=function(c) assert(c.read()==false) end}`}
	binary := fixtureHost(t)
	if err := Check(context.Background(), binary, *m, modules, fixtures); err == nil || !strings.Contains(err.Error(), "alternative 1") {
		t.Fatalf("missing variant accepted: %v", err)
	}
	fixtures["enabled.lua"] = `return {scenario={config={private="synthetic"}},config={enabled=true},run=function(c) assert(c.read()==true) end}`
	if err := Check(context.Background(), binary, *m, modules, fixtures); err != nil {
		t.Fatal(err)
	}
	modules["main.lua"] = `http.request({method="GET",url="https://one.example.com"}); return {read=function() return config.enabled end}`
	if err := Check(context.Background(), binary, *m, modules, fixtures); err == nil {
		t.Fatal("network initialization accepted through fixture mocks")
	}
}
func TestPublicationRequiresBehaviorFixtures(t *testing.T) {
	if Check(context.Background(), "", manifest.Manifest{}, nil, nil) == nil {
		t.Fatal("publication accepted no behavioral evidence")
	}
}

func TestPublicationChecksActualContractBehavior(t *testing.T) {
	m, err := manifest.Parse([]byte(`{"schema_version":1,"name":"Mail fixture","description":"Typed behavior evidence","files":["main.lua"],"implements":["mail.folders@1"],"proxy":[{"protocol":"http","origins":{"https://mail.example.com":{}}}]}`))
	if err != nil {
		t.Fatal(err)
	}
	binary := fixtureHost(t)
	modules := map[string]string{"main.lua": `return {listMailFolders=function() return {{id="inbox",name="Inbox"}} end}`}
	fixtures := map[string]string{"folders.lua": `return {scenario={},run=function(c) end}`}
	if err := Check(context.Background(), binary, *m, modules, fixtures); err == nil || !strings.Contains(err.Error(), "no successful behavioral fixture") {
		t.Fatalf("no-op interface fixture accepted: %v", err)
	}
	fixtures["folders.lua"] = `return {scenario={},run=function(c) assert(c.listMailFolders()) end}`
	modules["main.lua"] = `return {listMailFolders=function() return "wrong shape" end}`
	if err := Check(context.Background(), binary, *m, modules, fixtures); err == nil || !strings.Contains(err.Error(), "violates mail.folders@1") {
		t.Fatalf("invalid interface result accepted: %v", err)
	}
	modules["main.lua"] = `return {listMailFolders=function() return {{id="inbox",name="Inbox"}} end}`
	if err := Check(context.Background(), binary, *m, modules, fixtures); err != nil {
		t.Fatal(err)
	}
}
