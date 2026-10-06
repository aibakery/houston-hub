return {scenario={["auth_config"]={["token"]="fixture-private-password !@#"},["auth_method"]="token",["config"]={},["publisher"]={}}, run = function(exports)
    local count = 0
    for name, fn in exports do
        assert(type(name) == "string" and type(fn) == "function")
        count += 1
    end
    assert(count > 0)
end}
