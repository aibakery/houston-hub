-- Boundary validation for Umami's shared schema shapes. Unknown response fields
-- are retained; caller bodies also retain provider extension fields.
local schemas = require("lib/schemas.luau")
local NULL = json.decode("null")

local function check(value: any, schema: any, field: string, depth: number)
	assert(depth <= 32, field .. " exceeds the supported nesting depth")
	if schema["$ref"] then schema = schemas[schema["$ref"]] end
	assert(schema, "Unknown Umami schema")
	local variants = schema.anyOf or schema.oneOf
	if variants then
		for _, variant in variants do
			if pcall(check, value, variant, field, depth + 1) then return end
		end
		error(field .. " does not match an allowed Umami value")
	end
	if schema.const ~= nil then assert(value == schema.const, field .. " has an invalid value") end
	-- Some inferred upstream schemas contain an empty enum; it conveys no choices.
	if schema.enum and #schema.enum > 0 then assert(table.find(schema.enum, value), field .. " has an invalid choice") end
	local kind = schema.type
	if type(kind) == "table" then
		for _, candidate in kind do
			local alternative = table.clone(schema)
			alternative.type = candidate
			if pcall(check, value, alternative, field, depth + 1) then return end
		end
		error(field .. " has an invalid type")
	end
	if kind == "null" then assert(value == NULL, field .. " must be null"); return end
	if kind == "string" then
		assert(type(value) == "string", field .. " must be a string")
		local length = utf8.len(value)
		assert(length, field .. " must be UTF-8")
		assert(not schema.minLength or length >= schema.minLength, field .. " is too short")
		assert(not schema.maxLength or length <= schema.maxLength, field .. " is too long")
	elseif kind == "boolean" then
		assert(type(value) == "boolean", field .. " must be boolean")
	elseif kind == "number" or kind == "integer" then
		assert(type(value) == "number" and value == value and math.abs(value) <= 9007199254740991, field .. " must be a finite safe number")
		assert(kind ~= "integer" or value % 1 == 0, field .. " must be an integer")
		assert(not schema.minimum or value >= schema.minimum, field .. " is below minimum")
		assert(not schema.maximum or value <= schema.maximum, field .. " is above maximum")
		assert(not schema.exclusiveMinimum or value > schema.exclusiveMinimum, field .. " is below minimum")
	elseif kind == "array" then
		assert(type(value) == "table" and value ~= NULL, field .. " must be an array")
		local count = 0
		for key, item in value do
			assert(type(key) == "number" and key >= 1 and key % 1 == 0, field .. " must be a dense array")
			count += 1
			check(item, schema.items or {}, field .. "[]", depth + 1)
		end
		assert(count == #value, field .. " must be a dense array")
		assert(not schema.minItems or count >= schema.minItems, field .. " has too few items")
		assert(not schema.maxItems or count <= schema.maxItems, field .. " has too many items")
		assert(count > 0 or string.sub(json.encode(value), 1, 1) == "[", field .. " must use json.decode('[]') for an empty array")
	elseif kind == "object" then
		assert(type(value) == "table" and value ~= NULL, field .. " must be an object")
		for key, item in value do
			assert(type(key) == "string", field .. " must have named fields")
			local child = if schema.properties then schema.properties[key] else nil
			if child then check(item, child, field .. "." .. key, depth + 1)
			elseif type(schema.additionalProperties) == "table" then check(item, schema.additionalProperties, field .. "." .. key, depth + 1) end
		end
		for _, key in schema.required or {} do assert(value[key] ~= nil, field .. "." .. key .. " is required") end
	end
end

return function(value: any, schema: any, field: string)
	check(value, schema, field, 0)
end
