return {scenario={["auth_config"]={},["auth_method"]="oauth",["config"]={},["publisher"]={["client_id"]="fixture-value",["client_secret"]="fixture-private-password !@#"}},config={access="read-write"},configure=function()
    requests, responses = {}, {}
    http={request=function(req)
        requests[#requests+1]=req
        assert(#responses>0,"unexpected request: "..req.url)
        local response=table.remove(responses,1)
        if response.status then return response end
        return {status=200,body=json.encode(response)}
    end}
end,run=function(c)
responses={{labels={{id="z",name="Z"},{id="a",name="A"}}},{messages={{id="m1"}},nextPageToken="next+1"}}
local folders=c.listMailFolders()
assert(#folders==2 and folders[1].id=="a" and folders[2].id=="z")
assert(folders[1].name=="A")
local page=c.listMessages({pageToken="start+1",maxResults=2})
assert(page.nextPageToken=="next+1")
assert(string.find(requests[2].url,"pageToken=start%2B1",1,true))
responses={{status=401,body="secret upstream diagnostics"}}
local ok,err=pcall(c.getProfile)
assert(not ok and not string.find(tostring(err),"secret upstream diagnostics",1,true))
end}
