package manifest

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
)

type fieldShape struct {
	If       string   `json:"if,omitempty"`
	Type     string   `json:"type"`
	Required bool     `json:"required,omitempty"`
	Options  []string `json:"options,omitempty"`
}

type methodShape struct {
	If     string                `json:"if,omitempty"`
	Type   string                `json:"type"`
	Config map[string]fieldShape `json:"config,omitempty"`
}

// Shape fingerprints the configuration model that connections store values for:
// the config, publisher and auth fields with their types, requirement, options
// and conditions, and the auth methods with their types. Values such as labels,
// defaults, limits, OAuth endpoints and scopes, proxy rules, documentation and
// Lua are not part of the shape. Saved manifests decode leniently, so contract
// fields that no longer exist are ignored.
func Shape(raw []byte) (string, error) {
	var m struct {
		SchemaVersion int              `json:"schema_version"`
		Config        map[string]Field `json:"config"`
		Publisher     map[string]Field `json:"publisher"`
		Auth          map[string]struct {
			If     string           `json:"if"`
			Type   string           `json:"type"`
			Config map[string]Field `json:"config"`
		} `json:"auth"`
	}
	if err := json.Unmarshal(raw, &m); err != nil {
		return "", err
	}
	auth := map[string]methodShape{}
	for name, method := range m.Auth {
		auth[name] = methodShape{If: method.If, Type: method.Type, Config: fieldShapes(method.Config)}
	}
	b, err := json.Marshal(struct {
		SchemaVersion int                    `json:"schema_version"`
		Config        map[string]fieldShape  `json:"config"`
		Publisher     map[string]fieldShape  `json:"publisher"`
		Auth          map[string]methodShape `json:"auth"`
	}{m.SchemaVersion, fieldShapes(m.Config), fieldShapes(m.Publisher), auth})
	if err != nil {
		return "", err
	}
	sum := sha256.Sum256(b)
	return hex.EncodeToString(sum[:]), nil
}

func fieldShapes(fields map[string]Field) map[string]fieldShape {
	out := map[string]fieldShape{}
	for name, f := range fields {
		shape := fieldShape{If: f.If, Type: f.Type, Required: f.Required}
		for _, option := range f.Options {
			shape.Options = append(shape.Options, option.Value)
		}
		out[name] = shape
	}
	return out
}
