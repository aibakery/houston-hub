// Package conformance resolves fixture settings through the production contract.
package conformance

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"os/exec"
	"reflect"
	"sort"
	"strings"
	"time"

	"github.com/aibakery/houston-hub/manifest"
)

type Scenario struct {
	Publisher     map[string]any `json:"publisher"`
	Config        map[string]any `json:"config"`
	AuthMethod    string         `json:"auth_method"`
	AuthConfig    map[string]any `json:"auth_config"`
	GrantedScopes []string       `json:"granted_scopes"`
}
type metadata struct {
	Scenario Scenario       `json:"scenario"`
	Config   map[string]any `json:"config"`
}
type boundedOutput struct{ bytes.Buffer }

func (b *boundedOutput) Write(p []byte) (int, error) {
	if len(p) > 8<<20-b.Len() {
		return 0, fmt.Errorf("fixture output exceeds limit")
	}
	return b.Buffer.Write(p)
}
func call(ctx context.Context, binary, mode string, input any, output any) error {
	raw, err := json.Marshal(input)
	if err != nil {
		return err
	}
	ctx, cancel := context.WithTimeout(ctx, 15*time.Second)
	defer cancel()
	command := exec.CommandContext(ctx, binary, mode)
	command.Env = []string{"LANG=C"}
	command.Stdin = bytes.NewReader(append(raw, '\n'))
	var out, diagnostic boundedOutput
	command.Stdout = &out
	command.Stderr = &diagnostic
	if err := command.Run(); err != nil {
		return fmt.Errorf("fixture execution failed: %w: %s", err, strings.TrimSpace(diagnostic.String()))
	}
	decoder := json.NewDecoder(&out)
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(output); err != nil {
		return fmt.Errorf("invalid fixture response")
	}
	if decoder.Decode(new(any)) != io.EOF {
		return fmt.Errorf("trailing fixture response")
	}
	return nil
}

// Check requires runnable behavioral evidence for each method and variant, with configured Lua help.
func Check(ctx context.Context, binary string, m manifest.Manifest, modules, fixtures map[string]string) error {
	if binary == "" {
		binary = os.Getenv("HOUSTON_CLI")
	}
	if binary == "" {
		binary = "houston"
	}
	if len(fixtures) == 0 {
		return fmt.Errorf("bundle requires conformance fixtures")
	}
	names := make([]string, 0, len(fixtures))
	for name := range fixtures {
		names = append(names, name)
	}
	sort.Strings(names)
	methods := map[string]bool{}
	proxies := map[int]bool{}
	for _, name := range names {
		source := fixtures[name]
		var meta metadata
		if err := call(ctx, binary, "connector-fixture", map[string]any{"action": "inspect", "source": source}, &meta); err != nil {
			return fmt.Errorf("fixture %s metadata: %w", name, err)
		}
		scenario := meta.Scenario
		if scenario.Config == nil {
			scenario.Config = map[string]any{}
		}
		for key, value := range meta.Config {
			scenario.Config[key] = value
		}
		resolved, err := m.Resolve(scenario.Publisher, scenario.Config, scenario.AuthConfig, scenario.AuthMethod)
		if err != nil {
			return fmt.Errorf("fixture %s settings: %w", name, err)
		}
		if _, ok := resolved.PublicConfig["access"]; !ok {
			resolved.PublicConfig["access"] = "read-only"
		}
		input := map[string]any{"files": m.Files, "modules": modules, "config": resolved.PublicConfig, "protocol": m.Proxy[resolved.ProxyIndices[0]].Match.Protocol, "args": []any{}}
		input["auth"] = m.DiscoveryAuth(scenario.AuthMethod, scenario.GrantedScopes)
		var output struct {
			Type    string   `json:"type"`
			Exports []string `json:"exports"`
			Help    string   `json:"help"`
			Returns []any    `json:"returns"`
		}
		var discovery struct {
			Type    string   `json:"type"`
			Exports []string `json:"exports"`
			Help    string   `json:"help"`
			Returns []any    `json:"returns"`
		}
		if err := call(ctx, binary, "connector-host", input, &discovery); err != nil || discovery.Type != "result" {
			return fmt.Errorf("fixture %s initialization failed", name)
		}
		if err := call(ctx, binary, "connector-fixture", map[string]any{"action": "run", "source": source, "input": input}, &output); err != nil {
			return fmt.Errorf("fixture %s behavior: %w", name, err)
		}
		if output.Type != "result" {
			return fmt.Errorf("fixture %s failed", name)
		}
		if !reflect.DeepEqual(discovery.Exports, output.Exports) {
			return fmt.Errorf("fixture %s changed configured exports", name)
		}
		if strings.TrimSpace(discovery.Help) == "" {
			return fmt.Errorf("fixture %s requires connector Lua help", name)
		}
		if discovery.Help != output.Help {
			return fmt.Errorf("fixture %s changed configured help", name)
		}
		methods[scenario.AuthMethod] = true
		for _, index := range resolved.ProxyIndices {
			proxies[index] = true
		}
	}
	for method := range m.Auth {
		if !methods[method] {
			return fmt.Errorf("auth method %s has no conformance fixture", method)
		}
	}
	for i := range m.Proxy {
		if !proxies[i] {
			return fmt.Errorf("proxy rule %d has no conformance fixture", i)
		}
	}
	return nil
}
