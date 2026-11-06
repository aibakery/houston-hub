package main

import "slices"

// The reference describes filter-operator requirements and dynamic import values
// in prose. Express these rules without restricting custom field IDs or values.
func supplementCRM(op object) {
	body := obj(obj(obj(obj(op["requestBody"])["content"])["application/json"])["schema"])
	dateShapes(body)
	props := obj(body["properties"])
	if filter := obj(obj(props["filters"])["items"]); filter != nil {
		filter["required"] = slices.DeleteFunc(list(filter["required"]), func(v any) bool { return v == "value" })
		operator := func(values ...string) object {
			return object{"properties": object{"operator": object{"enum": values}}, "required": []string{"operator"}}
		}
		filter["allOf"] = []any{
			object{"if": operator("blank", "not_blank"), "then": object{"properties": object{"value": false}}, "else": object{"required": []string{"value"}}},
			object{"if": operator("in"), "then": object{"properties": object{"value": object{"type": "array", "items": object{"type": "string"}}}}},
			object{"if": operator("between"), "then": object{"properties": object{"value": object{"type": "array", "minItems": 2, "maxItems": 2}}}},
			object{"if": operator("last_x"), "then": object{"properties": object{"value": object{"type": "string", "pattern": "^[0-9]+ (days|weeks|months|years)$"}}}},
		}
	}
	if data := obj(props["dynamicInfo"]); data != nil {
		data["additionalProperties"] = object{"type": []string{"string", "number"}}
	}
}

// format is an annotation in the default JSON Schema vocabulary. Carta's
// oneOf(date, date-time) needs explicit disjoint lexical shapes to be useful
// without a validator-specific format assertion setting.
func dateShapes(s object) {
	if s == nil {
		return
	}
	if s["pattern"] == nil {
		switch s["format"] {
		case "date":
			s["pattern"] = `^[0-9]{4}-[0-9]{2}-[0-9]{2}$`
		case "date-time":
			s["pattern"] = `^[0-9]{4}-[0-9]{2}-[0-9]{2}[Tt][0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?([Zz]|[+-][0-9]{2}:[0-9]{2})$`
		}
	}
	for _, child := range obj(s["properties"]) {
		dateShapes(obj(child))
	}
	for _, key := range []string{"items", "additionalProperties", "not", "if", "then", "else"} {
		dateShapes(obj(s[key]))
	}
	for _, key := range []string{"oneOf", "anyOf", "allOf"} {
		for _, child := range list(s[key]) {
			dateShapes(obj(child))
		}
	}
}
