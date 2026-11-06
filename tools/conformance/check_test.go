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
	binary := os.Getenv("HOUSTON_RUNTIME")
	if binary == "" {
		binary = "houston-runtime"
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

func TestCustomCallerAccessReachesDiscoveryAndBehavior(t *testing.T) {
	m, err := manifest.Parse([]byte(`{"schema_version":1,"name":"Custom access","files":["main.lua"],"config":{"access":{"type":"string","label":"Access","default":"custom"}},"proxy":[{"match":{"protocol":"http","host":["example.com"]},"action":{}}]}`))
	if err != nil {
		t.Fatal(err)
	}
	modules := map[string]string{"main.lua": `local exports={read=function() return config.access end,help=function() return "Caller: "..houston.access end};if houston.access=="read-write" then exports.write=function() return true end end;return exports`}
	for _, tc := range []struct{ access, assertion string }{
		{"", `assert(c.write==nil)`},
		{`,caller_access="read-only"`, `assert(c.write==nil)`},
		{`,caller_access="read-write"`, `assert(c.write()==true)`},
	} {
		fixture := `return {scenario={config={}` + tc.access + `},run=function(c) assert(c.read()=="custom");` + tc.assertion + ` end}`
		if err := Check(context.Background(), fixtureHost(t), *m, modules, map[string]string{"access.lua": fixture}); err != nil {
			t.Fatal(err)
		}
	}
	for _, scenario := range []string{
		`{config={access="read-write"},caller_access="read-only"}`,
		`{config={access="read-only"},caller_access="read-write"}`,
	} {
		fixture := `return {scenario=` + scenario + `,run=function(c) assert(c.read()=="read-only" and c.write==nil) end}`
		if err := Check(context.Background(), fixtureHost(t), *m, modules, map[string]string{"limited.lua": fixture}); err != nil {
			t.Fatal(err)
		}
	}
	if err := Check(context.Background(), fixtureHost(t), *m, modules, map[string]string{"invalid.lua": `return {scenario={caller_access="custom"},run=function() end}`}); err == nil || !strings.Contains(err.Error(), "caller_access") {
		t.Fatalf("invalid caller access accepted: %v", err)
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
	m, err := manifest.Parse([]byte(`{"auth":{"oauth":{"authorize_url":"https://example.com/auth","client_auth":"none","client_id":"{{config.client_id}}","label":"OAuth","pkce":"S256","scopes":[{"values":["read","write"]}],"token_url":"https://example.com/token","type":"oauth2"}},"config":{"client_id":{"default":"public-id","label":"Client","type":"string"}},"files":["main.lua"],"name":"OAuth fixture","proxy":[{"action":{},"match":{"host":["example.com"],"protocol":"http"}}],"schema_version":1}`))
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

func TestPublicationProjectsBoundFacts(t *testing.T) {
	m, err := manifest.Parse([]byte(`{"auth":{"oauth":{"authorize_url":"https://example.com/auth","client_auth":"none","client_id":"{{config.client_id}}","label":"OAuth","pkce":"S256","token_response":{"facts":{"team_id":"/team/id"}},"token_url":"https://example.com/token","type":"oauth2"}},"config":{"client_id":{"default":"public-id","label":"Client","type":"string"}},"files":["main.lua"],"name":"Facts fixture","proxy":[{"action":{},"match":{"host":["example.com"],"path":["/teams/{{auth.oauth.team_id}}"],"protocol":"http"}}],"schema_version":1}`))
	if err != nil {
		t.Fatal(err)
	}
	modules := map[string]string{"main.lua": `local team=assert(auth.facts and auth.facts.team_id); assert(not pcall(function() auth.facts.team_id="forged" end)); return {help=function() return "team() returns the bound team" end,team=function() return team end}`}
	fixtures := map[string]string{"facts.lua": `return {scenario={auth_method="oauth",facts={team_id="T1"}},run=function(c) assert(c.team()=="T1") end}`}
	if err := Check(context.Background(), fixtureHost(t), *m, modules, fixtures); err != nil {
		t.Fatal(err)
	}
	fixtures["facts.lua"] = `return {scenario={auth_method="oauth",facts={team_id="T1",other="x"}},run=function() end}`
	if err := Check(context.Background(), fixtureHost(t), *m, modules, fixtures); err == nil || !strings.Contains(err.Error(), "fact other is not declared") {
		t.Fatalf("undeclared fixture fact accepted: %v", err)
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
			Help    struct {
				Text     string            `json:"text"`
				Sections map[string]string `json:"sections"`
			} `json:"help"`
			Returns []any `json:"returns"`
		}
		input := map[string]any{"files": m.Files, "modules": map[string]string{"main.lua": source}, "config": resolved.PublicConfig, "protocol": "http", "args": []any{}}
		if err = call(context.Background(), fixtureHost(t), "connector-host", input, &result); err != nil {
			t.Fatal(err)
		}
		want := "read()"
		if access == "read-write" {
			want += " write()"
		}
		if result.Help.Text != want || strings.Contains(strings.Join(result.Exports, " "), "help") {
			t.Fatalf("%s result %+v", access, result)
		}
	}
	fixtures := map[string]string{"test.lua": `return {scenario={},run=function(c) assert(c.read()) end}`}
	modules := map[string]string{"main.lua": `return {read=function() return true end,help=function() http.request({method="GET",url="https://example.com"}); return "read()" end}`}
	if err = Check(context.Background(), fixtureHost(t), *m, modules, fixtures); err == nil {
		t.Fatal("network help accepted")
	}
}

func TestFixturesResolveDatabaseConnectionsAndExpectedSettingsErrors(t *testing.T) {
	m, err := manifest.Parse([]byte(`{"schema_version":1,"name":"Database","files":["main.lua"],"config":{"port":{"type":"integer","label":"Port","default":5432},"password":{"type":"secret","label":"Password","required":true}},"proxy":[{"match":{"protocol":"postgres"},"action":{"connection":{"host":"db.example.com","port":"{{config.port}}","database":"app","user":"reader","password":"{{config.password}}"}}}]}`))
	if err != nil {
		t.Fatal(err)
	}
	modules := map[string]string{"main.lua": `return {help=function() return "ping() returns pong" end,ping=function() return "pong" end}`}
	binary := fixtureHost(t)
	valid := `return {scenario={config={password="synthetic"}},run=function(c) assert(c.ping()=="pong") end}`
	for fixture, want := range map[string]string{
		`return {scenario={config={password="synthetic",port=70000},settings_error="invalid resolved port"}}`: "",
		`return {scenario={config={password="synthetic",port=70000},settings_error="another error"}}`:         `want an error containing "another error"`,
		`return {scenario={config={password="synthetic"},settings_error="invalid resolved port"}}`:            "got <nil>",
	} {
		err := Check(context.Background(), binary, *m, modules, map[string]string{"valid.lua": valid, "settings.lua": fixture})
		if want == "" && err != nil || want != "" && (err == nil || !strings.Contains(err.Error(), want)) {
			t.Fatalf("%s: want %q, got %v", fixture, want, err)
		}
	}
}

func TestStructuredCatalogPolicyPreservesPublicationCompatibility(t *testing.T) {
	m, err := manifest.Parse([]byte(`{"schema_version":1,"name":"Notebook","files":["main.lua"],"proxy":[{"match":{"protocol":"http","host":["example.com"]},"action":{}}]}`))
	if err != nil {
		t.Fatal(err)
	}
	binary := fixtureHost(t)
	fixtures := map[string]string{"read.lua": `return {scenario={},run=function(c) assert(c.read().id=="note-example") end}`}
	for _, help := range []string{`"Full legacy reference."`, `{text="Full legacy reference."}`, `function() return "Full legacy reference." end`, `function() return {text="Full legacy reference."} end`} {
		modules := map[string]string{"main.lua": `return {read=function() return {id="note-example"} end,help=` + help + `}`}
		if err := Check(context.Background(), binary, *m, modules, fixtures); err != nil {
			t.Fatal(err)
		}
		if _, err := CheckCatalog(context.Background(), binary, *m, modules, fixtures); err == nil || !strings.Contains(err.Error(), "structured help.functions") {
			t.Fatalf("catalog accepted text-only source: %v", err)
		}
	}
	metadata := `{text="Notebook.",functions={read={description="Read one note.",args={},inputSchema={type="object",additionalProperties=false,examples={{}}},outputSchema={type="object",properties={id={type="string"}},required={"id"},additionalProperties=false}}}}`
	fixtures["read.lua"] = `return {scenario={},run=function() assert(fixture.example("read").id=="note-example") end}`
	for _, help := range []string{metadata, `function(...) assert(select("#",...)==0); return ` + metadata + ` end`} {
		modules := map[string]string{"main.lua": `return {read=function() return {id="note-example"} end,help=` + help + `}`}
		coverage, err := CheckCatalog(context.Background(), binary, *m, modules, fixtures)
		if err != nil {
			t.Fatal(err)
		}
		if len(coverage) != 1 || coverage[0].Fixture != "read.lua" || len(coverage[0].Exports) != 1 || coverage[0].Exports[0] != "read" {
			t.Fatalf("wrong coverage: %+v", coverage)
		}
		modules["main.lua"] = strings.Replace(modules["main.lua"], `return {id="note-example"}`, `return {id=42}`, 1)
		if _, err := CheckCatalog(context.Background(), binary, *m, modules, fixtures); err == nil || !strings.Contains(err.Error(), "help.functions.read.outputSchema") {
			t.Fatalf("invalid documented output accepted: %v", err)
		}
	}
	modules := map[string]string{"main.lua": `return {read=function() return {} end, help=function() return {text="Notebook",functions={}} end}`}
	if err := Check(context.Background(), binary, *m, modules, fixtures); err == nil || !strings.Contains(err.Error(), "help.functions.read") {
		t.Fatalf("missing record diagnostic: %v", err)
	}
}
