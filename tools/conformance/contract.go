package conformance

import (
	"bufio"
	"context"
	_ "embed"
	"encoding/json"
	"fmt"
	"net/http"
	"os/exec"
	"strings"
	"time"

	"github.com/aibakery/houston-hub/manifest"
)

//go:embed contract.luau
var contractHelpers string

// Lua's empty table has no array keys, so the worker encodes it as an object.
type fixtureStrings []string

func (s *fixtureStrings) UnmarshalJSON(raw []byte) error {
	if string(raw) == "{}" {
		*s = fixtureStrings{}
		return nil
	}
	return json.Unmarshal(raw, (*[]string)(s))
}

// checkContract evaluates bundle assertions against the production manifest
// implementation. The worker only receives synthetic fixture inputs and data.
func checkContract(ctx context.Context, binary string, m manifest.Manifest, modules map[string]string, source string) error {
	ctx, cancel := context.WithTimeout(ctx, 20*time.Second)
	defer cancel()
	command := exec.CommandContext(ctx, binary, "connector-fixture")
	command.Env = []string{"LANG=C"}
	input, err := command.StdinPipe()
	if err != nil {
		return err
	}
	output, err := command.StdoutPipe()
	if err != nil {
		return err
	}
	var diagnostic boundedOutput
	command.Stderr = &diagnostic
	if err := command.Start(); err != nil {
		return err
	}
	finished := false
	defer func() {
		input.Close()
		if !finished {
			command.Process.Kill()
			command.Wait()
		}
	}()
	encoder := json.NewEncoder(input)
	if err := encoder.Encode(map[string]any{"action": "contract", "source": source, "helpers": contractHelpers, "manifest": m, "modules": modules}); err != nil {
		return err
	}
	scanner := bufio.NewScanner(output)
	scanner.Buffer(make([]byte, 4096), 8<<20)
	calls := 0
	for scanner.Scan() {
		var message struct {
			Type      string          `json:"type"`
			Operation string          `json:"operation"`
			Args      json.RawMessage `json:"args"`
		}
		if err := json.Unmarshal(scanner.Bytes(), &message); err != nil {
			return fmt.Errorf("invalid contract response: %w", err)
		}
		if message.Type == "result" {
			input.Close()
			err := command.Wait()
			finished = true
			if err != nil {
				return fmt.Errorf("contract worker: %w: %s", err, diagnostic.String())
			}
			return nil
		}
		calls++
		if message.Type != "request" || calls > 8192 {
			return fmt.Errorf("invalid contract request or call limit exceeded")
		}
		value, err := contractCall(ctx, binary, m, modules, message.Operation, message.Args)
		response := map[string]any{"value": value}
		if err != nil {
			response["error"] = err.Error()
		}
		if err := encoder.Encode(response); err != nil {
			return err
		}
	}
	if err := scanner.Err(); err != nil {
		return err
	}
	err = command.Wait()
	finished = true
	return fmt.Errorf("contract fixture failed: %v: %s", err, strings.TrimSpace(diagnostic.String()))
}

func contractCall(ctx context.Context, binary string, m manifest.Manifest, modules map[string]string, operation string, raw json.RawMessage) (any, error) {
	var in struct {
		Publisher  map[string]any      `json:"publisher"`
		Config     map[string]any      `json:"config"`
		AuthConfig map[string]any      `json:"auth_config"`
		AuthMethod string              `json:"auth_method"`
		Context    manifest.Context    `json:"context"`
		Rules      manifest.ProxyRules `json:"rules"`
		Recipe     manifest.HTTPRecipe `json:"recipe"`
		HTTPMethod string              `json:"method"`
		URL        string              `json:"url"`
		Headers    http.Header         `json:"headers"`
		Scopes     fixtureStrings      `json:"scopes"`
		Facts      map[string]string   `json:"facts"`
		Text       string              `json:"text"`
		Auth       manifest.AuthMethod `json:"auth"`
	}
	if err := json.Unmarshal(raw, &in); err != nil {
		return nil, err
	}
	switch operation {
	case "exports":
		var result struct {
			Type      string   `json:"type"`
			Error     string   `json:"error,omitempty"`
			ErrorID   string   `json:"error_id,omitempty"`
			ErrorKind string   `json:"error_kind,omitempty"`
			Exports   []string `json:"exports,omitempty"`
			Help      string   `json:"help,omitempty"`
			Returns   []any    `json:"returns,omitempty"`
		}
		err := call(ctx, binary, "connector-host", map[string]any{
			"files": m.Files, "modules": modules, "config": in.Config,
			"protocol": m.Proxy[0].Match.Protocol, "args": []any{},
			"auth": m.DiscoveryAuth(in.AuthMethod, in.Scopes, in.Facts),
		}, &result)
		return result, err
	case "render":
		return manifest.RenderString(in.Text, in.Context)
	case "publisher_client":
		return in.Auth.PublisherClient(), nil
	case "resolve", "draft":
		var r *manifest.Resolved
		var err error
		if operation == "draft" {
			r, err = m.ResolveDraft(in.Publisher, in.Config, in.AuthConfig, in.AuthMethod)
		} else {
			r, err = m.Resolve(in.Publisher, in.Config, in.AuthConfig, in.AuthMethod)
		}
		if r != nil {
			r.Context.Errors = nil
		}
		return r, err
	case "recipe":
		return in.Rules.HTTPRecipe(in.HTTPMethod, in.URL, in.Headers)
	case "prepare":
		return in.Recipe.Prepare(in.Context, in.Headers)
	case "prepare_url":
		return in.Recipe.PrepareURL(in.Context)
	case "render_paths":
		return in.Rules.RenderPaths(in.Context)
	case "database":
		if len(in.Rules) != 1 {
			return nil, fmt.Errorf("expected one database proxy rule")
		}
		return in.Rules[0].ResolveDatabase(in.Context)
	case "credentials":
		return nil, m.RequireCredentials(in.Context)
	case "discovery":
		return m.DiscoveryAuth(in.AuthMethod, in.Scopes, in.Facts), nil
	default:
		return nil, fmt.Errorf("unknown manifest fixture operation %q", operation)
	}
}
