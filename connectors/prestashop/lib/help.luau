local native = require("lib/fields.luau")
local ID: any = {type = "integer", minimum = 1, maximum = 9007199254740991}
local FIELD = "^[A-Za-z_][A-Za-z0-9_]*$"
local XML_TEXT: any = {type = "string", pattern = "^[^\\u0000-\\u0008\\u000b\\u000c\\u000e-\\u001f\\ufffe\\uffff]*$"}
local SCALAR = {anyOf = {XML_TEXT, {type = {"number", "boolean"}}}}
local function object(properties: any, required: {string}?): any
	return {type = "object", properties = properties, required = required or json.decode("[]"), additionalProperties = false}
end
local function array(items: any, minimum: number?): any
	return {type = "array", items = items, minItems = minimum or 0}
end
local function translated(value: any): any
	return {anyOf = {value, array(object({id = ID, value = value}, {"id", "value"}), 1)}, description = "One value for every language, or an array of {id = language ID, value} translations."}
end
local ELEMENT = translated(SCALAR)
local EXAMPLES = {
	createProduct = {fields = {price = 9.5, active = true, name = {{id = 1, value = "Mug & co"}}, description_short = "<b>New</b>", associations = {categories = {{id = 2}, {id = 5}}}}},
	updateProduct = {id = 10, fields = {price = "12.00", name = "Mug"}, opts = {id_shop = 2}},
	createCustomer = {fields = {firstname = "Bo", lastname = "Lee", email = "bo@example.com", passwd = "replace-with-new-customer-password", newsletter = false}},
	updateCustomer = {id = 6, fields = {newsletter = false, company = "Example Studio"}},
	deleteCustomer = {id = 6, opts = {id_shop = 1}}, deleteProduct = {id = 10},
	createOrderHistory = {fields = {id_order = 123, id_order_state = 4}, opts = {sendemail = true}},
	updateOrderCarrier = {id = 7, fields = {tracking_number = "1Z999"}, opts = {sendemail = false}},
	updateStockAvailable = {id = 31, fields = {quantity = 12}},
}
-- The provider validates remaining semantic constraints (email/name/date formats,
-- store settings and custom modules). XML text constraints apply to every value.
local function fieldSchema(meta: any): any
	local validator = string.lower(meta.validator)
	local schema: any = {type = "string"}
	if validator == "" then schema = SCALAR
	elseif validator == "isbool" then schema = {enum = {false :: any, true, 0, 1, "0", "1"}}
	elseif validator == "isunsignedid" or validator == "isunsignedint" then
		schema = {anyOf = {{type = "integer", minimum = 0, maximum = 4294967295} :: any, {type = "string", pattern = "^(0|[1-9][0-9]{0,9})$", description = "Decimal unsigned integer, at most 4294967295."}, {type = "boolean"}}}
	elseif validator == "isint" then schema = {anyOf = {{type = "integer"}, {type = "string", pattern = "^-?(0|[1-9][0-9]*)$"}, {type = "boolean"}}}
	elseif validator == "isprice" then schema = {anyOf = {{type = "number", minimum = 0, exclusiveMaximum = 10000000000} :: any, {type = "string", pattern = "^[0-9]{1,10}(\\.[0-9]{1,9})?$"}, {type = "boolean"}}}
	elseif validator == "isfloat" or validator == "isunsignedfloat" then
		schema = {anyOf = {{type = "number", minimum = if validator == "isunsignedfloat" then 0 else nil}, {type = "string", pattern = if validator == "isunsignedfloat" then "^[+]?[0-9]+(\\.[0-9]+)?([eE][+-]?[0-9]+)?$" else "^[+-]?[0-9]+(\\.[0-9]+)?([eE][+-]?[0-9]+)?$"}, {type = "boolean"}}}
	end
	local value: any = {allOf = {schema, XML_TEXT}, description = meta.description .. (if meta.validator ~= "" then " PrestaShop validator: " .. meta.validator .. "." else "")}
	-- XML_TEXT restricts strings, while the other branches also accept native
	-- numbers/booleans. Its pattern applies without imposing a string type.
	value.allOf[2] = {pattern = XML_TEXT.pattern, maxLength = meta.maxLength}
	if meta.translated then return translated(value) end
	return value
