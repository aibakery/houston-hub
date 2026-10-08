return {scenario={["auth_config"]={},["auth_method"]="oauth",["config"]={},["publisher"]={["client_id"]="fixture-value",["client_secret"]="fixture-private-password !@#"}},configure=function()
    requests, responses = {}, {}
    http={request=function(req)
        requests[#requests+1]=req
        assert(#responses>0,"unexpected request: "..req.url)
        local response=table.remove(responses,1)
        if response.status then return response end
        return {status=200,body=json.encode(response)}
    end}
end,run=function(c)
assert(not pcall(c.statFile, ""))
assert(not pcall(c.statFile, 42))
assert(not pcall(c.statFile, "file", "extra"))
assert(#requests == 0, "bad arguments reached provider")
responses={{id="id:f1",name="Report",[".tag"]="file",size=42},{id="id:dir",name="Folder",[".tag"]="folder"},{entries={{id="id:f2",name="Next",[".tag"]="file"}},cursor="next+1",has_more=true}}
local file=c.statFile("id:f1")
assert(file.id=="id:f1" and file.name=="Report" and file.size==42 and not file.isFolder)
assert(c.statFile("id:dir").isFolder)
local page=c.listFiles({pageToken="start+1"})
assert(page.nextPageToken=="next+1")
assert(json.decode(requests[3].body).cursor=="start+1")
responses={{status=409,body="not found"}}
assert(not pcall(c.statFile,"missing"))
for _, size in {-1, 0.5, 9007199254740992} do
    responses={{id="bad",name="Bad size",size=size}}
    assert(not pcall(c.statFile, "bad"))
end
end}
