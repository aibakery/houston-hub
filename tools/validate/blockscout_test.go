package main

import (
	"net/http"
	"os"
	"regexp"
	"slices"
	"testing"

	"github.com/aibakery/houston-hub/manifest"
)

const blockscoutManifest = "../../connectors/blockscout/houston.json"

func resolveBlockscout(t *testing.T, config map[string]any) *manifest.Resolved {
	t.Helper()
	r, err := parseManifest(t, blockscoutManifest).Resolve(nil, config, nil, "")
	if err != nil {
		t.Fatal(err)
	}
	return r
}

func blockscoutSource(t *testing.T) string {
	t.Helper()
	source, err := os.ReadFile("../../connectors/blockscout/connector.luau")
	if err != nil {
		t.Fatal(err)
	}
	return string(source)
}

func TestBlockscoutChainsMatchTheConnector(t *testing.T) {
	m := parseManifest(t, blockscoutManifest)
	rows := regexp.MustCompile(`\{host = "([^"]+)", name = "([^"]+)", id = \d+\}`).FindAllStringSubmatch(blockscoutSource(t), -1)
	options := m.Config["chain"].Options
	if len(rows) == 0 || len(rows) != len(options) {
		t.Fatalf("%d connector chains for %d manifest options", len(rows), len(options))
	}
	for i, row := range rows {
		if options[i].Value != row[1] || options[i].Label != row[2] {
			t.Fatalf("chain %d: manifest %v, connector %q %q", i, options[i], row[1], row[2])
		}
	}
}

func TestBlockscoutRulesMatchTheEndpointTable(t *testing.T) {
	m := parseManifest(t, blockscoutManifest)
	var keyed, explorer []string
	for _, match := range regexp.MustCompile(`\{name = "\w+", path = "([^"]+)"`).FindAllStringSubmatch(blockscoutSource(t), -1) {
		keyed = append(keyed, "/{chain}/api/v2"+match[1])
		explorer = append(explorer, "/api/v2"+match[1])
	}
	if len(keyed) == 0 || !slices.Equal(m.Proxy[0].Match.Path, keyed) || !slices.Equal(m.Proxy[1].Match.Path, explorer) {
		t.Fatalf("endpoint paths %v do not match the rules %v and %v", explorer, m.Proxy[0].Match.Path, m.Proxy[1].Match.Path)
	}
}

func TestBlockscoutPublicExplorerRoutes(t *testing.T) {
	const address = "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045"
	const hash = "0x1ccc11eecc6d44bd0b03d278560a5257d4dc93ac8414a6d1982d96bd88a0ffbc"
	r := resolveBlockscout(t, nil)
	const api = "https://eth.blockscout.com/api/v2"
	assertAuthorizedRoutes(t, r, "", true,
		"GET "+api+"/addresses/"+address, "GET "+api+"/addresses/"+address+"/transactions?filter=to&sort=value&order=desc",
		"GET "+api+"/addresses/"+address+"/tokens?type=ERC-20", "GET "+api+"/transactions/"+hash+"/logs",
		"GET "+api+"/blocks/26303681/transactions", "GET "+api+"/tokens?q=usd",
		"GET "+api+"/tokens/"+address+"/instances/115792089237316195423570985008687907853269984665640564039457584007913129639935",
		"GET "+api+"/smart-contracts/"+address, "GET "+api+"/search?q=token%5Bname%5D", "GET "+api+"/stats")
	assertAuthorizedRoutes(t, r, "", false,
		"POST "+api+"/tokens/batch", "PATCH "+api+"/tokens/"+address+"/instances/1/refetch-metadata",
		"POST "+api+"/smart-contracts/"+address+"/verification/via/flattened-code",
		"GET "+api+"/addresses/"+address+"/token-balances", "GET "+api+"/addresses/"+address+"/transactions/csv",
		"GET "+api+"/tokens/"+address+"/holders/csv", "GET "+api+"/config/backend-version", "GET "+api+"/addresses/%2e%2e/stats",
		"GET https://eth.blockscout.com/api/account/v2/user/info", "GET https://eth.blockscout.com/api?module=account&action=balance",
		"GET https://eth.blockscout.com/api/eth-rpc", "GET https://eth.blockscout.com/graphiql",
		"GET https://base.blockscout.com/api/v2/stats", "GET https://gnosisscan.io/api/v2/stats",
		"GET https://api.blockscout.com/1/api/v2/stats", "GET https://gnosis.blockscout.com/api/v2/stats",
		"GET https://eth.blockscout.com.example.com/api/v2/stats", "GET http://eth.blockscout.com:8080/api/v2/stats",
		"GET https://blockscout.com/api/v2/stats", "GET https://evil.blockscout.com/api/v2/stats")

	r = resolveBlockscout(t, map[string]any{"chain": "gnosisscan.io"})
	assertAuthorizedRoutes(t, r, "", true, "GET https://gnosisscan.io/api/v2/stats")
	assertAuthorizedRoutes(t, r, "", false, "GET https://eth.blockscout.com/api/v2/stats")
	if _, err := parseManifest(t, blockscoutManifest).Resolve(nil, map[string]any{"chain": "evil.example.com"}, nil, ""); err == nil {
		t.Fatal("a host outside the chain list resolved")
	}
}

