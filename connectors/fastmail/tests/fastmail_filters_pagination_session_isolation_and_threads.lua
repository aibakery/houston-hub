return function(fastmail)

        requests, responses = {}, {}
        local encode = connector_http.encode
        connector_http = {
            encode = encode,
            fail = function(err) error(err.message) end,
            send = function(req)
                requests[#requests+1] = req
                assert(#responses > 0, "unexpected request")
                return table.remove(responses, 1)
            end,
            sendAsync = function(req) requests[#requests+1]=req; return #requests end,
            wait = function(handles)
                local out={}
                for _,_ in handles do out[#out+1]={status=200} end
                return out
            end,
        }
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
    

        local c={id="c1"}
        responses={session(),result("Mailbox/get",{list=folders}),result("Email/query",{ids={"m2"},position=0,total=3}),
            result("Mailbox/get",{list=folders}),result("Email/query",{ids={"m1"},position=1,total=3}),
            result("Email/get",{list={{id="m1",threadId="t1"}}}),session()}
        local page=fastmail.functions.listMessages(c,{maxResults=2,folder="INBOX",after="2026-01-01",from={"a","b"},text="hello"})
        assert(page.messages[1].id=="m2" and page.nextPageToken=="1") -- server returned fewer than requested
        local a=args(3)
        assert(a.accountId=="u1" and a.limit==2 and a.calculateTotal)
        local conditions=a.filter.conditions
        local seen={}
        for _,f in conditions do for k,v in f do seen[k]=v end end
        assert(seen.inMailbox=="in" and seen.after=="2026-01-01T00:00:00Z" and seen.text=="hello")
        assert(#conditions==5)
        local threads=fastmail.functions.listThreads(c,{pageToken=page.nextPageToken})
        assert(threads.threads[1].id=="t1" and threads.nextPageToken=="2")
        a=args(5)
        assert(a.position==1 and a.collapseThreads)
        assert(#a.filter.conditions==2 and a.filter.conditions[1].operator=="NOT")
        fastmail.functions.getProfile({id="c2"})
        assert(requests[7].connector_id=="c2")
        local ok,err=pcall(fastmail.functions.listMessages,c,{pageToken="bad"})
        assert(not ok and string.find(err,"pageToken",1,true))
        assert(#requests==7)
    
end
