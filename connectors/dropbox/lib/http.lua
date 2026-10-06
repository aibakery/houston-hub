-- Bundle-local HTTP convenience functions. Only the native request closure has
-- transport authority; these helpers hold no credentials or connection IDs.
local function encode(value: any)
    return (string.gsub(tostring(value), "[^A-Za-z0-9%-_%.~]", function(c: any)
        return string.format("%%%02X", string.byte(c))
    end))
end
local function query_string(params: any)
    local parts = {}
    local function add(key: any,value: any)
        if value == nil then return end
        if type(value) == "table" then for _, item in value do add(key, item) end
        else parts[#parts + 1] = encode(key) .. "=" .. encode(value) end
    end
    for key, value in params or {} do add(key, value) end
    table.sort(parts)
    return table.concat(parts, "&")
end
local function fail(fields: any)
    error(json.encode(fields))
end
local function request(opts: any)
    return http.request({method = opts.method or "GET", url = opts.url,
        headers = opts.headers, body = opts.body, src = opts.src, dest = opts.dest})
end
local function check(res: any,opts: any)
    if type(res) ~= "table" or type(res.status) ~= "number" then error("invalid HTTP response") end
    if res.status < 200 or res.status >= 300 then
        fail({layer = "upstream", upstream_status = res.status, operation = opts.operation,
            retryable = res.status == 429 or res.status == 502 or res.status == 503 or res.status == 504,
            message = "upstream HTTP request failed"})
    end
    return res
end
local function send(opts: any)
    local res = check(request(opts), opts)
    if opts.dest then return res end
    if res.body == nil or res.body == "" then return nil end
    if type(res.body) ~= "string" then error("upstream body must be text") end
    if opts.raw then return res.body end
    local ok, decoded = pcall(json.decode, res.body)
    if not ok then error("upstream returned invalid JSON") end
    return decoded
end
-- Downloads finish within the current invocation. These data results are not
-- reusable transport handles and never outlive invocation authority.
local function sendAsync(opts: any) return check(request(opts), opts) end
local function wait(results: any) return results end
return {encode = encode, query_string = query_string, fail = fail,
    send = send, sendAsync = sendAsync, wait = wait}
