package manifest

import (
	"encoding/json"
	"fmt"
	"math"
	"net"
	"net/url"
	"path"
	"regexp"
	"strings"
	"unicode"
	"unicode/utf8"
)

const MaxInteger = 9007199254740991

func ValidateValue(f Field, v any) error {
	if v == nil {
		if f.Required {
			return fmt.Errorf("required value missing")
		}
		return nil
	}
	switch f.Type {
	case "string", "secret":
		s, ok := v.(string)
		if !ok {
			return fmt.Errorf("expected string")
		}
		n := int64(utf8.RuneCountInString(s))
		if f.Required && s == "" {
			return fmt.Errorf("required value empty")
		}
		if f.MinLength != nil && n < *f.MinLength {
			return fmt.Errorf("value shorter than min_length")
		}
		if f.MaxLength != nil && n > *f.MaxLength {
			return fmt.Errorf("value longer than max_length")
		}
		if len(f.Options) > 0 {
			found := false
			for _, o := range f.Options {
				found = found || s == o.Value
			}
			if !found {
				return fmt.Errorf("value outside options")
			}
		}
	case "boolean":
		if _, ok := v.(bool); !ok {
			return fmt.Errorf("expected boolean")
		}
	case "integer", "number":
		n, ok := number(v)
		if !ok {
			return fmt.Errorf("expected finite number")
		}
		if f.Type == "integer" {
			if _, valid := integer(v); !valid {
				return fmt.Errorf("expected safe integer")
			}
		}
		if f.Minimum != nil && n < *f.Minimum {
			return fmt.Errorf("value below minimum")
		}
		if f.Maximum != nil && n > *f.Maximum {
			return fmt.Errorf("value above maximum")
		}
	default:
		return fmt.Errorf("invalid field type")
	}
	return nil
}
func validateField(f Field) error {
	if f.Label == "" {
		return fmt.Errorf("label required")
	}
	switch f.Type {
	case "string", "secret", "boolean", "integer", "number":
	default:
		return fmt.Errorf("unknown field type")
	}
	if f.Order < -MaxInteger || f.Order > MaxInteger {
		return fmt.Errorf("order outside safe integer range")
	}
	if f.Placeholder != "" && f.Type != "string" && f.Type != "secret" {
		return fmt.Errorf("placeholder requires string or secret")
	}
	if f.Display != "" && (f.Type != "string" || len(f.Options) > 0 || (f.Display != "plain" && f.Display != "masked")) {
		return fmt.Errorf("display requires string without options")
	}
	if f.Options != nil {
		if f.Type != "string" || len(f.Options) == 0 {
			return fmt.Errorf("options requires nonempty string options")
		}
		seen := map[string]bool{}
		for _, o := range f.Options {
			if o.Value == "" || o.Label == "" || seen[o.Value] {
				return fmt.Errorf("invalid or duplicate option")
			}
			seen[o.Value] = true
		}
	}
	if f.Minimum != nil || f.Maximum != nil {
		if f.Type != "integer" && f.Type != "number" {
			return fmt.Errorf("bounds require numeric type")
		}
		for _, p := range []*float64{f.Minimum, f.Maximum} {
			if p != nil && (math.IsNaN(*p) || math.IsInf(*p, 0) || (f.Type == "integer" && (math.Trunc(*p) != *p || math.Abs(*p) > MaxInteger))) {
				return fmt.Errorf("invalid numeric bound")
			}
		}
		if f.Minimum != nil && f.Maximum != nil && *f.Minimum > *f.Maximum {
			return fmt.Errorf("minimum exceeds maximum")
		}
	}
	if f.MinLength != nil || f.MaxLength != nil {
		if f.Type != "string" && f.Type != "secret" {
			return fmt.Errorf("length requires string or secret")
		}
		for _, p := range []*int64{f.MinLength, f.MaxLength} {
			if p != nil && (*p < 0 || *p > MaxInteger) {
				return fmt.Errorf("invalid length")
			}
		}
		if f.MinLength != nil && f.MaxLength != nil && *f.MinLength > *f.MaxLength {
			return fmt.Errorf("min_length exceeds max_length")
		}
	}
	if f.Default != nil {
		if f.Type == "secret" {
			return fmt.Errorf("secret defaults forbidden")
		}
		if e := ValidateValue(f, f.Default); e != nil {
			return fmt.Errorf("invalid default: %w", e)
		}
	}
	return nil
}
func BundlePath(s string) bool {
	return s != "" && !strings.ContainsAny(s, "\\:\x00") && !strings.HasPrefix(s, "/") && path.Clean(s) == s && s != "." && s != ".." && !strings.HasPrefix(s, "../") && (strings.HasSuffix(s, ".lua") || strings.HasSuffix(s, ".luau"))
}

