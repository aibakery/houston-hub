package main

// OpenAPI preserves Stripe's field-level definitions. These cross-field rules
// come from their descriptions; transport constraints apply at every depth.
func supplement(name string, s object) {
	props := obj(s["properties"])
	defs := obj(s["$defs"])
	if defs == nil {
		defs = object{}
		s["$defs"] = defs
	}
	value := object{"$ref": "#/$defs/HoustonFormValue"}
	defs["HoustonFormValue"] = object{"anyOf": []any{
		object{"type": []string{"string", "number", "boolean"}},
		object{"type": "array", "items": value},
		object{"type": "object", "propertyNames": object{"pattern": `^[^\[\]\u0000-\u001f\u007f]+$`}, "additionalProperties": value},
	}}
	s["allOf"] = []any{object{"propertyNames": object{"pattern": "^[A-Za-z][A-Za-z0-9_]*$"}, "additionalProperties": value}}
	alternatives := func(names ...string) []any {
		r := []any{}
		for _, n := range names {
			r = append(r, object{"required": []string{n}})
		}
		return r
	}
	switch name {
	case "createPaymentIntent", "createPayout", "createRefund":
		obj(props["amount"])["minimum"] = 1
	}
	switch name {
	case "createSubscription", "createPortalSession", "attachPaymentMethod", "createInvoiceItem":
		s["oneOf"] = alternatives("customer", "customer_account")
	case "createInvoice":
		s["anyOf"] = alternatives("customer", "customer_account", "from_invoice")
	case "createRefund":
		s["anyOf"] = append(alternatives("charge", "payment_intent"), object{"required": []string{"customer", "origin"}, "properties": object{"origin": object{"const": "customer_balance"}}})
	case "createCheckoutSession":
		obj(props["line_items"])["minItems"] = 1
		s["if"] = object{"properties": object{"mode": object{"enum": []string{"payment", "subscription"}}}, "required": []string{"mode"}}
		s["then"] = object{"required": []string{"line_items"}}
	}
}
