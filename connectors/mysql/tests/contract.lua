return {scenario={["auth_config"]={},["auth_method"]="",["config"]={["database"]="fixture_db",["host"]="database.example.com",["password"]="fixture-private-password !@#",["username"]="fixture_user"},["publisher"]={}}, run = function(exports)
    local count = 0
    for name, fn in exports do
        assert(type(name) == "string" and type(fn) == "function")
        count += 1
    end
    assert(count > 0)
end}