var interfaceRE = regexp.MustCompile(`^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)*@[1-9][0-9]*$`)

func (m *Manifest) Validate() error {
	if m.SchemaVersion != 1 {
		return fmt.Errorf("schema_version must be 1")
	}
	if m.Name == "" || m.Description == "" {
		return fmt.Errorf("name and description are required")
	}
	if m.Icon != "" && m.Icon != "icon.svg" && m.Icon != "icon.png" {
		return fmt.Errorf("invalid icon")
	}
	if len(m.Files) == 0 || len(m.Proxy) == 0 {
		return fmt.Errorf("files and proxy must be nonempty arrays")
	}
	seen := map[string]bool{}
	for _, f := range m.Files {
		if !BundlePath(f) || seen[f] {
			return fmt.Errorf("invalid or duplicate entrypoint %q", f)
		}
		seen[f] = true
	}
	seen = map[string]bool{}
	for _, s := range m.Implements {
		if !interfaceRE.MatchString(s) || seen[s] {
			return fmt.Errorf("invalid or duplicate interface %q", s)
		}
		seen[s] = true
	}
	used := map[string]bool{}
	for source, fields := range map[string]map[string]Field{"publisher": m.Publisher, "config": m.Config} {
		for n, f := range fields {
			if !nameRE.MatchString(n) {
				return fmt.Errorf("invalid field name %s", n)
			}
			if e := validateField(f); e != nil {
				return fmt.Errorf("%s.%s: %w", source, n, e)
			}
			if e := m.validatePredicate(f.If, source, used); e != nil {
				return fmt.Errorf("%s.%s.if: %w", source, n, e)
			}
		}
	}
	for k, a := range m.Auth {
		if !nameRE.MatchString(k) || a.Label == "" || a.Order < -MaxInteger || a.Order > MaxInteger {
			return fmt.Errorf("invalid auth method %q", k)
		}
		if e := m.validatePredicate(a.If, "auth", used); e != nil {
			return fmt.Errorf("auth.%s.if: %w", k, e)
		}
		switch a.Type {
		case "manual":
			if len(a.Config) == 0 {
				return fmt.Errorf("manual auth %s needs config", k)
			}
			for n, f := range a.Config {
				if !nameRE.MatchString(n) {
					return fmt.Errorf("invalid auth field name")
				}
				if e := validateField(f); e != nil {
					return fmt.Errorf("auth.%s.%s: %w", k, n, e)
				}
				if e := m.validatePredicate(f.If, "manual", used); e != nil {
					return e
				}
			}
		case "oauth2":
			if e := m.validateOAuth(k, a, used); e != nil {
				return fmt.Errorf("auth.%s: %w", k, e)
			}
		default:
			return fmt.Errorf("unknown auth type")
		}
	}
	for _, source := range []string{"publisher", "config"} {
		if _, e := m.fieldOrder(source); e != nil {
			return e
		}
	}
	for i, p := range m.Proxy {
		if e := m.validatePredicate(p.If, "proxy", used); e != nil {
			return fmt.Errorf("proxy[%d].if: %w", i, e)
		}
		if e := m.validateProxy(p, used); e != nil {
			return fmt.Errorf("proxy[%d]: %w", i, e)
		}
	}

	for n := range m.Publisher {
		if !used["publisher."+n] {
			return fmt.Errorf("unused publisher field %s", n)
		}
	}
	for n, f := range m.Config {
		if f.Type == "secret" && !used["config."+n] {
			return fmt.Errorf("unused secret config field %s", n)
		}
	}
	for k, a := range m.Auth {
		for n := range a.Config {
			if !used["auth."+k+"."+n] {
				return fmt.Errorf("unused auth field %s.%s", k, n)
			}
		}
	}
	return nil
}

