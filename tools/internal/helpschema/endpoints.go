package helpschema

import (
	"regexp"
	"strings"
)

// Endpoint is a declaration in the maintained Luau endpoint tables. Definition
// retains provider-specific options; generators interpret those explicitly.
type Endpoint struct {
	Name, Method, Path, Definition string
}

// Endpoints reads the literal name/method/path headers shared by the REST
// connectors. It does not evaluate Luau or infer request schemas from prose.
func Endpoints(source string) []Endpoint {
	matches := regexp.MustCompile(`(?m)^\s*(\w+) = \{method = "(\w+)", path = "([^"]+)"`).FindAllStringSubmatchIndex(source, -1)
	result := make([]Endpoint, 0, len(matches))
	for i, m := range matches {
		end := len(source)
		if i+1 < len(matches) {
			end = matches[i+1][0]
		}
		// Endpoint tables close at column zero; bodies and nested options are
		// indented. Keep the final definition within its declaring table.
		if close := strings.Index(source[m[0]:end], "\n}"); close >= 0 {
			end = m[0] + close
		}
		result = append(result, Endpoint{source[m[2]:m[3]], source[m[4]:m[5]], source[m[6]:m[7]], source[m[0]:end]})
	}
	return result
}
