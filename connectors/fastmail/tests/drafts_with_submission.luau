-- With Email submission, draft senders are verified identities and drafts can be sent.
return {scenario={["auth_config"]={["token"]="fixture-private-password !@#"},["auth_method"]="token",["config"]={},["publisher"]={}},config={access="read-write"}, configure=function()

        requests, responses = {}, {}
        http = {request = function(req)
            requests[#requests + 1] = req
            assert(#responses > 0, "unexpected request: " .. tostring(req.url))
            local response = table.remove(responses, 1)
            return fixture.operation({statusCode=200, headers={}, body=fixture.reader(json.encode(response))})
        end}
        local MAIL="urn:ietf:params:jmap:mail"
        local SUB="urn:ietf:params:jmap:submission"
        function session()
            return {username="me@example.com", primaryAccounts={[MAIL]="u1"}, accounts={u1={name="Me"}},
                capabilities={[MAIL]={}, [SUB]={}}, apiUrl="https://api.fastmail.com/jmap/api/"}
        end
        function result(name, args) return {methodResponses={{name, args, "0"}}} end
        folders={{id="in", role="inbox", name="Inbox"}, {id="dr", role="drafts", name="Drafts"}, {id="se", role="sent", name="Sent"}}
        identities={list={{id="i-me", email="me@example.com", name="Me"}, {id="i-sup", email="support@example.com", name="Support"}}}
        function draft(id, keywords)
            return {id=id, keywords=keywords or {["$draft"]=true}, from={{name="Support", email="Support@example.com"}}}
        end
        function jmapSince(start)
            local out = {}
            for i = start + 1, #requests do
                local decoded = json.decode(requests[i].body)
                out[#out + 1] = {name=decoded.methodCalls[1][1], args=decoded.methodCalls[1][2], using=decoded.using}
            end
            return out
        end

end, run=function(fastmail)
        responses={session(), result("Identity/get", identities), result("Mailbox/get", {list=folders}),
            result("Email/set", {created={draft={id="d1", threadId="t1"}}})}
        local made = fastmail.createDraft({to={{email="to@example.com"}}, text="Body", from="support@example.com"})
        assert(made.id == "d1")
        local calls = jmapSince(1)
        assert(#calls == 3 and calls[1].name == "Identity/get")
        local created = calls[3].args.create.draft
        assert(created.from[1].email == "support@example.com" and created.from[1].name == "Support")

        responses={result("Identity/get", identities)}
        local mark = #requests
        local ok, err = pcall(function() fastmail.createDraft({text="x", from="missing@example.com"}) end)
        assert(not ok and string.find(tostring(err), "listAliases", 1, true) and #requests == mark + 1)

        responses={result("Identity/get", identities), result("Email/get", {list={draft("d1")}}),
            result("Mailbox/get", {list=folders}), result("EmailSubmission/set", {created={send={id="s1"}}})}
        mark = #requests
        local sent = fastmail.sendDraft({id="d1"})
        assert(sent.id == "d1" and sent.submissionId == "s1")
        calls = jmapSince(mark)
        assert(#calls == 4 and calls[2].name == "Email/get" and calls[4].name == "EmailSubmission/set")
        local submission = calls[4].args
        assert(submission.create.send.emailId == "d1" and submission.create.send.identityId == "i-sup")
        assert(calls[4].using[3] == "urn:ietf:params:jmap:submission")
        assert(submission.onSuccessUpdateEmail["#send"].mailboxIds.se and submission.onSuccessUpdateEmail["#send"].keywords["$draft"] == nil)

        responses={result("Identity/get", identities), result("Email/get", {list={draft("d1")}}),
            result("Mailbox/get", {list=folders}), result("EmailSubmission/set", {created={send={id="s2"}}})}
        mark = #requests
        sent = fastmail.sendDraft({id="d1", identityId="i-me"})
        assert(sent.submissionId == "s2" and jmapSince(mark)[4].args.create.send.identityId == "i-me")

        responses={result("Identity/get", identities), result("Email/get", {list={draft("m", {["$seen"]=true})}})}
        mark = #requests
        ok, err = pcall(function() fastmail.sendDraft("m") end)
        assert(not ok and string.find(tostring(err), "not a draft", 1, true) and #requests == mark + 2)

        responses={result("Email/get", {list={draft("d1")}}), result("Identity/get", identities),
            result("Email/set", {created={draft={id="d2"}}}), result("Email/set", {destroyed={"d1"}})}
        mark = #requests
        made = fastmail.updateDraft({id="d1", from="me@example.com", text="Changed"})
        assert(made.id == "d2")
        calls = jmapSince(mark)
        created = calls[3].args.create.draft
        assert(created.from[1].email == "me@example.com" and created.from[1].name == "Me" and created.bodyValues.text.value == "Changed")
        assert(calls[4].args.destroy[1] == "d1")
        assert(#responses == 0)

end}