// sink modes encode the documented recipient and sensitivity boundaries.
func (m *Manifest) template(s, mode string, used map[string]bool) error {
	parts, e := parseTemplate(s)
	if e != nil {
		return e
	}
	refs, e := TemplateReferences(s)
	if e != nil {
		return e
	}
	if mode == "password" && len(refs) == 0 && s != "" {
		return fmt.Errorf("password requires a secret reference or explicit empty literal")
	}
	if mode == "client_id" || mode == "client_secret" {
		if len(parts) != 1 || len(refs) != 1 || len(parts[0].refs) != 1 || !strings.HasPrefix(refs[0], "publisher.") {
			return fmt.Errorf("OAuth client requires exact publisher reference")
		}
	}
	if mode == "port" && (len(parts) != 1 || len(parts[0].refs) == 0) {
		return fmt.Errorf("port must be an integer or whole-value reference")
	}
	for _, ref := range refs {
		f, e := m.reference(ref)
		if e != nil {
			return e
		}
		auth := strings.HasPrefix(ref, "auth.")
		managed := false
		if auth {
			p := strings.Split(ref, ".")
			managed = m.Auth[p[1]].Type == "oauth2"
		}
		switch mode {
		case "client_id":
			if f.Type != "string" {
				return fmt.Errorf("client_id requires publisher string")
			}
		case "client_secret":
			if f.Type != "secret" {
				return fmt.Errorf("client_secret requires publisher secret")
			}
		case "public":
			if auth || f.Type == "secret" {
				return fmt.Errorf("browser parameters require public publisher/config values")
			}
		case "token":
			if auth {
				return fmt.Errorf("token parameters cannot reference auth")
			}
		case "destination", "port":
			if f.Type == "secret" || managed {
				return fmt.Errorf("destination must not use secrets or OAuth")
			}
			if mode == "port" && f.Type != "integer" {
				return fmt.Errorf("port reference must be integer")
			}
		case "user":
			if managed {
				return fmt.Errorf("database credentials cannot use OAuth")
			}
		case "password":
			if f.Type != "secret" || managed {
				return fmt.Errorf("password requires secret field")
			}
		}
		used[ref] = true
	}
	return nil
}

var paramRE = regexp.MustCompile(`^[A-Za-z][A-Za-z0-9_-]*$`)
var reservedParams = map[string]bool{"client_id": true, "client_secret": true, "state": true, "response_type": true, "redirect_uri": true, "code": true, "grant_type": true, "refresh_token": true, "code_verifier": true, "code_challenge": true, "code_challenge_method": true}

