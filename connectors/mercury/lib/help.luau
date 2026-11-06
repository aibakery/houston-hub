-- Narrow native provider schemas to Mercury's connector transport. Exports and
-- documentation use the same endpoint and configuration gates in connector.luau.
local function build(endpoints: any): any
	local schemas = require("lib/schemas.luau")
	local docs: {[string]: any} = {}
	local text = {type = "string", minLength = 1}
	for name, endpoint in endpoints do
		local input: any = table.clone((assert(schemas[name], "missing schema for " .. name)))
		local properties: {[string]: any} = table.clone(input.properties)
		local required: {string} = {}
		for _, field in input.required or {} do table.insert(required, field) end
		input.properties, input.required = properties, required
		for field in string.gmatch(endpoint.path, "{([%w_]+)}") do properties[field] = {type = "string", pattern = "^[A-Za-z0-9_-]+$"} end
		for field, native in endpoint.query do
			local query = table.clone(native)
			if query.type == "array" then
				query.type = "string"
				query.description = "Comma-separated values. This connector accepts one string for this native array filter."
			end
			if query.type == "string" then query.minLength = 1 end
			if query.type == "integer" then query.minimum = math.max(query.minimum or -9007199254740991, -9007199254740991); query.maximum = math.min(query.maximum or 9007199254740991, 9007199254740991) end
			properties[field] = query
		end
		input["not"] = {required = {"start_after", "end_before"}}
		if endpoint.body then
			-- The implementation also checks these fields when supplied on a body.
			properties.amount = {type = "number", exclusiveMinimum = 0}
			properties.idempotencyKey = text
			if name == "createCard" then
				properties.type = {const = "virtual"}
				input["if"] = {required = {"kind"}, properties = {kind = {const = "debit"}}}
				input["then"] = {required = {"accountId"}, properties = {accountId = text}}
			end
		end
		if name == "createTransaction" or name == "requestSendMoney" then
			input["if"] = {required = {"paymentMethod"}, properties = {paymentMethod = {enum = {"domesticWire", "internationalWire"}}}}
			input["then"] = {required = {"purpose"}}
		end
		if endpoint.kind == "download" or endpoint.kind == "upload" then
			properties.path = {type = "string", minLength = 1, description = if endpoint.kind == "download" then "Session file destination; the completed PDF is returned with its signed download URL." else "Existing session file to stream; at most 32 MiB."}
			table.insert(required, "path")
		end
		if endpoint.kind == "upload" then
			properties.filename = {type = "string", minLength = 1, maxLength = 299, pattern = "^[^\\r\\n]+$", description = "Defaults to the source basename; at most 299 UTF-8 bytes."}
			properties.contentType = {type = "string", minLength = 1, pattern = "^[^\\r\\n]+$", default = "application/octet-stream"}
			if name == "uploadTransactionAttachment" then properties.attachmentType = {type = "string", enum = {"receipt", "bill", "other"}} end
		end
		if #required == 0 then input.required = nil end
		local description = endpoint.help .. " Native JSON fields, including nulls, are preserved."
		if endpoint.list ~= "" then description ..= " The result's " .. endpoint.list .. " array contains the items. This call fetches one page; see help('paging') for this endpoint's paging convention." end
		if endpoint.empty then description ..= " An empty successful response becomes {success=true}." end
		if name == "createTransaction" or name == "createInternalTransfer" then description ..= " Moves money. Retain one idempotencyKey per intended payment and inspect its outcome before retrying." end
		if name == "requestSendMoney" or name == "requestTransferMoney" then description ..= " Creates an approval request; it does not bypass Mercury's approval policy." end
		if endpoint.vault then description ..= " Returns sensitive agent-card PAN/CVC details through Mercury Vault; requires reveal_card_details=true." end
		local record: any = {description = description, inputSchema = input, annotations = {readOnlyHint = not endpoint.write and endpoint.kind ~= "download", destructiveHint = endpoint.write, idempotentHint = endpoint.method == "GET"}}
		if endpoint.kind == "download" then record.outputSchema = {type = "object", properties = {path = text, size = {type = "integer", minimum = 0}, url = text}, required = {"path", "size", "url"}} end
		docs[name] = record
	end
	return docs
end
return {build = build}
