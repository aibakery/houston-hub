package main

import (
	"encoding/json"
	"fmt"
	"github.com/aibakery/houston-hub/tools/internal/helpschema"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"sync"
	"time"
)

// Fetch only the published, versioned reference. Generation and runtime help
// consume local schemas; neither needs an authenticated Gusto connection.
func fetchSnapshots(source, directory string) error {
	if err := os.MkdirAll(directory, 0755); err != nil {
		return err
	}
	client := http.Client{Timeout: 30 * time.Second}
	slots := make(chan struct{}, 4)
	var wg sync.WaitGroup
	var mu sync.Mutex
	var failures []string
	for _, ep := range helpschema.Endpoints(source) {
		m := regexp.MustCompile(`doc = "([a-z0-9_-]+)"`).FindStringSubmatch(ep.Definition)
		if len(m) == 0 {
			return fmt.Errorf("missing reference page: %s", ep.Name)
		}
		name, page := ep.Name, m[1]
		wg.Add(1)
		go func() {
			defer wg.Done()
			slots <- struct{}{}
			defer func() { <-slots }()
			err := func() error {
				url := "https://docs.gusto.com/app-integrations/reference/" + page + ".md"
				response, err := client.Get(url)
				if err != nil {
					return err
				}
				defer response.Body.Close()
				if response.StatusCode != 200 {
					return fmt.Errorf("%s: %s", url, response.Status)
				}
				b, err := io.ReadAll(io.LimitReader(response.Body, 8<<20+1))
				if err != nil {
					return err
				}
				if len(b) > 8<<20 {
					return fmt.Errorf("oversized reference %s", url)
				}
				text := string(b)
				start := strings.Index(text, "```json\n")
				if start < 0 {
					return fmt.Errorf("missing OpenAPI in %s", url)
				}
				text = text[start+8:]
				end := strings.Index(text, "\n```")
				if end < 0 {
					return fmt.Errorf("unclosed OpenAPI in %s", url)
				}
				b = []byte(text[:end])
				if !json.Valid(b) {
					return fmt.Errorf("invalid OpenAPI in %s", url)
				}
				return os.WriteFile(filepath.Join(directory, name+".json"), b, 0644)
			}()
			if err != nil {
				mu.Lock()
				failures = append(failures, err.Error())
				mu.Unlock()
			}
		}()
	}
	wg.Wait()
	if len(failures) > 0 {
		return fmt.Errorf("%s", strings.Join(failures, "\n"))
	}
	return nil
}
