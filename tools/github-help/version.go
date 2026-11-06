package main

import (
	"fmt"
	"slices"
	"strings"
)

// GitHub publishes both merge patches and JSON Patch operations. Reject patch
// forms that this snapshot does not use rather than silently keeping old inputs.
func applyVersion(op object, version string) {
	changes := list(op["x-github-breaking-changes"])
	slices.SortStableFunc(changes, func(a, b any) int {
		return strings.Compare(fmt.Sprint(obj(a)["version"]), fmt.Sprint(obj(b)["version"]))
	})
	for _, v := range changes {
		change := obj(v)
		date, ok := change["version"].(string)
		if !ok {
			panic("versioned patch without version")
		}
		if date > version {
			continue
		}
		if patch := obj(change["patch"]); patch != nil {
			mergePatch(op, patch)
			continue
		}
		patch := list(change["patch"])
		if patch == nil {
			panic("unsupported version patch")
		}
		for _, v := range patch {
			step := obj(v)
			path, ok := step["path"].(string)
			if !ok || !strings.HasPrefix(path, "/") {
				panic("invalid patch pointer")
			}
			parts := strings.Split(path[1:], "/")
			parent := op
			for _, key := range parts[:len(parts)-1] {
				key = pointerKey(key)
				parent = obj(parent[key])
				if parent == nil {
					panic("patch does not address an object: " + path)
				}
			}
			key := pointerKey(parts[len(parts)-1])
			switch step["op"] {
			case "remove":
				if _, ok := parent[key]; !ok {
					panic("missing patch target " + path)
				}
				delete(parent, key)
			case "replace":
				if _, ok := parent[key]; !ok {
					panic("missing patch target " + path)
				}
				parent[key] = clone(step["value"])
			case "add":
				parent[key] = clone(step["value"])
			default:
				panic(fmt.Sprint("unsupported patch operation ", step["op"]))
			}
		}
	}
	delete(op, "x-github-breaking-changes")
}
func pointerKey(key string) string {
	return strings.ReplaceAll(strings.ReplaceAll(key, "~1", "/"), "~0", "~")
}
func mergePatch(target, patch object) {
	for key, value := range patch {
		if value == nil {
			delete(target, key)
		} else if child := obj(value); child != nil {
			dst := obj(target[key])
			if dst == nil {
				dst = object{}
				target[key] = dst
			}
			mergePatch(dst, child)
		} else {
			target[key] = clone(value)
		}
	}
}