end
return function(resource: any, verb: string, name: string, allowed: any, secret: any): any
	local withheld, sorts = {}, {}
	for field in secret do table.insert(withheld, field); table.insert(sorts, field .. "_ASC"); table.insert(sorts, field .. "_DESC") end
	table.sort(withheld); table.sort(sorts)
	local readable = {type = "string", pattern = FIELD, ["not"] = {enum = withheld}}
	local sort = {type = "string", pattern = "^[A-Za-z_][A-Za-z0-9_]*_(ASC|DESC)$", ["not"] = {enum = sorts}}
	local options = {
		display = {anyOf = {{const = "full"}, array(readable, 1)}, default = "full"},
		filter = {type = "object", minProperties = 1, propertyNames = readable, additionalProperties = {anyOf = {
			{type = "string", minLength = 1, description = "Native filter syntax, for example >[10], [a|b], [1,10] or %[mug]%."} :: any,
			{type = {"number", "boolean"}}, array({anyOf = {{type = "string", minLength = 1, pattern = "^[^|,\\[\\]]+$"} :: any, {type = {"number", "boolean"}}}}, 1),
		}}},
		sort = {anyOf = {sort, array(sort, 1)}},
		limit = {type = "integer", minimum = 1, maximum = 100, default = 50},
		offset = {type = "integer", minimum = 0, maximum = 9007199254740991, default = 0},
		language = ID, id_shop = {anyOf = {ID, {const = "all"}}},
		sendemail = {type = "boolean", default = false, description = "Send the status/shipment email. An email error can occur after the update was saved."},
	}
	local selected = {}
	for key, enabled in allowed do if enabled then selected[key] = options[key] end end
	local opts = object(selected)
	local schema, args, example: any
	local description = ""
	if verb == "list" then
		schema, example = opts, {limit = 20, offset = 0, sort = "id_ASC"}
		description = "List one page of " .. resource.many .. ". Native field filters, sorting and projection; offsets page forward, with no total count."
	elseif verb == "get" then
		schema, args, example = object({id = ID, opts = opts}, {"id"}), {"id", "opts"}, {id = 123, opts = {language = 1}}
		description = "Read one " .. resource.one .. " by ID, preserving zero, empty and false fields."
	else
		example = EXAMPLES[name]
		local properties: any = {opts = opts}
		local required = {}
		args = {}
		if verb ~= "create" then properties.id = ID; table.insert(required, "id"); table.insert(args, "id") end
		if verb ~= "delete" then
			local reference = native[resource.many]
			local fields, mandatory = {}, json.decode("[]")
			for key, meta in reference.fields do
				if key ~= "associations" then
					if meta.writable and (not secret[key] or (verb == "create" and key == "passwd")) then
						fields[key] = fieldSchema(meta)
						if verb == "create" and meta.required then table.insert(mandatory, key) end
					else fields[key] = false end
				end
			end
			for key in secret do if key ~= "passwd" or verb ~= "create" then fields[key] = false end end
			fields.id = false
			if fields.passwd then fields.passwd.writeOnly = true; fields.passwd.description = "New customer's plain password; PrestaShop hashes it. It cannot be changed through this connector." end
			local associations = {}
			for key, keys in reference.associations do
				local item = {}
				for _, field in keys do item[field] = ELEMENT end
				associations[key] = array({type = "object", properties = item, propertyNames = {pattern = FIELD}, additionalProperties = ELEMENT})
			end
			if next(associations) then fields.associations = {type = "object", properties = associations, propertyNames = {pattern = FIELD}, additionalProperties = array({type = "object", propertyNames = {pattern = FIELD}, additionalProperties = ELEMENT}), description = "Replaces each supplied association's complete set. An empty array clears that association."} end
			table.sort(mandatory)
			properties.fields = {type = "object", properties = fields, required = mandatory, propertyNames = {pattern = FIELD}, additionalProperties = ELEMENT, description = "Native PrestaShop fields serialized to XML. Store modules can add scalar or translated fields. Provider validators and store settings apply."}
			table.insert(required, "fields"); table.insert(args, "fields")
		end
		table.insert(args, "opts")
		schema = object(properties, required)
		description = (if verb == "create" then "Create " elseif verb == "update" then "Patch supplied fields of " else "Permanently delete ") .. "a " .. resource.one .. ". " .. (if verb == "update" then "PATCH requires PrestaShop 8 or later. " else "") .. "After an ambiguous failure, read the record before repeating the write."
	end
	schema.examples = {example}
	if name == "updateProduct" then table.insert(schema.examples, {id = 10, fields = {associations = {categories = json.decode("[]")}}}) end
	local record: any = {description = description, inputSchema = schema, args = args, annotations = {readOnlyHint = verb == "get" or verb == "list", destructiveHint = verb == "update" or verb == "delete", openWorldHint = true}}
	if verb ~= "delete" then
		local key = if verb == "list" then resource.many else resource.one
		record.outputSchema = {type = "object", properties = {[key] = if verb == "list" then array({type = "object"}) else {type = "object"}}, required = {key}}
	end
	return record
end
