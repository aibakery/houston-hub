package manifest

import (
	"fmt"
	"net/url"
	"slices"
	"strings"
)

func (p Proxy) validateOpaquePathParameters() error {
	if p.Match.OpaquePathParameters == nil {
		return nil
	}
	if p.Action.Rewrite != nil {
		return fmt.Errorf("opaque_path_parameters requires explicit paths without rewrite")
	}
	return p.Match.validatePathParameters("opaque_path_parameters", p.Match.OpaquePathParameters, true)
}

func (p Proxy) validateColonPathParameters() error {
	if p.Match.ColonPathParameters == nil {
		return nil
	}
	return p.Match.validatePathParameters("colon_path_parameters", p.Match.ColonPathParameters, false)
}

// validatePathParameters requires nonempty unique names, each naming a
// placeholder in every explicit path; only opaque parameters may name the
// terminal * wildcard.
func (m ProxyMatch) validatePathParameters(field string, names []string, wildcard bool) error {
	if len(names) == 0 || len(m.Path) == 0 {
		return fmt.Errorf("%s requires nonempty names and explicit paths", field)
	}
	seen := map[string]bool{}
	for _, name := range names {
		if name == "" || seen[name] || (name == "*" && !wildcard) {
			return fmt.Errorf("invalid or duplicate %s entry", field)
		}
		seen[name] = true
		for _, pattern := range m.Path {
			if !slices.ContainsFunc(strings.Split(pattern, "/"), func(part string) bool {
				if name == "*" {
					return part == "*"
				}
				parameter, _, ok := pathParameter(part)
				return ok && parameter == name
			}) {
				return fmt.Errorf("%s must name placeholders in every explicit path", field)
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
					matched = safeOpaqueSegment(strings.Join(segments[i:], "/"))
				} else {
					_, err := requestPath("/" + strings.Join(segments[i:], "/"))
					matched = err == nil
				}
				break
			}
			name, verb, parameter := pathParameter(part)
			if parameter && slices.Contains(m.OpaquePathParameters, name) {
				if value, ok := m.parameterValue(name, verb, segments[i]); !ok || !safeOpaqueSegment(value) {
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

func safeOpaqueSegment(raw string) bool {
	_, ok := decodeOpaque(raw)
	return ok
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
