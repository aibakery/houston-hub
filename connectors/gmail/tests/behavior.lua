return {scenario={["auth_config"]={},["auth_method"]="oauth",["config"]={["client_id"]="fixture-value",["client_secret"]="fixture-private-password !@#"}},config={access="read-write"},configure=function()
    requests, responses, files = {}, {}, {}
    http={request=function(req)
        requests[#requests+1]=req
        assert(#responses>0,"unexpected request: "..req.url)
        local response=table.remove(responses,1)
        if req.dest then
            files[req.dest] = response.body
            return {status=response.status,body=""}
        end
        if response.status then return response end
        return {status=200,body=json.encode(response)}
    end}
    fs = {
        read = function(path) return files[path] end,
        write = function(path, body) files[path] = body end,
        signedGetUrl = function(path) return "https://houston.test/files/" .. path end,
    }
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
responses={
    {status=200,body='{"data":"aGVsbG8","size":5}'},
    {status=200,body='{"data":"d29ybGQ","size":5}'},
}
local attachments=c.getAttachments("m1",{{id="a1",path="one.txt"},{id="a2",path="two.txt"}})
assert(#attachments==2 and attachments[1].path=="one.txt" and attachments[2].path=="two.txt")
assert(files["one.txt"]=="hello" and files["two.txt"]=="world")
assert(attachments[1].size==5 and attachments[2].url=="https://houston.test/files/two.txt")
assert(requests[4].dest=="one.txt" and requests[5].dest=="two.txt")
responses={{status=503,body="secret upstream diagnostics"}}
ok,err=pcall(c.getAttachment,"m1","a3","failed.txt")
assert(not ok and not string.find(tostring(err),"secret upstream diagnostics",1,true))
end}
