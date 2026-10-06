// Command analyze checks one bundle or every connector against trusted types.
package main

import (
	"context"
	"fmt"
	"github.com/aibakery/houston-hub/analysis"
	"github.com/aibakery/houston-hub/manifest"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
)

func main() {
	root := "."
	if len(os.Args) > 1 {
		root = os.Args[1]
	}
	paths := []string{root}
	if _, err := os.Stat(filepath.Join(root, "houston.json")); err != nil {
		paths = nil
		entries, err := os.ReadDir(filepath.Join(root, "connectors"))
		if err != nil {
			panic(err)
		}
		for _, entry := range entries {
			if entry.IsDir() {
				paths = append(paths, filepath.Join(root, "connectors", entry.Name()))
			}
		}
	}
	failed := false
	for _, path := range paths {
		if err := check(path); err != nil {
			fmt.Fprintln(os.Stderr, path, err)
			failed = true
		}
	}
	if failed {
		os.Exit(1)
	}
}
func check(root string) error {
	raw, err := os.ReadFile(filepath.Join(root, "houston.json"))
	if err != nil {
		return err
	}
	m, err := manifest.Parse(raw)
	if err != nil {
		return err
	}
	modules := map[string]string{}
	err = filepath.WalkDir(root, func(path string, entry fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		rel, err := filepath.Rel(root, path)
		if err != nil {
			return err
		}
		if entry.IsDir() {
			if rel == "tests" {
				return filepath.SkipDir
			}
			return nil
		}
		if strings.HasSuffix(path, ".lua") || strings.HasSuffix(path, ".luau") {
			raw, err := os.ReadFile(path)
			if err != nil {
				return err
			}
			modules[filepath.ToSlash(rel)] = string(raw)
		}
		return nil
	})
	if err != nil {
		return err
	}
	return analysis.Check(context.Background(), "", *m, modules)
}
