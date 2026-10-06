// Package interfaces defines Houston's trusted domain contracts. Definitions are
// release inputs: callers snapshot Definitions alongside connector source.
package interfaces

import (
	"bytes"
	"embed"
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

//go:embed *.json
var contracts embed.FS

var definitions = loadDefinitions()

func loadDefinitions() map[string]Definition {
	entries, err := contracts.ReadDir(".")
	if err != nil {
		panic(err)
	}
	definitions := make(map[string]Definition, len(entries))
	for _, entry := range entries {
		raw, err := contracts.ReadFile(entry.Name())
		if err != nil {
			panic(err)
		}
		var definition Definition
		decoder := json.NewDecoder(bytes.NewReader(raw))
		decoder.DisallowUnknownFields()
		if err := decoder.Decode(&definition); err != nil {
			panic(err)
		}
		if definition.Reference+".json" != entry.Name() || len(definition.Operations) == 0 {
			panic("invalid interface definition: " + entry.Name())
		}
		definitions[definition.Reference] = definition
	}
	return definitions
}

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
