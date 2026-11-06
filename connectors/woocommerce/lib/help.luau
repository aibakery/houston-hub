-- Shared by the WordPress REST connectors. Provider schemas supply native field
-- semantics; the connector narrows them to its transport and configured access.
local identifier = {type = {"integer", "string"}, minimum = 0, maximum = 9007199254740991, pattern = "^[A-Za-z0-9_-]+$"}
local scalar = {type = {"string", "number", "boolean"}}
local queryValue = {anyOf = {scalar :: any, {type = "array", minItems = 1, items = scalar}}}
local function querySchema(source: any): any
	if type(source) ~= "table" then return source end
	local schema: {[string]: any} = table.clone(source)
	if schema.type == "object" or schema.type == "null" then return nil end
	if type(schema.type) == "table" then
		local types: {string} = {}
		for _, kind in schema.type do if kind ~= "object" and kind ~= "null" then table.insert(types, kind) end end
		if #types == 0 then return nil end
		schema.type = types
	end
	for _, keyword in {"oneOf", "anyOf"} do
		if schema[keyword] then
			local choices: {any} = {}
			for _, choice in schema[keyword] do
				local narrowed = querySchema(choice)
				if narrowed then table.insert(choices, narrowed) end
			end
			if #choices == 0 then return nil end
			schema[keyword] = choices
		end
	end
	if schema.type == "array" or (type(schema.type) == "table" and table.find(schema.type, "array")) then
		schema.minItems = math.max(schema.minItems or 0, 1)
		schema.items = {allOf = {schema.items or {}, scalar}}
		if type(schema.default) == "table" and #schema.default == 0 then schema.default = nil end
	end
	local constraints: {any} = {}
	for _, constraint in schema.allOf or {} do table.insert(constraints, constraint) end
	table.insert(constraints, queryValue)
	schema.allOf = constraints
	return schema
end

local function build(provider: string, docsURL: string, endpoints: any, schemas: any, examples: any, meta: any, extra: any): any
	local records: {[string]: any} = {}
	for name, endpoint in endpoints do
		local schema: any = table.clone((assert(schemas[name], "missing route schema for " .. name)))
		local properties: {[string]: any} = {}
		local query = endpoint.method == "GET" or endpoint.method == "DELETE" or endpoint.upload
		for field, property in schema.properties do
			if not endpoint.private or config.access == "read-write" or endpoint.private[field] then
				properties[field] = if query then querySchema(property) else property
			end
		end
		if query then
			for field in meta do properties[field] = queryValue end
			schema.additionalProperties = if endpoint.private and config.access ~= "read-write" then false else queryValue
			local metaNames: {string} = {}
			for field in meta do table.insert(metaNames, field) end
			table.sort(metaNames)
			schema.propertyNames = {anyOf = {{pattern = "^[A-Za-z][A-Za-z0-9_]*$", ["not"] = {const = "rest_route"}} :: any, {enum = metaNames}}}
		end
		for field in string.gmatch(endpoint.path, "{([%w_]+)}") do properties[field] = identifier end
		if provider == "WordPress" and config.access ~= "read-write" then
			properties.context = {type = "string", enum = {"view", "embed"}, default = "view"}
			if endpoint.private and properties.orderby then
				local orderby = table.clone(properties.orderby)
				orderby["not"] = {const = "email"}
				properties.orderby = orderby
			end
		end
		schema.properties = properties
		local overrides = extra[name] or {}
		for field, property in overrides.properties or {} do properties[field] = property end
		for _, field in overrides.exclude or {} do properties[field] = nil end
		if overrides.required then
			local required: {string} = {}
			for _, field in (schema.required or {}) :: {string} do table.insert(required, field) end
			schema.required = required
			for _, field in overrides.required do if not table.find(schema.required, field) then table.insert(schema.required, field) end end
		end
		schema.examples = assert(examples[name], "missing examples for " .. name)
		local verb, resource = string.match(name, "^(%l+)(%u.*)$")
		local subject = string.lower((string.gsub(resource or name, "(%l)(%u)", "%1 %2")))
		local action = ({list = "List", get = "Read", create = "Create", update = "Update", delete = "Delete", batch = "Create, update or delete"})[verb or ""]
		local description = overrides.description or ((action or "Call") .. " " .. provider .. " " .. subject .. ".")
		if verb == "batch" then
			description ..= " Returns create/update/delete arrays; inspect each item for an error, because a batch can partially succeed. The default server limit is 100 total items."
		elseif query and verb == "list" then
			description ..= " Array responses become {items, total?, total_pages?}; object responses retain their native keys. Follow total_pages with page when present."
		else
			description ..= " Returns the native JSON resource or deletion result; array responses become {items, total?, total_pages?}."
		end
		description ..= " " .. endpoint.method .. " " .. endpoint.path .. ". Reference: " .. docsURL .. endpoint.doc .. "/."
		records[name] = {description = description, inputSchema = schema, annotations = {
			readOnlyHint = endpoint.method == "GET", destructiveHint = endpoint.method ~= "GET", idempotentHint = endpoint.method == "GET"}}
	end
	return records
end

return {build = build}
