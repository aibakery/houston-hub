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
responses={{id="f1",name="Report",mimeType="text/plain",size="42"},{id="dir",name="Folder",mimeType="application/vnd.google-apps.folder"},{files={{id="f2",name="Next"}},nextPageToken="next+1"}}
local file=c.statFile("f1")
assert(file.id=="f1" and file.name=="Report" and file.size==42 and not file.isFolder)
assert(c.statFile("dir").isFolder)
local page=c.listFiles({pageToken="start+1",pageSize=2})
assert(page.nextPageToken=="next+1")
assert(string.find(requests[3].url,"pageToken=start%2B1",1,true))
responses={{status=404,body="not found"}}
assert(not pcall(c.statFile,"missing"))
end}
