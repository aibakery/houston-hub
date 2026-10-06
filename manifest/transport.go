package manifest

import (
	"fmt"
	"net"
	"net/http"
	"net/url"
	"regexp"
	"strconv"
	"strings"
)

var headerRE = regexp.MustCompile("^[!#$%&'*+.^_`|~0-9A-Za-z-]+$")
var ownedHeaders = map[string]bool{"host": true, "content-length": true, "transfer-encoding": true, "connection": true, "keep-alive": true, "te": true, "trailer": true, "upgrade": true, "proxy-authorization": true, "proxy-authenticate": true}
var methods = map[string]bool{"GET": true, "HEAD": true, "POST": true, "PUT": true, "PATCH": true, "DELETE": true, "OPTIONS": true}

func ValidHeaderValue(s string) bool {
	for _, r := range s {
		if r == 127 || (r < 32 && r != '\t') {
			return false
		}
	}
	return true
}
func (m *Manifest) validateHeaders(headers map[string]HeaderValue, used map[string]bool) error {
	seen := map[string]bool{}
	for k, h := range headers {
		n := strings.ToLower(k)
		if !headerRE.MatchString(k) || ownedHeaders[n] || strings.HasPrefix(n, "x-houston-") || seen[n] {
			return fmt.Errorf("invalid, reserved or duplicate header %s", k)
		}
		seen[n] = true
		if !ValidHeaderValue(h.Value) {
			return fmt.Errorf("invalid header control character")
		}
		if e := m.validatePredicate(h.If, "header", used); e != nil {
			return e
		}
		if e := m.template(h.Value, "header", used); e != nil {
			return e
		}
	}
	return nil
}
func (m *Manifest) validateRecipe(h map[string]HeaderValue, b *BasicAuth, used map[string]bool) error {
	if e := m.validateHeaders(h, used); e != nil {
		return e
	}
	if b.Enabled() {
		for k := range h {
			if strings.EqualFold(k, "Authorization") {
				return fmt.Errorf("Basic conflicts with Authorization")
			}
		}
		if e := m.template(b.Username, "header", used); e != nil {
			return e
		}
		if !strings.Contains(b.Username, "{{") && strings.Contains(b.Username, ":") {
			return fmt.Errorf("Basic username contains colon")
		}
		if e := m.template(b.Password, "password", used); e != nil {
			return e
		}
	}
	return nil
}
func NormalizeOrigin(s string) (string, error) {
	if e := HTTPSURL(s, false); e != nil {
		return "", e
	}
	u, e := url.Parse(s)
	if e != nil || u.Path != "" || u.RawPath != "" {
		return "", fmt.Errorf("origin must not have a path")
	}
	host := strings.ToLower(u.Hostname())
	port := u.Port()
	if port != "" {
		n, e := strconv.Atoi(port)
		if e != nil || n < 1 || n > 65535 {
			return "", fmt.Errorf("invalid origin port")
		}
	}
	if strings.Contains(host, ":") {
		host = "[" + host + "]"
	}
	if port != "" && port != "443" {
		host = net.JoinHostPort(u.Hostname(), port)
		host = strings.ToLower(host)
	}
	return "https://" + host, nil
}
func ValidatePathPattern(s string) error {
	if !strings.HasPrefix(s, "/") || strings.ContainsAny(s, "?#\\%\x00") || strings.Contains(s, "//") {
		return fmt.Errorf("invalid path pattern")
	}
	for i, part := range strings.Split(s, "/")[1:] {
		if part == "." || part == ".." {
			return fmt.Errorf("dot segment forbidden")
		}
		if part == "*" && i == len(strings.Split(s, "/"))-2 {
			continue
		}
		if strings.HasPrefix(part, "{") && strings.HasSuffix(part, "}") && regexp.MustCompile(`^[A-Za-z_][A-Za-z0-9_]*$`).MatchString(part[1:len(part)-1]) {
			continue
		}
		if strings.ContainsAny(part, "*{}") {
			return fmt.Errorf("invalid path placeholder/wildcard")
		}
	}
	return nil
}
func placeholder(s string) bool { return strings.HasPrefix(s, "{") && strings.HasSuffix(s, "}") }
func PatternsOverlap(a, b string) bool {
	aa, bb := strings.Split(a, "/"), strings.Split(b, "/")
	for i := 0; i < len(aa) && i < len(bb); i++ {
		if aa[i] == "*" || bb[i] == "*" {
			return true
		}
		if aa[i] != bb[i] && !placeholder(aa[i]) && !placeholder(bb[i]) {
			return false
		}
		if aa[i] == "" && placeholder(bb[i]) || bb[i] == "" && placeholder(aa[i]) {
			return false
		}
	}
	return len(aa) == len(bb)
}
func PathMatches(pattern, p string) bool {
	a, b := strings.Split(pattern, "/"), strings.Split(p, "/")
	for i := 0; i < len(a) && i < len(b); i++ {
		if a[i] == "*" {
			return true
		}
		if a[i] != b[i] && (!placeholder(a[i]) || b[i] == "") {
			return false
		}
	}
	return len(a) == len(b)
}

