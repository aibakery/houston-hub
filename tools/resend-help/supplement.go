package main

// The OpenAPI export omits some constraints and describes automation configs only
// in prose. These shapes follow the native snake_case wire format and the types at
// https://github.com/resend/resend-node/blob/main/src/automations/interfaces/automation-step.interface.ts.
func ref(name string) object { return object{"$ref": "#/components/schemas/" + name} }
func shape(properties object, required ...string) object {
	s := object{"type": "object", "properties": properties, "additionalProperties": false}
	if len(required) > 0 {
		s["required"] = required
	}
	return s
}
func array(items any) object              { return object{"type": "array", "items": items} }
func stringsEnum(values ...string) object { return object{"type": "string", "enum": values} }
func atLeast(fields ...string) object {
	branches := []any{}
	for _, field := range fields {
		branches = append(branches, object{"required": []string{field}})
	}
	return object{"anyOf": branches}
}
func supplement(spec object) {
	defs := obj(obj(spec["components"])["schemas"])
	received := obj(obj(obj(spec["paths"])["/emails/receiving/{email_id}"])["get"])
	received["parameters"] = append(list(received["parameters"]), object{"name": "html_format", "in": "query", "schema": object{"type": "string", "enum": []string{"data_uri", "cid"}, "default": "data_uri", "description": "Inline image representation in HTML; large messages may still return cid. See https://resend.com/docs/api-reference/emails/retrieve-received-email."}})
	contacts := obj(obj(obj(spec["paths"])["/contacts"])["get"])
	contacts["parameters"] = append(list(contacts["parameters"]), object{"name": "segment_id", "in": "query", "schema": object{"type": "string", "minLength": 1, "description": "Only contacts in this segment. See https://resend.com/docs/api-reference/contacts/list-contacts."}})
	text := object{"type": "string"}
	nonempty := object{"type": "string", "minLength": 1}
	boolean := object{"type": "boolean"}
	scalar := object{"type": []string{"string", "number", "boolean", "null"}}
	// Template defaults can supply from/subject. A template and literal content
	// cannot be mixed; ordinary sends require a sender, subject and content.
	email := obj(defs["SendEmailRequest"])
	email["required"] = []string{"to"}
	email["if"] = object{"required": []string{"template"}}
	email["then"] = object{"properties": object{"html": false, "text": false}}
	email["else"] = object{"required": []string{"from", "subject"}, "anyOf": []any{object{"required": []string{"html"}}, object{"required": []string{"text"}}}}
	obj(email["properties"])["headers"] = object{"type": "object", "additionalProperties": text}
	attachment := obj(defs["Attachment"])
	attachment["anyOf"] = atLeast("content", "path")["anyOf"]
	obj(obj(attachment["properties"])["content"])["description"] = "Base64 file contents; files may instead be supplied by a public URL in path."
	delete(obj(obj(attachment["properties"])["content"]), "format")
	obj(obj(attachment["properties"])["content"])["contentEncoding"] = "base64"
	obj(defs["UpdateEmailOptions"])["required"] = []string{"scheduled_at"}
	for _, name := range []string{"CreateEventRequest", "UpdateEventRequest"} {
		obj(obj(defs[name])["properties"])["schema"] = object{"type": []string{"object", "null"}, "additionalProperties": stringsEnum("string", "number", "boolean", "date"), "description": "Flat payload field/type map, or null to clear it."}
	}
	event := obj(defs["SendEventRequest"])
	event["oneOf"] = []any{object{"required": []string{"email"}, "not": object{"required": []string{"contact_id"}}}, object{"required": []string{"contact_id"}, "not": object{"required": []string{"email"}}}}
	topic := obj(obj(obj(obj(defs["UpdateContactTopicsOptions"])["properties"])["topics"])["items"])
	topic["required"] = []string{"id", "subscription"}
	// Contact import fields travel as multipart text. The connector also accepts
	// their structured JSON equivalents and serializes those once.
	imported := obj(clone(defs["CreateContactImportOptions"]))
	delete(obj(imported["properties"]), "file")
	delete(imported, "required")
	mapping := shape(object{"email": text, "first_name": text, "last_name": text, "unsubscribed": text, "properties": object{"type": "object", "additionalProperties": shape(object{"column": text, "type": stringsEnum("string", "number", "boolean")}, "column")}})
	for name, s := range (object{"column_map": mapping, "segments": array(shape(object{"id": nonempty}, "id")), "topics": array(topic)}) {
		native := obj(imported["properties"])[name]
		obj(imported["properties"])[name] = object{"anyOf": []any{native, s}}
	}
	imported["additionalProperties"] = false
	defs["HoustonContactImport"] = imported
	// Recursive condition trees used by conditions and wait-for-event filters.
	rules := []any{}
	for _, group := range []struct {
		operators []string
		value     any
	}{
		{[]string{"eq", "neq"}, scalar}, {[]string{"gt", "gte", "lt", "lte"}, object{"type": "number"}}, {[]string{"contains", "starts_with", "ends_with"}, text}, {[]string{"exists", "is_empty"}, nil},
	} {
		p := object{"type": object{"const": "rule"}, "field": nonempty, "operator": stringsEnum(group.operators...)}
		required := []string{"type", "field", "operator"}
		if group.value != nil {
			p["value"] = group.value
			required = append(required, "value")
		}
		rules = append(rules, shape(p, required...))
	}
	rules = append(rules, shape(object{"type": stringsEnum("and", "or"), "rules": array(ref("HoustonConditionRule"))}, "type", "rules"))
	defs["HoustonConditionRule"] = object{"oneOf": rules}
	variable := shape(object{"var": nonempty}, "var")
	variableValue := object{"anyOf": []any{scalar, variable}}
	primitive := object{"type": []string{"string", "number", "boolean"}}
	literalMap := object{"type": "object", "additionalProperties": primitive}
	templateVariable := object{"anyOf": []any{primitive, variable, literalMap, array(object{"anyOf": []any{primitive, literalMap}})}}
	configs := object{
		"trigger":        shape(object{"event_name": nonempty}, "event_name"),
		"delay":          shape(object{"duration": nonempty}, "duration"),
		"send_email":     shape(object{"template": shape(object{"id": nonempty, "variables": object{"type": "object", "additionalProperties": templateVariable}}, "id"), "from": text, "subject": text, "reply_to": text}, "template"),
		"wait_for_event": shape(object{"event_name": nonempty, "timeout": nonempty, "filter_rule": ref("HoustonConditionRule")}, "event_name"),
		"condition":      ref("HoustonConditionRule"),
		"contact_update": shape(object{"first_name": object{"anyOf": []any{object{"type": []string{"string", "null"}}, variable}}, "last_name": object{"anyOf": []any{object{"type": []string{"string", "null"}}, variable}}, "unsubscribed": object{"anyOf": []any{boolean, variable}}, "properties": object{"type": "object", "additionalProperties": variableValue}}),
		"contact_delete": shape(object{}),
		"add_to_segment": shape(object{"segment_id": nonempty}, "segment_id"),
	}
	branches := []any{}
	// Fixed order keeps generated bundles byte-for-byte reproducible.
	for _, kind := range []string{"trigger", "send_email", "delay", "wait_for_event", "condition", "contact_update", "contact_delete", "add_to_segment"} {
		branches = append(branches, shape(object{"key": nonempty, "type": object{"const": kind}, "config": configs[kind]}, "key", "type", "config"))
	}
	defs["AutomationStep"] = object{"oneOf": branches}
	trigger := object{"type": "object", "required": []string{"type"}, "properties": object{"type": object{"const": "trigger"}}}
	obj(obj(obj(defs["CreateAutomationRequest"])["properties"])["steps"])["contains"] = trigger
	patch := obj(defs["PatchAutomationRequest"])
	patch["dependentRequired"] = object{"steps": []string{"connections"}, "connections": []string{"steps"}}
	patch["anyOf"] = atLeast("name", "status", "steps")["anyOf"]
}
