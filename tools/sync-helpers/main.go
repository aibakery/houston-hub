// Command sync-helpers copies the canonical private helper into each HTTP bundle.
package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

func main() {
	raw, err := os.ReadFile("helpers/http.lua")
	if err != nil {
		panic(err)
	}
	paths, _ := filepath.Glob("connectors/*/connector.lua")
	for _, p := range paths {
		code, err := os.ReadFile(p)
		if err != nil {
			panic(err)
		}
		if !strings.Contains(string(code), `require("lib/http.lua")`) {
			continue
		}
		dir := filepath.Join(filepath.Dir(p), "lib")
		if err := os.MkdirAll(dir, 0755); err != nil {
			panic(err)
		}
		if err := os.WriteFile(filepath.Join(dir, "http.lua"), raw, 0644); err != nil {
			panic(err)
		}
		fmt.Println(p)
	}
}
