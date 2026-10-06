return {scenario={["auth_config"]={["token"]="fixture-private-password !@#"},["auth_method"]="token",["config"]={},["publisher"]={}},configure=function()
    calls=0
    http={request=function(req)
        calls+=1
        if calls==1 then
            return {status=200,body=json.encode({username="mail@example.com",primaryAccounts={["urn:ietf:params:jmap:mail"]="account"},accounts={account={name="Account"}},apiUrl="https://api.fastmail.com/jmap/api/"})}
        end
        return {status=200,body=json.encode({methodResponses={{"Mailbox/get",{list={{id="z",name="Archive",role="archive"},{id="a",name="Inbox",role="inbox"}}},"0"}}})}
    end}
end,run=function(c)
    local folders=c.listMailFolders()
    assert(#folders==2 and folders[1].id=="a" and folders[1].name=="Inbox")
    assert(folders[2].id=="z" and folders[2].name=="Archive")
    assert(folders[1].role==nil)
end}