// RequestPath rejects encoded separators and dot segments before route matching.
func RequestPath(u *url.URL) (string, error) {
	raw := u.EscapedPath()
	if raw == "" {
		raw = "/"
	}
	lower := strings.ToLower(raw)
	if strings.Contains(lower, "%2f") || strings.Contains(lower, "%5c") || strings.Contains(lower, "%25") {
		return "", fmt.Errorf("encoded path separator forbidden")
	}
	p, e := url.PathUnescape(raw)
	if e != nil || !strings.HasPrefix(p, "/") || strings.ContainsAny(p, "\\\x00") || strings.Contains(p, "//") {
		return "", fmt.Errorf("invalid request path")
	}
	for _, s := range strings.Split(p, "/") {
		if s == "." || s == ".." {
			return "", fmt.Errorf("dot segments forbidden")
		}
	}
	return p, nil
}
func (m *Manifest) validateProxy(p Proxy, used map[string]bool) error {
	switch p.Protocol {
	case "http":
		if len(p.Origins) == 0 || p.Connection != nil {
			return fmt.Errorf("HTTP requires origins and forbids connection")
		}
		seen := map[string]bool{}
		for key, o := range p.Origins {
			origin, e := NormalizeOrigin(key)
			if e != nil {
				return e
			}
			if seen[origin] {
				return fmt.Errorf("duplicate normalized origin")
			}
			seen[origin] = true
			if e := m.validateRecipe(o.Headers, o.BasicAuth, used); e != nil {
				return e
			}
			if o.Allowlist != nil && len(o.Allowlist) == 0 {
				return fmt.Errorf("allowlist must be nonempty")
			}
			for i, r := range o.Allowlist {
				if len(r.Methods) == 0 || len(r.Paths) == 0 {
					return fmt.Errorf("allowlist requires methods and paths")
				}
				seen := map[string]bool{}
				for _, method := range r.Methods {
					if !methods[method] || seen[method] {
						return fmt.Errorf("invalid or duplicate HTTP method")
					}
					seen[method] = true
				}
				for j, pattern := range r.Paths {
					if e := ValidatePathPattern(pattern); e != nil {
						return e
					}
					for _, other := range r.Paths[:j] {
						if PatternsOverlap(pattern, other) {
							return fmt.Errorf("overlapping route patterns")
						}
					}
				}
				h, b := r.Headers, r.BasicAuth
				if h == nil {
					h = o.Headers
				}
				if b == nil {
					b = o.BasicAuth
				}
				if e := m.validateRecipe(h, b, used); e != nil {
					return e
				}
				for _, prev := range o.Allowlist[:i] {
					common := false
					for _, a := range prev.Methods {
						for _, b := range r.Methods {
							common = common || a == b
						}
					}
					if common {
						for _, a := range prev.Paths {
							for _, b := range r.Paths {
								if PatternsOverlap(a, b) {
									return fmt.Errorf("overlapping allowlist entries")
								}
							}
						}
					}
				}
			}
		}
	case "postgres", "mysql", "clickhouse":
		c := p.Connection
		if c == nil || p.Origins != nil {
			return fmt.Errorf("database requires connection and forbids origins")
		}
		if c.TLS != nil && c.TLS.Mode != "verify-full" {
			return fmt.Errorf("TLS must verify-full")
		}
		if c.Transport != "" && p.Protocol != "clickhouse" {
			return fmt.Errorf("transport only valid for ClickHouse")
		}
		for _, s := range []string{c.Host, c.Database, c.User} {
			if s == "" {
				return fmt.Errorf("database host/database/user required")
			}
		}
		for mode, ss := range map[string][]string{"destination": {c.Host, c.Database, c.Transport}, "user": {c.User}, "password": {c.Password}} {
			for _, s := range ss {
				if e := m.template(s, mode, used); e != nil {
					return e
				}
			}
		}
		if !strings.Contains(c.Host, "{{") && !ValidHost(c.Host) {
			return fmt.Errorf("invalid database host")
		}
		if c.Transport != "" && !strings.Contains(c.Transport, "{{") && c.Transport != "https" && c.Transport != "native" {
			return fmt.Errorf("invalid ClickHouse transport")
		}
		if c.Port != nil {
			if s, ok := c.Port.(string); ok {
				if e := m.template(s, "port", used); e != nil {
					return e
				}
			} else {
				n, ok := integer(c.Port)
				if !ok || n < 1 || n > 65535 {
					return fmt.Errorf("invalid database port")
				}
			}
		}
		publisherSecret := false
		for _, s := range []string{c.User, c.Password} {
			refs, _ := TemplateReferences(s)
			for _, r := range refs {
				f, _ := m.reference(r)
				publisherSecret = publisherSecret || strings.HasPrefix(r, "publisher.") && f.Type == "secret"
			}
		}
		if publisherSecret {
			dest := []string{c.Host}
			if s, ok := c.Port.(string); ok {
				dest = append(dest, s)
			}
			for _, s := range dest {
				refs, _ := TemplateReferences(s)
				for _, r := range refs {
					if !strings.HasPrefix(r, "publisher.") {
						return fmt.Errorf("publisher secrets require publisher-controlled database recipient")
					}
				}
			}
		}
	default:
		return fmt.Errorf("unknown proxy protocol")
	}
	return nil
}

