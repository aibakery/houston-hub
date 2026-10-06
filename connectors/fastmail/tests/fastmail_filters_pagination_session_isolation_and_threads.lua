return {scenario={["auth_config"]={["token"]="fixture-private-password !@#"},["auth_method"]="token",["config"]={},["publisher"]={}},config={access="read-write"}, configure=function()

        requests, responses = {}, {}
        http = {request = function(req)
            requests[#requests + 1] = req
            if req.dest and #responses == 0 then return {status=200, body="", bytes=123} end
            assert(#responses > 0, "unexpected request: " .. req.url)
            local response = table.remove(responses, 1)
            if req.dest then return {status=200,body="",bytes=response.bytes} end
            return {status=200,body=if type(response)=="string" then response else json.encode(response)}
        end}
        fs = {signedGetUrl=function(path) return "https://houston.test/"..path end}
        local MAIL="urn:ietf:params:jmap:mail"
        local SUB="urn:ietf:params:jmap:submission"
        function session()
            return {username="me@example.com",primaryAccounts={[MAIL]="u1"},accounts={u1={name="Me"}},
                capabilities={[MAIL]={},[SUB]={}},apiUrl="https://api.fastmail.com/jmap/api/",
                downloadUrl="https://www.fastmailusercontent.com/jmap/download/{accountId}/{blobId}/{name}?type={type}"}
        end
        function result(name, args) return {methodResponses={{name,args,"0"}}} end
        folders={{id="in",role="inbox",name="Inbox"},{id="tr",role="trash"},{id="sp",role="junk"},
            {id="dr",role="drafts"},{id="se",role="sent"}}
        function args(n) return json.decode(requests[n].body).methodCalls[1][2] end


end, run=function(fastmail)
        responses={session(),result("Mailbox/get",{list=folders}),result("Email/query",{ids={"m2"},position=0,total=3}),
            result("Mailbox/get",{list=folders}),result("Email/query",{ids={"m1"},position=1,total=3}),
            result("Email/get",{list={{id="m1",threadId="t1"}}}),session()}
        local page=fastmail.listMessages({maxResults=2,folder="INBOX",after="2026-01-01",from={"a","b"},text="hello"})
        assert(page.messages[1].id=="m2" and page.nextPageToken=="1") -- server returned fewer than requested
        local a=args(3)
        assert(a.accountId=="u1" and a.limit==2 and a.calculateTotal)
        local conditions=a.filter.conditions
        local seen={}
        for _,f in conditions do for k,v in f do seen[k]=v end end
        assert(seen.inMailbox=="in" and seen.after=="2026-01-01T00:00:00Z" and seen.text=="hello")
        assert(#conditions==5)
        local threads=fastmail.listThreads({pageToken=page.nextPageToken})
        assert(threads.threads[1].id=="t1" and threads.nextPageToken=="2")
        a=args(5)
        assert(a.position==1 and a.collapseThreads)
        assert(#a.filter.conditions==2 and a.filter.conditions[1].operator=="NOT")
        fastmail.getProfile()
        assert(#requests==6, "session must be cached within one invocation")
        local ok,err=pcall(fastmail.listMessages,{pageToken="bad"})
        assert(not ok and string.find(tostring(err),"pageToken",1,true))
        assert(#requests==6)

end}
