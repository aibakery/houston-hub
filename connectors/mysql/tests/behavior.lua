return {scenario={["auth_config"]={},["auth_method"]="",["config"]={["database"]="fixture_db",["host"]="database.example.com",["password"]="fixture-private-password !@#",["username"]="fixture_user"},["publisher"]={}},configure=function()
    requests={}
    db={query=function(req)
        requests[#requests+1]=req
        return {columns={"n"},rows={{n=42}},row_count=1,truncated=false}
    end}
end,run=function(c)
    local result=c.query("SELECT ? AS n",{params={42},limit=7})
    assert(result.rows[1].n==42)
    assert(requests[1].query=="SELECT ? AS n" and requests[1].params[1]==42)
    assert(requests[1].max_rows==7 and requests[1].read_only==true)
    assert(not pcall(c.query,""))
end}
