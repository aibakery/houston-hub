// Command validate checks manifests using the same contract as Houston.
package main

import (
	"bytes"
	"context"
	"fmt"
	"github.com/aibakery/houston-hub/assets"
	"github.com/aibakery/houston-hub/manifest"
	"github.com/aibakery/houston-hub/tools/conformance"
	"github.com/aibakery/houston-hub/tools/typecheck"
	"os"
	"path/filepath"
	"slices"
	"strings"
)

// Bundles migrated to the current runtime. Pass a directory to validate another.
var migrated = []string{"connectors/fastmail", "connectors/notion", "connectors/gmail", "connectors/gcalendar", "connectors/gdrive", "connectors/gsheets", "connectors/gforms", "connectors/mercury", "connectors/x", "connectors/linkedin", "connectors/clickhouse", "connectors/mariadb", "connectors/mysql", "connectors/postgres", "connectors/redis", "connectors/imap", "connectors/supabase", "connectors/woocommerce", "connectors/prestashop", "connectors/dolibarr", "connectors/calcom", "connectors/calendly", "connectors/carta", "connectors/carta-crm", "connectors/dropbox", "connectors/resend", "connectors/stripe", "connectors/wise", "connectors/github", "connectors/meta", "connectors/gusto", "connectors/assessfirst"}

// Bundles still on the old synchronous HTTP API: they fail type analysis, but their
// fixtures run. Every bundle belongs to exactly one of these lists.
var unmigrated = []string{"connectors/attio", "connectors/granola", "connectors/slack"}

func main() {
	roots := append(append([]string{}, migrated...), unmigrated...)
	if len(os.Args) > 2 {
		fmt.Fprintln(os.Stderr, "usage: go run ./tools/validate [bundle-or-catalog-directory]")
		os.Exit(2)
	}
	if len(os.Args) == 2 {
		roots = os.Args[1:]
	}
	count := 0
	for _, root := range roots {
		n, err := validate(root)
		if err != nil {
			fmt.Fprintf(os.Stderr, "%s: %v\n", root, err)
			os.Exit(1)
		}
		count += n
	}
	fmt.Printf("%d connector bundles validated\n", count)
}
func validate(root string) (int, error) {
	if _, err := os.Stat(filepath.Join(root, "houston.json")); err == nil {
		return 1, validateBundle(root, typed(filepath.Base(root)))
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
		if err := validateBundle(filepath.Join(root, "connectors", entry.Name()), typed(entry.Name())); err != nil {
			return count, fmt.Errorf("%s: %w", entry.Name(), err)
		}
		count++
	}
	if count == 0 {
		return 0, fmt.Errorf("empty connector catalog")
	}
	return count, nil
}

// typed reports whether a bundle is on the current runtime and so gets type analysis.
func typed(name string) bool { return !slices.Contains(unmigrated, "connectors/"+name) }

// validateBundle runs every publication check; typed=false skips type analysis for
// bundles still on the old runtime API.
func validateBundle(dir string, typed bool) error {
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
	if typed {
		if err := typecheck.Check(context.Background(), "", *m, modules); err != nil {
			return err
		}
	}
	if err := conformance.Check(context.Background(), "", *m, modules, fixtures); err != nil {
		return err
	}
	if m.Icon != "" {
		raw, err := bundleFile(dir, m.Icon)
		if err != nil {
			return err
		}
		if err := assets.ValidateIcon(m.Icon, raw); err != nil {
			return err
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
