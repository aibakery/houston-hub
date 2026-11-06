-- Nested provider shapes supplement the connector's own argument/option declarations.
-- https://docs.attio.com/rest-api/guides/filtering-and-sorting
local text: any = {type = "string", minLength = 1}
local scalar: any = {type = {"string", "number", "boolean", "null"}}
local path = {type = "array", minItems = 1, items = {type = "array", minItems = 2, maxItems = 2, items = text},
	description = "Pairs of object/list slug and attribute slug, following record references."}
local comparison: any = {type = "object", properties = {
	["$eq"] = scalar, ["$in"] = {type = "array", items = scalar}, ["$not_empty"] = {type = "boolean"},
	["$contains"] = {type = "string"}, ["$starts_with"] = {type = "string"}, ["$ends_with"] = {type = "string"},
	["$lt"] = {type = {"string", "number"}}, ["$lte"] = {type = {"string", "number"}},
	["$gt"] = {type = {"string", "number"}}, ["$gte"] = {type = {"string", "number"}},
}, additionalProperties = {["$ref"] = "#/$defs/attribute"},
	description = "Comparators or nested attribute subfields. Attio validates the operators supported by each workspace attribute; use listAttributes to discover its type."}
local definitions = {
	attribute = {anyOf = {scalar, comparison}},
	filter = {type = "object", properties = {
		["$and"] = {type = "array", items = {["$ref"] = "#/$defs/filter"}},
		["$or"] = {type = "array", items = {["$ref"] = "#/$defs/filter"}},
		["$not"] = {["$ref"] = "#/$defs/filter"}, path = path, constraints = comparison,
	}, dependentRequired = {path = {"constraints"}, constraints = {"path"}}, additionalProperties = {["$ref"] = "#/$defs/attribute"},
		description = "Attribute names map to shorthand values or comparator objects. Combine conditions with $and, $or and $not, or follow a relation using path and constraints."},
}
local complex: {[string]: any} = {
	filter = {["$ref"] = "#/$defs/filter"},
	request_as = {type = "object", properties = {type = {enum = {"workspace", "workspace-member"}}, workspace_member_id = text, email_address = text},
		required = {"type"}, oneOf = {
			{properties = {type = {const = "workspace"}}},
			{properties = {type = {const = "workspace-member"}}, required = {"workspace_member_id"}},
			{properties = {type = {const = "workspace-member"}}, required = {"email_address"}},
		}, description = "Search as the workspace or as a member identified by workspace_member_id or email_address."},
	sorts = {anyOf = {
		{type = "array", items = {type = "object", properties = {direction = {enum = {"asc", "desc"}}, attribute = text, field = text, path = path},
			required = {"direction"}, oneOf = {{required = {"attribute"}}, {required = {"path"}}}}} :: any,
		{type = "object", maxProperties = 0},
	}, description = "Ordered sorts by attribute (optional subfield) or relation path. An empty table or JSON array clears sorts."},
}

local function kindSchema(kind: any, field: string): any
	if type(kind) == "number" then return {type = "integer", minimum = 1, maximum = kind} end
	if type(kind) == "table" then return {type = "string", enum = kind} end
	if kind == "count" or kind == "offset" then return {type = "integer", minimum = if kind == "offset" then 0 else 1, maximum = 2 ^ 53} end
	if kind == "boolean" then return {type = "boolean"} end
	if kind == "string" then return {type = "string", maxLength = if field == "query" then 256 else nil} end
	if kind == "texts" then
		return {anyOf = {text, {type = "array", minItems = 1, items = text}},
			description = "Nonempty string or array. For GET calls, array entries are sent comma-separated."}
	end
	if kind == "array" or kind == "table" then
		assert(complex[field], "missing Attio shape for " .. field)
		return complex[field]
	end
	return text
end

-- Existing APIs accept an ID, a composite id table, or the provider's complete row.
local function identifier(field: string, kind: any): any
	local value: any = table.clone(kindSchema(kind or "text", field))
	value.description = "ID or slug accepted by this route; one url.segment value (no separators, dot segments, percent signs or control characters)."
	return {anyOf = {value, {type = "object", properties = {[field] = value, id = {type = "object", properties = {[field] = value}}, api_slug = value},
		anyOf = {{required = {field}}, {required = {"id"}, properties = {id = {required = {field}}}}, {required = {"api_slug"}}}}},
		description = "String, row or composite ID. The connector uses the named field, then id." .. field .. ", then api_slug."}
end

return function(endpoints)
	local docs = {}
	for name, endpoint in endpoints do
		local properties = {}
		for field, kind in endpoint.options do
			if not table.find(endpoint.params, field) then
				local schema = table.clone(kindSchema(kind, field))
				if endpoint.defaults then schema.default = endpoint.defaults[field] end
				properties[field] = schema
			end
		end
		local options: any = {type = "object", properties = properties, additionalProperties = false}
		if name == "listEmails" then
			for _, field in {"participants", "linked_record_ids"} do properties[field].anyOf[2].maxItems = 10 end
		end
		if endpoint.required then options.required = endpoint.required end
		if properties.filter then options["not"] = {required = {"filter", "filter_view_id"}} end
		local pairs = {parent_object = "parent_record_id", linked_object = if name == "listEmails" then "linked_record_ids" else "linked_record_id", object = "record_id", list = "entry_id"}
		local dependencies = {}
		for a, b in pairs do
			if properties[a] and properties[b] then dependencies[a], dependencies[b] = {b}, {a} end
		end
		if next(dependencies) then options.dependentRequired = dependencies end
		if name == "listEmails" then options.anyOf = {{required = {"linked_object", "linked_record_ids"}}, {required = {"participants"}}, {required = {"domain"}}} end
		if name == "listThreads" then options.oneOf = {{required = {"object", "record_id"}}, {required = {"list", "entry_id"}}} end
		local input: any, args: any = options, nil
		if #endpoint.params > 0 then
			local positional = {}
			local required = table.clone(endpoint.params)
			args = table.clone(endpoint.params)
			for _, field in endpoint.params do
				positional[field] = if string.find(endpoint.path, "{" .. field .. "}", 1, true) then identifier(field, endpoint.options[field]) else kindSchema(endpoint.options[field], field)
			end
			if next(properties) then
				positional.options = options
				table.insert(args, "options")
				if endpoint.required then table.insert(required, "options") end
			end
			input = {type = "object", properties = positional, required = required, additionalProperties = false}
		elseif not next(properties) then args = {} end
		input.examples = endpoint.examples
		if properties.filter then input["$defs"] = definitions end
		local output: any = {type = "object"}
		if not endpoint.bare then
			-- Lists and getters both preserve the native data envelope.
			output.properties = {data = {type = {"object", "array"}}, pagination = {type = "object", properties = {next_cursor = {type = {"string", "null"}}}}}
			output.required = {"data"}
		end
		docs[name] = {description = endpoint.method .. " /v2" .. endpoint.path .. ". " .. endpoint.help, args = args,
			inputSchema = input, outputSchema = output, annotations = {readOnlyHint = true, idempotentHint = true}}
	end
	return docs
end
