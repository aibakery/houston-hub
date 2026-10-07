package manifest

import (
	"fmt"
	"net"
	"net/http"
	"net/url"
	"regexp"
	"slices"
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
		if !mutableHeader(k) || seen[n] {
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
	if !ValidHost(host) {
		return "", fmt.Errorf("invalid origin hostname")
	}
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

// Origin patterns allow one leading wildcard label; request origins stay literal.
func normalizeOriginPattern(s string) (string, error) {
	if strings.Contains(s, "://") {
		return "", fmt.Errorf("host pattern must not contain a scheme")
	}
	s = "https://" + s
	const prefix = "https://*."
	if !strings.HasPrefix(s, prefix) {
		return NormalizeOrigin(s)
	}
	origin, err := NormalizeOrigin("https://" + strings.TrimPrefix(s, prefix))
	if err != nil {
		return "", err
	}
	u, _ := url.Parse(origin)
	if net.ParseIP(u.Hostname()) != nil {
		return "", fmt.Errorf("origin wildcard requires a DNS hostname")
	}
	return prefix + strings.TrimPrefix(origin, "https://"), nil
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
	switch p.Match.Protocol {
	case "http":
		if len(p.Match.Host) == 0 || p.Action.Connection != nil {
			return fmt.Errorf("HTTP requires match.host and forbids action.connection")
		}
		seen := map[string]bool{}
		for _, host := range p.Match.Host {
			normalized, err := normalizeOriginPattern(host)
			if err != nil {
				return err
			}
			if seen[normalized] {
				return fmt.Errorf("duplicate normalized host")
			}
			seen[normalized] = true
		}
		for field, values := range map[string][]string{"method": p.Match.Method, "path": p.Match.Path} {
			if values != nil && len(values) == 0 {
				return fmt.Errorf("match.%s must be nonempty", field)
			}
			seen := map[string]bool{}
			for _, value := range values {
				if seen[value] {
					return fmt.Errorf("duplicate match.%s", field)
				}
				seen[value] = true
				if field == "method" && !methods[value] {
					return fmt.Errorf("invalid HTTP method")
				}
				if field == "path" {
					if err := ValidatePathPattern(value); err != nil {
						return err
					}
				}
			}
		}
		if err := validateHeaderFilters(p.Match.Header); err != nil {
			return err
		}
		if err := m.validateRecipe(p.Action.httpRecipe("").Headers, p.Action.BasicAuth, used); err != nil {
			return err
		}
		seen = map[string]bool{}
		for _, name := range p.Action.Headers.Remove {
			key := strings.ToLower(name)
			if !mutableHeader(name) || seen[key] {
				return fmt.Errorf("invalid, reserved or duplicate removed header %s", name)
			}
			seen[key] = true
		}
		if r := p.Action.Rewrite; r != nil {
			if err := validateStripPrefix(r.StripPrefix); err != nil {
				return err
			}
		}
	case "postgres", "mysql", "clickhouse":
		c := p.Action.Connection
		if c == nil || p.Match.Host != nil || p.Match.Method != nil || p.Match.Path != nil || p.Match.Header != nil || p.Action.Headers.Set != nil || p.Action.Headers.Remove != nil || p.Action.BasicAuth != nil || p.Action.Rewrite != nil {
			return fmt.Errorf("database requires action.connection and forbids HTTP filters/actions")
		}
		if c.TLS != nil && c.TLS.Mode != "verify-full" {
			return fmt.Errorf("TLS must verify-full")
		}
		if c.Transport != "" && p.Match.Protocol != "clickhouse" {
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

// HTTPRecipe is the single selected action, including its rewritten URL.
type HTTPRecipe struct {
	URL           string
	Headers       map[string]HeaderValue
	BasicAuth     *BasicAuth
	RemoveHeaders []string
}

// Proxy sets are unconditional templates; OAuth account headers reuse preparation
// with their separate conditional HeaderValue contract.
func (a ProxyAction) httpRecipe(rawURL string) HTTPRecipe {
	headers := make(map[string]HeaderValue, len(a.Headers.Set))
	for name, value := range a.Headers.Set {
		headers[name] = HeaderValue{Value: value}
	}
	return HTTPRecipe{URL: rawURL, Headers: headers, BasicAuth: a.BasicAuth, RemoveHeaders: a.Headers.Remove}
}

func (rules ProxyRules) Select(indices []int) ProxyRules {
	selected := make(ProxyRules, 0, len(indices))
	for _, i := range indices {
		selected = append(selected, rules[i])
	}
	return selected
}

// OriginDeniedError contains only the normalized origin, never a path or query.
type OriginDeniedError struct{ Origin string }

func (e *OriginDeniedError) Error() string { return "origin denied: " + e.Origin }

// HTTPRecipe matches active rules in manifest order against the original request.
// A selected action's failure never falls through to another rule.
func (rules ProxyRules) HTTPRecipe(method, rawURL string, caller http.Header) (HTTPRecipe, error) {
	var out HTTPRecipe
	if !methods[method] {
		return out, fmt.Errorf("HTTP operation unavailable")
	}
	u, err := url.Parse(rawURL)
	if err != nil || u.User != nil || u.Fragment != "" {
		return out, fmt.Errorf("invalid request URL")
	}
	origin, err := NormalizeOrigin(u.Scheme + "://" + u.Host)
	if err != nil {
		return out, err
	}
	path, err := RequestPath(u)
	if err != nil {
		return out, err
	}
	originFound := false
	for _, rule := range rules {
		if rule.Match.Protocol != "http" {
			continue
		}
		found := false
		for _, host := range rule.Match.Host {
			pattern, err := normalizeOriginPattern(host)
			if err == nil && originMatches(pattern, origin) {
				found = true
				break
			}
		}
		if !found {
			continue
		}
		originFound = true
		if !rule.Match.matchesRequest(method, path, caller) {
			continue
		}
		out = rule.Action.httpRecipe(rawURL)
		if rewrite := rule.Action.Rewrite; rewrite != nil {
			if err := validateStripPrefix(rewrite.StripPrefix); err != nil {
				return HTTPRecipe{}, err
			}
			prefix := rewrite.StripPrefix
			if path != prefix && !strings.HasPrefix(path, prefix+"/") {
				return HTTPRecipe{}, fmt.Errorf("rewrite prefix does not match request path")
			}
			// Encoded separators are already forbidden. Slice whole escaped segments
			// so stripping a prefix never changes the remaining path's escaping.
			escaped := strings.Split(u.EscapedPath(), "/")
			u.RawPath = "/" + strings.Join(escaped[strings.Count(prefix, "/")+1:], "/")
			u.Path = strings.TrimPrefix(path, prefix)
			if u.Path == "" {
				u.Path = "/"
			}
			if _, err := RequestPath(u); err != nil {
				return HTTPRecipe{}, err
			}
			out.URL = u.String()
		}
		return out, nil
	}
	if !originFound {
		return out, &OriginDeniedError{Origin: origin}
	}
	return out, fmt.Errorf("request denied by proxy rules")
}
func originMatches(pattern, origin string) bool {
	if pattern == origin {
		return true
	}
	suffix, wildcard := strings.CutPrefix(pattern, "https://*")
	return wildcard && strings.HasSuffix(strings.TrimPrefix(origin, "https://"), suffix)
}
func (m ProxyMatch) matchesRequest(method, path string, caller http.Header) bool {
	if m.Method != nil && !slices.Contains(m.Method, method) {
		return false
	}
	if m.Path != nil {
		found := false
		for _, pattern := range m.Path {
			if PathMatches(pattern, path) {
				found = true
				break
			}
		}
		if !found {
			return false
		}
	}
	for name, filter := range m.Header {
		found := false
		for key, values := range caller {
			if !strings.EqualFold(key, name) {
				continue
			}
			for _, value := range values {
				if filter == true || filter == value {
					found = true
					break
				}
			}
		}
		if !found {
			return false
		}
	}
	return true
}
func validateHeaderFilters(filters map[string]any) error {
	seen := map[string]bool{}
	for name, value := range filters {
		key := strings.ToLower(name)
		if !headerRE.MatchString(name) || seen[key] {
			return fmt.Errorf("invalid or duplicate header filter %s", name)
		}
		seen[key] = true
		switch v := value.(type) {
		case string:
			if !ValidHeaderValue(v) {
				return fmt.Errorf("invalid header filter value")
			}
		case bool:
			if !v {
				return fmt.Errorf("header presence filter must be true")
			}
		default:
			return fmt.Errorf("header filter must be a string or true")
		}
	}
	return nil
}
func validateStripPrefix(prefix string) error {
	if err := ValidatePathPattern(prefix); err != nil {
		return fmt.Errorf("invalid rewrite prefix")
	}
	if prefix == "/" || strings.HasSuffix(prefix, "/") || strings.ContainsAny(prefix, "*{}") {
		return fmt.Errorf("invalid rewrite prefix")
	}
	return nil
}
func mutableHeader(name string) bool {
	lower := strings.ToLower(name)
	return headerRE.MatchString(name) && !ownedHeaders[lower] && !strings.HasPrefix(lower, "x-houston-")
}
func removeHeader(headers http.Header, name string) {
	for key := range headers {
		if strings.EqualFold(key, name) {
			delete(headers, key)
		}
	}
}

func (r HTTPRecipe) Prepare(c Context, caller http.Header) (http.Header, error) {
	h := caller.Clone()
	if h == nil {
		h = http.Header{}
	}
	for name := range h {
		if ownedHeaders[strings.ToLower(name)] || strings.HasPrefix(strings.ToLower(name), "x-houston-") {
			delete(h, name)
		}
	}
	for _, k := range r.RemoveHeaders {
		removeHeader(h, k)
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
		removeHeader(h, k)
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
		removeHeader(h, "Authorization")
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
	out := ResolvedDatabase{Protocol: p.Match.Protocol, TLSMode: "verify-full"}
	v := p.Action.Connection
	if v == nil || p.Match.Protocol == "http" {
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
	switch p.Match.Protocol {
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
