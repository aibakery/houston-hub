// Command meta-help derives native parameter types and enums from the pinned
// official Business SDK. Python source is parsed as data, never executed.
package main

import (
	"crypto/sha256"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
)

type object = map[string]any

func must(e error) {
	if e != nil {
		panic(e)
	}
}

var methods = map[string][]string{
	"createPost": {"page.create_feed"}, "updatePost": {"post.api_update"}, "uploadPhoto": {"page.create_photo"}, "uploadVideo": {"page.create_video"},
	"createComment": {"post.create_comment"}, "updateComment": {"comment.api_update", "igcomment.api_update"}, "createInstagramReply": {"igcomment.create_reply"}, "updateInstagramMedia": {"igmedia.api_update"},
	"sendMessage": {"page.create_message"}, "createInstagramContainer": {"iguser.create_media"}, "publishInstagramMedia": {"iguser.create_media_publish"},
	"listFeed": {"page.get_feed"}, "listPublishedPosts": {"page.get_published_posts"}, "listScheduledPosts": {"page.get_scheduled_posts"}, "listTaggedPosts": {"page.get_tagged"}, "listPhotos": {"page.get_photos"}, "listVideos": {"page.get_videos"}, "listReels": {"page.get_video_reels"}, "listRatings": {"page.get_ratings"},
	"listComments": {"post.get_comments"}, "listReactions": {"post.get_reactions"}, "getInsights": {"page.get_insights", "iguser.get_insights", "igmedia.get_insights"}, "listConversations": {"page.get_conversations"}, "listMessages": {"unifiedthread.get_messages"},
	"listInstagramMedia": {"iguser.get_media"}, "listInstagramStories": {"iguser.get_stories"}, "listInstagramTags": {"iguser.get_tags"}, "listInstagramChildren": {"igmedia.get_children"}, "listInstagramComments": {"igmedia.get_comments"}, "listInstagramReplies": {"igcomment.get_replies"}, "getInstagramPublishingLimit": {"iguser.get_content_publishing_limit"},
	"listHashtagTopMedia": {"shadowighashtag.get_top_media"}, "listHashtagRecentMedia": {"shadowighashtag.get_recent_media"},
}

