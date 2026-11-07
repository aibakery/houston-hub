package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// A shared request layer must satisfy every consumer's real provider fixtures.
// Run each distinct implementation in every bundle of its family, so a helper
// change is checked against all consumers without requiring identical spelling.
func TestSharedRequestLayerContracts(t *testing.T) {
	paths, err := filepath.Glob("../../connectors/*/connector.luau")
	if err != nil {
		t.Fatal(err)
	}
	type consumer struct{ dir, prefix, suffix string }
	type family struct {
		consumers []consumer
		layers    []string
		seen      map[string]bool
	}
	families := map[string]*family{}
	for _, path := range paths {
		raw, err := os.ReadFile(path)
		if err != nil {
			t.Fatal(err)
		}
		prefix, rest, shared := strings.Cut(string(raw), "-- Request layer shared verbatim by the ")
		if !shared {
			continue
		}
		group, _, _ := strings.Cut(rest, " connectors")
		_, body, _ := strings.Cut(rest, "\n")
		layer, suffix, ended := strings.Cut(body, "-- End of the shared request layer.")
		if !ended {
			t.Fatalf("cannot load shared request layer from %s", path)
		}
		f := families[group]
		if f == nil {
			f = &family{seen: map[string]bool{}}
			families[group] = f
		}
		f.consumers = append(f.consumers, consumer{filepath.Dir(path), prefix, suffix})
		if !f.seen[layer] {
			f.layers = append(f.layers, layer)
			f.seen[layer] = true
		}
	}
	if len(families) == 0 {
		t.Fatal("no shared request layers to exercise")
	}
	for group, f := range families {
		for i, layer := range f.layers {
			for _, c := range f.consumers {
				t.Run(fmt.Sprintf("%s/%d/%s", group, i, filepath.Base(c.dir)), func(t *testing.T) {
					dir := t.TempDir()
					if err := os.CopyFS(dir, os.DirFS(c.dir)); err != nil {
						t.Fatal(err)
					}
					if err := os.WriteFile(filepath.Join(dir, "connector.luau"), []byte(c.prefix+layer+c.suffix), 0600); err != nil {
						t.Fatal(err)
					}
					if err := validateBundle(dir); err != nil {
						t.Fatal(err)
					}
				})
			}
		}
	}
}