func TestBlockscoutAPIKeyRoutes(t *testing.T) {
	const address = "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913"
	r := resolveBlockscout(t, map[string]any{"chain": "base.blockscout.com", "use_api_key": true, "api_key": "proapi_synthetic"})
	const api = "https://api.blockscout.com/8453/api/v2"
	assertAuthorizedRoutes(t, r, "Bearer proapi_synthetic", true,
		"GET "+api+"/tokens/"+address+"/holders", "GET "+api+"/addresses/"+address+"/transactions?block_number=1&index=4",
		"GET "+api+"/transactions/0x1ccc11eecc6d44bd0b03d278560a5257d4dc93ac8414a6d1982d96bd88a0ffbc/summary")
	assertAuthorizedRoutes(t, r, "", false,
		"POST "+api+"/tokens/batch", "GET "+api+"/addresses/"+address+"/token-balances",
		"GET https://api.blockscout.com/v2/api?chain_id=8453&module=account&action=balance",
		"GET https://api.blockscout.com/8453/api?module=account&action=balance", "GET https://api.blockscout.com/8453/json-rpc",
		"GET https://api.blockscout.com/8453/stats-service/api/v1/counters", "GET https://api.blockscout.com/services/metadata/api/v1/metadata",
		"GET https://api.blockscout.com/api/v2/stats", "GET https://base.blockscout.com/api/v2/stats",
		"GET https://eth.blockscout.com/api/v2/stats", "GET https://api.blockscout.com.example.com/8453/api/v2/stats")

	recipe, err := r.Proxy.HTTPRecipe("GET", api+"/stats", nil)
	if err != nil {
		t.Fatal(err)
	}
	if prepared, err := recipe.PrepareURL(r.Context); err != nil || prepared != api+"/stats" {
		t.Fatalf("the key reached the URL: %s %v", prepared, err)
	}
	dropped := []string{"X-HTTP-Method-Override", "X-HTTP-Method", "X-Method-Override", "Cookie"}
	caller := http.Header{"Accept": {"application/json"}, "Authorization": {"Bearer forged"}}
	for _, name := range dropped {
		caller.Set(name, "caller-value")
	}
	headers, err := recipe.Prepare(r.Context, caller)
	if err != nil || headers.Get("Accept") != "application/json" || headers.Get("Authorization") != "Bearer proapi_synthetic" {
		t.Fatalf("prepare: %v %v", headers, err)
	}
	for _, name := range dropped {
		if headers.Get(name) != "" {
			t.Fatalf("%s reached Blockscout", name)
		}
	}
}

func TestBlockscoutAPIKeyNeedsAValue(t *testing.T) {
	m := parseManifest(t, blockscoutManifest)
	for _, config := range []map[string]any{{"use_api_key": true}, {"use_api_key": true, "api_key": ""}} {
		if _, err := m.Resolve(nil, config, nil, ""); err == nil {
			t.Fatalf("%v resolved", config)
		}
	}
}
