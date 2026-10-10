package typecheck

import (
	"context"
	"github.com/aibakery/houston-hub/manifest"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func TestRealTypeAnalysis(t *testing.T) {
	if _, err := exec.LookPath("luau-analyze"); err != nil {
		t.Fatal("publication requires luau-analyze installed")
	}
	m := manifest.Manifest{Files: []string{"main.lua"}, Config: map[string]manifest.Field{"token": {Type: "secret"}, "mode": {Type: "string", Required: true}}}
	for _, tc := range []struct {
		name, source string
		bad          bool
	}{{"reserved access without declaration", `local access:string=config.access; return {help=function() return access end}`, false}, {"valid", `return {statFile=function(id:string):{id:string,name:string,isFolder:boolean,size:number?} return {id=id,name=config.mode,isFolder=false} end}`, false}, {"wrong return type", `return {statFile=function(id:number):string return id end}`, true}, {"wrong host", `return {statFile=function(id:string) return http.request({url=42}) end}`, true}, {"secret unavailable", `return {statFile=function(id:string) return config.token end}`, true}, {"nocheck", `--!nocheck
return {statFile=function() end}`, true}} {
		t.Run(tc.name, func(t *testing.T) {
			err := Check(context.Background(), "", m, map[string]string{"main.lua": tc.source})
			if (err != nil) != tc.bad {
				t.Fatalf("bad=%v: %v", tc.bad, err)
			}
			if err != nil && strings.Contains(err.Error(), "no such file") {
				t.Fatal(err)
			}
		})
	}
}

func TestRuntimeIOContracts(t *testing.T) {
	m := manifest.Manifest{Files: []string{"main.lua"}}
	for _, tc := range []struct {
		name, source string
		bad          bool
	}{
		{"response reader", `local res = await(http.request({method="GET",url="https://example.com",headers={accept={"application/json"}}})); local status:number=res.statusCode; local bytes:string=await(res.body:readAll()); return bytes`, false},
		{"awaitable file", `local fd=fs.open("file.txt","w"); local opened:File=await(fd); fd:write("foo"); fd:write("bar"); local position:number=await(fd:seek(0,"start")); local closed:nil=await(fd:close()); return opened==fd`, false},
		{"download pipeline", `local res=await(http.request({method="GET",url="https://example.com"})); local fd=fs.open("export.gz","w"); fd:write(compression.gzip(res.body)); await(fd:close()); return await(fs.signedGetUrl("export.gz"))`, false},
		{"file source", `local res=await(http.request({method="POST",url="https://example.com",body=compression.gzip(fs.open("input","r"))})); res.body:close(); return true`, false},
		{"multipart source", `local body,contentType=http.multipart({{name="file",filename="x.pdf",contentType="application/pdf",body=fs.open("input","r")},{name="part_number",body="1"}}); local res=await(http.request({method="POST",url="https://example.com",headers={["content-type"]={contentType}},body=body})); res.body:close(); return true`, false},
		{"invalid multipart source", `return http.multipart({{name="file",body=42}})`, true},
		{"packed nil", `local fd=fs.open("out","w"); local results:PackedResults<nil> = awaitAll({fd:close()},100); local count:number=results.n; return count`, false},
		{"mixed packed results", `local fd=fs.open("out","w"); local results=awaitAll({fd:write("x"),fd:close(),fs.exists("out")}); local count:number=results.n; return count`, false},
		{"file helpers", `local exists:boolean=await(fs.exists("x")); local children:{string}=await(fs.list()); local result:GrepResult=await(fs.grep("text")); return exists`, false},
		{"header string shorthand", `return http.request({method="GET",url="https://example.com",headers={accept="application/json"}})`, true},
		{"buffered body assumption", `local res=await(http.request({method="GET",url="https://example.com"})); return json.decode(res.body)`, true},
		{"old status", `local res=await(http.request({method="GET",url="https://example.com"})); return res.status`, true},
		{"missing await", `local res=http.request({method="GET",url="https://example.com"}); return res.statusCode`, true},
		{"wrong result", `local bytes:number=await(fs.open("x","r"):readAll()); return bytes`, true},
		{"invalid mode", `return fs.open("x","a")`, true},
		{"invalid seek", `return fs.open("x","r"):seek(0,"begin")`, true},
		{"invalid read bound", `return fs.open("x","r"):readAll("large")`, true},
		{"invalid wait", `return await("not an operation")`, true},
		{"invalid group", `return awaitAll({42})`, true},
		{"invalid timeout", `return await(fs.stat("x"),"soon")`, true},
		{"removed convenience", `return fs.read("x")`, true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			err := Check(context.Background(), "", m, map[string]string{"main.lua": tc.source})
			if (err != nil) != tc.bad {
				t.Fatalf("bad=%v: %v", tc.bad, err)
			}
		})
	}
}

func TestFastmailRuntimeTypes(t *testing.T) {
	root := filepath.Join("..", "..", "connectors", "fastmail")
	raw, err := os.ReadFile(filepath.Join(root, "houston.json"))
	if err != nil {
		t.Fatal(err)
	}
	m, err := manifest.Parse(raw)
	if err != nil {
		t.Fatal(err)
	}
	modules := make(map[string]string, len(m.Files))
	for _, name := range m.Files {
		source, err := os.ReadFile(filepath.Join(root, name))
		if err != nil {
			t.Fatal(err)
		}
		modules[name] = string(source)
	}
	if err := Check(context.Background(), "", *m, modules); err != nil {
		t.Fatal(err)
	}
}