func block(source, marker string) string {
	start := strings.Index(source, marker)
	if start < 0 {
		panic("missing " + marker)
	}
	s := source[start+len(marker):]
	end := strings.Index(s, "\n        }")
	if end < 0 {
		panic("unterminated " + marker)
	}
	return s[:end]
}
func main() {
	directory := flag.String("sdk", "", "local facebook_business/adobjects from Business SDK26.0.2")
	root := flag.String("root", ".", "Hub root")
	flag.Parse()
	if *directory == "" {
		panic("provide -sdk directory")
	}
	version, err := os.ReadFile(filepath.Join(*directory, "../__init__.py"))
	must(err)
	if !strings.Contains(string(version), "__version__ = '26.0.2'") {
		panic("expected Business SDK 26.0.2")
	}
	cache := map[string]string{}
	sources := map[string]string{}
	read := func(file string) string {
		if s, ok := cache[file]; ok {
			return s
		}
		b, e := os.ReadFile(filepath.Join(*directory, file+".py"))
		must(e)
		cache[file] = string(b)
		sources[file] = fmt.Sprintf("%x", sha256.Sum256(b))
		return string(b)
	}
	values := func(class, enum string) []any {
		source := read(strings.ToLower(class))
		start := strings.Index(source, "    class "+enum+":")
		if start < 0 {
			panic("missing enum " + class + "." + enum)
		}
		s := source[start+len("    class "+enum+":"):]
		if next := regexp.MustCompile(`(?m)^    (class |def |_)`).FindStringIndex(s); next != nil {
			s = s[:next[0]]
		}
		result := []any{}
		for _, m := range regexp.MustCompile(`(?m)^        [A-Za-z_][A-Za-z0-9_]* = (?:'([^']*)'|(-?[0-9]+))`).FindAllStringSubmatch(s, -1) {
			if m[2] != "" {
				v, e := strconv.Atoi(m[2])
				must(e)
				result = append(result, v)
			} else {
				result = append(result, m[1])
			}
		}
		if len(result) == 0 {
			panic("empty enum " + class + "." + enum)
		}
		return result
	}
	result := object{}
	for name, locations := range methods {
		props := object{}
		for _, location := range locations {
			parts := strings.Split(location, ".")
			source := read(parts[0])
			start := strings.Index(source, "    def "+parts[1]+"(")
			if start < 0 {
				panic("missing SDK method " + location)
			}
			method := source[start:]
			if next := strings.Index(method[1:], "\n    def "); next >= 0 {
				method = method[:next+1]
			}
			enums := map[string][]any{}
			for _, m := range regexp.MustCompile(`'([^']+)': ([A-Za-z0-9_]+)\.([A-Za-z0-9_]+)\.__dict__\.values\(\)`).FindAllStringSubmatch(block(method, "enums = {"), -1) {
				enums[m[1]] = values(m[2], m[3])
			}
			for _, m := range regexp.MustCompile(`(?s)'([^']+)': \[([^]]*)\]`).FindAllStringSubmatch(block(method, "enums = {"), -1) {
				items := []any{}
				for _, value := range regexp.MustCompile(`'([^']*)'`).FindAllStringSubmatch(m[2], -1) {
					items = append(items, value[1])
				}
				if len(items) == 0 {
					panic("empty inline enum " + m[1])
				}
				enums[m[1]] = items
			}
			var schema func(string) object
			schema = func(kind string) object {
				if values, ok := enums[kind]; ok {
					return object{"enum": values}
				}
				if strings.HasPrefix(kind, "list<") {
					return object{"type": "array", "items": schema(kind[5 : len(kind)-1])}
				}
				if strings.HasPrefix(kind, "map<") {
					return object{"type": "object"}
				}
				switch kind {
				case "string":
					return object{"type": "string"}
				case "bool":
					return object{"type": "boolean"}
				case "int", "unsigned int":
					min := any(nil)
					pattern := "^-?[0-9]+$"
					if kind == "unsigned int" {
						min = 0
						pattern = "^[0-9]+$"
					}
					n := object{"type": "integer", "maximum": 9007199254740991, "minimum": -9007199254740991}
					if min != nil {
						n["minimum"] = min
					}
					return object{"anyOf": []any{n, object{"type": "string", "pattern": pattern}}}
				case "float", "double":
					return object{"type": "number"}
				case "datetime":
					return object{"anyOf": []any{object{"type": "integer"}, object{"type": "string"}}, "description": "Native Graph timestamp or date/time string."}
				case "Object", "map", "object":
					return object{"type": "object"}
				case "list":
					return object{"type": "array"}
				case "file":
					return object{"description": "Use the connector's session path upload option."}
				default:
					panic("unsupported SDK type " + kind + " in " + location)
				}
			}
			for _, m := range regexp.MustCompile(`'([^']+)': '([^']+)'`).FindAllStringSubmatch(block(method, "param_types = {"), -1) {
				s := schema(m[2])
				if previous := props[m[1]]; previous != nil {
					a, _ := json.Marshal(previous)
					b, _ := json.Marshal(s)
					if string(a) != string(b) {
						s = object{"anyOf": []any{previous, s}}
					}
				}
				props[m[1]] = s
			}
		}
		result[name] = object{"type": "object", "properties": props}
	}
	b, e := json.MarshalIndent(object{"schemas": result, "sources": sources}, "", "\t")
	must(e)
	must(os.WriteFile(filepath.Join(*root, "connectors/meta/lib/native.luau"), []byte("-- Code generated by go run ./tools/meta-help -sdk <facebook_business/adobjects>; DO NOT EDIT.\n-- Source: https://github.com/facebook/facebook-python-business-sdk/tree/26.0.2/facebook_business/adobjects\n-- SHA-256 of each input source is recorded below.\nreturn json.decode([====[\n"+string(b)+"\n]====])\n"), 0644))
	must(writeRoutes(*root))
}
