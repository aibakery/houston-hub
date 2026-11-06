package main

import (
	"bytes"
	"compress/zlib"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"sync"
	"time"
)

// fetchSnapshots reads only public documentation. Runtime discovery and normal
// generation use the saved operation JSON and never contact Carta.
func fetchSnapshots(connector, directory string) error {
	client := http.Client{Timeout: 30 * time.Second}
	get := func(url string) ([]byte, error) {
		response, e := client.Get(url)
		if e != nil {
			return nil, e
		}
		defer response.Body.Close()
		if response.StatusCode != 200 {
			return nil, fmt.Errorf("%s: %s", url, response.Status)
		}
		b, e := io.ReadAll(io.LimitReader(response.Body, 16<<20+1))
		if e == nil && len(b) > 16<<20 {
			return nil, fmt.Errorf("documentation asset exceeds 16 MiB: %s", url)
		}
		return b, e
	}
	kind, prefix, page := "api-platform", "v-1-alpha-1-", "user-get-current-user"
	if connector == "carta-crm" {
		kind, prefix, page = "crm", "public-", "organization-configuration-controller-get-current-user"
	}
	html, e := get("https://docs.carta.com/" + kind + "/reference/" + prefix + page)
	if e != nil {
		return e
	}
	assets := regexp.MustCompile(`<script[^>]+src=["']?(https://[^\s"'>]+/(?:runtime~main|main)\.[^\s"'>]+\.js)`).FindAllSubmatch(html, -1)
	var index, runtime []byte
	var base string
	for _, asset := range assets {
		url := string(asset[1])
		b, e := get(url)
		if e != nil {
			return e
		}
		if strings.Contains(url, "/runtime~main.") {
			runtime = b
			base = url[:strings.LastIndex(url, "/assets/js/")]
		} else {
			index = b
		}
	}
	if len(index) == 0 || len(runtime) == 0 {
		return fmt.Errorf("public documentation scripts not found")
	}
	modules := regexp.MustCompile(`Promise\.all\(\[([^\]]+)\]\)\.then\(t\.bind\(t,\d+\)\),"@site/docs/([^"]+)"`).FindAllSubmatch(index, -1)
	if e = os.MkdirAll(directory, 0755); e != nil {
		return e
	}
	type job struct{ doc, url string }
	jobs := []job{}
	for _, module := range modules {
		path := string(module[2])
		if !strings.HasPrefix(path, kind+"/reference/"+prefix) || !strings.HasSuffix(path, ".api.mdx") {
			continue
		}
		ids := regexp.MustCompile(`t\.e\("(\d+)"\)`).FindAllSubmatch(module[1], -1)
		if len(ids) == 0 {
			return fmt.Errorf("missing documentation chunk for %s", path)
		}
		id := string(ids[len(ids)-1][1])
		hashes := regexp.MustCompile(`(?:\{|,)`+id+`:"([^"]+)"`).FindAllSubmatch(runtime, -1)
		if len(hashes) != 2 {
			return fmt.Errorf("unexpected chunk mapping for %s", path)
		}
		url := base + "/assets/js/" + string(hashes[0][1]) + "." + string(hashes[1][1]) + ".js"
		doc := strings.TrimSuffix(strings.TrimPrefix(path, kind+"/reference/"+prefix), ".api.mdx")
		if !regexp.MustCompile(`^[a-z0-9-]+$`).MatchString(doc) {
			return fmt.Errorf("unexpected documentation name %q", doc)
		}
		jobs = append(jobs, job{doc, url})
	}
	if len(jobs) == 0 {
		return fmt.Errorf("no operation assets found")
	}
	var wg sync.WaitGroup
	gate := make(chan struct{}, 4)
	errors := make(chan error, len(jobs))
	for _, job := range jobs {
		doc, url := job.doc, job.url
		wg.Add(1)
		go func() {
			defer wg.Done()
			gate <- struct{}{}
			defer func() { <-gate }()
			e := func() error {
				b, e := get(url)
				if e != nil {
					return e
				}
				m := regexp.MustCompile(`"api":"([^"]+)"`).FindSubmatch(b)
				if len(m) == 0 {
					return fmt.Errorf("missing operation data in %s", url)
				}
				compressed, e := base64.StdEncoding.DecodeString(string(m[1]))
				if e != nil {
					return e
				}
				reader, e := zlib.NewReader(bytes.NewReader(compressed))
				if e != nil {
					return e
				}
				data, e := io.ReadAll(io.LimitReader(reader, 16<<20+1))
				reader.Close()
				if e != nil {
					return e
				}
				if len(data) > 16<<20 {
					return fmt.Errorf("operation data exceeds 16 MiB: %s", doc)
				}
				var op object
				if e = json.Unmarshal(data, &op); e != nil {
					return e
				}
				delete(op, "postman")
				delete(op, "responses")
				op["x-documentation-url"] = "https://docs.carta.com/" + kind + "/reference/" + prefix + doc
				op["x-documentation-asset"] = url
				data, e = json.MarshalIndent(op, "", "\t")
				if e != nil {
					return e
				}
				return os.WriteFile(filepath.Join(directory, doc+".json"), data, 0644)
			}()
			if e != nil {
				errors <- e
			}
		}()
	}
	wg.Wait()
	close(errors)
	for e := range errors {
		return e
	}
	return nil
}
