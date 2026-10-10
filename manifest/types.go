// Package manifest is the authoritative connector manifest v1 contract. Its
// contexts contain private values and must never be exposed to connector code.
package manifest

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"unicode/utf8"
)

type Manifest struct {
	SchemaVersion   int                   `json:"schema_version"`
	Name            string                `json:"name"`
	Description     string                `json:"description,omitempty"`
	Setup           string                `json:"setup,omitempty"`
	Icon            string                `json:"icon,omitempty"`
	VerificationKey string                `json:"verification_key,omitempty"`
	Files           []string              `json:"files"`
	Config          map[string]Field      `json:"config,omitempty"`
	Publisher       map[string]Field      `json:"publisher,omitempty"`
	Auth            map[string]AuthMethod `json:"auth,omitempty"`
	Proxy           ProxyRules            `json:"proxy"`
}
type Field struct {
	If          string   `json:"if,omitempty"`
	Type        string   `json:"type"`
	Label       string   `json:"label"`
	Description string   `json:"description,omitempty"`
	Placeholder string   `json:"placeholder,omitempty"`
	Required    bool     `json:"required,omitempty"`
	Default     any      `json:"default,omitempty"`
	Options     []Option `json:"options,omitempty"`
	Minimum     *float64 `json:"minimum,omitempty"`
	Maximum     *float64 `json:"maximum,omitempty"`
	MinLength   *int64   `json:"min_length,omitempty"`
	MaxLength   *int64   `json:"max_length,omitempty"`
	Order       int64    `json:"order,omitempty"`
	Display     string   `json:"display,omitempty"`
}
type Option struct {
	Value string `json:"value"`
	Label string `json:"label"`
}
type AuthMethod struct {
	If              string            `json:"if,omitempty"`
	Type            string            `json:"type"`
	Label           string            `json:"label"`
	Description     string            `json:"description,omitempty"`
	Order           int64             `json:"order,omitempty"`
	Config          map[string]Field  `json:"config,omitempty"`
	AuthorizeURL    string            `json:"authorize_url,omitempty"`
	TokenURL        string            `json:"token_url,omitempty"`
	ClientID        string            `json:"client_id,omitempty"`
	ClientSecret    string            `json:"client_secret,omitempty"`
	ClientAuth      string            `json:"client_auth,omitempty"`
	TokenEncoding   string            `json:"token_encoding,omitempty"`
	TokenHeaders    map[string]string `json:"token_headers,omitempty"`
	PKCE            string            `json:"pkce,omitempty"`
	Scopes          []ScopeGroup      `json:"scopes,omitempty"`
	ScopeParameter  string            `json:"scope_parameter,omitempty"`
	ScopeSeparator  string            `json:"scope_separator,omitempty"`
	AuthorizeParams map[string]string `json:"authorize_params,omitempty"`
	TokenParams     map[string]string `json:"token_params,omitempty"`
	RefreshParams   map[string]string `json:"refresh_params,omitempty"`
	TokenResponse   TokenResponse     `json:"token_response,omitempty"`
	RefreshResponse TokenResponse     `json:"refresh_response,omitempty"`
	RequireRefresh  bool              `json:"require_refresh,omitempty"`
	Account         *OAuthAccount     `json:"account,omitempty"`
}
type ScopeGroup struct {
	If     string   `json:"if,omitempty"`
	Values []string `json:"values"`
}
type TokenResponse struct {
	AccessToken  string          `json:"access_token,omitempty"`
	RefreshToken string          `json:"refresh_token,omitempty"`
	ExpiresIn    string          `json:"expires_in,omitempty"`
	Scopes       string          `json:"scopes,omitempty"`
	Checks       []ResponseCheck `json:"checks,omitempty"`
}
type ResponseCheck struct {
	Path  string `json:"path"`
	Op    string `json:"op"`
	Value any    `json:"value,omitempty"`
}
type OAuthAccount struct {
	URL      string                 `json:"url"`
	Method   string                 `json:"method,omitempty"`
	Headers  map[string]HeaderValue `json:"headers,omitempty"`
	Label    string                 `json:"label"`
	Checks   []ResponseCheck        `json:"checks,omitempty"`
	Bindings map[string]string      `json:"bindings,omitempty"`
}
type Proxy struct {
	If     string      `json:"if,omitempty"`
	Match  ProxyMatch  `json:"match"`
	Action ProxyAction `json:"action"`
}
type ProxyRules []Proxy
type ProxyMatch struct {
	Protocol             string         `json:"protocol"`
	Host                 []string       `json:"host,omitempty"`
	Method               []string       `json:"method,omitempty"`
	Path                 []string       `json:"path,omitempty"`
	OpaquePathParameters []string       `json:"opaque_path_parameters,omitempty"`
	Header               map[string]any `json:"header,omitempty"`
}
type ProxyAction struct {
	Rewrite    *Rewrite            `json:"rewrite,omitempty"`
	Headers    HeaderActions       `json:"headers,omitempty"`
	BasicAuth  *BasicAuth          `json:"basic_auth,omitempty"`
	Connection *DatabaseConnection `json:"connection,omitempty"`
}
type HeaderActions struct {
	Set    map[string]string `json:"set,omitempty"`
	Remove []string          `json:"remove,omitempty"`
}
type Rewrite struct {
	StripPrefix string `json:"strip_prefix"`
}
type HeaderValue struct {
	If    string `json:"if,omitempty"`
	Value string `json:"value"`
}
type BasicAuth struct {
	Username string `json:"username,omitempty"`
	Password string `json:"password,omitempty"`
	enabled  bool
}

