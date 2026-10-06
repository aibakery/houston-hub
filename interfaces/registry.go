// Package interfaces defines Houston's trusted domain contracts. Definitions are
// release inputs: callers snapshot Definitions alongside connector source.
package interfaces

import (
	"encoding/json"
	"fmt"
	"math"
	"sort"
)

type Type struct {
	Kind     string          `json:"kind"`
	Fields   map[string]Type `json:"fields,omitempty"`
	Optional bool            `json:"optional,omitempty"`
	Element  *Type           `json:"element,omitempty"`
	Nonempty bool            `json:"nonempty,omitempty"`
	Minimum  *float64        `json:"minimum,omitempty"`
}
type Operation struct {
	Access    string `json:"access"`
	Arguments []Type `json:"arguments"`
	Result    Type   `json:"result"`
	Help      string `json:"help"`
}
type Definition struct {
	Reference   string               `json:"reference"`
	Description string               `json:"description"`
	Operations  map[string]Operation `json:"operations"`
	Semantics   string               `json:"semantics"`
}

func str() Type                          { return Type{Kind: "string"} }
func id() Type                           { return Type{Kind: "string", Nonempty: true} }
func object(fields map[string]Type) Type { return Type{Kind: "object", Fields: fields} }

var zero = 0.0
var definitions = map[string]Definition{
	"mail.folders@1": {
		Reference: "mail.folders@1", Description: "List the named mail folders or labels in one mailbox.",
		Operations: map[string]Operation{"listMailFolders": {Access: "read", Arguments: []Type{}, Result: Type{Kind: "array", Element: ptr(object(map[string]Type{"id": id(), "name": str()}))}, Help: "listMailFolders(): {id: string, name: string}[]"}},
		Semantics:  "No arguments or defaults. Returns every available mail folder/label, sorted by ID in ascending byte order. IDs are opaque, unique and scoped to this connection; names are display text and need not be unique. No pagination. Provider failures raise an error and never return an empty success. Gmail labels and Fastmail mailboxes are both organizational containers; membership semantics are outside this capability.",
	},
	"files.metadata@1": {
		Reference: "files.metadata@1", Description: "Read metadata for one file or folder in file storage.",
		Operations: map[string]Operation{"statFile": {Access: "read", Arguments: []Type{id()}, Result: object(map[string]Type{"id": id(), "name": str(), "isFolder": {Kind: "boolean"}, "size": {Kind: "integer", Optional: true, Minimum: &zero}}), Help: "statFile(id: string): {id: string, name: string, isFolder: boolean, size?: integer}"}},
		Semantics:  "One nonempty opaque provider ID scoped to this connection; no defaults. Returns one file or folder, with size in bytes only when known for a non-folder. Cloud-native documents may omit size. Names are display text, not paths. No pagination or ordering. Missing or inaccessible IDs and provider failures raise errors. Extra provider fields are excluded from the normalized result.",
	},
}

func ptr(t Type) *Type { return &t }

// Resolve returns detached definitions so a release or caller cannot mutate the registry.
func Resolve(refs []string) ([]Definition, error) {
	out := make([]Definition, 0, len(refs))
	seen := map[string]bool{}
	for _, ref := range refs {
		d, ok := definitions[ref]
		if !ok {
			return nil, fmt.Errorf("unknown interface %q", ref)
		}
		if seen[ref] {
			return nil, fmt.Errorf("duplicate interface %q", ref)
		}
		seen[ref] = true
		raw, _ := json.Marshal(d)
		var copy Definition
		_ = json.Unmarshal(raw, &copy)
		out = append(out, copy)
	}
	return out, nil
}

// Configured implements the complete/absent/partial rule for configured discovery.
func Configured(defs []Definition, exports []string) ([]Definition, error) {
	available := map[string]bool{}
	for _, n := range exports {
		available[n] = true
	}
	active := []Definition{}
	for _, d := range defs {
		n := 0
		for name := range d.Operations {
			if available[name] {
				n++
			}
		}
		if n == 0 {
			continue
		}
		if n != len(d.Operations) {
			return nil, fmt.Errorf("partial interface %s", d.Reference)
		}
		active = append(active, d)
	}
	return active, nil
}
func OperationFor(defs []Definition, name string) (Operation, bool) {
	for _, d := range defs {
		if op, ok := d.Operations[name]; ok {
			return op, true
		}
	}
	return Operation{}, false
}
func ValidateArguments(op Operation, args []any) error {
	if len(args) != len(op.Arguments) {
		return fmt.Errorf("expected %d arguments, got %d", len(op.Arguments), len(args))
	}
	for i, t := range op.Arguments {
		if err := t.Validate(args[i]); err != nil {
			return fmt.Errorf("argument %d: %w", i+1, err)
		}
	}
	return nil
}
func ValidateResult(op Operation, value any) error { return op.Result.Validate(value) }
func (t Type) Validate(value any) error {
	if value == nil && t.Optional {
		return nil
	}
	switch t.Kind {
	case "string":
		s, ok := value.(string)
		if !ok || t.Nonempty && s == "" {
			return fmt.Errorf("expected %sstring", map[bool]string{true: "nonempty "}[t.Nonempty])
		}
	case "boolean":
		if _, ok := value.(bool); !ok {
			return fmt.Errorf("expected boolean")
		}
	case "integer":
		var n float64
		switch v := value.(type) {
		case float64:
			n = v
		case int:
			n = float64(v)
		case int64:
			n = float64(v)
		case json.Number:
			var err error
			n, err = v.Float64()
			if err != nil {
				return err
			}
		default:
			return fmt.Errorf("expected integer")
		}
		if math.IsNaN(n) || math.IsInf(n, 0) || math.Trunc(n) != n || math.Abs(n) > 9007199254740991 || t.Minimum != nil && n < *t.Minimum {
			return fmt.Errorf("invalid integer")
		}
	case "array":
		a, ok := value.([]any)
		if !ok {
			return fmt.Errorf("expected array")
		}
		for i, v := range a {
			if err := t.Element.Validate(v); err != nil {
				return fmt.Errorf("item %d: %w", i, err)
			}
		}
	case "object":
		o, ok := value.(map[string]any)
		if !ok {
			return fmt.Errorf("expected object")
		}
		for k := range o {
			if _, ok := t.Fields[k]; !ok {
				return fmt.Errorf("unknown result field %q", k)
			}
		}
		keys := make([]string, 0, len(t.Fields))
		for k := range t.Fields {
			keys = append(keys, k)
		}
		sort.Strings(keys)
		for _, k := range keys {
			if err := t.Fields[k].Validate(o[k]); err != nil {
				return fmt.Errorf("field %s: %w", k, err)
			}
		}
	default:
		return fmt.Errorf("unknown interface type %q", t.Kind)
	}
	return nil
}
