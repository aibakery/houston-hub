return {scenario={["auth_config"]={["token"]="fixture-private-password !@#"},["auth_method"]="token",["config"]={},["publisher"]={}},config = {access = "read-only"}, run = function(exports)
    assert(exports.sendMessage == nil, "read-only configuration must omit write exports")
    local count = 0
    for name, fn in exports do
        assert(type(name) == "string" and type(fn) == "function")
        count += 1
    end
    assert(count > 0)
end}
