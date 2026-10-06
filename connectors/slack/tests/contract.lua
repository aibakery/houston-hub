return {scenario={["auth_config"]={},["auth_method"]="oauth",["config"]={["workspace_id"]="T_FIXTURE"},["publisher"]={["client_id"]="fixture-value",["client_secret"]="fixture-private-password !@#"}},config = {access = "read-only"}, run = function(exports)
    assert(exports.postMessage == nil, "read-only configuration must omit write exports")
    local count = 0
    for name, fn in exports do
        assert(type(name) == "string" and type(fn) == "function")
        count += 1
    end
    assert(count > 0)
end}
