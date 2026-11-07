package conformance

import (
	"context"
	"strings"
	"testing"
	"time"

	"github.com/aibakery/houston-hub/manifest"
)

func TestBundleContractExercisesProductionTransport(t *testing.T) {
	m, err := manifest.Parse([]byte(`{"schema_version":1,"name":"Contract fixture","files":["main.luau"],"auth":{"key":{"type":"manual","label":"Key","config":{"token":{"type":"secret","label":"Token","required":true}}}},"proxy":[{"match":{"protocol":"http","host":["api.example.com"],"method":["GET"],"path":["/items"]},"action":{"headers":{"set":{"Authorization":"Bearer {{auth.key.token}}"}}}}]}`))
	if err != nil {
		t.Fatal(err)
	}
	binary := fixtureHost(t)
	modules := map[string]string{"main.luau": `return {read=function() return true end,help=function() return "read() returns true" end}`}
	source := `return {contract=function(m)
        local r, err=m.resolve(nil,nil,{token="fixture-secret"},"key")
        assert(r and not err,tostring(err))
        assert(r.PublicConfig.token==nil)
        m.routes(r,"Bearer fixture-secret",true,{"GET https://api.example.com/items"})
        m.routes(r,"",false,{"POST https://api.example.com/items","GET https://api.example.com.evil.test/items"})
        m.rejectOverrides(r,{"GET https://api.example.com/items"})
        local _, missing=m.resolve(nil,nil,{},"key")
        assert(missing and string.find(missing,"token",1,true))
    end}`
	if err := checkContract(context.Background(), binary, *m, modules, source); err != nil {
		t.Fatal(err)
	}
	// A changed credential recipient or injection value must fail the bundle's test.
	changed := *m
	changed.Proxy = append(manifest.ProxyRules(nil), m.Proxy...)
	changed.Proxy[0].Action.Headers.Set = map[string]string{"Authorization": "wrong"}
	if err := checkContract(context.Background(), binary, changed, modules, source); err == nil || !strings.Contains(err.Error(), "credential injection") {
		t.Fatalf("wrong injection accepted: %v", err)
	}
	// Contract assertions supplement, and cannot stand in for, operation fixtures.
	if err := Check(context.Background(), binary, *m, modules, map[string]string{"contract.luau": source}); err == nil || !strings.Contains(err.Error(), "no conformance fixture") {
		t.Fatalf("contract counted as behavior coverage: %v", err)
	}
	fixtures := map[string]string{"contract.luau": source, "behavior.luau": `return {scenario={auth_method="key",auth_config={token="fixture-secret"}},run=function(c) assert(c.read()) end}`}
	if err := Check(context.Background(), binary, *m, modules, fixtures); err != nil {
		t.Fatal(err)
	}
}

func TestBundleContractBoundsAndIsolation(t *testing.T) {
	m, err := manifest.Parse([]byte(`{"schema_version":1,"name":"Bounded fixture","files":["main.luau"],"proxy":[{"match":{"protocol":"http","host":["api.example.com"]},"action":{}}]}`))
	if err != nil {
		t.Fatal(err)
	}
	binary := fixtureHost(t)
	for name, body := range map[string]string{
		"assertion":     `error("deliberate fixture failure")`,
		"filesystem":    `io.open("/etc/passwd")`,
		"network":       `http.request({url="https://example.com"})`,
		"data boundary": `m.resolve(nil,{value=function() end},nil,"")`,
	} {
		t.Run(name, func(t *testing.T) {
			err := checkContract(context.Background(), binary, *m, nil, `return {contract=function(m) `+body+` end}`)
			if err == nil {
				t.Fatal("invalid fixture passed")
			}
			if name == "assertion" && !strings.Contains(err.Error(), "deliberate fixture failure") {
				t.Fatal(err)
			}
		})
	}
	ctx, cancel := context.WithTimeout(context.Background(), 100*time.Millisecond)
	defer cancel()
	started := time.Now()
	err = checkContract(ctx, binary, *m, nil, `return {contract=function() while true do end end}`)
	if err == nil || time.Since(started) > 3*time.Second {
		t.Fatalf("fixture cancellation failed: %v", err)
	}
}
