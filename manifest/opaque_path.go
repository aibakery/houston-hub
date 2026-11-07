package manifest

import (
	"fmt"
	"net/url"
	"slices"
	"strings"
)

// validatePathParameters requires nonempty unique names of explicit path
// placeholders. Opaque parameters change how the whole rule matches, so each
// must appear in every path and only they may name the terminal * wildcard; a
// colon parameter only widens its own placeholder, so one path suffices, and
// it cannot repeat an opaque parameter, which already accepts colons.
func (m ProxyMatch) validatePathParameters(field string, names []string, opaque bool) error {
	if len(names) == 0 || len(m.Path) == 0 {
		return fmt.Errorf("%s requires nonempty names and explicit paths", field)
	}
	found := map[string]int{} // Paths naming each placeholder; "*" counts terminal wildcards.
	for _, pattern := range m.Path {
		inPath := map[string]bool{}
		for _, part := range strings.Split(pattern, "/") {
			if name, _, ok := pathParameter(part); ok {
				inPath[name] = true
			} else if part == "*" {
				inPath["*"] = true
			}
		}
		for name := range inPath {
			found[name]++
		}
	}
	seen := map[string]bool{}
	for _, name := range names {
		if name == "" || seen[name] || (name == "*" && !opaque) {
			return fmt.Errorf("invalid or duplicate %s entry", field)
		}
		seen[name] = true
		if opaque && found[name] != len(m.Path) {
			return fmt.Errorf("%s must name a placeholder in every explicit path", field)
		}
		if found[name] == 0 {
			return fmt.Errorf("%s must name a placeholder in at least one explicit path", field)
		}
		if !opaque && slices.Contains(m.OpaquePathParameters, name) {
			return fmt.Errorf("colon_path_parameters repeats opaque parameter %s, which already accepts colons", name)
		}
	}
	return nil
}

// Match original escaped segments, so encoded delimiters inside an explicitly
// opaque parameter never change the route's structure or another parameter.
func (m ProxyMatch) matchesOpaquePath(segments []string) bool {
	for _, pattern := range m.Path {
		if templated(pattern) {
			continue
		}
		parts := strings.Split(pattern, "/")
		wildcard := parts[len(parts)-1] == "*"
		if len(segments) < len(parts) || (!wildcard && len(parts) != len(segments)) {
			continue
		}
		matched := true
		for i, part := range parts {
			if part == "*" {
				if slices.Contains(m.OpaquePathParameters, "*") {
					_, matched = decodeOpaque(strings.Join(segments[i:], "/"))
				} else {
					_, err := requestPath("/" + strings.Join(segments[i:], "/"))
					matched = err == nil
				}
				break
			}
			name, verb, parameter := pathParameter(part)
			if parameter && slices.Contains(m.OpaquePathParameters, name) {
				value, ok := m.parameterValue(name, verb, segments[i])
				if _, safe := decodeOpaque(value); !ok || !safe {
					matched = false
					break
				}
				continue
			}
			segment, err := requestPath("/" + segments[i])
			if err != nil {
				matched = false
				break
			}
			if literalMatches(part, strings.TrimPrefix(segment, "/"), segments[i]) {
				continue
			}
			if _, ok := m.parameterValue(name, verb, segments[i]); !parameter || !ok {
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

// decodeOpaque decodes valid percent triples repeatedly and returns the final
// value. It fails for an empty value, or for control bytes or dot segments at
// any of up to 16 decoding depths.
func decodeOpaque(raw string) (string, bool) {
	if raw == "" {
		return "", false
	}
	for depth := 0; depth < 16; depth++ {
		for _, b := range []byte(raw) {
			if b < 32 || b == 127 {
				return "", false
			}
		}
		for _, part := range strings.FieldsFunc(raw, func(r rune) bool { return r == '/' || r == '\\' }) {
			if part == "." || part == ".." {
				return "", false
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
			return raw, true
		}
		raw = decoded.String()
	}
	return "", false
}
