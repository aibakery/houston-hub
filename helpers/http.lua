-- One request/decode/fail path for every connector. Retry, truncation, and
-- resume hook here so later PRs do not fork six copies.

local function retryable_status(status)
	status = tonumber(status)
	return status == 429 or status == 502 or status == 503 or status == 504
end

local function encode(s)
	s = tostring(s)
	return (string.gsub(s, "[^A-Za-z0-9%-_%.~]", function(c)
		return string.format("%%%02X", string.byte(c))
	end))
end

local function scalar(value)
	if type(value) == "boolean" then
		if value then
			return "true"
		end
		return "false"
	end
	return tostring(value)
end

local function add_query(parts, key, value)
	if value == nil then
		return
	end
	if type(value) == "table" then
		for _, item in value do
			add_query(parts, key, item)
		end
		return
	end
	parts[#parts + 1] = encode(key) .. "=" .. encode(scalar(value))
end

local function query_string(params)
	if type(params) ~= "table" then
		return ""
	end
	local parts = {}
	for key, value in params do
		add_query(parts, key, value)
	end
	if #parts == 0 then
		return ""
	end
	local s = parts[1]
	for i = 2, #parts do
		s = s .. "&" .. parts[i]
	end
	return s
end

local function snippet(body)
	local s = tostring(body or "")
	if #s > 512 then
		return string.sub(s, 1, 512)
	end
	return s
end

local function layer_of(status, body)
	status = tonumber(status) or 0
	local text = tostring(body or "")
	if status == 401 then
		return "auth"
	end
	if status == 403 then
		return "permission"
	end
	if status == 408 then
		return "timeout"
	end
	if status == 502 and string.find(text, "connector unavailable", 1, true) then
		return "houston-proxy"
	end
	return "upstream"
end

local function recovery_of(layer, retryable, extra)
	extra = extra or {}
	if layer == "auth" then
		return "reauth"
	end
	if layer == "decode" or extra.truncated then
		return "reduce limit"
	end
	if retryable then
		local cursor = extra.affected_cursor
		if cursor ~= nil and cursor ~= "" then
			return "resume with token " .. tostring(cursor)
		end
		return "retry"
	end
	return "do not retry"
end

local function fail(fields)
	fields = fields or {}
	if fields.layer == nil or fields.layer == "" then
		fields.layer = "upstream"
	end
	if fields.retryable == nil then
		if fields.upstream_status ~= nil then
			fields.retryable = retryable_status(fields.upstream_status)
		else
			fields.retryable = false
		end
	end
	if fields.request_id == nil then
		fields.request_id = ""
	end
	if fields.retained == nil then
		fields.retained = 0
	end
	if fields.recovery == nil then
		fields.recovery = recovery_of(fields.layer, fields.retryable, fields)
	end
	if type(houston) == "table" and type(houston.fail) == "function" then
		houston.fail(fields)
	end
	error(json.encode(fields))
end

local function transport_layer(message)
	local text = string.lower(tostring(message or ""))
	if string.find(text, "timeout", 1, true) or string.find(text, "timed out", 1, true) then
		return "timeout"
	end
	return "houston-proxy"
end

local function http_opts(opts)
	return {
		connector_id = opts.connector_id,
		dest = opts.dest or opts.file,
		src = opts.src or opts.upload,
	}
end

local function sendAsync(opts)
	if type(opts) ~= "table" then
		fail({
			layer = "houston-proxy",
			retryable = false,
			recovery = "do not retry",
		})
	end
	local ok, handle = pcall(http.sendAsync, opts.method or "GET", opts.url, opts.headers, opts.body, http_opts(opts))
	if not ok then
		fail({
			layer = transport_layer(handle),
			retryable = true,
			request_id = "",
			connector = opts.connector,
			operation = opts.operation,
			path = opts.path,
			affected_cursor = opts.affected_cursor,
			retained = opts.retained,
			message = snippet(handle),
		})
	end
	return handle
end

local function wait(...)
	local ok, res = pcall(http.wait, ...)
	if not ok then
		fail({
			layer = transport_layer(res),
			retryable = false,
			request_id = "",
			message = snippet(res),
		})
	end
	return res
end

local function send(opts)
	if type(opts) ~= "table" then
		fail({
			layer = "houston-proxy",
			retryable = false,
			recovery = "do not retry",
		})
	end
	local dest = opts.dest or opts.file
	local ok, res = pcall(http.send, opts.method or "GET", opts.url, opts.headers, opts.body, http_opts(opts))
	if not ok then
		fail({
			layer = transport_layer(res),
			retryable = true,
			request_id = "",
			connector = opts.connector,
			operation = opts.operation,
			path = opts.path,
			affected_cursor = opts.affected_cursor,
			retained = opts.retained,
			message = snippet(res),
		})
	end
	if type(res) ~= "table" then
		fail({
			layer = "houston-proxy",
			retryable = true,
			request_id = "",
			connector = opts.connector,
			operation = opts.operation,
			path = opts.path,
			affected_cursor = opts.affected_cursor,
			retained = opts.retained,
			message = "http.send returned nothing",
		})
	end
	local request_id = res.request_id
	if type(request_id) ~= "string" then
		request_id = ""
	end
	if res.status < 200 or res.status >= 300 then
		fail({
			layer = layer_of(res.status, res.body),
			upstream_status = res.status,
			retryable = retryable_status(res.status),
			request_id = request_id,
			connector = opts.connector,
			operation = opts.operation,
			path = opts.path,
			affected_cursor = opts.affected_cursor,
			retained = opts.retained,
			truncated = res.truncated,
			message = snippet(res.body or "request failed"),
		})
	end
	if dest ~= nil and dest ~= "" then
		return res
	end
	if res.body == nil or res.body == "" then
		return nil
	end
	if opts.raw then
		return res.body
	end
	local decoded_ok, decoded = pcall(json.decode, res.body)
	if not decoded_ok then
		fail({
			layer = "decode",
			upstream_status = res.status,
			retryable = false,
			request_id = request_id,
			connector = opts.connector,
			operation = opts.operation,
			path = opts.path,
			affected_cursor = opts.affected_cursor,
			retained = opts.retained,
			truncated = res.truncated,
			recovery = "reduce limit",
			message = snippet(decoded),
		})
	end
	return decoded
end

return {
	fail = fail,
	send = send,
	sendAsync = sendAsync,
	wait = wait,
	retryable_status = retryable_status,
	encode = encode,
	query_string = query_string,
}