// HTTPRecipe contains server-private templates selected by a validated request.
// ControlledHeaders is the origin-wide union that must be stripped from callers.
type HTTPRecipe struct {
	Headers           map[string]HeaderValue
	BasicAuth         *BasicAuth
	ControlledHeaders []string
}

func (p Proxy) HTTPRecipe(method, rawURL string) (HTTPRecipe, error) {
	var out HTTPRecipe
	if p.Protocol != "http" || !methods[method] {
		return out, fmt.Errorf("HTTP operation unavailable")
	}
	u, e := url.Parse(rawURL)
	if e != nil || u.User != nil || u.Fragment != "" {
		return out, fmt.Errorf("invalid request URL")
	}
	origin, e := NormalizeOrigin(u.Scheme + "://" + u.Host)
	if e != nil {
		return out, e
	}
	var o HTTPOrigin
	found := false
	for k, v := range p.Origins {
		n, _ := NormalizeOrigin(k)
		if n == origin {
			o = v
			found = true
			break
		}
	}
	if !found {
		return out, fmt.Errorf("origin denied")
	}
	path, e := RequestPath(u)
	if e != nil {
		return out, e
	}
	out.Headers = o.Headers
	out.BasicAuth = o.BasicAuth
	reserved := map[string]bool{}
	add := func(h map[string]HeaderValue, b *BasicAuth) {
		for k := range h {
			reserved[http.CanonicalHeaderKey(k)] = true
		}
		if b.Enabled() {
			reserved["Authorization"] = true
		}
	}
	add(o.Headers, o.BasicAuth)
	matched := o.Allowlist == nil
	for _, r := range o.Allowlist {
		add(r.Headers, r.BasicAuth)
		methodOK := false
		for _, m := range r.Methods {
			methodOK = methodOK || m == method
		}
		if !methodOK {
			continue
		}
		for _, p := range r.Paths {
			if PathMatches(p, path) {
				if matched {
					return out, fmt.Errorf("ambiguous route")
				}
				matched = true
				if r.Headers != nil {
					out.Headers = r.Headers
				}
				if r.BasicAuth != nil {
					out.BasicAuth = r.BasicAuth
				}
			}
		}
	}
	if !matched {
		return out, fmt.Errorf("route denied")
	}
	for k := range reserved {
		out.ControlledHeaders = append(out.ControlledHeaders, k)
	}
	return out, nil
}
func (r HTTPRecipe) Prepare(c Context, caller http.Header) (http.Header, error) {
	h := caller.Clone()
	if h == nil {
		h = http.Header{}
	}
	for name := range h {
		if ownedHeaders[strings.ToLower(name)] || strings.HasPrefix(strings.ToLower(name), "x-houston-") {
			h.Del(name)
		}
	}
	for _, k := range r.ControlledHeaders {
		h.Del(k)
	}
	for k, v := range r.Headers {
		yes, e := EvaluatePredicate(v.If, c)
		if e != nil {
			return nil, e
		}
		if !yes {
			continue
		}
		value, e := RenderString(v.Value, c)
		if e != nil {
			return nil, e
		}
		if !ValidHeaderValue(value) {
			return nil, fmt.Errorf("invalid resolved header")
		}
		h.Set(k, value)
	}
	if r.BasicAuth.Enabled() {
		username, e := RenderString(r.BasicAuth.Username, c)
		if e != nil {
			return nil, e
		}
		password, e := RenderString(r.BasicAuth.Password, c)
		if e != nil {
			return nil, e
		}
		if strings.Contains(username, ":") {
			return nil, fmt.Errorf("invalid Basic username")
		}
		req := http.Request{Header: h}
		req.SetBasicAuth(username, password)
	}
	return h, nil
}

