package main

import (
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
)

// Bundles cannot import each other's files, so related connectors carry the same request
// layer between markers that name the group.
func TestConnectorsShareOneRequestLayer(t *testing.T) {
	paths, err := filepath.Glob("../../connectors/*/connector.lua")
	if err != nil {
		t.Fatal(err)
	}
	layers := map[string][]string{}
	for _, path := range paths {
		raw, err := os.ReadFile(path)
		if err != nil {
			t.Fatal(err)
		}
		_, rest, started := strings.Cut(string(raw), "-- Request layer shared verbatim by the ")
		if !started {
			continue
		}
		group, _, _ := strings.Cut(rest, " connectors")
		layer, _, ended := strings.Cut(rest, "-- End of the shared request layer.")
		if !ended {
			t.Fatalf("%s: shared request layer end marker missing", path)
		}
		if len(layers[group]) > 0 && layer != layers[group][0] {
			t.Errorf("%s: shared request layer differs from the other %s connectors", path, group)
		}
		layers[group] = append(layers[group], layer)
	}
	groups := []string{}
	for group, copies := range layers {
		if len(copies) < 2 {
			t.Errorf("%s: shared request layer has a single copy", group)
		}
		groups = append(groups, group)
	}
	slices.Sort(groups)
	if !slices.Equal(groups, []string{"Cal.com, Calendly and Resend", "Google"}) {
		t.Errorf("shared request layer groups %v", groups)
	}
}
