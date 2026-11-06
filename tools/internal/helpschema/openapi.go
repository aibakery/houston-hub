// Package helpschema composes connector input schemas from OpenAPI operations.
// It preserves nested request constraints and localizes their references for offline help.
package helpschema

import (
	"encoding/json"
	"fmt"
	"regexp"
	"slices"
	"strings"
)

type object = map[string]any

func obj(v any) object { m, _ := v.(map[string]any); return m }
func clone(v any) any  { b, _ := json.Marshal(v); var out any; _ = json.Unmarshal(b, &out); return out }
func resolve(spec object, ref string) (any, error) {
	if !strings.HasPrefix(ref, "#/") {
		return nil, fmt.Errorf("external reference %q", ref)
	}
	var v any = spec
	for _, key := range strings.Split(strings.TrimPrefix(ref, "#/"), "/") {
		key = strings.ReplaceAll(strings.ReplaceAll(key, "~1", "/"), "~0", "~")
		v = obj(v)[key]
	}
	if v == nil {
		return nil, fmt.Errorf("missing reference %q", ref)
	}
	return v, nil
}

// expandRoot follows only root references and combinators. URL parameters are
// flattened beside body fields by the connector, so closed body branches must
// explicitly allow these fields. Nested request objects remain unchanged.
func expandRoot(spec object, value any, params object, depth int) (object, error) {
	if depth > 64 {
		return nil, fmt.Errorf("recursive root schema")
	}
	if boolean, ok := value.(bool); ok {
		if boolean {
			return object{}, nil
		}
		return object{"not": object{}}, nil
	}
	schema := obj(clone(value))
	if schema == nil {
		return nil, fmt.Errorf("request body must be an object schema")
	}
	if ref, ok := schema["$ref"].(string); ok {
		target, err := resolve(spec, ref)
		if err != nil {
			return nil, err
		}
		delete(schema, "$ref")
		expanded, err := expandRoot(spec, target, params, depth+1)
		if err != nil {
			return nil, err
		}
		// JSON Schema $ref siblings are conjunctive.
		if len(schema) > 0 {
			siblings, err := expandRoot(spec, schema, params, depth+1)
			if err != nil {
				return nil, err
			}
			return object{"allOf": []any{expanded, siblings}}, nil
		}
		return expanded, nil
	}
	for _, key := range []string{"allOf", "anyOf", "oneOf", "if", "then", "else", "not"} {
		switch v := schema[key].(type) {
		case []any:
			for i, branch := range v {
				expanded, err := expandRoot(spec, branch, params, depth+1)
				if err != nil {
					return nil, err
				}
				v[i] = expanded
			}
		case map[string]any:
			expanded, err := expandRoot(spec, v, params, depth+1)
			if err != nil {
				return nil, err
			}
			schema[key] = expanded
		}
	}
	if schema["additionalProperties"] == false || schema["unevaluatedProperties"] == false {
		props := obj(schema["properties"])
		if props == nil {
			props = object{}
			schema["properties"] = props
		}
		for key := range params {
			if _, exists := props[key]; exists {
				return nil, fmt.Errorf("body and URL parameter share %q", key)
			}
			props[key] = true
		}
	}
	return schema, nil
}
func Input(spec, op object, path string, queries, mandatory []string, body bool) (object, error) {
	props := object{}
	required := append([]string{}, mandatory...)
	pathNames := regexp.MustCompile(`\{([^}]+)\}`).FindAllStringSubmatch(path, -1)
	for _, name := range pathNames {
		required = append(required, name[1])
	}
	wanted := append(slices.Clone(queries), required...)
	parameters, _ := op["parameters"].([]any)
	for _, raw := range parameters {
		param := obj(raw)
		if ref, ok := param["$ref"].(string); ok {
			v, err := resolve(spec, ref)
			if err != nil {
				return nil, err
			}
			param = obj(v)
		}
		name, _ := param["name"].(string)
		if !slices.Contains(wanted, name) {
			continue
		}
		value := clone(param["schema"])
		if value == nil {
			return nil, fmt.Errorf("parameter %s lacks schema", name)
		}
		if param["in"] == "query" && param["required"] != true && !slices.Contains(mandatory, name) {
			value = object{"anyOf": []any{value, object{"type": "null"}}, "description": "Null omits this query parameter."}
		}
		props[name] = value
		if param["required"] == true {
			required = append(required, name)
		}
	}
	for _, name := range wanted {
		if props[name] == nil {
			return nil, fmt.Errorf("missing URL parameter schema %s", name)
		}
	}
	slices.Sort(required)
	required = slices.Compact(required)
	schema := object{"type": "object", "properties": props, "required": required}
	if body {
		request := obj(op["requestBody"])
		if ref, ok := request["$ref"].(string); ok {
			v, err := resolve(spec, ref)
			if err != nil {
				return nil, err
			}
			request = obj(v)
		}
		raw := obj(obj(request["content"])["application/json"])["schema"]
		if raw == nil {
			return nil, fmt.Errorf("JSON body lacks schema")
		}
		expanded, err := expandRoot(spec, raw, props, 0)
		if err != nil {
			return nil, err
		}
		schema["allOf"] = []any{expanded}
	} else {
		schema["additionalProperties"] = false
	}
	defs := object{}
	if err := localize(spec, schema, defs); err != nil {
		return nil, err
	}
	if len(defs) > 0 {
		schema["$defs"] = defs
	}
	if version, _ := spec["openapi"].(string); strings.HasPrefix(version, "3.0.") {
		schema = obj(normalize30(schema))
	}
	return schema, nil
}

