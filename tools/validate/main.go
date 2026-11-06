// Command validate checks manifests using the same contract as Houston.
package main

import (
	"bytes"
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"github.com/aibakery/houston-hub/assets"
	"github.com/aibakery/houston-hub/manifest"
	"github.com/aibakery/houston-hub/tools/conformance"
	"github.com/aibakery/houston-hub/tools/typecheck"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
)

func main() {
	reportPath := flag.String("help-report", "", "require structured catalog help and write per-fixture coverage JSON")
	flag.Parse()
	roots := []string{"."}
	if flag.NArg() > 1 {
		fmt.Fprintln(os.Stderr, "usage: go run ./tools/validate [-help-report path] [bundle-or-catalog-directory]")
		os.Exit(2)
	}
	if flag.NArg() == 1 {
		roots = flag.Args()
	}
	var report map[string][]conformance.Coverage
	if *reportPath != "" {
		report = map[string][]conformance.Coverage{}
	}
	count := 0
	for _, root := range roots {
		n, err := validateWithCoverage(root, report)
		if err != nil {
			fmt.Fprintf(os.Stderr, "%s: %v\n", root, err)
			os.Exit(1)
		}
		count += n
	}
	if report != nil {
		raw, err := json.MarshalIndent(report, "", "  ")
		if err == nil {
			err = os.WriteFile(*reportPath, append(raw, '\n'), 0644)
		}
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
	}
	fmt.Printf("%d connector bundles validated\n", count)
}
func validate(root string) (int, error) {
	return validateWithCoverage(root, nil)
}
func validateWithCoverage(root string, report map[string][]conformance.Coverage) (int, error) {
	if _, err := os.Stat(filepath.Join(root, "houston.json")); err == nil {
		return 1, validateBundleWithCoverage(root, report)
	}
	directories, err := catalogDirectories(root)
	if err != nil {
		return 0, err
	}
	// A maintained catalog requires structured coverage; standalone publication
	// remains compatible with existing third-party string documentation.
	if report == nil {
		report = map[string][]conformance.Coverage{}
	}
	count := 0
	for _, directory := range directories {
		if err := validateBundleWithCoverage(directory, report); err != nil {
			return count, fmt.Errorf("%s: %w", directory, err)
		}
		count++
	}
	return count, nil
}

func catalogDirectories(root string) ([]string, error) {
	var directories []string
	err := filepath.WalkDir(filepath.Join(root, "connectors"), func(path string, entry fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if !entry.IsDir() && entry.Name() == "houston.json" {
			directories = append(directories, filepath.Dir(path))
		}
		return nil
	})
	if err == nil && len(directories) == 0 {
		err = fmt.Errorf("empty connector catalog")
	}
	return directories, err
}

// validateBundle runs every publication check.
func validateBundle(dir string) error {
	return validateBundleWithCoverage(dir, nil)
}
func validateBundleWithCoverage(dir string, report map[string][]conformance.Coverage) error {
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
	if err := typecheck.Check(context.Background(), "", *m, modules); err != nil {
		return err
	}
	if report != nil {
		coverage, err := conformance.CheckCatalog(context.Background(), "", *m, modules, fixtures)
		if err != nil {
			return err
		}
		report[filepath.ToSlash(dir)] = coverage
	} else {
		if err := conformance.Check(context.Background(), "", *m, modules, fixtures); err != nil {
			return err
		}
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
