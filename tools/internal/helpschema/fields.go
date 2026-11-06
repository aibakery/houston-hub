package helpschema

import (
	"fmt"
	"regexp"
	"strconv"
	"strings"
)

// Fields reads maintained endpoint field lists: literal arrays, named literal
// arrays, list(...)/join(...) concatenation, or paged(...) with the source's PAGE suffix.
// It does not execute Luau; unsupported declarations fail generation.
func Fields(source, definition, key string) ([]string, error) {
	match := regexp.MustCompile(`\b` + regexp.QuoteMeta(key) + `\s*=\s*`).FindStringIndex(definition)
	if match == nil {
		return []string{}, nil
	}
	expression, err := fieldExpression(definition[match[1]:])
	if err != nil {
		return nil, err
	}
	active := map[string]bool{}
	var parse func(string) ([]string, error)
	parse = func(expression string) ([]string, error) {
		if strings.HasPrefix(expression, "table.freeze(") && strings.HasSuffix(expression, ")") {
			return parse(strings.TrimSuffix(strings.TrimPrefix(expression, "table.freeze("), ")"))
		}
		suffix := ""
		if strings.HasPrefix(expression, "paged(") {
			suffix = "PAGE"
		} else if strings.HasPrefix(expression, "list(") || strings.HasPrefix(expression, "join(") {
		} else if strings.Contains(expression, "(") {
			return nil, fmt.Errorf("unsupported field-list expression %s", expression)
		}
		tokens := regexp.MustCompile(`"(?:\\.|[^"\\])*"|[A-Za-z_][A-Za-z0-9_]*`).FindAllString(expression, -1)
		result := []string{}
		for index, token := range tokens {
			if index == 0 && (token == "list" || token == "join" || token == "paged") && strings.Contains(expression, "(") {
				continue
			}
			if strings.HasPrefix(token, `"`) {
				value, e := strconv.Unquote(token)
				if e != nil {
					return nil, e
				}
				result = append(result, value)
				continue
			}
			if active[token] {
				return nil, fmt.Errorf("recursive field list %s", token)
			}
			declaration := regexp.MustCompile(`(?m)^local\s+` + regexp.QuoteMeta(token) + `(?:\s*:[^=\n]+)?\s*=\s*`).FindStringIndex(source)
			if declaration == nil {
				return nil, fmt.Errorf("missing field list %s", token)
			}
			value, e := fieldExpression(source[declaration[1]:])
			if e != nil {
				return nil, e
			}
			active[token] = true
			fields, e := parse(value)
			delete(active, token)
			if e != nil {
				return nil, e
			}
			result = append(result, fields...)
		}
		if suffix != "" {
			fields, e := parse(suffix)
			if e != nil {
				return nil, e
			}
			result = append(result, fields...)
		}
		return result, nil
	}
	return parse(expression)
}
func fieldExpression(source string) (string, error) {
	source = strings.TrimLeft(source, " \t\r\n")
	depth := 0
	quoted, escaped := false, false
	for i, c := range source {
		if quoted {
			if escaped {
				escaped = false
			} else if c == '\\' {
				escaped = true
			} else if c == '"' {
				quoted = false
			}
			continue
		}
		if c == '"' {
			quoted = true
			continue
		}
		switch c {
		case '{', '(':
			depth++
		case '}', ')':
			depth--
			if depth == 0 {
				return source[:i+1], nil
			}
			if depth < 0 {
				return "", fmt.Errorf("invalid field list")
			}
		case ',', ' ', '\t', '\r', '\n':
			if depth == 0 {
				return source[:i], nil
			}
		}
	}
	if depth != 0 || quoted {
		return "", fmt.Errorf("unclosed field list")
	}
	return source, nil
}
