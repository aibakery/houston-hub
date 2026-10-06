return {scenario={["auth_config"]={["token"]="fixture-private-password !@#"},["auth_method"]="token",["config"]={},["publisher"]={}},configure=function()
    requests, responses = {}, {}
    http={request=function(req)
        requests[#requests+1]=req
        assert(#responses>0,"unexpected request: "..req.url)
        local response=table.remove(responses,1)
        if response.status then return response end
        return {status=200,body=json.encode(response)}
    end}
end,run=function(c)
responses={{data={{id={record_id="r1"}}},pagination={next_cursor="next+1"}},{data={id={record_id="r/2"}}}}
local page=c.listEmails({cursor="start+1",domain="example.com"})
assert(page.pagination.next_cursor=="next+1")
assert(string.find(requests[1].url,"cursor=start%2B1",1,true))
c.getRecord("people","r/2")
assert(string.find(requests[2].url,"r%2F2",1,true))
responses={{status=429,body="private upstream diagnostics"}}
assert(not pcall(c.listObjects))
end}