func (b *BasicAuth) Enabled() bool {
	return b != nil && (b.enabled || b.Username != "" || b.Password != "")
}
func (b *BasicAuth) UnmarshalJSON(data []byte) error {
	type plain BasicAuth
	var p plain
	if err := decode(data, &p); err != nil {
		return err
	}
	var keys map[string]json.RawMessage
	_ = json.Unmarshal(data, &keys)
	if len(keys) != 0 {
		if _, ok := keys["username"]; !ok {
			return fmt.Errorf("basic_auth requires username and password")
		}
		if _, ok := keys["password"]; !ok {
			return fmt.Errorf("basic_auth requires username and password")
		}
		p.enabled = true
	}
	*b = BasicAuth(p)
	return nil
}
func (b BasicAuth) MarshalJSON() ([]byte, error) {
	if !(&b).Enabled() {
		return []byte("{}"), nil
	}
	return json.Marshal(map[string]string{"username": b.Username, "password": b.Password})
}

type DatabaseConnection struct {
	Host      string `json:"host"`
	Port      any    `json:"port,omitempty"`
	Database  string `json:"database"`
	User      string `json:"user"`
	Password  string `json:"password"`
	TLS       *TLS   `json:"tls,omitempty"`
	Transport string `json:"transport,omitempty"`
}
type TLS struct {
	Mode string `json:"mode"`
}

func decode(data []byte, v any) error {
	d := json.NewDecoder(bytes.NewReader(data))
	d.DisallowUnknownFields()
	d.UseNumber()
	if err := d.Decode(v); err != nil {
		return err
	}
	if err := d.Decode(new(any)); err != io.EOF {
		return fmt.Errorf("trailing JSON value")
	}
	return nil
}

// Parse rejects duplicate keys, nulls, unknown properties and invalid semantics.
func Parse(data []byte) (*Manifest, error) {
	return parseManifest(data, true)
}

// UnmarshalJSON keeps pinned snapshots and catalog readers on the same strict
// contract. Defaults are already captured by Parse at publication; decoding a
// snapshot must not silently add defaults from the running implementation.
func (m *Manifest) UnmarshalJSON(data []byte) error {
	parsed, err := parseManifest(data, false)
	if err != nil {
		return err
	}
	*m = *parsed
	return nil
}

