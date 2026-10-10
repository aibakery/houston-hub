package manifest

import (
	"fmt"
	"net/url"
	"slices"
	"strings"
)

func (p Proxy) validateOpaquePathParameters() error {
	names := p.Match.OpaquePathParameters
	if names == nil {
		return nil
	}
	if len(names) == 0 || len(p.Match.Path) == 0 || p.Action.Rewrite != nil {
		return fmt.Errorf("opaque_path_parameters requires nonempty names and explicit paths without rewrite")
	}
	seen := map[string]bool{}
	for _, name := range names {
		if name == "" || seen[name] {
			return fmt.Errorf("invalid or duplicate opaque path parameter")
		}
		seen[name] = true
		for _, pattern := range p.Match.Path {
			want := "{" + name + "}"
			if name == "*" {
				want = "*"
			}
			if !slices.Contains(strings.Split(pattern, "/"), want) {
				return fmt.Errorf("opaque path parameters must name placeholders in every explicit path")
			}
		}
	}
	return nil
}

// Match original escaped segments, so encoded delimiters inside an explicitly
// opaque parameter never change the route's structure or another parameter.
func (m ProxyMatch) matchesOpaquePath(raw string) bool {
	segments := strings.Split(raw, "/")
	for _, pattern := range m.Path {
		parts := strings.Split(pattern, "/")
		wildcard := parts[len(parts)-1] == "*"
		if len(segments) < len(parts) || (!wildcard && len(parts) != len(segments)) {
			continue
		}
		matched := true
		for i, part := range parts {
			if part == "*" {
				if slices.Contains(m.OpaquePathParameters, "*") {
					matched = safeOpaqueSegment(strings.Join(segments[i:], "/"))
				} else {
					_, err := requestPath("/" + strings.Join(segments[i:], "/"))
					matched = err == nil
				}
				break
			}
			if placeholder(part) && slices.Contains(m.OpaquePathParameters, part[1:len(part)-1]) {
				if !safeOpaqueSegment(segments[i]) {
					matched = false
					break
				}
				continue
			}
			segment, err := requestPath("/" + segments[i])
			if err != nil || (part != strings.TrimPrefix(segment, "/") && (!placeholder(part) || segment == "/")) {
				matched = false
				break
			}
		}
		if matched {
			return true
		}
	}
	return false
}

func safeOpaqueSegment(raw string) bool {
	if raw == "" {
		return false
	}
	for depth := 0; depth < 16; depth++ {
		for _, b := range []byte(raw) {
			if b < 32 || b == 127 {
				return false
			}
		}
		for _, part := range strings.FieldsFunc(raw, func(r rune) bool { return r == '/' || r == '\\' }) {
			if part == "." || part == ".." {
				return false
			}
		}
		// Decode only valid percent triples. A literal percent is valid opaque
		// data, including when another escape appears later in the same ID.
		var decoded strings.Builder
		changed := false
		for i := 0; i < len(raw); i++ {
			if raw[i] == '%' && i+2 < len(raw) {
				if value, err := url.PathUnescape(raw[i : i+3]); err == nil {
					decoded.WriteString(value)
					i += 2
					changed = true
					continue
				}
			}
			decoded.WriteByte(raw[i])
		}
		if !changed {
			return true
		}
		raw = decoded.String()
	}
	return false
}
