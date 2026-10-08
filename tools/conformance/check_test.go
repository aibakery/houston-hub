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
	m, err := manifest.Parse([]byte(`{"config":{"enabled":{"default":false,"label":"Enabled","type":"boolean"},"private":{"label":"Private","required":true,"type":"secret"}},"description":"Publication projection","files":["main.lua"],"name":"Fixture","proxy":[{"action":{"headers":{"set":{"Authorization":"{{config.private}}"}}},"if":"{{ is config.enabled false }}","match":{"host":["one.example.com"],"protocol":"http"}},{"action":{"headers":{"set":{"Authorization":"{{config.private}}"}}},"if":"{{ is config.enabled true }}","match":{"host":["two.example.com"],"protocol":"http"}}],"schema_version":1}`))
	if err != nil {
		t.Fatal(err)
	}
	modules := map[string]string{"main.lua": `return {read=function() return config.enabled end}`}
	fixtures := map[string]string{"disabled.lua": `return {scenario={config={private="synthetic"}},run=function(c) assert(c.read()==false) end}`}
	binary := fixtureHost(t)
	if err := Check(context.Background(), binary, *m, modules, fixtures, manifest.Operations{"read": "read", "listMailFolders": "read"}); err == nil || !strings.Contains(err.Error(), "proxy rule 1") {
		t.Fatalf("missing variant accepted: %v", err)
	}
	fixtures["enabled.lua"] = `return {scenario={config={private="synthetic"}},config={enabled=true},run=function(c) assert(c.read()==true) end}`
	if err := Check(context.Background(), binary, *m, modules, fixtures, manifest.Operations{"read": "read", "listMailFolders": "read"}); err != nil {
		t.Fatal(err)
	}
	modules["main.lua"] = `http.request({method="GET",url="https://one.example.com"}); return {read=function() return config.enabled end}`
	if err := Check(context.Background(), binary, *m, modules, fixtures, manifest.Operations{"read": "read", "listMailFolders": "read"}); err == nil {
		t.Fatal("network initialization accepted through fixture mocks")
	}
}
func TestPublicationRequiresBehaviorFixtures(t *testing.T) {
	if Check(context.Background(), "", manifest.Manifest{}, nil, nil, nil) == nil {
		t.Fatal("publication accepted no behavioral evidence")
	}
}

func TestPublicationProjectsKnownAuthRestrictions(t *testing.T) {
	m, err := manifest.Parse([]byte(`{"files":["main.lua"],"name":"OAuth fixture","publisher":{"client_id":{"type":"string","label":"Client","default":"public-id"}},"auth":{"oauth":{"type":"oauth2","label":"OAuth","authorize_url":"https://example.com/auth","token_url":"https://example.com/token","client_id":"{{publisher.client_id}}","client_auth":"none","pkce":"S256","scopes":[{"values":["read","write"]}]}},"proxy":[{"action":{},"match":{"host":["example.com"],"protocol":"http"}}],"schema_version":1}`))
	if err != nil {
		t.Fatal(err)
	}
	modules := map[string]string{"main.lua": `assert(auth.method=="oauth"); local c={read=function() return auth.scopes end}; if auth.scopes and table.find(auth.scopes,"write") then c.write=function() end end; return c`}
	fixtures := map[string]string{
		"read.lua":    `return {scenario={auth_method="oauth",granted_scopes={"read","private-upstream-value"}},run=function(c) assert(c.write==nil); local scopes=c.read(); assert(#scopes==1 and scopes[1]=="read") end}`,
		"write.lua":   `return {scenario={auth_method="oauth",granted_scopes={"read","write"}},run=function(c) assert(type(c.write)=="function") end}`,
		"unknown.lua": `return {scenario={auth_method="oauth"},run=function(c) assert(c.read()==nil) end}`,
	}
	if err := Check(context.Background(), fixtureHost(t), *m, modules, fixtures, manifest.Operations{"read": "read", "write": "write"}); err != nil {
		t.Fatal(err)
	}
}

func TestPublicationRejectsUnclassifiedExports(t *testing.T) {
	m, err := manifest.Parse([]byte(`{"files":["main.lua"],"name":"Fixture","proxy":[{"action":{},"match":{"host":["mail.example.com"],"protocol":"http"}}],"schema_version":1}`))
	if err != nil {
		t.Fatal(err)
	}
	err = Check(context.Background(), fixtureHost(t), *m, map[string]string{"main.lua": `return {read=function() return true end}`}, map[string]string{"test.lua": `return {scenario={},run=function(c) assert(c.read()) end}`}, nil)
	if err == nil || !strings.Contains(err.Error(), "no reviewed access classification") {
		t.Fatal(err)
	}
}