func HTTPSURL(s string, query bool) error {
	u, e := url.Parse(s)
	if e != nil || u.Scheme != "https" || u.Hostname() == "" || u.User != nil || u.Fragment != "" || (!query && (u.RawQuery != "" || u.ForceQuery)) || strings.ContainsAny(s, "{}\\") {
		return fmt.Errorf("invalid literal HTTPS URL")
	}
	return nil
}
func validPointer(s string) bool {
	if !strings.HasPrefix(s, "/") {
		return false
	}
	for i := 0; i < len(s); i++ {
		if s[i] == '~' {
			i++
			if i == len(s) || (s[i] != '0' && s[i] != '1') {
				return false
			}
		}
	}
	return true
}
func overlapPointer(a, b string) bool {
	return a == b || strings.HasPrefix(a, b+"/") || strings.HasPrefix(b, a+"/")
}
func validateChecks(checks []ResponseCheck) error {
	for _, c := range checks {
		if !validPointer(c.Path) {
			return fmt.Errorf("invalid check pointer")
		}
		switch c.Op {
		case "exists":
			if c.Value != nil {
				return fmt.Errorf("exists forbids value")
			}
		case "equals":
			if _, e := scalarString(c.Value); e != nil {
				return fmt.Errorf("equals requires scalar")
			}
		default:
			return fmt.Errorf("unknown response check")
		}
	}
	return nil
}
func validateResponse(r TokenResponse) error {
	r = ResponseDefaults(r)
	paths := []string{r.AccessToken, r.RefreshToken, r.ExpiresIn, r.Scopes}
	for _, p := range paths {
		if !validPointer(p) {
			return fmt.Errorf("invalid token pointer")
		}
	}
	for i := 0; i < len(paths); i++ {
		for j := i + 1; j < len(paths); j++ {
			if overlapPointer(paths[i], paths[j]) {
				return fmt.Errorf("token selectors overlap")
			}
		}
	}
	return validateChecks(r.Checks)
}
func (m *Manifest) validateOAuth(key string, a AuthMethod, used map[string]bool) error {
	if e := HTTPSURL(a.AuthorizeURL, false); e != nil {
		return e
	}
	if e := HTTPSURL(a.TokenURL, false); e != nil {
		return e
	}
	if e := m.template(a.ClientID, "client_id", used); e != nil {
		return e
	}
	if a.ClientAuth == "" {
		a.ClientAuth = "basic"
	}
	if a.PKCE == "" {
		a.PKCE = "S256"
	}
	if a.ScopeParameter == "" {
		a.ScopeParameter = "scope"
	}
	switch a.ClientAuth {
	case "basic", "body":
		if e := m.template(a.ClientSecret, "client_secret", used); e != nil {
			return e
		}
	case "none":
		if a.ClientSecret != "" || a.PKCE != "S256" {
			return fmt.Errorf("public clients require PKCE and no client_secret")
		}
	default:
		return fmt.Errorf("invalid client_auth")
	}
	if a.PKCE != "S256" && a.PKCE != "none" {
		return fmt.Errorf("invalid pkce")
	}
	if !paramRE.MatchString(a.ScopeParameter) || reservedParams[a.ScopeParameter] {
		return fmt.Errorf("invalid scope_parameter")
	}
	for _, g := range a.Scopes {
		if len(g.Values) == 0 {
			return fmt.Errorf("empty scope group")
		}
		seen := map[string]bool{}
		for _, s := range g.Values {
			if s == "" || seen[s] || strings.Contains(s, "{{") {
				return fmt.Errorf("invalid scope")
			}
			seen[s] = true
		}
		if e := m.validatePredicate(g.If, "scope", used); e != nil {
			return e
		}
	}
	for mode, params := range map[string]map[string]string{"public": a.AuthorizeParams, "token": a.TokenParams, "refresh": a.RefreshParams} {
		for k, v := range params {
			if !paramRE.MatchString(k) || reservedParams[k] || k == "scope" || k == a.ScopeParameter {
				return fmt.Errorf("reserved or invalid OAuth parameter %s", k)
			}
			sink := mode
			if sink == "refresh" {
				sink = "token"
			}
			if e := m.template(v, sink, used); e != nil {
				return e
			}
		}
	}
	if e := validateResponse(a.TokenResponse); e != nil {
		return e
	}
	if e := validateResponse(a.RefreshResponse); e != nil {
		return e
	}
	if a.Account != nil {
		c := a.Account
		if e := HTTPSURL(c.URL, true); e != nil {
			return e
		}
		if c.Method != "" && c.Method != "GET" && c.Method != "POST" {
			return fmt.Errorf("invalid account method")
		}
		if !validPointer(c.Label) {
			return fmt.Errorf("invalid account label pointer")
		}
		if e := validateChecks(c.Checks); e != nil {
			return e
		}
		if e := m.validateHeaders(c.Headers, used); e != nil {
			return e
		}
		for k, p := range c.Bindings {
			if _, ok := a.AuthorizeParams[k]; !ok || !validPointer(p) {
				return fmt.Errorf("invalid account binding")
			}
		}
		for _, r := range []TokenResponse{ResponseDefaults(a.TokenResponse), ResponseDefaults(a.RefreshResponse)} {
			for _, p := range append([]string{c.Label}, mapValues(c.Bindings)...) {
				if overlapPointer(p, r.AccessToken) || overlapPointer(p, r.RefreshToken) {
					return fmt.Errorf("account metadata targets credentials")
				}
			}
		}
	}
	return nil
}
func mapValues(m map[string]string) []string {
	v := []string{}
	for _, s := range m {
		v = append(v, s)
	}
	return v
}
func ValidHost(host string) bool {
	if host == "" || strings.ContainsAny(host, "/@?#\\\x00") || strings.IndexFunc(host, unicode.IsSpace) >= 0 {
		return false
	}
	if net.ParseIP(host) != nil {
		return true
	}
	if strings.Contains(host, ":") || len(host) > 253 {
		return false
	}
	for _, label := range strings.Split(strings.TrimSuffix(host, "."), ".") {
		if len(label) == 0 || len(label) > 63 || label[0] == '-' || label[len(label)-1] == '-' {
			return false
		}
		for _, c := range label {
			if !(c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' || c >= '0' && c <= '9' || c == '-') {
				return false
			}
		}
	}
	return true
}

