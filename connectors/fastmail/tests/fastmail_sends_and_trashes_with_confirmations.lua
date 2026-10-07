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
        responses={session(),result("Identity/get",{list={{id="i",email="me@example.com",name="Me"}}}),
            result("Mailbox/get",{list=folders}),result("Email/set",{created={draft={id="m"}}}),
            result("EmailSubmission/set",{created={send={id="s"}}}),result("Mailbox/get",{list=folders}),
            result("Email/set",json.decode([[{"updated":{"m":null},"notUpdated":null}]]))}
        local sent=fastmail.sendMessage({to={{email="to@example.com"}},subject="Hi",text="Body"})
        assert(sent.id=="m" and sent.submissionId=="s")
        assert(args(4).create.draft.mailboxIds.dr and args(4).create.draft.bodyValues.text.value=="Body")
        assert(args(4).create.draft.attachments == nil and args(4).create.draft.inReplyTo == nil)
        local a=args(5)
        assert(a.create.send.emailId=="m" and a.create.send.identityId=="i")
        assert(a.onSuccessUpdateEmail["#send"].mailboxIds.se)
        assert(a.onSuccessUpdateEmail["#send"].keywords["$draft"]==nil)
        assert(fastmail.trashMessage("m").id=="m")
        assert(args(7).update.m.mailboxIds.tr and not args(7).update.m.mailboxIds.dr)

end}
