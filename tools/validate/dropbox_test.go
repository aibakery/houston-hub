package main

import (
	"bytes"
	"context"
	"encoding/json"
	"maps"
	"os"
	"os/exec"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/aibakery/houston-hub/manifest"
)

func TestDropboxScopesAndRoutes(t *testing.T) {
	m := parseManifest(t, "../../connectors/dropbox/houston.json")
	// Write scopes add to the read scopes, so narrowing a caller to read-only keeps a granted set.
	readScopes := []string{"account_info.read", "files.metadata.read", "files.content.read", "sharing.read", "file_requests.read"}
	writeScopes := []string{"files.content.write", "sharing.write", "file_requests.write"}
	method := "oauth"
	for _, access := range []string{"read-only", "read-write"} {
		publisher := map[string]any{"client_id": "publisher-key", "client_secret": "publisher-secret"}
		config := map[string]any{"access": access}

		r, err := m.Resolve(publisher, config, nil, method)
		if err != nil {
			t.Fatal(err)
		}
		scopes := readScopes
		if access == "read-write" {
			scopes = slices.Concat(readScopes, writeScopes)
		}
		if !slices.Equal(r.Scopes, scopes) {
			t.Fatalf("access=%s scopes %v", access, r.Scopes)
		}
		r.Context.Auth[method]["access_token"] = "fixture-token"
		assertRoutes(t, r, "fixture-token", true,
			"POST https://api.dropboxapi.com/2/files/list_folder", "POST https://api.dropboxapi.com/2/sharing/revoke_shared_link",
			"POST https://content.dropboxapi.com/2/files/download", "POST https://content.dropboxapi.com/2/files/upload")
		// The token never reaches the OAuth endpoint, other hosts or non-POST requests.
		assertRoutes(t, r, "fixture-token", false,
			"POST https://api.dropboxapi.com/oauth2/token", "GET https://api.dropboxapi.com/2/files/list_folder",
			"POST https://notify.dropboxapi.com/2/files/list_folder/longpoll", "GET https://dl.dropboxusercontent.com/apitl/1/file",
			"POST https://api.dropboxapi.com.evil.test/2/files/list_folder")
	}
}

func TestDropboxPublisherClient(t *testing.T) {
	m := parseManifest(t, "../../connectors/dropbox/houston.json")
	publisher := map[string]any{"client_id": "publisher-key", "client_secret": "publisher-secret"}
	r, err := m.Resolve(publisher, nil, nil, "oauth")
	if err != nil {
		t.Fatal(err)
	}
	client, err := manifest.RenderString(m.Auth["oauth"].ClientID, r.Context)
	if err != nil || client != "publisher-key" || !m.Auth["oauth"].PublisherClient() {
		t.Fatalf("wrong OAuth client: %q %v", client, err)
	}
	for _, field := range r.ConnectionFields {
		if field.Name == "client_id" || field.Name == "client_secret" || field.Name == "own_app" {
			t.Fatal("connection exposes app credentials")
		}
	}
	for _, missing := range []string{"client_id", "client_secret"} {
		inputs := maps.Clone(publisher)
		delete(inputs, missing)
		if _, err := m.Resolve(inputs, nil, nil, "oauth"); err == nil {
			t.Fatalf("missing %s accepted", missing)
		}
	}
}

func TestDropboxDiscoveryUsesGrantedScopes(t *testing.T) {
	source, err := os.ReadFile("../../connectors/dropbox/connector.luau")
	if err != nil {
		t.Fatal(err)
	}
	binary := os.Getenv("HOUSTON_CLI")
	if binary == "" {
		binary = "houston"
	}
	for _, test := range []struct {
		name    string
		scopes  []string
		exports []string
	}{
		{name: "none", scopes: []string{}},
		{name: "account", scopes: []string{"account_info.read"}, exports: []string{"getCurrentAccount", "getSpaceUsage"}},
		{name: "metadata", scopes: []string{"files.metadata.read"}, exports: []string{"getMetadata", "listFolder", "listFolderContinue", "listFolderGetLatestCursor", "listRevisions", "search", "searchContinue", "statFile"}},
	} {
		t.Run(test.name, func(t *testing.T) {
			input, err := json.Marshal(map[string]any{
				"files": []string{"connector.luau"}, "modules": map[string]string{"connector.luau": string(source)},
				"config": map[string]string{"access": "read-write"}, "protocol": "http", "args": []any{},
				"auth": map[string]any{"method": "oauth", "scopes": test.scopes},
			})
			if err != nil {
				t.Fatal(err)
			}
			ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
			defer cancel()
			command := exec.CommandContext(ctx, binary, "connector-host")
			command.Env = []string{"LANG=C"}
			command.Stdin = bytes.NewReader(append(input, '\n'))
			raw, err := command.CombinedOutput()
			if err != nil {
				t.Fatalf("connector host failed: %v: %s", err, raw)
			}
			var result struct {
				Type    string   `json:"type"`
				Error   string   `json:"error"`
				Exports []string `json:"exports"`
				Help    string   `json:"help"`
			}
			if err := json.Unmarshal(raw, &result); err != nil {
				t.Fatalf("invalid connector host response: %v: %s", err, raw)
			}
			if len(test.exports) == 0 {
				if result.Type != "error" || !strings.Contains(result.Error, "configured bundle has no exports") {
					t.Fatalf("empty grant exposed operations: %s", raw)
				}
				return
			}
			if result.Type != "result" || !slices.Equal(result.Exports, test.exports) {
				t.Fatalf("wrong configured exports: %s", raw)
			}
			var documented []string
			for _, line := range strings.Split(result.Help, "\n") {
				name, _, found := strings.Cut(line, "(")
				if found && name != "" && !strings.ContainsAny(name, " \t") {
					documented = append(documented, name)
				}
			}
			if !slices.Equal(documented, test.exports) {
				t.Fatalf("help documents %v; enabled operations are %v", documented, test.exports)
			}
		})
	}
}
