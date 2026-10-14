package main

import (
	"os"
	"strings"
	"testing"
)

// Bundles cannot import each other's files, so related connectors carry the same request layer.
func TestConnectorsShareOneRequestLayer(t *testing.T) {
	for _, group := range [][]string{{"gcalendar", "gdrive", "gmail"}, {"calcom", "calendly"}} {
		var shared string
		for _, name := range group {
			raw, err := os.ReadFile("../../connectors/" + name + "/connector.lua")
			if err != nil {
				t.Fatal(err)
			}
			_, rest, started := strings.Cut(string(raw), "-- Request layer shared verbatim")
			layer, _, ended := strings.Cut(rest, "-- End of the shared request layer.")
			if !started || !ended {
				t.Fatalf("%s: shared request layer markers missing", name)
			}
			if shared == "" {
				shared = layer
			} else if layer != shared {
				t.Fatalf("%s: shared request layer differs from %s's", name, group[0])
			}
		}
	}
}
