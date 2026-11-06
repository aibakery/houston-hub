package helpschema

import (
	"fmt"
	"slices"
)

// FlattenObject merges plain object conjunctions so connector transport or
// configured policy can add/select named fields. Optional null request bodies
// are narrowed to objects because these connectors always send options objects.
// It refuses unions and repeated constraints that would need schema algebra.
func FlattenObject(source map[string]any) (map[string]any, error) {
	result := object{"type": "object", "properties": object{}}
	required := []string{}
	var visit func(object) error
	visit = func(s object) error {
		for key, value := range s {
			switch key {
			case "allOf":
				for _, part := range value.([]any) {
					if err := visit(obj(part)); err != nil {
						return err
					}
				}
			case "oneOf":
				branches, ok := value.([]any)
				if !ok || len(branches) != 2 || obj(branches[1])["type"] != "null" {
					return fmt.Errorf("unexpected argument union")
				}
				if err := visit(obj(branches[0])); err != nil {
					return err
				}
			case "properties":
				for name, p := range obj(value) {
					if _, exists := obj(result["properties"])[name]; exists {
						return fmt.Errorf("duplicate argument %s", name)
					}
					obj(result["properties"])[name] = p
				}
			case "required":
				for _, name := range value.([]any) {
					required = append(required, name.(string))
				}
			case "type":
				if value != "object" {
					return fmt.Errorf("expected object type, got %v", value)
				}
			case "title", "description":
				result[key] = value
			default:
				if _, exists := result[key]; exists {
					return fmt.Errorf("repeated root constraint %s", key)
				}
				result[key] = value
			}
		}
		return nil
	}
	if err := visit(source); err != nil {
		return nil, err
	}
	if len(required) > 0 {
		slices.Sort(required)
		result["required"] = slices.Compact(required)
	}
	return result, nil
}
