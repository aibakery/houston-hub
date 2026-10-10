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
	modules := map[string]string{"main.lua": `return {help=function() return "read() returns the configured enabled value" end,read=function() return config.enabled end}`}
	fixtures := map[string]string{"disabled.lua": `return {scenario={config={private="synthetic"}},run=function(c) assert(c.read()==false) end}`}
	binary := fixtureHost(t)
	if err := Check(context.Background(), binary, *m, modules, fixtures); err == nil || !strings.Contains(err.Error(), "proxy rule 1") {
		t.Fatalf("missing variant accepted: %v", err)
	}
	fixtures["enabled.lua"] = `return {scenario={config={private="synthetic"}},config={enabled=true},run=function(c) assert(c.read()==true) end}`
	if err := Check(context.Background(), binary, *m, modules, fixtures); err != nil {
		t.Fatal(err)
	}
	modules["main.lua"] = `http.request({method="GET",url="https://one.example.com"}); return {help=function() return "read() returns the configured enabled value" end,read=function() return config.enabled end}`
	if err := Check(context.Background(), binary, *m, modules, fixtures); err == nil {
		t.Fatal("network initialization accepted through fixture mocks")
	}
}
func TestPublicationRequiresBehaviorFixtures(t *testing.T) {
	if Check(context.Background(), "", manifest.Manifest{}, nil, nil) == nil {
		t.Fatal("publication accepted no behavioral evidence")
	}
}

func TestPublicationFixturesUseNativeIOOperations(t *testing.T) {
	m, err := manifest.Parse([]byte(`{"files":["main.lua"],"name":"I/O fixture","proxy":[{"action":{},"match":{"host":["example.com"],"protocol":"http"}}],"schema_version":1}`))
	if err != nil {
		t.Fatal(err)
	}
	modules := map[string]string{"main.lua": `return {
        help=function() return "copy() downloads binary fixture bytes to a session file" end,
        copy=function()
            local request=http.request({method="GET",url="https://example.com/data",headers={accept={"application/octet-stream"}}})
            local response=await(request)
            assert(response.statusCode==200 and await(request).body==response.body)
            local output=fs.open("binary.dat","w")
            assert(await(output)==output)
            output:write(response.body)
            local closing=output:close()
            assert(output:close()==closing)
            await(closing)
            local input=fs.open("binary.dat","r")
            local content=await(input:readAll())
            await(input:close())
            return #content, string.byte(content,1), string.byte(content,2)
        end,
    }`}
	fixtures := map[string]string{"io.lua": `return {
        scenario={},
        configure=function()
            fs=fixture.files()
            http={request=function(options)
                assert(options.headers.accept[1]=="application/octet-stream")
                return fixture.operation({statusCode=200,headers={},body=fixture.reader(string.char(0,255))})
            end}
        end,
        run=function(c)
            local length,first,second=c.copy()
            assert(length==2 and first==0 and second==255)
            local ok,err=pcall(function() await({}) end)
            assert(not ok and err.code=="invalid_argument")
        end,
    }`}
	if err := Check(context.Background(), fixtureHost(t), *m, modules, fixtures); err != nil {
		t.Fatal(err)
	}
}

func TestPublicationProjectsKnownAuthRestrictions(t *testing.T) {
	m, err := manifest.Parse([]byte(`{"files":["main.lua"],"name":"OAuth fixture","publisher":{"client_id":{"type":"string","label":"Client","default":"public-id"}},"auth":{"oauth":{"type":"oauth2","label":"OAuth","authorize_url":"https://example.com/auth","token_url":"https://example.com/token","client_id":"{{publisher.client_id}}","client_auth":"none","pkce":"S256","scopes":[{"values":["read","write"]}]}},"proxy":[{"action":{},"match":{"host":["example.com"],"protocol":"http"}}],"schema_version":1}`))
	if err != nil {
		t.Fatal(err)
	}
	modules := map[string]string{"main.lua": `assert(auth.method=="oauth"); local c={help=function() return "Configured OAuth fixture help" end,read=function() return auth.scopes end}; if auth.scopes and table.find(auth.scopes,"write") then c.write=function() end end; return c`}
	fixtures := map[string]string{
		"read.lua":    `return {scenario={auth_method="oauth",granted_scopes={"read","private-upstream-value"}},run=function(c) assert(c.write==nil); local scopes=c.read(); assert(#scopes==1 and scopes[1]=="read") end}`,
		"write.lua":   `return {scenario={auth_method="oauth",granted_scopes={"read","write"}},run=function(c) assert(type(c.write)=="function") end}`,
		"unknown.lua": `return {scenario={auth_method="oauth"},run=function(c) assert(c.read()==nil) end}`,
	}
	if err := Check(context.Background(), fixtureHost(t), *m, modules, fixtures); err != nil {
		t.Fatal(err)
	}
}

func TestPublicationRequiresLuaHelp(t *testing.T) {
	m, err := manifest.Parse([]byte(`{"files":["main.lua"],"name":"Fixture","proxy":[{"action":{},"match":{"host":["mail.example.com"],"protocol":"http"}}],"schema_version":1}`))
	if err != nil {
		t.Fatal(err)
	}
	err = Check(context.Background(), fixtureHost(t), *m, map[string]string{"main.lua": `return {read=function() return true end}`}, map[string]string{"test.lua": `return {scenario={},run=function(c) assert(c.read()) end}`})
	if err == nil || !strings.Contains(err.Error(), "requires connector Lua help") {
		t.Fatal(err)
	}
}

func TestConfiguredLuaHelpIsOfflineAndMatchesExports(t *testing.T) {
	m, err := manifest.Parse([]byte(`{"schema_version":1,"name":"Help fixture","files":["main.lua"],"config":{"access":{"type":"string","label":"Access","default":"read-only"}},"proxy":[{"match":{"protocol":"http","host":["example.com"]},"action":{}}]}`))
	if err != nil {
		t.Fatal(err)
	}
	source := `local c={read=function() return true end}; if config.access=="read-write" then c.write=function() return true end end; c.help=function() local names={}; for name in c do if name~="help" then names[#names+1]=name.."()" end end; table.sort(names); return table.concat(names," ") end; return c`
	for _, access := range []string{"read-only", "read-write"} {
		resolved, err := m.Resolve(nil, map[string]any{"access": access}, nil, "")
		if err != nil {
			t.Fatal(err)
		}
		var result struct {
			Type    string   `json:"type"`
			Exports []string `json:"exports"`
			Help    string   `json:"help"`
			Returns []any    `json:"returns"`
		}
		input := map[string]any{"files": m.Files, "modules": map[string]string{"main.lua": source}, "config": resolved.PublicConfig, "protocol": "http", "args": []any{}}
		if err = call(context.Background(), fixtureHost(t), "connector-host", input, &result); err != nil {
			t.Fatal(err)
		}
		want := "read()"
		if access == "read-write" {
			want += " write()"
		}
		if result.Help != want || strings.Contains(strings.Join(result.Exports, " "), "help") {
			t.Fatalf("%s result %+v", access, result)
		}
	}
	fixtures := map[string]string{"test.lua": `return {scenario={},run=function(c) assert(c.read()) end}`}
	modules := map[string]string{"main.lua": `return {read=function() return true end,help=function() http.request({method="GET",url="https://example.com"}); return "read()" end}`}
	if err = Check(context.Background(), fixtureHost(t), *m, modules, fixtures); err == nil {
		t.Fatal("network help accepted")
	}
}
