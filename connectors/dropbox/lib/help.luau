-- Native schemas are generated once; transport and folder policy narrow them here.
local schemas = require("lib/schemas.luau")
local text = {type = "string", minLength = 1}
local function build(name: string, endpoint: any, policy: any): any
	local input: any = table.clone((assert(schemas[name], "missing schema for " .. name)))
	input.properties = table.clone(input.properties)
	if endpoint.style then
		local required: {string} = {}
		for _, field in input.required or {} do table.insert(required, field) end
		input.required = required
		input.properties.session_path = {type = "string", minLength = 1, description = if endpoint.style == "upload" then "Existing session file to stream, at most 150 MiB." else "Session destination for the downloaded file; returns its signed Houston URL."}
		table.insert(input.required, "session_path")
	end
	if policy then input = policy.schema(name, input) end
	local description = "POST /2/" .. endpoint.route .. ". Returns " .. string.gsub(endpoint.help, "^%b()%s*%->%s*", "")
	if policy then description ..= " Custom folder restrictions apply; see help('access')." end
	local record: any = {description = description, inputSchema = input,
		annotations = {readOnlyHint = endpoint.read and endpoint.style ~= "download", destructiveHint = not endpoint.read, idempotentHint = endpoint.read}}
	if endpoint.style == "download" then
		record.outputSchema = {type = "object", properties = {session_path = text, url = text, size = {type = "integer", minimum = 0}, result = {type = "object"}}, required = {"session_path", "url", "size", "result"}, additionalProperties = false}
	end
	return record
end
local function statFile(policy: any): any
	local native = table.clone(schemas.getMetadata)
	if policy then native = policy.schema("getMetadata", native) end
	return {description = "Looks up one file or folder. Returns {id, name, isFolder, size?}; size is absent for folders. " .. (if policy then "Requires an ordinary absolute path in a granted folder; see help('access')." else "Accepts a Dropbox file ID or path."),
		args = {"id"}, inputSchema = {type = "object", properties = {id = native.properties.path}, required = {"id"}, additionalProperties = false, ["$defs"] = native["$defs"], examples = {{id = native.examples[1].path}}},
		outputSchema = {type = "object", properties = {id = text, name = {type = "string"}, isFolder = {type = "boolean"}, size = {type = "integer", minimum = 0, maximum = 9007199254740991}}, required = {"id", "name", "isFolder"}, additionalProperties = false},
		annotations = {readOnlyHint = true, destructiveHint = false, idempotentHint = true}}
end
return {build = build, statFile = statFile}
