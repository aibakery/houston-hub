return {scenario={["auth_config"]={["token"]="fixture-private-password !@#"},["auth_method"]="token",["config"]={},["publisher"]={}},config={access="read-write"}, configure=function()

        requests, responses = {}, {}
        http = {request = function(req)
            requests[#requests + 1] = req
            if string.find(req.url, "/jmap/download/", 1, true) then return fixture.operation({statusCode=200, headers={}, body=fixture.reader(string.rep("x", 123))}) end
            assert(#responses > 0, "unexpected request: " .. req.url)
            local response = table.remove(responses, 1)
            return fixture.operation({statusCode=200, headers={}, body=fixture.reader(if type(response)=="string" then response else json.encode(response))})
        end}
        fs = fixture.files()
        local MAIL="urn:ietf:params:jmap:mail"
        local SUB="urn:ietf:params:jmap:submission"
        function session()
            return {username="me@example.com",primaryAccounts={[MAIL]="u1"},accounts={u1={name="Me"}},
                capabilities={[MAIL]={},[SUB]={}},apiUrl="https://api.fastmail.com/jmap/api/",
                downloadUrl="https://phl-www.fastmailusercontent.com/jmap/download/{accountId}/{blobId}/{name}?type={type}"}
        end
        function result(name, args) return {methodResponses={{name,args,"0"}}} end
        folders={{id="in",role="inbox",name="Inbox"},{id="tr",role="trash"},{id="sp",role="junk"},
            {id="dr",role="drafts"},{id="se",role="sent"}}
        function args(n) return json.decode(requests[n].body).methodCalls[1][2] end


end, run=function(fastmail)
        local message=json.decode([[{"id":"m1","threadId":"t1","from":[{"name":null,"email":"a@example.com"}],
            "to":null,"cc":null,"bcc":null,"replyTo":null,"sentAt":"2026-09-01T12:00:00Z","messageId":["m@example.com"],
            "headers":[{"name":"Received","value":"by mail"}],"textBody":[{"partId":"p"}],"htmlBody":[],
            "bodyValues":{"p":{"value":"Hello","isTruncated":true}},
            "attachments":[{"blobId":"b1","name":"file +.txt","type":"text/plain","size":123,"cid":null,"disposition":"attachment"}]}]])
        responses={session(),result("Email/get",{list={{id="m2",preview="two"},message}}),
            result("Email/get",{list={message}})}
        local messages=fastmail.getMessages({{id="m1"},"m2"},{maxBodyValueBytes=1234})
        local m=messages[1]
        assert(args(2).maxBodyValueBytes==1234)
        assert(m.id=="m1" and messages[2].id=="m2")
        assert(m.from=="a@example.com" and m.to=="" and m.body=="Hello" and m.bodyTruncated)
        assert(m.messageId=="m@example.com" and m.received[1]=="by mail")
        assert(m.attachments[1].id=="b1" and not m.attachments[1].inline and not m.attachments[1].contentId)
        -- Return a fresh provider object; connector decoration must not alter transport fixtures.
        responses[1]=result("Email/get",{list={json.decode([[{"id":"m1","attachments":[{"blobId":"b1","name":"file +.txt","type":"text/plain","size":123}]}]])}})
        local downloaded=fastmail.getAttachment("m1","b1","mail/a.txt")
        assert(downloaded.size==123 and downloaded.url=="https://houston.test/mail/a.txt")
        local contents = fs.open("mail/a.txt", "r")
        assert(await(contents:readAll()) == string.rep("x", 123))
        await(contents:close())
        assert(requests[4].url=="https://phl-www.fastmailusercontent.com/jmap/download/u1/b1/file%20%2B.txt?type=text%2Fplain")
        local ids={}
        for i=1,51 do ids[i]="m"..i end
        assert(not pcall(fastmail.getMessages,ids))

end}
