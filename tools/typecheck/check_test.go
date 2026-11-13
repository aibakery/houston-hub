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
	}{{"reserved access without declaration", `local access:string=config.access; return {help=function() return access end}`, false}, {"valid", `return {statFile=function(id:string):{id:string,name:string,isFolder:boolean,size:number?} return {id=id,name=config.mode,isFolder=false} end}`, false}, {"wrong return type", `return {statFile=function(id:number):string return id end}`, true}, {"wrong host", `return {statFile=function(id:string) return http.request({url=42}) end}`, true}, {"secret unavailable", `return {statFile=function(id:string) return config.token end}`, true}, {"bound facts", `local team:string=(auth.facts and auth.facts.team_id) or ""; return {team=function():string return team end}`, false}, {"facts are strings", `local team:number=(auth.facts and auth.facts.team_id) or 0; return {team=function():number return team end}`, true}, {"nocheck", `--!nocheck
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
		{"download pipeline", `local res=await(http.request({method="GET",url="https://example.com"})); local fd=fs.open("export.gz","w"); fd:write(gzip.encode(res.body)); await(fd:close()); return await(fs.signedGetUrl("export.gz"))`, false},
		{"file source", `local res=await(http.request({method="POST",url="https://example.com",body=gzip.encode(fs.open("input","r"))})); res.body:close(); return true`, false},
		{"multipart source", `local form=multipart.create({{name="file",filename="x.pdf",contentType="application/pdf",body=fs.open("input","r")},{name="part_number",body="1"}}); local res=await(http.request({method="POST",url="https://example.com",headers={["content-type"]={form.contentType}},body=form.body})); res.body:close(); return true`, false},
		{"invalid multipart source", `return multipart.create({{name="file",body=42}})`, true},
		{"url helpers and error snippet", `local res=await(http.request({method="GET",url="https://example.com/items/"..url.segment("a b","id").."?q="..url.encode("x&y")})); local snippet:string=await(res.body:readPrefix(4096)); return snippet`, false},
		{"segment without a string", `return url.segment(42)`, true},
		{"encode scalars", `local query:string=url.encode(42)..url.encode(true); return query`, false},
		{"zip archives", `local body=zip.create({{name="[Content_Types].xml",body="<Types/>"},{name="media/a.png",body=fs.open("a.png","r"),method="store"}}); local fd=fs.open("a.zip","w"); fd:write(body); await(fd:close()); local archive=await(zip.open(fs.open("a.zip","r"))); local size:number=archive.entries[1].compressedSize; local xml:string=await(archive:open("[Content_Types].xml"):readAll()); archive:close(); return xml`, false},
		{"unzip a byte string", `local archive=await(zip.open("PK")); local name:string=archive.entries[1].name; return name`, false},
		{"unzip a stream", `local res=await(http.request({method="GET",url="https://example.com"})); return zip.open(res.body)`, true},
		{"zip method", `return zip.create({{name="a",body="x",method="bzip2"}})`, true},
		{"gzip byte strings", `local packed:string=gzip.encode(json.encode({a=1})); local plain:string=gzip.decode(buffer.fromstring(packed)); return plain`, false},
		{"gzip a stream", `local fd=fs.open("out.gz","w"); fd:write(gzip.encode(fs.open("in","r"))); await(fd:close()); local plain:string=await(gzip.decode(fs.open("out.gz","r")):readAll()); return plain`, false},
		{"gzip string is not a Reader", `return gzip.encode("x"):readAll()`, true},
		{"json from a stream", `local res=await(http.request({method="GET",url="https://example.com"})); local value=await(json.decode(res.body)); local direct=json.decode(buffer.fromstring("{}")); return value, direct`, false},
		{"gzip a number", `return gzip.encode(42)`, true},
		{"base64 helpers", `local encoded:string=base64.encode("x",{url=true,pad=false,wrap=false}); local decoded:string=base64.decode(encoded); return decoded`, false},
		{"base64 option type", `return base64.encode("x",{wrap=1})`, true},
		{"sha digests", `local hex:string=sha.sha256("x"); local text:string=sha.sha1("x",{encoding="base64"}); local raw:string=sha.sha512("x",{encoding="raw"}); return base64.encode(raw,{url=true,pad=false})..hex..text`, false},
		{"sha encoding", `return sha.sha256("x",{encoding="base32"})`, true},
		{"streamed base64 inside JSON", `local body=stream.concat({'{"content":"',base64.encode(fs.open("a.png","r"),{wrap=false}),'"}'}); local res=await(http.request({method="PUT",url="https://example.com",body=body})); local decoded:string=await(base64.decode(res.body):readAll()); return decoded`, false},
		{"streamed digest", `local digest:string=await(sha.sha256(fs.open("a.png","r"),{encoding="hex"})); return digest`, false},
		{"awaited string digest", `return await(sha.sha256("x"))`, true},
		{"concat a number", `return stream.concat({"x",42})`, true},
		{"prefix without a limit", `local res=await(http.request({method="GET",url="https://example.com"})); return res.body:readPrefix()`, true},
		{"prefix of a file", `return fs.open("x","r"):readPrefix(10)`, true},
		{"packed nil", `local fd=fs.open("out","w"); local results:PackedResults<nil> = awaitAll({fd:close()},100); local count:number=results.n; return count`, false},
		{"mixed packed results", `local fd=fs.open("out","w"); local results=awaitAll({fd:write("x"),fd:close(),fs.exists("out")}); local count:number=results.n; return count`, false},
		{"file helpers", `local exists:boolean=await(fs.exists("x")); local children:{string}=await(fs.list()); local result:GrepResult=await(fs.grep("text")); local reason:string=result.skipped[1].reason; return exists`, false},
		{"header string shorthand", `return http.request({method="GET",url="https://example.com",headers={accept="application/json"}})`, true},
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
