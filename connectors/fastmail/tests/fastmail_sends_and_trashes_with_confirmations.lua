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
    

        local c={id="c"}
        responses={session(),result("Identity/get",{list={{id="i",email="me@example.com",name="Me"}}}),
            result("Mailbox/get",{list=folders}),result("Email/set",{created={draft={id="m"}}}),
            result("EmailSubmission/set",{created={send={id="s"}}}),result("Mailbox/get",{list=folders}),
            result("Email/set",json.decode([[{"updated":{"m":null},"notUpdated":null}]]))}
        local sent=fastmail.writes.sendMessage(c,{to={{email="to@example.com"}},subject="Hi",text="Body"})
        assert(sent.id=="m" and sent.submissionId=="s")
        assert(args(4).create.draft.mailboxIds.dr and args(4).create.draft.bodyValues.text.value=="Body")
        local a=args(5)
        assert(a.create.send.emailId=="m" and a.create.send.identityId=="i")
        assert(a.onSuccessUpdateEmail["#send"].mailboxIds.se)
        assert(a.onSuccessUpdateEmail["#send"].keywords["$draft"]==nil)
        assert(fastmail.writes.trashMessage(c,"m").id=="m")
        assert(args(7).update.m.mailboxIds.tr and not args(7).update.m.mailboxIds.dr)
    
end
