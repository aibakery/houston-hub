// Command validate checks manifests using the same contract as Houston.
package main

import (
	"bytes"
	"context"
	"fmt"
	"github.com/aibakery/houston-hub/analysis"
	"github.com/aibakery/houston-hub/conformance"
	"github.com/aibakery/houston-hub/manifest"
	"image/png"
	"os"
	"path/filepath"
	"strings"
)

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
	fmt.Printf("%d connector bundles validated\n", count)
}
func validate(root string) (int, error) {
	if _, err := os.Stat(filepath.Join(root, "houston.json")); err == nil {
		return 1, validateBundle(root)
	}
	entries, err := os.ReadDir(filepath.Join(root, "connectors"))
	if err != nil {
		return 0, err
	}
	count := 0
	for _, entry := range entries {
		if !entry.IsDir() {
			continue
		}
		if err := validateBundle(filepath.Join(root, "connectors", entry.Name())); err != nil {
			return count, fmt.Errorf("%s: %w", entry.Name(), err)
		}
		count++
	}
	if count == 0 {
		return 0, fmt.Errorf("empty connector catalog")
	}
	return count, nil
}
func validateBundle(dir string) error {
	raw, err := bundleFile(dir, "houston.json")
	if err != nil {
		return err
	}
	m, err := manifest.Parse(raw)
	if err != nil {
		return err
	}
	modules := map[string]string{}
	fixtures := map[string]string{}
	for _, file := range m.Files {
		if _, err := bundleFile(dir, file); err != nil {
			return fmt.Errorf("entrypoint: %w", err)
		}
	}
	if err := filepath.WalkDir(dir, func(path string, entry os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if entry.IsDir() {
			return nil
		}
		rel, err := filepath.Rel(dir, path)
		if err != nil {
			return err
		}
		if luaFile(rel) {
			var source []byte
			source, err = bundleFile(dir, rel)
			if strings.HasPrefix(filepath.ToSlash(rel), "tests/") {
				fixtures[filepath.ToSlash(rel)] = string(source)
			} else {
				modules[filepath.ToSlash(rel)] = string(source)
			}
		}
		return err
	}); err != nil {
		return err
	}
	if err := analysis.Check(context.Background(), "", *m, modules); err != nil {
		return err
	}
	if err := conformance.Check(context.Background(), "", *m, modules, fixtures); err != nil {
		return err
	}
	if m.Icon != "" {
		raw, err := bundleFile(dir, m.Icon)
		if err != nil {
			return err
		}
		if m.Icon == "icon.png" {
			image, err := png.DecodeConfig(bytes.NewReader(raw))
			if err != nil || image.Width != 1024 || image.Height != 1024 {
				return fmt.Errorf("icon must be a 1024x1024 PNG")
			}
		} else if !bytes.Contains(bytes.ToLower(raw), []byte("<svg")) {
			return fmt.Errorf("icon must be an SVG document")
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
