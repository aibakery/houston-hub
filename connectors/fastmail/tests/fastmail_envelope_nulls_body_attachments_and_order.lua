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
        local message=json.decode([[{"id":"m1","threadId":"t1","from":[{"name":null,"email":"a@example.com"}],
            "to":null,"cc":null,"bcc":null,"replyTo":null,"sentAt":"2026-09-01T12:00:00Z","messageId":["m@example.com"],
            "headers":[{"name":"Received","value":"by mail"}],"textBody":[{"partId":"p"}],"htmlBody":[],
            "bodyValues":{"p":{"value":"Hello","isTruncated":true}},
            "attachments":[{"blobId":"b1","name":"file +.txt","type":"text/plain","size":123,"cid":null,"disposition":"attachment"}]}]])
        responses={session(),result("Email/get",{list={{id="m2",preview="two"},message}}),
            result("Email/get",{list={message}})}
        local messages=fastmail.functions.getMessages(c,{{id="m1"},"m2"},{maxBodyValueBytes=1234})
        local m=messages[1]
        assert(args(2).maxBodyValueBytes==1234)
        assert(m.id=="m1" and messages[2].id=="m2")
        assert(m.from=="a@example.com" and m.to=="" and m.body=="Hello" and m.bodyTruncated)
        assert(m.messageId=="m@example.com" and m.received[1]=="by mail")
        assert(m.attachments[1].id=="b1" and not m.attachments[1].inline and not m.attachments[1].contentId)
        -- Return a fresh provider object; connector decoration must not alter transport fixtures.
        responses[1]=result("Email/get",{list={json.decode([[{"id":"m1","attachments":[{"blobId":"b1","name":"file +.txt","type":"text/plain","size":123}]}]])}})
        local downloaded=fastmail.functions.getAttachment(c,"m1","b1","mail/a.txt")
        assert(downloaded.size==123 and downloaded.url=="https://houston.test/mail/a.txt")
        assert(requests[4].dest=="mail/a.txt")
        assert(requests[4].url=="https://www.fastmailusercontent.com/jmap/download/u1/b1/file%20%2B.txt?type=text%2Fplain")
        local ids={}
        for i=1,51 do ids[i]="m"..i end
        assert(not pcall(fastmail.functions.getMessages,c,ids))
    
end
