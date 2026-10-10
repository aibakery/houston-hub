package manifest

import (
	"encoding/json"
	"reflect"
	"strings"
)

// Schema derives property names and JSON shapes from the same Go definitions as
// Parse. Cross-field graph, reference/sink, and lifecycle checks remain normative
// parser/runtime checks; JSON Schema alone cannot establish those boundaries.
func Schema() ([]byte, error) {
	defs := map[string]any{}
	var schemaType func(reflect.Type) map[string]any
	schemaType = func(t reflect.Type) map[string]any {
		if t.Kind() == reflect.Pointer {
			return schemaType(t.Elem())
		}
		switch t.Kind() {
		case reflect.Interface:
			return map[string]any{"type": []string{"string", "boolean", "number"}}
		case reflect.String:
			return map[string]any{"type": "string"}
		case reflect.Bool:
			return map[string]any{"type": "boolean"}
		case reflect.Int, reflect.Int64:
			return map[string]any{"type": "integer", "minimum": -MaxInteger, "maximum": MaxInteger}
		case reflect.Float64:
			return map[string]any{"type": "number"}
		case reflect.Slice:
			return map[string]any{"type": "array", "items": schemaType(t.Elem())}
		case reflect.Map:

			return map[string]any{"type": "object", "additionalProperties": schemaType(t.Elem())}
		case reflect.Struct:
			name := t.Name()
			if _, ok := defs[name]; !ok {
				defs[name] = nil
				props := map[string]any{}
				required := []string{}
				for i := 0; i < t.NumField(); i++ {
					f := t.Field(i)
					tag := strings.Split(f.Tag.Get("json"), ",")
					if tag[0] == "" || tag[0] == "-" {
						continue
					}
					props[tag[0]] = schemaType(f.Type)
					if len(tag) == 1 {
						required = append(required, tag[0])
					}
				}
				defs[name] = map[string]any{"type": "object", "additionalProperties": false, "properties": props, "required": required}
			}
			return map[string]any{"$ref": "#/$defs/" + name}
		}
		panic("unsupported manifest schema type")
	}
	schemaType(reflect.TypeOf(Manifest{}))
	def := func(n string) map[string]any { return defs[n].(map[string]any) }
	props := func(n string) map[string]any { return def(n)["properties"].(map[string]any) }
	enum := func(n, k string, values ...string) { p := props(n)[k].(map[string]any); p["enum"] = values }
	enum("Field", "type", "string", "boolean", "integer", "number", "secret")
	enum("Field", "display", "plain", "masked")
	enum("AuthMethod", "type", "manual", "oauth2")
	enum("AuthMethod", "client_auth", "basic", "body", "none")
	enum("AuthMethod", "token_encoding", "form", "json")
	enum("AuthMethod", "pkce", "S256", "none")
	enum("OAuthAccount", "method", "GET", "POST")
	enum("ResponseCheck", "op", "exists", "equals")
	enum("ProxyMatch", "protocol", "http", "postgres", "mysql", "clickhouse", "redis")
	enum("TLS", "mode", "verify-full")
	enum("Manifest", "icon", "icon.svg", "icon.png")
	props("ProxyMatch")["opaque_path_parameters"].(map[string]any)["minItems"] = 1
	props("ProxyMatch")["opaque_path_parameters"].(map[string]any)["uniqueItems"] = true
	props("ProxyMatch")["opaque_path_parameters"].(map[string]any)["items"] = map[string]any{"type": "string", "pattern": `^(\*|[A-Za-z_][A-Za-z0-9_]*)$`}
	props("Manifest")["schema_version"] = map[string]any{"const": 1}
	for _, nk := range [][2]string{{"Manifest", "files"}, {"Manifest", "proxy"}, {"Field", "options"}, {"ScopeGroup", "values"}, {"ProxyMatch", "host"}, {"ProxyMatch", "method"}, {"ProxyMatch", "path"}} {
		props(nk[0])[nk[1]].(map[string]any)["minItems"] = 1
	}
	for _, nk := range [][2]string{{"Manifest", "files"}, {"ScopeGroup", "values"}, {"ProxyMatch", "host"}, {"ProxyMatch", "method"}, {"ProxyMatch", "path"}, {"HeaderActions", "remove"}} {
		props(nk[0])[nk[1]].(map[string]any)["uniqueItems"] = true
	}
	for _, nk := range [][2]string{{"Manifest", "name"}, {"Manifest", "verification_key"}, {"Field", "label"}, {"Option", "value"}, {"Option", "label"}, {"AuthMethod", "label"}, {"AuthMethod", "scope_separator"}, {"AuthMethod", "scope_parameter"}} {
		props(nk[0])[nk[1]].(map[string]any)["minLength"] = 1
	}
	for _, nk := range [][2]string{{"Manifest", "config"}, {"Manifest", "publisher"}, {"Manifest", "auth"}, {"AuthMethod", "config"}} {
		props(nk[0])[nk[1]].(map[string]any)["propertyNames"] = map[string]any{"pattern": nameRE.String()}
	}
	for _, n := range []string{"Field", "AuthMethod", "ScopeGroup", "Proxy", "HeaderValue"} {
		props(n)["if"].(map[string]any)["pattern"] = `^\s*\{\{.+\}\}\s*$`
	}
	props("Field")["min_length"].(map[string]any)["minimum"] = 0
	props("Field")["max_length"].(map[string]any)["minimum"] = 0

	props("ProxyMatch")["method"].(map[string]any)["items"] = map[string]any{"type": "string", "enum": []string{"GET", "HEAD", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"}}
	props("ProxyMatch")["header"].(map[string]any)["additionalProperties"] = map[string]any{"oneOf": []any{map[string]any{"type": "string"}, map[string]any{"const": true}}}
	props("ProxyMatch")["host"].(map[string]any)["description"] = "Hostnames with optional ports; HTTPS only. Leading *. matches subdomains, not the base host."

	props("AuthMethod")["config"].(map[string]any)["minProperties"] = 1
	// Conditional requirements mirror discriminated unions without adding aliases.
	condition := func(key string, value any) map[string]any {
		return map[string]any{"properties": map[string]any{key: map[string]any{"const": value}}, "required": []string{key}}
	}
	forbid := func(keys ...string) map[string]any {
		p := map[string]any{}
		for _, k := range keys {
			p[k] = false
		}
		return map[string]any{"properties": p}
	}
	def("Proxy")["allOf"] = []any{
		map[string]any{
			"if":   map[string]any{"properties": map[string]any{"match": condition("protocol", "http")}},
			"then": map[string]any{"properties": map[string]any{"match": map[string]any{"required": []string{"host"}}, "action": forbid("connection")}},
			"else": map[string]any{"properties": map[string]any{"match": forbid("host", "method", "path", "opaque_path_parameters", "header"), "action": map[string]any{"required": []string{"connection"}, "properties": map[string]any{"headers": false, "rewrite": false, "basic_auth": false}}}},
		},
	}

	manualKeys := []string{"authorize_url", "token_url", "client_id", "client_secret", "client_auth", "token_encoding", "token_headers", "pkce", "scopes", "scope_parameter", "scope_separator", "authorize_params", "token_params", "refresh_params", "token_response", "refresh_response", "require_refresh", "account"}
	manual := forbid(manualKeys...)
	manual["required"] = []string{"config"}
	oauth := forbid("config")
	oauth["required"] = []string{"authorize_url", "token_url", "client_id"}
	def("AuthMethod")["allOf"] = []any{map[string]any{"if": condition("type", "manual"), "then": manual, "else": oauth}, map[string]any{"if": condition("type", "oauth2"), "then": map[string]any{"if": condition("client_auth", "none"), "then": map[string]any{"properties": map[string]any{"client_secret": false, "pkce": map[string]any{"const": "S256"}}}, "else": map[string]any{"required": []string{"client_secret"}}}}}
	def("BasicAuth")["oneOf"] = []any{map[string]any{"maxProperties": 0}, map[string]any{"required": []string{"username", "password"}}}
	def("ResponseCheck")["allOf"] = []any{map[string]any{"if": condition("op", "equals"), "then": map[string]any{"required": []string{"value"}}, "else": forbid("value")}}
	def("Field")["allOf"] = []any{map[string]any{"if": condition("type", "secret"), "then": forbid("default", "display", "options")}, map[string]any{"if": map[string]any{"properties": map[string]any{"type": map[string]any{"enum": []string{"string", "secret"}}}}, "then": forbid("minimum", "maximum"), "else": forbid("placeholder", "min_length", "max_length", "options", "display")}, map[string]any{"if": map[string]any{"required": []string{"options"}}, "then": forbid("display")}}
	return json.MarshalIndent(map[string]any{"$schema": "https://json-schema.org/draft/2020-12/schema", "$id": "https://ok-houston.com/schemas/connector-manifest-v1.json", "title": "Houston connector manifest v1", "$ref": "#/$defs/Manifest", "$defs": defs}, "", "  ")
}
