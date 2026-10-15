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
responses={{notes={{id="n1"}},next_cursor="next+1"},{id="n/2",transcript="text"}}
local page=c.listNotes({cursor="start+1",created_after="2026-01-02T03:04:05Z"})
assert(page.next_cursor=="next+1")
assert(string.find(requests[1].url,"cursor=start%2B1",1,true))
assert(string.find(requests[1].url,"created_after=2026-01-02",1,true))
c.getNote("n/2",{includeTranscript=true})
assert(string.find(requests[2].url,"n%2F2",1,true))
responses={{status=503,body="upstream unavailable"}}
assert(not pcall(c.listNotes))
end}