func parseManifest(data []byte, defaults bool) (*Manifest, error) {
	if !utf8.Valid(data) {
		return nil, fmt.Errorf("manifest must be UTF-8")
	}
	d := json.NewDecoder(bytes.NewReader(data))
	d.UseNumber()
	if err := scanJSON(d, "manifest"); err != nil {
		return nil, err
	}
	if _, err := d.Token(); err != io.EOF {
		return nil, fmt.Errorf("trailing JSON value")
	}
	var raw map[string]json.RawMessage
	if err := json.Unmarshal(data, &raw); err != nil {
		return nil, err
	}
	if raw == nil {
		return nil, fmt.Errorf("manifest must be an object")
	}
	type plainManifest Manifest
	var decoded plainManifest
	if err := decode(data, &decoded); err != nil {
		return nil, err
	}
	m := Manifest(decoded)
	if err := checkPresence(data); err != nil {
		return nil, err
	}
	if defaults {
		m.defaults()
	}
	if err := m.Validate(); err != nil {
		return nil, err
	}
	return &m, nil
}
func scanJSON(d *json.Decoder, path string) error {
	t, err := d.Token()
	if err != nil {
		return err
	}
	if t == nil {
		return fmt.Errorf("%s: null is forbidden", path)
	}
	switch t {
	case json.Delim('{'):
		seen := map[string]bool{}
		for d.More() {
			k, err := d.Token()
			if err != nil {
				return err
			}
			s := k.(string)
			if seen[s] {
				return fmt.Errorf("%s.%s: duplicate key", path, s)
			}
			seen[s] = true
			if err := scanJSON(d, path+"."+s); err != nil {
				return err
			}
		}
		_, err = d.Token()
		return err
	case json.Delim('['):
		for i := 0; d.More(); i++ {
			if err := scanJSON(d, fmt.Sprintf("%s[%d]", path, i)); err != nil {
				return err
			}
		}
		_, err = d.Token()
		return err
	}
	return nil
}
func (m *Manifest) defaults() {
	if m.Config == nil {
		m.Config = map[string]Field{}
	}
	if m.Publisher == nil {
		m.Publisher = map[string]Field{}
	}
	if m.Auth == nil {
		m.Auth = map[string]AuthMethod{}
	}
	for k, a := range m.Auth {
		if a.Type == "oauth2" {
			if a.ClientAuth == "" {
				a.ClientAuth = "basic"
			}
			if a.TokenEncoding == "" {
				a.TokenEncoding = "form"
			}
			if a.PKCE == "" {
				a.PKCE = "S256"
			}
			if a.ScopeParameter == "" {
				a.ScopeParameter = "scope"
			}
			if a.ScopeSeparator == "" {
				a.ScopeSeparator = " "
			}
			a.TokenResponse = ResponseDefaults(a.TokenResponse)
			a.RefreshResponse = ResponseDefaults(a.RefreshResponse)
			if a.Account != nil && a.Account.Method == "" {
				a.Account.Method = "GET"
			}
			m.Auth[k] = a
		}
	}
	for i := range m.Proxy {
		c := m.Proxy[i].Action.Connection
		if c != nil {
			if c.TLS == nil {
				c.TLS = &TLS{Mode: "verify-full"}
			}
			if m.Proxy[i].Match.Protocol == "clickhouse" && c.Transport == "" {
				c.Transport = "https"
			}
		}
	}
}
func ResponseDefaults(r TokenResponse) TokenResponse {
	if r.AccessToken == "" {
		r.AccessToken = "/access_token"
	}
	if r.RefreshToken == "" {
		r.RefreshToken = "/refresh_token"
	}
	if r.ExpiresIn == "" {
		r.ExpiresIn = "/expires_in"
	}
	if r.Scopes == "" {
		r.Scopes = "/scope"
	}
	return r
}
