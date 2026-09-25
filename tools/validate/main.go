// Command validate checks public bundle layout without credentials or dependencies.
// The Houston hub performs full policy validation and Lua tests before publication.
package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"image/png"
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

var slugPattern = regexp.MustCompile(`^[a-z][a-z0-9_-]{0,63}$`)

type manifest struct {
	SchemaVersion int               `json:"schema_version"`
	ID            string            `json:"id"`
	Name          string            `json:"name"`
	Description   string            `json:"description"`
	Setup         string            `json:"setup"`
	ConfigFields  []json.RawMessage `json:"config_fields"`
	Module        string            `json:"module"`
	PublisherID   string            `json:"publisher_id"`
	Icon          string            `json:"icon"`
	Auth          json.RawMessage   `json:"auth"`
	Access        []struct {
		ID string `json:"id"`
	} `json:"access"`
	Proxy struct {
		Protocol string `json:"protocol"`
	} `json:"proxy"`
}

type authMethod struct {
	ID    string                     `json:"id"`
	Type  string                     `json:"type"`
	OAuth map[string]json.RawMessage `json:"oauth"`
}

func main() {
	root := "."
	if len(os.Args) > 2 {
		fmt.Fprintln(os.Stderr, "usage: go run ./tools/validate [hub-checkout]")
		os.Exit(2)
	}
	if len(os.Args) == 2 {
		root = os.Args[1]
	}
	count, err := validate(root)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	fmt.Printf("%d connector bundle layouts validated\n", count)
}

func validate(root string) (int, error) {
	entries, err := os.ReadDir(filepath.Join(root, "connectors"))
	if err != nil {
		return 0, err
	}
	count := 0
	for _, entry := range entries {
		if !entry.IsDir() {
			continue
		}
		if err := validateBundle(filepath.Join(root, "connectors", entry.Name()), entry.Name()); err != nil {
			return count, fmt.Errorf("%s: %w", entry.Name(), err)
		}
		count++
	}
	if count == 0 {
		return 0, fmt.Errorf("empty connector catalog")
	}
	return count, nil
}

func validateBundle(dir, slug string) error {
	raw, err := bundleFile(dir, "houston.json")
	if err != nil {
		return err
	}
	var m manifest
	if err := json.Unmarshal(raw, &m); err != nil {
		return err
	}
	if m.ID != slug || !slugPattern.MatchString(m.ID) {
		return fmt.Errorf("id must match connector folder and be a slug")
	}
	if m.SchemaVersion != 1 {
		return fmt.Errorf("schema_version must be 1")
	}
	if strings.TrimSpace(m.Name) == "" {
		return fmt.Errorf("name is required")
	}
	if err := validateAuth(m.Auth, m.PublisherID); err != nil {
		return err
	}
	methods, _ := authMethods(m.Auth)
	for i, method := range methods {
		effective, err := resolveMethod(raw, method)
		if err != nil {
			return fmt.Errorf("auth method %d: %w", i+1, err)
		}
		if err := validateEffective(dir, effective); err != nil {
			return fmt.Errorf("auth method %d: %w", i+1, err)
		}
	}
	tests, err := os.ReadDir(filepath.Join(dir, "tests"))
	if err != nil {
		return err
	}
	if len(tests) == 0 {
		return fmt.Errorf("at least one Lua test is required")
	}
	for _, test := range tests {
		if !luaFile(test.Name()) {
			return fmt.Errorf("test %q must use .lua or .luau", test.Name())
		}
		if _, err := bundleFile(dir, filepath.Join("tests", test.Name())); err != nil {
			return fmt.Errorf("test: %w", err)
		}
	}
	if m.Icon != "" {
		if m.Icon != "icon.png" {
			return fmt.Errorf("icon must be icon.png")
		}
		raw, err := bundleFile(dir, m.Icon)
		if err != nil {
			return err
		}
		image, err := png.DecodeConfig(bytes.NewReader(raw))
		if err != nil || image.Width != 1024 || image.Height != 1024 {
			return fmt.Errorf("icon must be a 1024x1024 PNG")
		}
	}
	return nil
}

func authMethods(raw json.RawMessage) ([]json.RawMessage, error) {
	raw = bytes.TrimSpace(raw)
	var methods []json.RawMessage
	if len(raw) > 0 && raw[0] == '[' {
		if err := json.Unmarshal(raw, &methods); err != nil {
			return nil, err
		}
	} else {
		methods = []json.RawMessage{raw}
	}
	if len(methods) == 0 {
		return nil, fmt.Errorf("auth requires at least one method")
	}
	return methods, nil
}

