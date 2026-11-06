-- Discovery supplies native field schemas; endpoint declarations select the
-- fields this connector routes. Keep this helper identical across Google bundles.
local function object(value: any): any
	return {type = "object", properties = value, additionalProperties = false}
end

local function definitions(schema: any, source: any)
	local found: {[string]: any} = {}
	local function visit(value: any)
		if type(value) ~= "table" then return end
		local ref = value["$ref"]
		if type(ref) == "string" then
			local name = string.match(ref, "^#/%$defs/(.+)$")
			if name then
				name = string.gsub(string.gsub(name, "~1", "/"), "~0", "~")
				if not found[name] then
					assert(source[name], "missing Google discovery definition " .. name)
					found[name] = source[name]
					visit(source[name])
				end
			end
		end
		for _, child in value do visit(child) end
	end
	visit(schema)
	if next(found) then schema["$defs"] = found end
end

local function input(endpoint: any, native: any): any
	local schema = if endpoint.body and native.body then table.clone(native.body) else object({})
	schema.properties = table.clone(schema.properties or {})
	local required: {[string]: boolean} = {}
	for _, field in schema.required or {} do required[field] = true end
	local function parameter(field: string, mandatory: boolean)
		assert(native.parameters[field], "missing Google discovery parameter " .. field)
		local property = table.clone(native.parameters[field])
		if mandatory then property.minLength = 1 end
		schema.properties[field] = property
		if mandatory and not (endpoint.defaults and endpoint.defaults[field] ~= nil) then required[field] = true end
	end
	for field in string.gmatch(endpoint.path, "{(%w+)}") do parameter(field, true) end
	for _, field in endpoint.query or {} do parameter(field, false) end
	for field, value in endpoint.defaults or {} do
		if schema.properties[field] then
			local property = table.clone(schema.properties[field])
			property.default = value
			schema.properties[field] = property
		end
	end
	for _, field in native.required do
		if schema.properties[field] and not (endpoint.defaults and endpoint.defaults[field] ~= nil) then required[field] = true end
	end
	for field, kind in endpoint.required or {} do
		required[field] = true
		local property = table.clone(schema.properties[field] or {})
		property.type = kind
		property[if kind == "array" then "minItems" elseif kind == "object" then "minProperties" else "minLength"] = 1
		schema.properties[field] = property
	end
	local names: {string} = {}
	for field in required do table.insert(names, field) end
	table.sort(names)
	schema.required = if #names > 0 then names else nil
	return schema
end

local function build(bundle: any, endpoints: any, exportedHelp: any, records: any, overview: {string}): any
	local functions: {[string]: any} = {}
	for name, description in exportedHelp do
		local record = table.clone((assert(records[name], "missing Google help record " .. name)))
		local endpoint = endpoints[name]
		local schema = record.inputSchema or input(endpoint, (assert(bundle.methods[name], "missing Google discovery method " .. name)))
		record.inputSchema = schema
		if record.properties then
			for field, property in record.properties do schema.properties[field] = property end
			record.properties = nil
		end
		if record.required then
			schema.required = table.clone(schema.required or {})
			for _, field in record.required do
				if not table.find(schema.required, field) then table.insert(schema.required, field) end
			end
			record.required = nil
		end
		schema.examples, record.examples = record.examples, nil
		definitions(schema, bundle.definitions)
		record.description = description
		record.annotations = record.annotations or {readOnlyHint = endpoint.read, destructiveHint = not endpoint.read, idempotentHint = endpoint.read}
		functions[name] = record
	end
	return {text = table.concat(overview, "\n"), functions = functions}
end

return {build = build}