// checkPresence preserves the distinction between omitted optional members and
// explicit invalid empty values that plain Go zero values cannot represent.
func checkPresence(data []byte) error {
	var root map[string]any
	d := json.NewDecoder(strings.NewReader(string(data)))
	d.UseNumber()
	if e := d.Decode(&root); e != nil {
		return e
	}
	var walk func(any, string) error
	walk = func(v any, p string) error {
		switch x := v.(type) {
		case map[string]any:
			// Dictionary keys (including a valid HTTP header named "if") are
			// declarations, not predicate properties. Their values still recurse.
			parts := strings.Split(p, ".")
			dictionary := p == "manifest.config" || p == "manifest.publisher" || p == "manifest.auth" ||
				p == "manifest.proxy[].match.header" || p == "manifest.proxy[].action.headers.set" ||
				len(parts) == 4 && parts[1] == "auth" && parts[3] == "config" ||
				len(parts) == 5 && parts[1] == "auth" && parts[3] == "account" && parts[4] == "headers"
			for k, v := range x {
				if k == "if" && !dictionary {
					if s, ok := v.(string); !ok || s == "" {
						return fmt.Errorf("%s.if: predicate required", p)
					}
				}
				if e := walk(v, p+"."+k); e != nil {
					return e
				}
			}
		case []any:
			for _, v := range x {
				if e := walk(v, p+"[]"); e != nil {
					return e
				}
			}
		}
		return nil
	}
	if e := walk(root, "manifest"); e != nil {
		return e
	}
	if v, ok := root["verification_key"]; ok && v == "" {
		return fmt.Errorf("verification_key must be nonempty")
	}
	if v, ok := root["icon"]; ok && v == "" {
		return fmt.Errorf("icon must be nonempty")
	}
	var fields func(any) error
	fields = func(v any) error {
		m, ok := v.(map[string]any)
		if !ok {
			return nil
		}
		for _, v := range m {
			f, ok := v.(map[string]any)
			if !ok {
				continue
			}
			t, _ := f["type"].(string)
			for _, k := range []string{"placeholder", "min_length", "max_length"} {
				if _, ok := f[k]; ok && t != "string" && t != "secret" {
					return fmt.Errorf("%s forbidden for %s", k, t)
				}
			}
			if _, ok := f["display"]; ok {
				if t != "string" || f["display"] == "" {
					return fmt.Errorf("invalid display")
				}
				if _, ok := f["options"]; ok {
					return fmt.Errorf("display forbidden with options")
				}
			}
		}
		return nil
	}
	if e := fields(root["config"]); e != nil {
		return e
	}
	if e := fields(root["publisher"]); e != nil {
		return e
	}
	if auth, ok := root["auth"].(map[string]any); ok {
		for _, v := range auth {
			a, ok := v.(map[string]any)
			if !ok {
				continue
			}
			typ, _ := a["type"].(string)
			if typ == "manual" {
				for k := range a {
					switch k {
					case "if", "type", "label", "description", "order", "config":
					default:
						return fmt.Errorf("manual method forbids %s", k)
					}
				}
				if e := fields(a["config"]); e != nil {
					return e
				}
			} else if typ == "oauth2" {
				if _, ok := a["config"]; ok {
					return fmt.Errorf("OAuth forbids config")
				}
				for _, k := range []string{"client_auth", "pkce", "scope_parameter", "scope_separator"} {
					if v, ok := a[k]; ok && v == "" {
						return fmt.Errorf("%s must be nonempty", k)
					}
				}
				for _, k := range []string{"token_response", "refresh_response"} {
					if r, ok := a[k].(map[string]any); ok {
						for _, p := range []string{"access_token", "refresh_token", "expires_in", "scopes"} {
							if v, ok := r[p]; ok && v == "" {
								return fmt.Errorf("empty token selector")
							}
						}
					}
				}
			}
		}
	}

	if proxies, ok := root["proxy"].([]any); ok {
		for _, v := range proxies {
			p, ok := v.(map[string]any)
			if !ok {
				continue
			}
			match, ok := p["match"].(map[string]any)
			if !ok {
				return fmt.Errorf("proxy match required")
			}
			action, ok := p["action"].(map[string]any)
			if !ok {
				return fmt.Errorf("proxy action required")
			}
			if match["protocol"] != "http" {
				for _, key := range []string{"host", "method", "path", "header"} {
					if _, exists := match[key]; exists {
						return fmt.Errorf("database forbids HTTP filters")
					}
				}
				for _, key := range []string{"headers", "rewrite", "basic_auth"} {
					if _, exists := action[key]; exists {
						return fmt.Errorf("database forbids HTTP actions")
					}
				}
			}
			if c, ok := action["connection"].(map[string]any); ok {
				if _, exists := c["password"]; !exists {
					return fmt.Errorf("database password required")
				}
				if v, exists := c["transport"]; exists && (match["protocol"] != "clickhouse" || v == "") {
					return fmt.Errorf("transport requires clickhouse")
				}
			}
		}
	}
	return nil
}