// Mode fields replace whole top-level values. Omission inherits; there is no
// deep merge of access lists, configuration fields or proxy routes.
func resolveMethod(raw, method json.RawMessage) (manifest, error) {
	var base, fields map[string]json.RawMessage
	var effective manifest
	if err := json.Unmarshal(raw, &base); err != nil {
		return effective, err
	}
	if err := json.Unmarshal(method, &fields); err != nil {
		return effective, err
	}
	for _, key := range []string{"schema_version", "name", "publisher_id", "icon"} {
		if _, ok := fields[key]; ok {
			return effective, fmt.Errorf("%s belongs at the manifest top level", key)
		}
	}
	for _, key := range []string{"module", "description", "setup", "access", "config_fields", "proxy"} {
		if value, ok := fields[key]; ok {
			if bytes.Equal(bytes.TrimSpace(value), []byte("null")) {
				return effective, fmt.Errorf("%s override must not be null", key)
			}
			base[key] = value
		}
	}
	base["auth"] = method
	resolved, err := json.Marshal(base)
	if err != nil {
		return effective, err
	}
	if err := json.Unmarshal(resolved, &effective); err != nil {
		return effective, err
	}
	return effective, nil
}

func validateEffective(dir string, m manifest) error {
	if strings.TrimSpace(m.Description) == "" {
		return fmt.Errorf("description is required")
	}
	if m.Module == "" {
		m.Module = "connector.lua"
	}
	if !luaFile(m.Module) || strings.ContainsAny(m.Module, "/\\") {
		return fmt.Errorf("module must be a .lua or .luau file in the bundle")
	}
	if _, err := bundleFile(dir, m.Module); err != nil {
		return fmt.Errorf("module: %w", err)
	}
	switch m.Proxy.Protocol {
	case "http", "postgres", "mysql", "clickhouse":
	default:
		return fmt.Errorf("unknown proxy protocol")
	}
	var selected authMethod
	if err := json.Unmarshal(m.Auth, &selected); err != nil {
		return err
	}
	if selected.Type == "oauth2" && m.Proxy.Protocol != "http" {
		return fmt.Errorf("oauth2 requires the http protocol")
	}
	if len(m.Access) == 0 {
		return fmt.Errorf("access modes are required")
	}
	for _, mode := range m.Access {
		if mode.ID != "read-only" && mode.ID != "read-write" {
			return fmt.Errorf("invalid access mode %q", mode.ID)
		}
	}
	return nil
}

func validateAuth(raw json.RawMessage, publisher string) error {
	methods, err := authMethods(raw)
	if err != nil {
		return err
	}
	ids := map[string]bool{}
	types := map[string]int{}
	parsed := make([]authMethod, len(methods))
	for i, method := range methods {
		if err := json.Unmarshal(method, &parsed[i]); err != nil {
			return fmt.Errorf("auth: %w", err)
		}
		if parsed[i].Type != "secret" && parsed[i].Type != "oauth2" {
			return fmt.Errorf("auth type must be secret or oauth2")
		}
		types[parsed[i].Type]++
		var fields map[string]json.RawMessage
		if err := json.Unmarshal(method, &fields); err != nil {
			return err
		}
		for _, key := range []string{"client_secret", "access_token", "refresh_token"} {
			if _, ok := fields[key]; ok {
				return fmt.Errorf("auth must not contain %s", key)
			}
			if _, ok := parsed[i].OAuth[key]; ok {
				return fmt.Errorf("oauth must not contain %s", key)
			}
		}
	}
	for _, method := range parsed {
		id := method.ID
		if id == "" {
			if types[method.Type] != 1 {
				return fmt.Errorf("auth methods sharing a type require explicit ids")
			}
			id = method.Type
		}
		if !slugPattern.MatchString(id) || ids[id] {
			return fmt.Errorf("auth method ids must be unique slugs")
		}
		ids[id] = true
		if method.Type == "oauth2" {
			var registration string
			_ = json.Unmarshal(method.OAuth["registration_id"], &registration)
			if publisher == "" || registration == "" {
				return fmt.Errorf("oauth2 requires publisher_id and oauth.registration_id")
			}
		}
	}
	return nil
}

func luaFile(name string) bool { ext := filepath.Ext(name); return ext == ".lua" || ext == ".luau" }

func bundleFile(dir, name string) ([]byte, error) {
	if name == "" || filepath.IsAbs(name) || strings.Contains(name, "\\") {
		return nil, fmt.Errorf("invalid bundle path %q", name)
	}
	for _, part := range strings.Split(filepath.ToSlash(name), "/") {
		if part == ".." {
			return nil, fmt.Errorf("bundle path escapes its directory")
		}
	}
	root, err := filepath.Abs(dir)
	if err != nil {
		return nil, err
	}
	full := filepath.Join(root, name)
	info, err := os.Lstat(full)
	if err != nil {
		return nil, err
	}
	if !info.Mode().IsRegular() {
		return nil, fmt.Errorf("bundle files must be regular files")
	}
	resolved, err := filepath.EvalSymlinks(full)
	if err != nil {
		return nil, err
	}
	rel, err := filepath.Rel(root, resolved)
	if err != nil || rel == ".." || strings.HasPrefix(rel, ".."+string(filepath.Separator)) {
		return nil, fmt.Errorf("bundle path escapes its directory")
	}
	if info.Size() > 4<<20 {
		return nil, fmt.Errorf("bundle file exceeds 4 MiB")
	}
	raw, err := os.ReadFile(full)
	if err != nil {
		return nil, err
	}
	if len(bytes.TrimSpace(raw)) == 0 {
		return nil, fmt.Errorf("empty bundle file %s", name)
	}
	return raw, nil
}
