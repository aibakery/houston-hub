package typecheck

import (
	"context"
	"github.com/aibakery/houston-hub/manifest"
	"os/exec"
	"strings"
	"testing"
)

func TestRealTypeAnalysis(t *testing.T) {
	if _, err := exec.LookPath("luau-analyze"); err != nil {
		t.Fatal("publication requires luau-analyze installed")
	}
	m := manifest.Manifest{Files: []string{"main.lua"}, Implements: []string{"files.metadata@1"}, Config: map[string]manifest.Field{"token": {Type: "secret"}, "mode": {Type: "string", Required: true}}}
	for _, tc := range []struct {
		name, source string
		bad          bool
	}{{"valid", `return {statFile=function(id:string):{id:string,name:string,isFolder:boolean,size:number?} return {id=id,name=config.mode,isFolder=false} end}`, false}, {"wrong signature", `return {statFile=function(id:number):string return tostring(id) end}`, true}, {"wrong host", `return {statFile=function(id:string) return http.request({url=42}) end}`, true}, {"secret unavailable", `return {statFile=function(id:string) return config.token end}`, true}, {"nocheck", `--!nocheck
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