// OpenAPI 3.0 uses nullable and boolean exclusive bounds. Convert only schema
// positions, leaving literal examples/defaults and extension payloads intact.
func normalize30(value any) any {
	schema := obj(value)
	if schema == nil {
		return value
	}
	for _, key := range []string{"properties", "patternProperties", "$defs"} {
		for name, child := range obj(schema[key]) {
			obj(schema[key])[name] = normalize30(child)
		}
	}
	for _, key := range []string{"items", "additionalProperties", "not", "if", "then", "else", "contains"} {
		if child, ok := schema[key]; ok {
			schema[key] = normalize30(child)
		}
	}
	for _, key := range []string{"allOf", "oneOf", "anyOf", "prefixItems"} {
		if children, ok := schema[key].([]any); ok {
			for i, child := range children {
				children[i] = normalize30(child)
			}
		}
	}
	for _, bound := range []struct{ exclusive, inclusive string }{{"exclusiveMinimum", "minimum"}, {"exclusiveMaximum", "maximum"}} {
		if exclusive, ok := schema[bound.exclusive].(bool); ok {
			delete(schema, bound.exclusive)
			if exclusive {
				if value, ok := schema[bound.inclusive]; ok {
					schema[bound.exclusive] = value
					delete(schema, bound.inclusive)
				}
			}
		}
	}
	if nullable, ok := schema["nullable"].(bool); ok {
		delete(schema, "nullable")
		if nullable {
			return object{"anyOf": []any{schema, object{"type": "null"}}}
		}
	}
	return schema
}
func localize(spec object, value any, defs object) error {
	switch v := value.(type) {
	case map[string]any:
		for key, child := range v {
			if key == "$ref" {
				ref, ok := child.(string)
				if !ok || !strings.HasPrefix(ref, "#/components/schemas/") {
					return fmt.Errorf("unsupported schema reference %v", child)
				}
				name := strings.TrimPrefix(ref, "#/components/schemas/")
				v[key] = "#/$defs/" + name
				if _, exists := defs[name]; !exists {
					target, err := resolve(spec, ref)
					if err != nil {
						return err
					}
					defs[name] = clone(target)
					if err = localize(spec, defs[name], defs); err != nil {
						return err
					}
				}
			} else if err := localize(spec, child, defs); err != nil {
				return err
			}
		}
	case []any:
		for _, child := range v {
			if err := localize(spec, child, defs); err != nil {
				return err
			}
		}
	}
	return nil
}
