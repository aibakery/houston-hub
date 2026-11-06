-- Native body schemas plus the same path/query/header declarations used by request().
local bodies = require("lib/body-schemas.luau")
local examples = require("lib/examples.luau")
local text = {type = "string", minLength = 1, pattern = "^[^\\u0000-\\u001f\\u007f]+$"}
local currency = {type = "string", pattern = "^[A-Z]{3}$"}
local uuid = {type = "string", pattern = "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"}
local function integer(minimum: number?, maximum: number?): any
	local low, high = minimum or 0, maximum or 9007199254740991
	assert(low == 0 or low == 1, "integer schema needs a zero/one lower bound")
	local digits = string.format("%.0f", high)
	local alternatives = {digits}
	if low == 0 then table.insert(alternatives, "0") end
	if #digits > 1 then table.insert(alternatives, "[1-9][0-9]{0," .. tostring(#digits - 2) .. "}") end
	for index = 1, #digits do
		local digit = tonumber(string.sub(digits, index, index)) :: number
		local first = if index == 1 then 1 else 0
		if digit > first then table.insert(alternatives, string.sub(digits, 1, index - 1) .. "[" .. tostring(first) .. "-" .. tostring(digit - 1) .. "][0-9]{" .. tostring(#digits - index) .. "}") end
	end
	return {anyOf = {{type = "integer", minimum = low, maximum = high} :: any, {type = "string", maxLength = 16, pattern = "^0*(?:" .. table.concat(alternatives, "|") .. ")$"}}, description = "Integer or decimal digit string (at most 16 digits), numeric value from " .. tostring(low) .. " to " .. digits .. "."}
end
local function querySchema(spec: any): any
	if spec.type == "integer" then return integer(spec.minimum, spec.maximum) end
	if spec.type == "currency" then return currency end
	if spec.type == "boolean" then return {type = "boolean"} end
	local item: any = table.clone(text)
	if spec.type ~= "list" then if spec.enum then item.enum = spec.enum end; return item end
	local token = if spec.enum then "(?:" .. table.concat(spec.enum, "|") .. ")" else "[^, \\u0000-\\u001f\\u007f](?:[^,\\u0000-\\u001f\\u007f]*[^, \\u0000-\\u001f\\u007f])?"
	if spec.enum then item.pattern = "^ *" .. token .. " *$" end
	return {anyOf = {{type = "array", minItems = 1, items = item} :: any, {type = "string", pattern = "^ *" .. token .. " *(?:, *" .. token .. " *)*$"}}, description = "Nonempty list or comma-separated text; spaces around list items are trimmed. " .. (if spec.enum then "Allowed values: " .. table.concat(spec.enum, ", ") .. "." else "Each item must be nonempty text without control characters.")}
end
local function build(name: string, endpoint: any, formats: {string}, uuidFields: {string}): any
	local input: any = table.clone(bodies[name] or {type = "object", properties = {}, additionalProperties = false})
	local properties: {[string]: any} = table.clone(input.properties)
	local required: {string} = {}
	local function need(field: string) if not table.find(required, field) then table.insert(required, field) end end
	for _, field in input.required or {} do need(field) end
	for _, field in endpoint.required or {} do need(field) end
	for field in string.gmatch(endpoint.path, "{(%w+)}") do
		need(field)
		properties[field] = if table.find(uuidFields, field) then uuid elseif field == "currency" then currency elseif field == "format" then {type = "string", enum = formats} else integer(1)
	end
	for field, spec in endpoint.query or {} do properties[field] = querySchema(spec) end
	if endpoint.idempotence then properties.idempotenceUuid = uuid end
	if endpoint.kind == "download" then properties.path = text; need("path") end
	for _, field in uuidFields do
		if properties[field] then properties[field] = if table.find(required, field) then uuid else {anyOf = {uuid :: any, {type = "null"}}, description = "UUID; null is omitted from the request body."} end
	end
	if name == "createQuote" then
		local amount = {type = "number", exclusiveMinimum = 0}
		properties.sourceAmount, properties.targetAmount = {anyOf = {amount :: any, {type = "null"}}}, {anyOf = {amount :: any, {type = "null"}}}
		input.oneOf = {{required = {"sourceAmount"}, properties = {sourceAmount = amount, targetAmount = {type = "null"}}} :: any, {required = {"targetAmount"}, properties = {targetAmount = amount, sourceAmount = {type = "null"}}}}
	elseif name == "createBalance" then
		properties.type = {type = "string", enum = {"STANDARD", "SAVINGS"}}
		input["if"] = {properties = {type = {const = "SAVINGS"}}, required = {"type"}}
		input["then"] = {required = {"name"}, properties = {name = text}}
	elseif name == "createBalanceMovement" then
		input.oneOf = {{required = {"quoteId"}, properties = {quoteId = uuid}, ["not"] = {anyOf = {{required = {"amount"}}, {required = {"sourceBalanceId"}}, {required = {"targetBalanceId"}}}}} :: any,
			{required = {"amount", "sourceBalanceId", "targetBalanceId"}, properties = {quoteId = {type = "null"}}}}
	elseif name == "fundTransfer" or name == "fundBatchGroup" then properties.type = {const = "BALANCE"} end
	input.properties, input.required, input.examples = properties, if #required > 0 then required else nil, assert(examples[name], "missing examples for " .. name)
	local description = endpoint.about .. " " .. endpoint.method .. " " .. endpoint.path .. "."
	if endpoint.idempotence then description ..= " idempotenceUuid is sent as X-idempotence-uuid, not in the JSON body." end
	if endpoint.minor then description ..= " Uses Accept-Minor-Version: 1." end
	if endpoint.merge then description ..= " Uses application/merge-patch+json." end
	if name == "createRecipient" or name == "refreshAccountRequirements" or name == "validateTransferRequirements" or name == "createTransfer" or name == "createBatchTransfer" then description ..= " Additional route-dependent details come from requirements; see help('requirements')." end
	local record: any = {description = description, inputSchema = input,
		annotations = {readOnlyHint = endpoint.method == "GET" and endpoint.kind ~= "download", idempotentHint = endpoint.method == "GET"}}
	if endpoint.kind == "download" then record.outputSchema = {type = "object", properties = {path = text, url = text, size = {type = "integer", minimum = 0}}, required = {"path", "url", "size"}, additionalProperties = false} end
	return record
end
return {build = build}