type ResolvedDatabase struct {
	Protocol, Host, Database, User, Password, Transport string
	Port                                                int
	TLSMode                                             string
}

func (p Proxy) ResolveDatabase(c Context) (ResolvedDatabase, error) {
	out := ResolvedDatabase{Protocol: p.Protocol, TLSMode: "verify-full"}
	v := p.Connection
	if v == nil || p.Protocol == "http" {
		return out, fmt.Errorf("database unavailable")
	}
	var e error
	if out.Host, e = RenderString(v.Host, c); e != nil {
		return out, e
	}
	if !ValidHost(out.Host) {
		return out, fmt.Errorf("invalid database host")
	}
	if out.Database, e = RenderString(v.Database, c); e != nil {
		return out, e
	}
	if out.User, e = RenderString(v.User, c); e != nil {
		return out, e
	}
	if out.Database == "" || out.User == "" || strings.ContainsRune(out.Database, 0) || strings.ContainsRune(out.User, 0) {
		return out, fmt.Errorf("invalid database identity")
	}
	if out.Password, e = RenderString(v.Password, c); e != nil {
		return out, e
	}
	switch p.Protocol {
	case "postgres":
		out.Port = 5432
	case "mysql":
		out.Port = 3306
	case "clickhouse":
		out.Transport = v.Transport
		if out.Transport == "" {
			out.Transport = "https"
		}
		if out.Transport, e = RenderString(out.Transport, c); e != nil {
			return out, e
		}
		switch out.Transport {
		case "https":
			out.Port = 8443
		case "native":
			out.Port = 9440
		default:
			return out, fmt.Errorf("invalid ClickHouse transport")
		}
	default:
		return out, fmt.Errorf("unknown database protocol")
	}
	if v.Port != nil {
		port := v.Port
		if s, ok := port.(string); ok {
			port, e = Render(s, c)
			if e != nil {
				return out, e
			}
		}
		n, ok := integer(port)
		if !ok || n < 1 || n > 65535 {
			return out, fmt.Errorf("invalid resolved port")
		}
		out.Port = int(n)
	}
	return out, nil
}
